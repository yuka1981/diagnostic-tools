# Intel MLC Web-Triggered Installation - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enable web-triggered installation of Intel MLC binary to remote HPC nodes with automatic Lmod modulefile generation.

**Architecture:** Rails handles tarball upload, checksum verification, binary selection, and job orchestration. Agent receives installation command via SSH, extracts tarball, detects version, installs binary to `/opt/qct/utils/qis/software/mlc-<version>/`, and generates Lmod modulefile at `/opt/qct/utils/qis/modulefiles/mlc/<version>`.

**Tech Stack:** Rails 7.2 (Hotwire/Turbo), Go (Cobra CLI), PostgreSQL, RSpec, Go testing

---

## Phase 1: Database Layer

### Task 1: Create MlcInstallation Migration

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_create_mlc_installations.rb`

**Step 1: Generate migration**

```bash
bin/rails generate migration CreateMlcInstallations
```

**Step 2: Write migration content**

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_mlc_installations.rb
class CreateMlcInstallations < ActiveRecord::Migration[7.2]
  def change
    create_table :mlc_installations do |t|
      t.string :uuid, null: false, index: { unique: true }
      t.integer :status, null: false, default: 0
      t.integer :source_type, null: false, default: 0
      t.string :source_path
      t.string :binary_path
      t.string :checksum_algorithm
      t.string :checksum_value
      t.boolean :checksum_verified, default: false
      t.string :detected_version
      t.string :install_dir, default: "/opt/qct/utils/qis/software"
      t.string :module_dir, default: "/opt/qct/utils/qis/modulefiles"
      t.integer :failure_mode, null: false, default: 0
      t.references :created_by, foreign_key: { to_table: :users }
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end
  end
end
```

**Step 3: Run migration**

```bash
bin/rails db:migrate
```
Expected: Migration completes successfully

**Step 4: Commit**

```bash
git add db/migrate/*_create_mlc_installations.rb db/schema.rb
git commit -m "feat(db): add mlc_installations table"
```

---

### Task 2: Create MlcInstallationNode Migration

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_create_mlc_installation_nodes.rb`

**Step 1: Generate migration**

```bash
bin/rails generate migration CreateMlcInstallationNodes
```

**Step 2: Write migration content**

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_mlc_installation_nodes.rb
class CreateMlcInstallationNodes < ActiveRecord::Migration[7.2]
  def change
    create_table :mlc_installation_nodes do |t|
      t.references :mlc_installation, null: false, foreign_key: true
      t.references :node, null: false, foreign_key: true
      t.integer :status, null: false, default: 0
      t.integer :step_current, default: 0
      t.integer :step_total, default: 7
      t.string :step_name
      t.text :error_message
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :mlc_installation_nodes, [:mlc_installation_id, :node_id], unique: true
  end
end
```

**Step 3: Run migration**

```bash
bin/rails db:migrate
```
Expected: Migration completes successfully

**Step 4: Commit**

```bash
git add db/migrate/*_create_mlc_installation_nodes.rb db/schema.rb
git commit -m "feat(db): add mlc_installation_nodes table"
```

---

## Phase 2: Rails Models

### Task 3: Create MlcInstallation Model with Tests

**Files:**
- Create: `app/models/mlc_installation.rb`
- Create: `spec/models/mlc_installation_spec.rb`
- Create: `spec/factories/mlc_installations.rb`

**Step 1: Write the failing test**

```ruby
# spec/models/mlc_installation_spec.rb
require "rails_helper"

RSpec.describe MlcInstallation, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:created_by).class_name("User").optional }
    it { is_expected.to have_many(:mlc_installation_nodes).dependent(:destroy) }
    it { is_expected.to have_many(:nodes).through(:mlc_installation_nodes) }
  end

  describe "enums" do
    it do
      is_expected.to define_enum_for(:status)
        .with_values(pending: 0, running: 1, completed: 2, failed: 3, cancelled: 4)
        .with_default(:pending)
    end

    it do
      is_expected.to define_enum_for(:source_type)
        .with_values(upload: 0, shared_path: 1)
        .with_default(:upload)
    end

    it do
      is_expected.to define_enum_for(:failure_mode)
        .with_values(stop_on_first: 0, continue_on_failure: 1)
        .with_default(:stop_on_first)
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:uuid) }

    it "validates uniqueness of uuid" do
      create(:mlc_installation)
      is_expected.to validate_uniqueness_of(:uuid)
    end
  end

  describe "callbacks" do
    it "generates uuid before validation on create" do
      installation = build(:mlc_installation, uuid: nil)
      installation.valid?
      expect(installation.uuid).to be_present
    end
  end

  describe "#progress_percentage" do
    let(:installation) { create(:mlc_installation) }

    context "with no nodes" do
      it "returns 0" do
        expect(installation.progress_percentage).to eq(0)
      end
    end

    context "with completed nodes" do
      before do
        create(:mlc_installation_node, mlc_installation: installation, status: :success)
        create(:mlc_installation_node, mlc_installation: installation, status: :pending)
      end

      it "returns percentage of completed nodes" do
        expect(installation.progress_percentage).to eq(50)
      end
    end
  end
end
```

**Step 2: Write the factory**

```ruby
# spec/factories/mlc_installations.rb
FactoryBot.define do
  factory :mlc_installation do
    uuid { SecureRandom.uuid }
    status { :pending }
    source_type { :upload }
    source_path { "/tmp/mlc_upload_#{SecureRandom.hex(8)}.tgz" }
    install_dir { "/opt/qct/utils/qis/software" }
    module_dir { "/opt/qct/utils/qis/modulefiles" }
    failure_mode { :stop_on_first }
    association :created_by, factory: :user

    trait :running do
      status { :running }
      started_at { Time.current }
    end

    trait :completed do
      status { :completed }
      started_at { 10.minutes.ago }
      completed_at { Time.current }
      detected_version { "3.11" }
    end

    trait :with_checksum do
      checksum_algorithm { "sha256" }
      checksum_value { SecureRandom.hex(32) }
      checksum_verified { true }
    end
  end
end
```

**Step 3: Run test to verify it fails**

```bash
bin/rspec spec/models/mlc_installation_spec.rb -v
```
Expected: FAIL with "uninitialized constant MlcInstallation"

**Step 4: Write minimal implementation**

```ruby
# app/models/mlc_installation.rb
class MlcInstallation < ApplicationRecord
  belongs_to :created_by, class_name: "User", optional: true
  has_many :mlc_installation_nodes, dependent: :destroy
  has_many :nodes, through: :mlc_installation_nodes

  enum :status, { pending: 0, running: 1, completed: 2, failed: 3, cancelled: 4 }, default: :pending
  enum :source_type, { upload: 0, shared_path: 1 }, default: :upload
  enum :failure_mode, { stop_on_first: 0, continue_on_failure: 1 }, default: :stop_on_first

  validates :uuid, presence: true, uniqueness: true

  before_validation :generate_uuid, on: :create

  def progress_percentage
    return 0 if mlc_installation_nodes.empty?

    completed = mlc_installation_nodes.where(status: [:success, :failed, :skipped]).count
    total = mlc_installation_nodes.count
    ((completed.to_f / total) * 100).to_i
  end

  private

  def generate_uuid
    self.uuid ||= SecureRandom.uuid
  end
end
```

**Step 5: Run test to verify it passes**

```bash
bin/rspec spec/models/mlc_installation_spec.rb -v
```
Expected: PASS

**Step 6: Commit**

```bash
git add app/models/mlc_installation.rb spec/models/mlc_installation_spec.rb spec/factories/mlc_installations.rb
git commit -m "feat(model): add MlcInstallation model with validations"
```

---

### Task 4: Create MlcInstallationNode Model with Tests

**Files:**
- Create: `app/models/mlc_installation_node.rb`
- Create: `spec/models/mlc_installation_node_spec.rb`
- Create: `spec/factories/mlc_installation_nodes.rb`

**Step 1: Write the failing test**

```ruby
# spec/models/mlc_installation_node_spec.rb
require "rails_helper"

RSpec.describe MlcInstallationNode, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:mlc_installation) }
    it { is_expected.to belong_to(:node) }
  end

  describe "enums" do
    it do
      is_expected.to define_enum_for(:status)
        .with_values(pending: 0, running: 1, success: 2, failed: 3, skipped: 4)
        .with_default(:pending)
    end
  end

  describe "#completed?" do
    it "returns true for success status" do
      node = build(:mlc_installation_node, status: :success)
      expect(node.completed?).to be true
    end

    it "returns true for failed status" do
      node = build(:mlc_installation_node, status: :failed)
      expect(node.completed?).to be true
    end

    it "returns false for running status" do
      node = build(:mlc_installation_node, status: :running)
      expect(node.completed?).to be false
    end
  end

  describe "#duration" do
    it "returns nil when not completed" do
      node = build(:mlc_installation_node, started_at: Time.current, completed_at: nil)
      expect(node.duration).to be_nil
    end

    it "returns duration in seconds when completed" do
      node = build(:mlc_installation_node, started_at: 10.seconds.ago, completed_at: Time.current)
      expect(node.duration).to be_within(1).of(10)
    end
  end
end
```

**Step 2: Write the factory**

```ruby
# spec/factories/mlc_installation_nodes.rb
FactoryBot.define do
  factory :mlc_installation_node do
    association :mlc_installation
    association :node
    status { :pending }
    step_current { 0 }
    step_total { 7 }

    trait :running do
      status { :running }
      started_at { Time.current }
      step_current { 3 }
      step_name { "Installing binary" }
    end

    trait :success do
      status { :success }
      started_at { 30.seconds.ago }
      completed_at { Time.current }
      step_current { 7 }
      step_total { 7 }
    end

    trait :failed do
      status { :failed }
      started_at { 30.seconds.ago }
      completed_at { Time.current }
      error_message { "Permission denied: /opt/qct/utils/qis/software" }
    end
  end
end
```

**Step 3: Run test to verify it fails**

```bash
bin/rspec spec/models/mlc_installation_node_spec.rb -v
```
Expected: FAIL with "uninitialized constant MlcInstallationNode"

**Step 4: Write minimal implementation**

```ruby
# app/models/mlc_installation_node.rb
class MlcInstallationNode < ApplicationRecord
  belongs_to :mlc_installation
  belongs_to :node

  enum :status, { pending: 0, running: 1, success: 2, failed: 3, skipped: 4 }, default: :pending

  def completed?
    success? || failed? || skipped?
  end

  def duration
    return nil unless started_at && completed_at

    completed_at - started_at
  end
end
```

**Step 5: Run test to verify it passes**

```bash
bin/rspec spec/models/mlc_installation_node_spec.rb -v
```
Expected: PASS

**Step 6: Commit**

```bash
git add app/models/mlc_installation_node.rb spec/models/mlc_installation_node_spec.rb spec/factories/mlc_installation_nodes.rb
git commit -m "feat(model): add MlcInstallationNode model"
```

---

## Phase 3: Upload & Checksum Services

### Task 5: Create Mlc::UploadService with Tests

**Files:**
- Create: `app/services/mlc/upload_service.rb`
- Create: `spec/services/mlc/upload_service_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/services/mlc/upload_service_spec.rb
require "rails_helper"

RSpec.describe Mlc::UploadService do
  let(:tempfile) { Tempfile.new(["mlc", ".tgz"]) }
  let(:uploaded_file) do
    ActionDispatch::Http::UploadedFile.new(
      tempfile: tempfile,
      filename: "mlc_v3.11.tgz",
      type: "application/gzip"
    )
  end

  before do
    tempfile.write("fake tarball content")
    tempfile.rewind
  end

  after do
    tempfile.close
    tempfile.unlink
  end

  describe "#call" do
    subject(:service) { described_class.new(uploaded_file) }

    it "stores the uploaded file" do
      result = service.call
      expect(result.success?).to be true
      expect(result.stored_path).to be_present
      expect(File.exist?(result.stored_path)).to be true
    end

    it "computes checksum" do
      result = service.call
      expect(result.computed_checksum).to match(/\A[a-f0-9]{64}\z/)
    end
  end

  describe "#verify_checksum" do
    subject(:service) { described_class.new(uploaded_file) }

    before { service.call }

    it "returns true for matching checksum" do
      computed = service.result.computed_checksum
      expect(service.verify_checksum("sha256", computed)).to be true
    end

    it "returns false for mismatched checksum" do
      expect(service.verify_checksum("sha256", "wrong")).to be false
    end
  end
end
```

**Step 2: Run test to verify it fails**

```bash
bin/rspec spec/services/mlc/upload_service_spec.rb -v
```
Expected: FAIL with "uninitialized constant Mlc::UploadService"

**Step 3: Write minimal implementation**

```ruby
# app/services/mlc/upload_service.rb
module Mlc
  class UploadService
    Result = Struct.new(:success?, :stored_path, :computed_checksum, :error, keyword_init: true)

    UPLOAD_DIR = Rails.root.join("storage", "mlc_uploads")

    attr_reader :result

    def initialize(uploaded_file)
      @uploaded_file = uploaded_file
      @result = nil
    end

    def call
      FileUtils.mkdir_p(UPLOAD_DIR)

      filename = "#{SecureRandom.uuid}_#{sanitize_filename(@uploaded_file.original_filename)}"
      stored_path = UPLOAD_DIR.join(filename)

      File.open(stored_path, "wb") do |file|
        file.write(@uploaded_file.read)
      end

      checksum = Digest::SHA256.file(stored_path).hexdigest

      @result = Result.new(
        success?: true,
        stored_path: stored_path.to_s,
        computed_checksum: checksum
      )
    rescue StandardError => e
      @result = Result.new(success?: false, error: e.message)
    end

    def verify_checksum(algorithm, expected)
      return false unless @result&.stored_path

      actual = case algorithm.downcase
               when "sha256" then Digest::SHA256.file(@result.stored_path).hexdigest
               when "sha1" then Digest::SHA1.file(@result.stored_path).hexdigest
               when "md5" then Digest::MD5.file(@result.stored_path).hexdigest
               else return false
               end

      ActiveSupport::SecurityUtils.secure_compare(actual, expected.downcase)
    end

    private

    def sanitize_filename(filename)
      filename.gsub(/[^a-zA-Z0-9._-]/, "_")
    end
  end
end
```

**Step 4: Run test to verify it passes**

```bash
bin/rspec spec/services/mlc/upload_service_spec.rb -v
```
Expected: PASS

**Step 5: Commit**

```bash
git add app/services/mlc/upload_service.rb spec/services/mlc/upload_service_spec.rb
git commit -m "feat(service): add Mlc::UploadService for tarball upload and checksum"
```

---

### Task 6: Create Mlc::BinaryDetectionService with Tests

**Files:**
- Create: `app/services/mlc/binary_detection_service.rb`
- Create: `spec/services/mlc/binary_detection_service_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/services/mlc/binary_detection_service_spec.rb
require "rails_helper"

RSpec.describe Mlc::BinaryDetectionService do
  let(:extract_dir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(extract_dir) }

  describe "#call" do
    context "with valid tarball structure" do
      before do
        # Create mock extracted structure
        linux_dir = File.join(extract_dir, "mlc_v3.11", "Linux")
        FileUtils.mkdir_p(linux_dir)
        File.write(File.join(linux_dir, "mlc"), "ELF binary content")
      end

      it "detects binary candidates" do
        service = described_class.new(extract_dir)
        result = service.call

        expect(result.success?).to be true
        expect(result.candidates).not_to be_empty
        expect(result.candidates.first[:path]).to include("Linux/mlc")
      end
    end

    context "with no binaries found" do
      it "returns error" do
        service = described_class.new(extract_dir)
        result = service.call

        expect(result.success?).to be false
        expect(result.error).to include("No MLC binary")
      end
    end
  end

  describe "#detect_version" do
    let(:binary_path) { File.join(extract_dir, "mlc") }

    before do
      # Create a mock binary that outputs version
      File.write(binary_path, "#!/bin/bash\necho 'Intel(R) Memory Latency Checker - v3.11'")
      FileUtils.chmod(0o755, binary_path)
    end

    it "extracts version from binary output" do
      service = described_class.new(extract_dir)
      version = service.detect_version(binary_path)
      expect(version).to eq("3.11")
    end
  end
end
```

**Step 2: Run test to verify it fails**

```bash
bin/rspec spec/services/mlc/binary_detection_service_spec.rb -v
```
Expected: FAIL with "uninitialized constant Mlc::BinaryDetectionService"

**Step 3: Write minimal implementation**

```ruby
# app/services/mlc/binary_detection_service.rb
module Mlc
  class BinaryDetectionService
    Result = Struct.new(:success?, :candidates, :error, keyword_init: true)
    Candidate = Struct.new(:path, :relative_path, :size, :file_type, keyword_init: true)

    VERSION_REGEX = /v?(\d+\.\d+(?:\.\d+)?)/

    def initialize(extract_dir)
      @extract_dir = extract_dir
    end

    def call
      candidates = find_binary_candidates
      if candidates.empty?
        Result.new(success?: false, error: "No MLC binary detected in extracted contents")
      else
        Result.new(success?: true, candidates: candidates)
      end
    end

    def detect_version(binary_path)
      return nil unless File.executable?(binary_path)

      output = `#{Shellwords.escape(binary_path)} --version 2>&1`.strip
      match = output.match(VERSION_REGEX)
      match ? match[1] : nil
    rescue StandardError
      nil
    end

    private

    def find_binary_candidates
      candidates = []

      Dir.glob(File.join(@extract_dir, "**", "*")).each do |path|
        next unless File.file?(path)
        next unless File.basename(path).downcase.include?("mlc")

        file_type = detect_file_type(path)
        next unless binary_file_type?(file_type)

        relative = path.sub("#{@extract_dir}/", "")
        candidates << Candidate.new(
          path: path,
          relative_path: relative,
          size: File.size(path),
          file_type: file_type
        )
      end

      candidates
    end

    def detect_file_type(path)
      `file -b #{Shellwords.escape(path)}`.strip
    rescue StandardError
      "unknown"
    end

    def binary_file_type?(file_type)
      file_type.match?(/ELF|PE32|Mach-O|executable/i)
    end
  end
end
```

**Step 4: Run test to verify it passes**

```bash
bin/rspec spec/services/mlc/binary_detection_service_spec.rb -v
```
Expected: PASS

**Step 5: Commit**

```bash
git add app/services/mlc/binary_detection_service.rb spec/services/mlc/binary_detection_service_spec.rb
git commit -m "feat(service): add Mlc::BinaryDetectionService for binary detection"
```

---

## Phase 4: Go Agent Installation Command

### Task 7: Create Agent mlc-install Command Skeleton

**Files:**
- Create: `agent/cmd/mlc_install.go`
- Create: `agent/cmd/mlc_install_test.go`

**Step 1: Write the failing test**

```go
// agent/cmd/mlc_install_test.go
package cmd

import (
	"bytes"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestNewMLCInstallCmd(t *testing.T) {
	cmd := NewMLCInstallCmd()
	assert.Equal(t, "mlc-install", cmd.Use)
	assert.NotEmpty(t, cmd.Short)
}

func TestMLCInstallCmd_RequiredFlags(t *testing.T) {
	cmd := NewMLCInstallCmd()
	buf := new(bytes.Buffer)
	cmd.SetOut(buf)
	cmd.SetErr(buf)

	// Execute without required flags should fail
	err := cmd.Execute()
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "required flag")
}

func TestMLCInstallCmd_DryRun(t *testing.T) {
	cmd := NewMLCInstallCmd()
	buf := new(bytes.Buffer)
	cmd.SetOut(buf)
	cmd.SetErr(buf)

	cmd.SetArgs([]string{
		"--tarball", "/tmp/test.tgz",
		"--binary-path", "Linux/mlc",
		"--dry-run",
	})

	err := cmd.Execute()
	assert.NoError(t, err)
	assert.Contains(t, buf.String(), "Dry Run")
}
```

**Step 2: Run test to verify it fails**

```bash
cd agent && go test ./cmd -run TestNewMLCInstallCmd -v
```
Expected: FAIL with undefined: NewMLCInstallCmd

**Step 3: Write minimal implementation**

```go
// agent/cmd/mlc_install.go
package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

type mlcInstallOptions struct {
	tarball     string
	binaryPath  string
	installDir  string
	moduleDir   string
	server      string
	token       string
	installID   string
	dryRun      bool
}

func (o *mlcInstallOptions) addFlags(cmd *cobra.Command) {
	cmd.Flags().StringVar(&o.tarball, "tarball", "", "Path to MLC tarball (required)")
	cmd.Flags().StringVar(&o.binaryPath, "binary-path", "", "Path to binary within tarball (required)")
	cmd.Flags().StringVar(&o.installDir, "install-dir", "/opt/qct/utils/qis/software", "Installation directory")
	cmd.Flags().StringVar(&o.moduleDir, "module-dir", "/opt/qct/utils/qis/modulefiles", "Modulefiles directory")
	cmd.Flags().StringVar(&o.server, "server", "", "Server URL for progress updates")
	cmd.Flags().StringVar(&o.token, "token", "", "Authentication token")
	cmd.Flags().StringVar(&o.installID, "id", "", "Installation job ID")
	cmd.Flags().BoolVar(&o.dryRun, "dry-run", false, "Print what would be done without executing")

	cmd.MarkFlagRequired("tarball")
	cmd.MarkFlagRequired("binary-path")
}

// NewMLCInstallCmd creates the mlc-install command.
func NewMLCInstallCmd() *cobra.Command {
	opts := &mlcInstallOptions{}
	cmd := &cobra.Command{
		Use:   "mlc-install",
		Short: "Install Intel MLC binary and configure Lmod module",
		Long: `Install Intel Memory Latency Checker (MLC) from a tarball.

This command:
1. Extracts the specified tarball
2. Detects MLC version from the binary
3. Installs to /opt/qct/utils/qis/software/mlc-<version>/
4. Generates Lmod modulefile at /opt/qct/utils/qis/modulefiles/mlc/<version>

Examples:
  # Install MLC from tarball
  qis-agent mlc-install --tarball /tmp/mlc.tgz --binary-path Linux/mlc

  # Dry run to see what would be installed
  qis-agent mlc-install --tarball /tmp/mlc.tgz --binary-path Linux/mlc --dry-run`,
		RunE: func(cmd *cobra.Command, args []string) error {
			return runMLCInstall(cmd, opts)
		},
	}
	opts.addFlags(cmd)
	return cmd
}

func runMLCInstall(cmd *cobra.Command, opts *mlcInstallOptions) error {
	if opts.dryRun {
		return printMLCInstallDryRun(cmd, opts)
	}

	// TODO: Implement actual installation in Task 8
	return fmt.Errorf("installation not yet implemented")
}

func printMLCInstallDryRun(cmd *cobra.Command, opts *mlcInstallOptions) error {
	fmt.Fprintln(cmd.OutOrStdout(), "=== MLC Install Dry Run ===")
	fmt.Fprintf(cmd.OutOrStdout(), "Tarball: %s\n", opts.tarball)
	fmt.Fprintf(cmd.OutOrStdout(), "Binary Path: %s\n", opts.binaryPath)
	fmt.Fprintf(cmd.OutOrStdout(), "Install Dir: %s\n", opts.installDir)
	fmt.Fprintf(cmd.OutOrStdout(), "Module Dir: %s\n", opts.moduleDir)

	if opts.server != "" {
		fmt.Fprintf(cmd.OutOrStdout(), "Server: %s\n", opts.server)
	}
	if opts.installID != "" {
		fmt.Fprintf(cmd.OutOrStdout(), "Install ID: %s\n", opts.installID)
	}

	fmt.Fprintln(cmd.OutOrStdout(), "\nSteps that would be executed:")
	fmt.Fprintln(cmd.OutOrStdout(), "  1. Validate tarball exists")
	fmt.Fprintln(cmd.OutOrStdout(), "  2. Extract to temp directory")
	fmt.Fprintln(cmd.OutOrStdout(), "  3. Detect version from binary")
	fmt.Fprintln(cmd.OutOrStdout(), "  4. Install binary")
	fmt.Fprintln(cmd.OutOrStdout(), "  5. Generate modulefile")
	fmt.Fprintln(cmd.OutOrStdout(), "  6. Cleanup temp files")
	fmt.Fprintln(cmd.OutOrStdout(), "  7. Report success")

	return nil
}

func init() {
	rootCmd.AddCommand(NewMLCInstallCmd())
}
```

**Step 4: Run test to verify it passes**

```bash
cd agent && go test ./cmd -run TestMLCInstall -v
```
Expected: PASS

**Step 5: Commit**

```bash
git add agent/cmd/mlc_install.go agent/cmd/mlc_install_test.go
git commit -m "feat(agent): add mlc-install command skeleton"
```

---

### Task 8: Implement MLC Install Workflow

**Files:**
- Create: `agent/mlc/install_workflow.go`
- Create: `agent/mlc/install_workflow_test.go`

**Step 1: Write the failing test**

```go
// agent/mlc/install_workflow_test.go
package mlc

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestInstallWorkflow_ValidateTarball(t *testing.T) {
	w := &InstallWorkflow{}

	t.Run("missing tarball returns error", func(t *testing.T) {
		err := w.validateTarball("/nonexistent/path.tgz")
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "not found")
	})

	t.Run("existing tarball passes", func(t *testing.T) {
		tmpfile, err := os.CreateTemp("", "test*.tgz")
		require.NoError(t, err)
		defer os.Remove(tmpfile.Name())
		tmpfile.Close()

		err = w.validateTarball(tmpfile.Name())
		assert.NoError(t, err)
	})
}

func TestInstallWorkflow_DetectVersion(t *testing.T) {
	w := &InstallWorkflow{}

	t.Run("parses version from output", func(t *testing.T) {
		output := "Intel(R) Memory Latency Checker - v3.11"
		version := w.parseVersion(output)
		assert.Equal(t, "3.11", version)
	})

	t.Run("handles version with patch", func(t *testing.T) {
		output := "Intel(R) Memory Latency Checker - v3.11.2"
		version := w.parseVersion(output)
		assert.Equal(t, "3.11.2", version)
	})

	t.Run("returns empty for no match", func(t *testing.T) {
		output := "no version here"
		version := w.parseVersion(output)
		assert.Empty(t, version)
	})
}

func TestInstallWorkflow_GenerateModulefile(t *testing.T) {
	w := &InstallWorkflow{}

	content := w.generateModulefile("3.11", "/opt/qct/utils/qis/software/mlc-3.11")

	assert.Contains(t, content, "help([[Intel Memory Latency Checker")
	assert.Contains(t, content, "v3.11")
	assert.Contains(t, content, `prepend_path("PATH"`)
	assert.Contains(t, content, "mlc-3.11")
}

func TestInstallWorkflow_Run(t *testing.T) {
	// Create a temp directory structure simulating extracted tarball
	tmpDir, err := os.MkdirTemp("", "mlc-install-test")
	require.NoError(t, err)
	defer os.RemoveAll(tmpDir)

	// Create mock tarball (we'll skip actual extraction in unit test)
	tarball := filepath.Join(tmpDir, "mlc.tgz")
	err = os.WriteFile(tarball, []byte("mock tarball"), 0644)
	require.NoError(t, err)

	// Create install and module dirs
	installDir := filepath.Join(tmpDir, "software")
	moduleDir := filepath.Join(tmpDir, "modulefiles")
	os.MkdirAll(installDir, 0755)
	os.MkdirAll(moduleDir, 0755)

	// We can't fully test Run() without a real tarball,
	// but we can test the workflow structure exists
	w := NewInstallWorkflow(nil) // nil runner for structure test
	assert.NotNil(t, w)
}
```

**Step 2: Run test to verify it fails**

```bash
cd agent && go test ./mlc -run TestInstallWorkflow -v
```
Expected: FAIL with undefined: InstallWorkflow

**Step 3: Write minimal implementation**

```go
// agent/mlc/install_workflow.go
package mlc

import (
	"archive/tar"
	"compress/gzip"
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/yuka1981/diagnostic-tools/agent/core/ports"
)

const (
	DefaultInstallDir = "/opt/qct/utils/qis/software"
	DefaultModuleDir  = "/opt/qct/utils/qis/modulefiles"
)

var versionRegex = regexp.MustCompile(`v?(\d+\.\d+(?:\.\d+)?)`)

// InstallParams defines parameters for MLC installation.
type InstallParams struct {
	Tarball    string
	BinaryPath string // Relative path within tarball (e.g., "Linux/mlc")
	InstallDir string
	ModuleDir  string
	InstallID  string
}

// InstallResult contains the result of installation.
type InstallResult struct {
	Success        bool
	Version        string
	InstallPath    string
	ModulePath     string
	ErrorMessage   string
	FailedAtStep   int
	FailedStepName string
}

// InstallWorkflow manages the MLC installation process.
type InstallWorkflow struct {
	Runner ports.CommandRunner
}

// NewInstallWorkflow creates a new install workflow.
func NewInstallWorkflow(runner ports.CommandRunner) *InstallWorkflow {
	return &InstallWorkflow{Runner: runner}
}

// Run executes the installation workflow.
func (w *InstallWorkflow) Run(ctx context.Context, params *InstallParams) *InstallResult {
	// Step 1: Validate tarball
	if err := w.validateTarball(params.Tarball); err != nil {
		return &InstallResult{
			Success: false, ErrorMessage: err.Error(),
			FailedAtStep: 1, FailedStepName: "Validate tarball",
		}
	}

	// Step 2: Extract to temp directory
	extractDir, err := w.extractTarball(params.Tarball)
	if err != nil {
		return &InstallResult{
			Success: false, ErrorMessage: fmt.Sprintf("Extract failed: %v", err),
			FailedAtStep: 2, FailedStepName: "Extract tarball",
		}
	}
	defer os.RemoveAll(extractDir)

	// Step 3: Detect version
	binaryPath := filepath.Join(extractDir, params.BinaryPath)
	version, err := w.detectVersion(binaryPath)
	if err != nil {
		return &InstallResult{
			Success: false, ErrorMessage: fmt.Sprintf("Version detection failed: %v", err),
			FailedAtStep: 3, FailedStepName: "Detect version",
		}
	}

	// Step 4: Install binary
	installPath := filepath.Join(params.InstallDir, fmt.Sprintf("mlc-%s", version))
	if err := w.installBinary(binaryPath, installPath); err != nil {
		return &InstallResult{
			Success: false, ErrorMessage: fmt.Sprintf("Install failed: %v", err),
			FailedAtStep: 4, FailedStepName: "Install binary",
		}
	}

	// Step 5: Generate modulefile
	modulePath := filepath.Join(params.ModuleDir, "mlc", version)
	if err := w.writeModulefile(version, installPath, modulePath); err != nil {
		return &InstallResult{
			Success: false, ErrorMessage: fmt.Sprintf("Modulefile creation failed: %v", err),
			FailedAtStep: 5, FailedStepName: "Generate modulefile",
		}
	}

	// Step 6: Update symlink
	latestLink := filepath.Join(params.InstallDir, "mlc-latest")
	os.Remove(latestLink) // Remove old symlink if exists
	os.Symlink(installPath, latestLink)

	return &InstallResult{
		Success:     true,
		Version:     version,
		InstallPath: installPath,
		ModulePath:  modulePath,
	}
}

func (w *InstallWorkflow) validateTarball(path string) error {
	info, err := os.Stat(path)
	if os.IsNotExist(err) {
		return fmt.Errorf("tarball not found: %s", path)
	}
	if err != nil {
		return fmt.Errorf("cannot access tarball: %w", err)
	}
	if info.IsDir() {
		return fmt.Errorf("path is a directory, not a tarball: %s", path)
	}
	return nil
}

func (w *InstallWorkflow) extractTarball(tarballPath string) (string, error) {
	extractDir, err := os.MkdirTemp("", "mlc-extract-")
	if err != nil {
		return "", err
	}

	file, err := os.Open(tarballPath)
	if err != nil {
		os.RemoveAll(extractDir)
		return "", err
	}
	defer file.Close()

	gzr, err := gzip.NewReader(file)
	if err != nil {
		os.RemoveAll(extractDir)
		return "", err
	}
	defer gzr.Close()

	tr := tar.NewReader(gzr)
	for {
		header, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			os.RemoveAll(extractDir)
			return "", err
		}

		target := filepath.Join(extractDir, header.Name)

		// Security: prevent path traversal
		if !strings.HasPrefix(target, filepath.Clean(extractDir)+string(os.PathSeparator)) {
			continue
		}

		switch header.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(target, 0755); err != nil {
				os.RemoveAll(extractDir)
				return "", err
			}
		case tar.TypeReg:
			if err := os.MkdirAll(filepath.Dir(target), 0755); err != nil {
				os.RemoveAll(extractDir)
				return "", err
			}
			f, err := os.OpenFile(target, os.O_CREATE|os.O_RDWR, os.FileMode(header.Mode))
			if err != nil {
				os.RemoveAll(extractDir)
				return "", err
			}
			if _, err := io.Copy(f, tr); err != nil {
				f.Close()
				os.RemoveAll(extractDir)
				return "", err
			}
			f.Close()
		}
	}

	return extractDir, nil
}

func (w *InstallWorkflow) detectVersion(binaryPath string) (string, error) {
	if _, err := os.Stat(binaryPath); os.IsNotExist(err) {
		return "", fmt.Errorf("binary not found at: %s", binaryPath)
	}

	// Make binary executable
	os.Chmod(binaryPath, 0755)

	cmd := exec.Command(binaryPath, "--version")
	output, err := cmd.CombinedOutput()
	if err != nil {
		// Try without --version flag (some versions just output on run)
		cmd = exec.Command(binaryPath)
		output, _ = cmd.CombinedOutput()
	}

	version := w.parseVersion(string(output))
	if version == "" {
		return "", fmt.Errorf("could not detect version from binary output")
	}

	return version, nil
}

func (w *InstallWorkflow) parseVersion(output string) string {
	match := versionRegex.FindStringSubmatch(output)
	if len(match) >= 2 {
		return match[1]
	}
	return ""
}

func (w *InstallWorkflow) installBinary(srcBinary, installDir string) error {
	if err := os.MkdirAll(installDir, 0755); err != nil {
		return fmt.Errorf("failed to create install directory: %w", err)
	}

	dstBinary := filepath.Join(installDir, "mlc")

	src, err := os.Open(srcBinary)
	if err != nil {
		return err
	}
	defer src.Close()

	dst, err := os.OpenFile(dstBinary, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0755)
	if err != nil {
		return err
	}
	defer dst.Close()

	if _, err := io.Copy(dst, src); err != nil {
		return err
	}

	return nil
}

func (w *InstallWorkflow) writeModulefile(version, installDir, modulePath string) error {
	moduleDir := filepath.Dir(modulePath)
	if err := os.MkdirAll(moduleDir, 0755); err != nil {
		return fmt.Errorf("failed to create modulefile directory: %w", err)
	}

	content := w.generateModulefile(version, installDir)

	return os.WriteFile(modulePath, []byte(content), 0644)
}

func (w *InstallWorkflow) generateModulefile(version, installDir string) string {
	return fmt.Sprintf(`-- Intel Memory Latency Checker (MLC) v%s
-- Auto-generated modulefile

help([[Intel Memory Latency Checker (MLC) v%s
Memory subsystem benchmarking tool from Intel.
]])

whatis("Name: Intel MLC")
whatis("Version: %s")
whatis("Description: Memory subsystem benchmarking tool")

local base = "%s"

prepend_path("PATH", base)
`, version, version, version, installDir)
}
```

**Step 4: Run test to verify it passes**

```bash
cd agent && go test ./mlc -run TestInstallWorkflow -v
```
Expected: PASS

**Step 5: Commit**

```bash
git add agent/mlc/install_workflow.go agent/mlc/install_workflow_test.go
git commit -m "feat(agent): add MLC install workflow with tarball extraction"
```

---

### Task 9: Wire Install Workflow to Command

**Files:**
- Modify: `agent/cmd/mlc_install.go`

**Step 1: Update the command to use workflow**

```go
// agent/cmd/mlc_install.go - update runMLCInstall function
func runMLCInstall(cmd *cobra.Command, opts *mlcInstallOptions) error {
	ctx := cmd.Context()

	if opts.dryRun {
		return printMLCInstallDryRun(cmd, opts)
	}

	fmt.Fprintln(cmd.OutOrStdout(), "Starting MLC installation...")

	params := &mlc.InstallParams{
		Tarball:    opts.tarball,
		BinaryPath: opts.binaryPath,
		InstallDir: opts.installDir,
		ModuleDir:  opts.moduleDir,
		InstallID:  opts.installID,
	}

	workflow := mlc.NewInstallWorkflow(nil)
	result := workflow.Run(ctx, params)

	if !result.Success {
		fmt.Fprintf(cmd.ErrOrStderr(), "Installation failed at step %d (%s): %s\n",
			result.FailedAtStep, result.FailedStepName, result.ErrorMessage)
		return fmt.Errorf("installation failed: %s", result.ErrorMessage)
	}

	fmt.Fprintf(cmd.OutOrStdout(), "Installation successful!\n")
	fmt.Fprintf(cmd.OutOrStdout(), "  Version: %s\n", result.Version)
	fmt.Fprintf(cmd.OutOrStdout(), "  Install path: %s\n", result.InstallPath)
	fmt.Fprintf(cmd.OutOrStdout(), "  Module path: %s\n", result.ModulePath)
	fmt.Fprintf(cmd.OutOrStdout(), "\nTo use: module load mlc/%s\n", result.Version)

	return nil
}
```

**Step 2: Run tests**

```bash
cd agent && go test ./cmd -run TestMLCInstall -v && go test ./mlc -v
```
Expected: PASS

**Step 3: Build and verify**

```bash
cd agent && go build -o qis-agent . && ./qis-agent mlc-install --help
```
Expected: Help output shows mlc-install command

**Step 4: Commit**

```bash
git add agent/cmd/mlc_install.go
git commit -m "feat(agent): wire mlc-install command to workflow"
```

---

## Phase 5: Rails Installation Trigger

### Task 10: Create Mlc::TriggerInstallService

**Files:**
- Create: `app/services/mlc/trigger_install_service.rb`
- Create: `spec/services/mlc/trigger_install_service_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/services/mlc/trigger_install_service_spec.rb
require "rails_helper"

RSpec.describe Mlc::TriggerInstallService do
  let(:node) { create(:node, :with_ssh_config) }
  let(:installation) { create(:mlc_installation, source_path: "/tmp/mlc.tgz", binary_path: "Linux/mlc") }
  let(:installation_node) { create(:mlc_installation_node, mlc_installation: installation, node: node) }

  describe "#build_command" do
    subject(:service) do
      described_class.new(
        installation: installation,
        installation_node: installation_node,
        server_url: "http://localhost:3000",
        agent_token: "test-token"
      )
    end

    it "builds correct agent command" do
      command = service.send(:build_agent_command)

      expect(command).to include("mlc-install")
      expect(command).to include("--tarball")
      expect(command).to include("--binary-path Linux/mlc")
      expect(command).to include("--server http://localhost:3000")
    end
  end
end
```

**Step 2: Run test to verify it fails**

```bash
bin/rspec spec/services/mlc/trigger_install_service_spec.rb -v
```
Expected: FAIL with "uninitialized constant Mlc::TriggerInstallService"

**Step 3: Write minimal implementation**

```ruby
# app/services/mlc/trigger_install_service.rb
module Mlc
  class TriggerInstallService < ::SshExecutionService
    DEFAULT_TIMEOUT = 600 # 10 minutes for installation

    def initialize(installation:, installation_node:, server_url:, agent_token:, ssh_config: {})
      @installation = installation
      @installation_node = installation_node
      @server_url = server_url
      @agent_token = agent_token
      super(installation_node.node, ssh_config: ssh_config)
    end

    def call
      result = execute_ssh_command(build_ssh_command)

      unless result.success?
        return error_result("SSH command failed: #{result.error}")
      end

      if result.output.include?("INSTALL_STARTED")
        Result.new(success: true, output: result.output)
      elsif result.output.include?("STARTUP_ERROR:")
        error_msg = result.output.sub("STARTUP_ERROR:", "").strip
        error_result("Installation failed to start: #{error_msg}")
      else
        error_result("Unexpected output: #{result.output.truncate(200)}")
      end
    rescue StandardError => e
      error_result("Unexpected error: #{e.message}")
    end

    private

    def build_ssh_command
      agent_bin = resolve_agent_path
      agent_cmd = build_agent_command

      <<~BASH.squish
        if [ ! -x #{Shellwords.escape(agent_bin)} ]; then
          echo 'STARTUP_ERROR: Agent binary not found at #{agent_bin}';
          exit 1;
        fi &&
        nohup #{agent_cmd} > /tmp/mlc_install_#{@installation.uuid}.log 2>&1 &
        INSTALL_PID=$! &&
        sleep 2 &&
        if kill -0 $INSTALL_PID 2>/dev/null; then
          echo "INSTALL_STARTED PID=$INSTALL_PID";
        else
          echo "STARTUP_ERROR: $(cat /tmp/mlc_install_#{@installation.uuid}.log | head -20)";
          exit 1;
        fi
      BASH
    end

    def build_agent_command
      parts = [
        resolve_agent_path,
        "mlc-install",
        "--tarball #{Shellwords.escape(@installation.source_path)}",
        "--binary-path #{Shellwords.escape(@installation.binary_path)}",
        "--install-dir #{Shellwords.escape(@installation.install_dir)}",
        "--module-dir #{Shellwords.escape(@installation.module_dir)}",
        "--id #{@installation.uuid}"
      ]

      if @server_url.present?
        parts << "--server #{Shellwords.escape(@server_url)}"
      end

      if @agent_token.present?
        parts << "--token #{Shellwords.escape(@agent_token)}"
      end

      parts.join(" ")
    end

    def resolve_agent_path
      @installation_node.node.effective_agent_path || "/usr/local/bin/qis-agent"
    end

    def error_result(message)
      Result.new(success: false, error: message)
    end
  end
end
```

**Step 4: Run test to verify it passes**

```bash
bin/rspec spec/services/mlc/trigger_install_service_spec.rb -v
```
Expected: PASS

**Step 5: Commit**

```bash
git add app/services/mlc/trigger_install_service.rb spec/services/mlc/trigger_install_service_spec.rb
git commit -m "feat(service): add Mlc::TriggerInstallService for remote installation"
```

---

### Task 11: Create Mlc::InstallJob

**Files:**
- Create: `app/jobs/mlc/install_job.rb`
- Create: `spec/jobs/mlc/install_job_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/jobs/mlc/install_job_spec.rb
require "rails_helper"

RSpec.describe Mlc::InstallJob, type: :job do
  let(:installation) { create(:mlc_installation) }
  let(:node) { create(:node, :with_ssh_config) }
  let!(:installation_node) { create(:mlc_installation_node, mlc_installation: installation, node: node) }

  describe "#perform" do
    it "updates installation status to running" do
      allow_any_instance_of(Mlc::TriggerInstallService).to receive(:call)
        .and_return(SshExecutionService::Result.new(success: true, output: "INSTALL_STARTED PID=123"))

      described_class.perform_now(installation.id, "http://localhost:3000", "token")

      installation.reload
      expect(installation.status).to eq("running")
    end

    it "processes nodes sequentially by default" do
      trigger_service = instance_double(Mlc::TriggerInstallService)
      allow(Mlc::TriggerInstallService).to receive(:new).and_return(trigger_service)
      allow(trigger_service).to receive(:call)
        .and_return(SshExecutionService::Result.new(success: true, output: "INSTALL_STARTED PID=123"))

      described_class.perform_now(installation.id, "http://localhost:3000", "token")

      expect(trigger_service).to have_received(:call).once
    end
  end
end
```

**Step 2: Run test to verify it fails**

```bash
bin/rspec spec/jobs/mlc/install_job_spec.rb -v
```
Expected: FAIL with "uninitialized constant Mlc::InstallJob"

**Step 3: Write minimal implementation**

```ruby
# app/jobs/mlc/install_job.rb
module Mlc
  class InstallJob < ApplicationJob
    queue_as :default

    def perform(installation_id, server_url, agent_token, user_id: nil)
      @installation = MlcInstallation.find(installation_id)
      @server_url = server_url
      @agent_token = agent_token
      @user_id = user_id

      @installation.update!(status: :running, started_at: Time.current)
      broadcast_status_update

      process_nodes
    rescue StandardError => e
      @installation&.update!(status: :failed, completed_at: Time.current)
      notify_failure(e.message)
      raise
    end

    private

    def process_nodes
      pending_nodes = @installation.mlc_installation_nodes.pending.includes(:node)

      pending_nodes.find_each do |installation_node|
        result = process_single_node(installation_node)

        if !result.success? && @installation.stop_on_first?
          skip_remaining_nodes(pending_nodes.where("id > ?", installation_node.id))
          @installation.update!(status: :failed, completed_at: Time.current)
          notify_failure("Installation stopped: #{result.error}")
          return
        end
      end

      finalize_installation
    end

    def process_single_node(installation_node)
      installation_node.update!(status: :running, started_at: Time.current, step_current: 1, step_name: "Starting")
      broadcast_node_update(installation_node)

      service = TriggerInstallService.new(
        installation: @installation,
        installation_node: installation_node,
        server_url: @server_url,
        agent_token: @agent_token
      )

      result = service.call

      if result.success?
        installation_node.update!(status: :success, completed_at: Time.current, step_current: 7)
      else
        installation_node.update!(status: :failed, completed_at: Time.current, error_message: result.error)
      end

      broadcast_node_update(installation_node)
      result
    end

    def skip_remaining_nodes(nodes)
      nodes.update_all(status: :skipped, completed_at: Time.current)
    end

    def finalize_installation
      if @installation.mlc_installation_nodes.failed.any?
        @installation.update!(status: :failed, completed_at: Time.current)
      else
        @installation.update!(status: :completed, completed_at: Time.current)
      end

      notify_completion
    end

    def broadcast_status_update
      @installation.broadcast_replace_to(
        "mlc_installation_#{@installation.id}",
        target: "mlc_installation_status",
        partial: "mlc_installations/status",
        locals: { installation: @installation }
      )
    end

    def broadcast_node_update(installation_node)
      installation_node.broadcast_replace_to(
        "mlc_installation_#{@installation.id}",
        target: "mlc_installation_node_#{installation_node.id}",
        partial: "mlc_installations/node_status",
        locals: { installation_node: installation_node }
      )
    end

    def notify_completion
      return unless @user_id

      NotificationService.new.notify(
        user_id: @user_id,
        title: "MLC Installation #{@installation.completed? ? 'Complete' : 'Failed'}",
        message: "Installation #{@installation.uuid} finished with status: #{@installation.status}"
      )
    end

    def notify_failure(message)
      return unless @user_id

      NotificationService.new.notify(
        user_id: @user_id,
        title: "MLC Installation Failed",
        message: message
      )
    end
  end
end
```

**Step 4: Run test to verify it passes**

```bash
bin/rspec spec/jobs/mlc/install_job_spec.rb -v
```
Expected: PASS

**Step 5: Commit**

```bash
git add app/jobs/mlc/install_job.rb spec/jobs/mlc/install_job_spec.rb
git commit -m "feat(job): add Mlc::InstallJob for orchestrating installation"
```

---

## Phase 6: API Endpoints

### Task 12: Create API Controller for Progress Updates

**Files:**
- Create: `app/controllers/api/v1/mlc_installations_controller.rb`
- Create: `spec/requests/api/v1/mlc_installations_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/requests/api/v1/mlc_installations_spec.rb
require "rails_helper"

RSpec.describe "Api::V1::MlcInstallations", type: :request do
  let(:api_key) { create(:api_key) }
  let(:headers) { { "Authorization" => "Bearer #{api_key.token}" } }
  let(:installation) { create(:mlc_installation, :running) }
  let(:node) { create(:node) }
  let!(:installation_node) { create(:mlc_installation_node, :running, mlc_installation: installation, node: node) }

  describe "POST /api/v1/mlc_installations/:id/progress" do
    let(:params) do
      {
        node_id: node.uuid,
        step: 4,
        total_steps: 7,
        step_name: "Installing binary",
        status: "running"
      }
    end

    it "updates node progress" do
      post "/api/v1/mlc_installations/#{installation.uuid}/progress", params: params, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      installation_node.reload
      expect(installation_node.step_current).to eq(4)
      expect(installation_node.step_name).to eq("Installing binary")
    end
  end

  describe "POST /api/v1/mlc_installations/:id/complete" do
    context "with success status" do
      let(:params) do
        {
          node_id: node.uuid,
          status: "success",
          detected_version: "3.11",
          install_path: "/opt/qct/utils/qis/software/mlc-3.11",
          module_path: "/opt/qct/utils/qis/modulefiles/mlc/3.11"
        }
      end

      it "marks node as successful" do
        post "/api/v1/mlc_installations/#{installation.uuid}/complete", params: params, headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        installation_node.reload
        expect(installation_node.status).to eq("success")
      end

      it "updates detected version on installation" do
        post "/api/v1/mlc_installations/#{installation.uuid}/complete", params: params, headers: headers, as: :json

        installation.reload
        expect(installation.detected_version).to eq("3.11")
      end
    end

    context "with failed status" do
      let(:params) do
        {
          node_id: node.uuid,
          status: "failed",
          error_message: "Permission denied",
          failed_at_step: 4,
          failed_step_name: "Installing binary"
        }
      end

      it "marks node as failed with error message" do
        post "/api/v1/mlc_installations/#{installation.uuid}/complete", params: params, headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        installation_node.reload
        expect(installation_node.status).to eq("failed")
        expect(installation_node.error_message).to eq("Permission denied")
      end
    end
  end
end
```

**Step 2: Run test to verify it fails**

```bash
bin/rspec spec/requests/api/v1/mlc_installations_spec.rb -v
```
Expected: FAIL with routing error

**Step 3: Add routes**

```ruby
# config/routes.rb - add inside api/v1 namespace
namespace :api do
  namespace :v1 do
    # ... existing routes ...
    resources :mlc_installations, only: [], param: :uuid do
      member do
        post :progress
        post :complete
      end
    end
  end
end
```

**Step 4: Write controller implementation**

```ruby
# app/controllers/api/v1/mlc_installations_controller.rb
module Api
  module V1
    class MlcInstallationsController < BaseController
      before_action :set_installation
      before_action :set_installation_node

      def progress
        @installation_node.update!(
          step_current: params[:step],
          step_total: params[:total_steps],
          step_name: params[:step_name]
        )

        broadcast_progress_update

        render json: { status: "ok" }
      end

      def complete
        if params[:status] == "success"
          handle_success
        else
          handle_failure
        end

        check_installation_complete

        render json: { status: "ok" }
      end

      private

      def set_installation
        @installation = MlcInstallation.find_by!(uuid: params[:uuid])
      end

      def set_installation_node
        node = Node.find_by!(uuid: params[:node_id])
        @installation_node = @installation.mlc_installation_nodes.find_by!(node: node)
      end

      def handle_success
        @installation_node.update!(
          status: :success,
          completed_at: Time.current,
          step_current: @installation_node.step_total
        )

        if params[:detected_version].present? && @installation.detected_version.blank?
          @installation.update!(detected_version: params[:detected_version])
        end
      end

      def handle_failure
        @installation_node.update!(
          status: :failed,
          completed_at: Time.current,
          error_message: params[:error_message],
          step_current: params[:failed_at_step],
          step_name: params[:failed_step_name]
        )
      end

      def check_installation_complete
        return unless @installation.mlc_installation_nodes.pending.empty? &&
                      @installation.mlc_installation_nodes.running.empty?

        if @installation.mlc_installation_nodes.failed.any?
          @installation.update!(status: :failed, completed_at: Time.current)
        else
          @installation.update!(status: :completed, completed_at: Time.current)
        end

        broadcast_installation_complete
      end

      def broadcast_progress_update
        @installation_node.broadcast_replace_to(
          "mlc_installation_#{@installation.id}",
          target: "mlc_installation_node_#{@installation_node.id}",
          partial: "mlc_installations/node_status",
          locals: { installation_node: @installation_node }
        )
      end

      def broadcast_installation_complete
        @installation.broadcast_replace_to(
          "mlc_installation_#{@installation.id}",
          target: "mlc_installation_status",
          partial: "mlc_installations/status",
          locals: { installation: @installation }
        )
      end
    end
  end
end
```

**Step 5: Run test to verify it passes**

```bash
bin/rspec spec/requests/api/v1/mlc_installations_spec.rb -v
```
Expected: PASS

**Step 6: Commit**

```bash
git add config/routes.rb app/controllers/api/v1/mlc_installations_controller.rb spec/requests/api/v1/mlc_installations_spec.rb
git commit -m "feat(api): add MLC installation progress and complete endpoints"
```

---

## Phase 7: Web Interface Controller

### Task 13: Create MlcInstallationsController

**Files:**
- Create: `app/controllers/mlc_installations_controller.rb`
- Create: `spec/requests/mlc_installations_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/requests/mlc_installations_spec.rb
require "rails_helper"

RSpec.describe "MlcInstallations", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /mlc_installations/new" do
    it "renders the new installation form" do
      get new_mlc_installation_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Intel MLC Installation")
    end
  end

  describe "POST /mlc_installations" do
    let(:node) { create(:node, :with_ssh_config) }
    let(:tarball) do
      fixture_file_upload(
        Rails.root.join("spec/fixtures/files/mlc_test.tgz"),
        "application/gzip"
      )
    end

    before do
      # Create test fixture
      FileUtils.mkdir_p(Rails.root.join("spec/fixtures/files"))
      File.write(Rails.root.join("spec/fixtures/files/mlc_test.tgz"), "fake tarball")
    end

    it "creates installation and redirects to show" do
      post mlc_installations_path, params: {
        mlc_installation: {
          source_type: "upload",
          binary_path: "Linux/mlc",
          node_ids: [node.id],
          failure_mode: "stop_on_first"
        },
        tarball: tarball
      }

      expect(response).to have_http_status(:redirect)
      expect(MlcInstallation.count).to eq(1)
    end
  end

  describe "GET /mlc_installations/:id" do
    let(:installation) { create(:mlc_installation, :running, created_by: user) }

    it "renders the installation status" do
      get mlc_installation_path(installation)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(installation.uuid)
    end
  end

  describe "DELETE /mlc_installations/:id" do
    let(:installation) { create(:mlc_installation, :running, created_by: user) }

    it "cancels the installation" do
      delete mlc_installation_path(installation)

      installation.reload
      expect(installation.status).to eq("cancelled")
    end
  end
end
```

**Step 2: Run test to verify it fails**

```bash
bin/rspec spec/requests/mlc_installations_spec.rb -v
```
Expected: FAIL with routing error

**Step 3: Add routes**

```ruby
# config/routes.rb - add at top level
resources :mlc_installations, only: [:new, :create, :show, :destroy] do
  member do
    post :verify_checksum
    get :select_binary
  end
end
```

**Step 4: Write controller implementation**

```ruby
# app/controllers/mlc_installations_controller.rb
class MlcInstallationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_installation, only: [:show, :destroy]

  def new
    @installation = MlcInstallation.new
    @nodes = Node.online.order(:hostname)
  end

  def create
    @installation = MlcInstallation.new(installation_params)
    @installation.created_by = current_user

    if params[:tarball].present?
      upload_result = handle_upload(params[:tarball])
      unless upload_result.success?
        flash.now[:alert] = upload_result.error
        @nodes = Node.online.order(:hostname)
        return render :new, status: :unprocessable_entity
      end

      @installation.source_path = upload_result.stored_path
    end

    if @installation.save
      create_installation_nodes
      enqueue_installation_job

      redirect_to @installation, notice: "Installation started"
    else
      @nodes = Node.online.order(:hostname)
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @installation_nodes = @installation.mlc_installation_nodes.includes(:node)
  end

  def destroy
    @installation.update!(status: :cancelled, completed_at: Time.current)
    @installation.mlc_installation_nodes.pending.update_all(status: :skipped)
    @installation.mlc_installation_nodes.running.update_all(status: :cancelled, completed_at: Time.current)

    redirect_to @installation, notice: "Installation cancelled"
  end

  def verify_checksum
    upload_service = Mlc::UploadService.new(nil)
    upload_service.instance_variable_set(:@result, Mlc::UploadService::Result.new(
      success?: true,
      stored_path: params[:stored_path]
    ))

    verified = upload_service.verify_checksum(params[:algorithm], params[:checksum])

    render json: { verified: verified }
  end

  def select_binary
    extract_dir = extract_tarball_for_selection(params[:stored_path])
    detection_service = Mlc::BinaryDetectionService.new(extract_dir)
    result = detection_service.call

    if result.success?
      render json: { candidates: result.candidates.map(&:to_h) }
    else
      render json: { error: result.error }, status: :unprocessable_entity
    end
  ensure
    FileUtils.rm_rf(extract_dir) if extract_dir
  end

  private

  def set_installation
    @installation = MlcInstallation.find(params[:id])
  end

  def installation_params
    params.require(:mlc_installation).permit(
      :source_type, :source_path, :binary_path,
      :checksum_algorithm, :checksum_value, :checksum_verified,
      :install_dir, :module_dir, :failure_mode,
      node_ids: []
    )
  end

  def handle_upload(uploaded_file)
    upload_service = Mlc::UploadService.new(uploaded_file)
    upload_service.call
    upload_service.result
  end

  def create_installation_nodes
    node_ids = params[:mlc_installation][:node_ids].reject(&:blank?)
    node_ids.each do |node_id|
      @installation.mlc_installation_nodes.create!(node_id: node_id)
    end
  end

  def enqueue_installation_job
    Mlc::InstallJob.perform_later(
      @installation.id,
      server_url,
      agent_token,
      user_id: current_user.id
    )
  end

  def server_url
    request.base_url
  end

  def agent_token
    ApiKey.active.first&.token || ""
  end

  def extract_tarball_for_selection(stored_path)
    extract_dir = Dir.mktmpdir("mlc-select-")
    system("tar", "-xzf", stored_path, "-C", extract_dir)
    extract_dir
  end
end
```

**Step 5: Run test to verify it passes**

```bash
bin/rspec spec/requests/mlc_installations_spec.rb -v
```
Expected: PASS

**Step 6: Commit**

```bash
git add config/routes.rb app/controllers/mlc_installations_controller.rb spec/requests/mlc_installations_spec.rb
git commit -m "feat(controller): add MlcInstallationsController for web interface"
```

---

## Phase 8: Views (Remaining Tasks)

### Task 14-18: Create View Templates

These tasks create the view templates. Each follows the same pattern:

**Task 14:** Create `app/views/mlc_installations/new.html.erb` - Upload form with checksum verification
**Task 15:** Create `app/views/mlc_installations/_binary_selector.html.erb` - Tree view for binary selection
**Task 16:** Create `app/views/mlc_installations/show.html.erb` - Progress display
**Task 17:** Create `app/views/mlc_installations/_node_status.html.erb` - Individual node status partial
**Task 18:** Create `app/views/mlc_installations/_status.html.erb` - Overall status partial

For brevity, I'll outline Task 14 as the template; others follow the same structure.

**Task 14: Create New Installation View**

**Files:**
- Create: `app/views/mlc_installations/new.html.erb`

**Step 1: Create the view**

```erb
<%# app/views/mlc_installations/new.html.erb %>
<%= content_for :title, "Intel MLC Installation" %>

<div class="max-w-4xl mx-auto">
  <h1 class="text-2xl font-bold mb-6">Intel MLC Installation</h1>

  <%= form_with model: @installation, local: true, data: { controller: "mlc-upload" } do |f| %>
    <% if @installation.errors.any? %>
      <div class="bg-red-50 border border-red-200 rounded p-4 mb-6">
        <h3 class="text-red-800 font-medium">Errors:</h3>
        <ul class="list-disc list-inside text-red-700">
          <% @installation.errors.full_messages.each do |msg| %>
            <li><%= msg %></li>
          <% end %>
        </ul>
      </div>
    <% end %>

    <%# Step 1: Source Selection %>
    <div class="bg-white border rounded-lg p-6 mb-6">
      <h2 class="text-lg font-semibold mb-4">Step 1: Upload Tarball</h2>

      <div class="mb-4">
        <%= f.label :source_type, class: "block text-sm font-medium mb-2" %>
        <div class="flex gap-4">
          <%= f.radio_button :source_type, "upload", checked: true, data: { action: "mlc-upload#toggleSource" } %>
          <%= f.label :source_type_upload, "Upload tarball", class: "mr-4" %>
          <%= f.radio_button :source_type, "shared_path", data: { action: "mlc-upload#toggleSource" } %>
          <%= f.label :source_type_shared_path, "Shared storage path" %>
        </div>
      </div>

      <div data-mlc-upload-target="uploadSection">
        <div class="border-2 border-dashed border-gray-300 rounded-lg p-8 text-center"
             data-mlc-upload-target="dropzone"
             data-action="dragover->mlc-upload#dragover drop->mlc-upload#drop">
          <p class="text-gray-600 mb-2">Drag & drop MLC tarball or click to browse</p>
          <%= file_field_tag :tarball, accept: ".tgz,.tar.gz", class: "hidden", data: { mlc_upload_target: "fileInput", action: "change->mlc-upload#handleFile" } %>
          <button type="button" class="btn btn-secondary" data-action="mlc-upload#browse">
            Select File
          </button>
          <p data-mlc-upload-target="fileName" class="mt-2 text-sm text-gray-500"></p>
        </div>
      </div>

      <div data-mlc-upload-target="pathSection" class="hidden">
        <%= f.label :source_path, "Shared path", class: "block text-sm font-medium mb-1" %>
        <%= f.text_field :source_path, placeholder: "/shared/software/mlc.tgz", class: "input w-full" %>
      </div>

      <%# Checksum Verification %>
      <div class="mt-4 pt-4 border-t">
        <h3 class="text-sm font-medium mb-2">Checksum Verification (optional)</h3>
        <div class="flex gap-2 items-end">
          <%= f.select :checksum_algorithm, [["SHA256", "sha256"], ["SHA1", "sha1"], ["MD5", "md5"]], {}, class: "input w-32" %>
          <%= f.text_field :checksum_value, placeholder: "Enter expected checksum", class: "input flex-1", data: { mlc_upload_target: "checksumInput" } %>
          <button type="button" class="btn btn-secondary" data-action="mlc-upload#verifyChecksum" data-mlc-upload-target="verifyBtn" disabled>
            Verify
          </button>
        </div>
        <p data-mlc-upload-target="checksumResult" class="mt-2 text-sm"></p>
      </div>
    </div>

    <%# Step 2: Binary Selection %>
    <div class="bg-white border rounded-lg p-6 mb-6" data-mlc-upload-target="binarySection">
      <h2 class="text-lg font-semibold mb-4">Step 2: Select Binary</h2>
      <div data-mlc-upload-target="binaryTree" class="border rounded p-4 min-h-32">
        <p class="text-gray-500">Upload a tarball to see available binaries</p>
      </div>
      <%= f.hidden_field :binary_path, data: { mlc_upload_target: "binaryPath" } %>
      <p data-mlc-upload-target="versionInfo" class="mt-2 text-sm text-gray-600"></p>
    </div>

    <%# Step 3: Node Selection %>
    <div class="bg-white border rounded-lg p-6 mb-6">
      <h2 class="text-lg font-semibold mb-4">Step 3: Select Target Nodes</h2>

      <div class="max-h-64 overflow-y-auto border rounded p-2">
        <% @nodes.each do |node| %>
          <label class="flex items-center gap-2 p-2 hover:bg-gray-50 rounded">
            <%= check_box_tag "mlc_installation[node_ids][]", node.id, false, class: "rounded" %>
            <span class="flex-1"><%= node.hostname %></span>
            <span class="text-sm <%= node.online? ? 'text-green-600' : 'text-red-600' %>">
              <%= node.online? ? "Online" : "Offline" %>
            </span>
          </label>
        <% end %>
      </div>
    </div>

    <%# Step 4: Options %>
    <div class="bg-white border rounded-lg p-6 mb-6">
      <h2 class="text-lg font-semibold mb-4">Installation Options</h2>

      <div class="mb-4">
        <%= f.label :failure_mode, "On failure", class: "block text-sm font-medium mb-1" %>
        <div class="flex gap-4">
          <%= f.radio_button :failure_mode, "stop_on_first", checked: true %>
          <%= f.label :failure_mode_stop_on_first, "Stop on first failure (recommended)", class: "mr-4" %>
          <%= f.radio_button :failure_mode, "continue_on_failure" %>
          <%= f.label :failure_mode_continue_on_failure, "Continue and report failures at end" %>
        </div>
      </div>
    </div>

    <div class="flex justify-end gap-4">
      <%= link_to "Cancel", root_path, class: "btn btn-secondary" %>
      <%= f.submit "Install", class: "btn btn-primary" %>
    </div>
  <% end %>
</div>
```

**Step 2: Commit**

```bash
git add app/views/mlc_installations/new.html.erb
git commit -m "feat(view): add MLC installation new form"
```

---

## Phase 9: Stimulus Controllers

### Task 19: Create mlc_upload_controller.js

**Files:**
- Create: `app/javascript/controllers/mlc_upload_controller.js`

**Step 1: Create the Stimulus controller**

```javascript
// app/javascript/controllers/mlc_upload_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "uploadSection", "pathSection", "dropzone", "fileInput", "fileName",
    "checksumInput", "checksumResult", "verifyBtn",
    "binarySection", "binaryTree", "binaryPath", "versionInfo"
  ]

  connect() {
    this.storedPath = null
  }

  toggleSource(event) {
    const isUpload = event.target.value === "upload"
    this.uploadSectionTarget.classList.toggle("hidden", !isUpload)
    this.pathSectionTarget.classList.toggle("hidden", isUpload)
  }

  browse() {
    this.fileInputTarget.click()
  }

  dragover(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.add("border-blue-500", "bg-blue-50")
  }

  drop(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.remove("border-blue-500", "bg-blue-50")

    const files = event.dataTransfer.files
    if (files.length > 0) {
      this.fileInputTarget.files = files
      this.handleFile()
    }
  }

  async handleFile() {
    const file = this.fileInputTarget.files[0]
    if (!file) return

    this.fileNameTarget.textContent = `${file.name} (${this.formatSize(file.size)}) ✓ Selected`
    this.verifyBtnTarget.disabled = false

    // Upload file and get stored path
    const formData = new FormData()
    formData.append("tarball", file)

    try {
      const response = await fetch("/mlc_installations/upload_preview", {
        method: "POST",
        body: formData,
        headers: {
          "X-CSRF-Token": document.querySelector("[name='csrf-token']").content
        }
      })

      const data = await response.json()
      if (data.stored_path) {
        this.storedPath = data.stored_path
        this.loadBinaryOptions()
      }
    } catch (error) {
      console.error("Upload error:", error)
    }
  }

  async verifyChecksum() {
    const algorithm = this.element.querySelector("[name='mlc_installation[checksum_algorithm]']").value
    const checksum = this.checksumInputTarget.value

    if (!this.storedPath || !checksum) return

    try {
      const response = await fetch(`/mlc_installations/verify_checksum?stored_path=${encodeURIComponent(this.storedPath)}&algorithm=${algorithm}&checksum=${encodeURIComponent(checksum)}`, {
        headers: {
          "X-CSRF-Token": document.querySelector("[name='csrf-token']").content
        }
      })

      const data = await response.json()

      if (data.verified) {
        this.checksumResultTarget.textContent = "✓ Checksum verified"
        this.checksumResultTarget.className = "mt-2 text-sm text-green-600"
      } else {
        this.checksumResultTarget.textContent = "✗ Checksum mismatch"
        this.checksumResultTarget.className = "mt-2 text-sm text-red-600"
      }
    } catch (error) {
      this.checksumResultTarget.textContent = "Error verifying checksum"
      this.checksumResultTarget.className = "mt-2 text-sm text-red-600"
    }
  }

  async loadBinaryOptions() {
    if (!this.storedPath) return

    try {
      const response = await fetch(`/mlc_installations/select_binary?stored_path=${encodeURIComponent(this.storedPath)}`, {
        headers: {
          "X-CSRF-Token": document.querySelector("[name='csrf-token']").content
        }
      })

      const data = await response.json()

      if (data.candidates) {
        this.renderBinaryTree(data.candidates)
      } else if (data.error) {
        this.binaryTreeTarget.innerHTML = `<p class="text-red-600">${data.error}</p>`
      }
    } catch (error) {
      console.error("Error loading binaries:", error)
    }
  }

  renderBinaryTree(candidates) {
    const html = candidates.map((c, i) => `
      <label class="flex items-center gap-2 p-2 hover:bg-gray-50 rounded cursor-pointer">
        <input type="radio" name="binary_selection" value="${c.relative_path}"
               data-action="change->mlc-upload#selectBinary"
               ${i === 0 ? 'checked' : ''}>
        <span class="font-mono text-sm">${c.relative_path}</span>
        <span class="text-xs text-gray-500">(${c.file_type}, ${this.formatSize(c.size)})</span>
      </label>
    `).join("")

    this.binaryTreeTarget.innerHTML = html

    // Auto-select first option
    if (candidates.length > 0) {
      this.binaryPathTarget.value = candidates[0].relative_path
    }
  }

  selectBinary(event) {
    this.binaryPathTarget.value = event.target.value
  }

  formatSize(bytes) {
    if (bytes < 1024) return `${bytes} B`
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
  }
}
```

**Step 2: Register controller (if not auto-registered)**

**Step 3: Commit**

```bash
git add app/javascript/controllers/mlc_upload_controller.js
git commit -m "feat(js): add mlc-upload Stimulus controller"
```

---

## Phase 10: Integration & Final Testing

### Task 20: Add Integration Tests

**Files:**
- Create: `spec/system/mlc_installation_spec.rb`

**Step 1: Write integration test**

```ruby
# spec/system/mlc_installation_spec.rb
require "rails_helper"

RSpec.describe "MLC Installation", type: :system do
  let(:user) { create(:user) }
  let!(:node) { create(:node, :with_ssh_config, hostname: "compute-001") }

  before do
    sign_in user
    driven_by(:rack_test)
  end

  describe "creating a new installation" do
    it "shows the installation form" do
      visit new_mlc_installation_path

      expect(page).to have_content("Intel MLC Installation")
      expect(page).to have_content("Upload Tarball")
      expect(page).to have_content("Select Target Nodes")
      expect(page).to have_content("compute-001")
    end
  end

  describe "viewing installation progress" do
    let(:installation) { create(:mlc_installation, :running, created_by: user) }
    let!(:installation_node) { create(:mlc_installation_node, :running, mlc_installation: installation, node: node) }

    it "shows progress for each node" do
      visit mlc_installation_path(installation)

      expect(page).to have_content(installation.uuid)
      expect(page).to have_content("compute-001")
      expect(page).to have_content("Running")
    end
  end
end
```

**Step 2: Run test**

```bash
bin/rspec spec/system/mlc_installation_spec.rb -v
```
Expected: PASS

**Step 3: Commit**

```bash
git add spec/system/mlc_installation_spec.rb
git commit -m "test(system): add MLC installation integration tests"
```

---

### Task 21: Run Full Test Suite

**Step 1: Run all Rails tests**

```bash
bin/rspec
```
Expected: All tests pass

**Step 2: Run all Go tests**

```bash
cd agent && go test ./... -v
```
Expected: All tests pass

**Step 3: Run linters**

```bash
bin/rubocop -f github
cd agent && golangci-lint run
```
Expected: No offenses

**Step 4: Final commit**

```bash
git add -A
git commit -m "feat: complete Intel MLC web-triggered installation feature"
```

---

## Summary

This plan implements 21 tasks across 10 phases:

1. **Database Layer** (Tasks 1-2): Migrations for MlcInstallation and MlcInstallationNode
2. **Rails Models** (Tasks 3-4): Models with validations, enums, and associations
3. **Upload Services** (Tasks 5-6): Tarball upload, checksum, and binary detection
4. **Go Agent** (Tasks 7-9): mlc-install command with full workflow
5. **Rails Trigger** (Tasks 10-11): SSH trigger service and background job
6. **API Endpoints** (Task 12): Progress and completion callbacks
7. **Web Controller** (Task 13): Full CRUD for installations
8. **Views** (Tasks 14-18): Upload form, binary selector, progress display
9. **Stimulus** (Task 19): Interactive upload controller
10. **Integration** (Tasks 20-21): System tests and full suite validation

Each task follows TDD with explicit test-first steps, exact file paths, and commit points.
