# Rails CoC Violations Fix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Refactor codebase to follow Rails Convention over Configuration principles

**Architecture:** Extract business logic from controllers into models and concerns. Consolidate duplicate code. Standardize file organization.

**Tech Stack:** Rails 7.2, RSpec, RuboCop

---

## Task 1: Create RangeOverlap Concern (Extract Duplicate Logic)

**Files:**
- Create: `app/models/concerns/range_overlap.rb`
- Modify: `app/models/node.rb:183-185`
- Modify: `app/services/racks/validate_layout_service.rb:71-73`
- Create: `spec/models/concerns/range_overlap_spec.rb`

**Step 1: Write the failing test**

Create `spec/models/concerns/range_overlap_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe RangeOverlap do
  let(:test_class) do
    Class.new do
      include RangeOverlap
    end
  end

  subject(:instance) { test_class.new }

  describe "#ranges_overlap?" do
    it "returns true when ranges overlap completely" do
      expect(instance.ranges_overlap?(1, 5, 2, 4)).to be true
    end

    it "returns true when ranges overlap partially" do
      expect(instance.ranges_overlap?(1, 5, 4, 8)).to be true
    end

    it "returns true when ranges share an edge" do
      expect(instance.ranges_overlap?(1, 5, 5, 8)).to be true
    end

    it "returns false when ranges do not overlap" do
      expect(instance.ranges_overlap?(1, 5, 6, 10)).to be false
    end

    it "returns true when one range contains another" do
      expect(instance.ranges_overlap?(1, 10, 3, 7)).to be true
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/models/concerns/range_overlap_spec.rb`
Expected: FAIL with "uninitialized constant RangeOverlap"

**Step 3: Write minimal implementation**

Create `app/models/concerns/range_overlap.rb`:

```ruby
# frozen_string_literal: true

module RangeOverlap
  extend ActiveSupport::Concern

  # Checks if two ranges overlap (inclusive boundaries)
  # @param a_start [Integer] Start of first range
  # @param a_end [Integer] End of first range
  # @param b_start [Integer] Start of second range
  # @param b_end [Integer] End of second range
  # @return [Boolean] true if ranges overlap
  def ranges_overlap?(a_start, a_end, b_start, b_end)
    a_start <= b_end && b_start <= a_end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rspec spec/models/concerns/range_overlap_spec.rb`
Expected: PASS

**Step 5: Update Node model to use concern**

Modify `app/models/node.rb`:
- Add `include RangeOverlap` after class declaration
- Remove the private `ranges_overlap?` method (lines 183-185)

**Step 6: Update ValidateLayoutService to use concern**

Modify `app/services/racks/validate_layout_service.rb`:
- Add `include RangeOverlap` inside the class
- Remove the private `ranges_overlap?` method (lines 71-73)

**Step 7: Run existing tests to verify no regressions**

Run: `bin/rspec spec/models/node_spec.rb spec/services/racks/validate_layout_service_spec.rb`
Expected: All PASS

**Step 8: Run RuboCop**

Run: `bin/rubocop app/models/concerns/range_overlap.rb app/models/node.rb app/services/racks/validate_layout_service.rb`
Expected: No offenses

**Step 9: Commit**

```bash
git add app/models/concerns/range_overlap.rb spec/models/concerns/range_overlap_spec.rb app/models/node.rb app/services/racks/validate_layout_service.rb
git commit -m "$(cat <<'EOF'
refactor: extract ranges_overlap? to shared concern

DRY violation fix - both Node model and ValidateLayoutService
had identical implementations. Now both include RangeOverlap concern.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Move Benchmark::RunForm to app/forms

**Files:**
- Move: `app/models/benchmark/run_form.rb` → `app/forms/benchmark/run_form.rb`
- Verify: `spec/models/benchmark/run_form_spec.rb` still passes

**Step 1: Create forms/benchmark directory**

Run: `mkdir -p app/forms/benchmark`

**Step 2: Move the file**

Run: `git mv app/models/benchmark/run_form.rb app/forms/benchmark/run_form.rb`

**Step 3: Run existing tests**

Run: `bin/rspec spec/models/benchmark/run_form_spec.rb`
Expected: PASS (Rails autoloads from app/forms)

**Step 4: Run RuboCop**

Run: `bin/rubocop app/forms/benchmark/run_form.rb`
Expected: No offenses

**Step 5: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
refactor: move Benchmark::RunForm to app/forms

Consistent with Profiling::RunForm location. Form objects using
ActiveModel::Model belong in app/forms per Rails convention.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Extract Artifact Path Validation to Model

**Files:**
- Modify: `app/models/artifact_index.rb`
- Modify: `app/controllers/benchmark_runs_controller.rb:89-134`
- Modify: `spec/models/artifact_index_spec.rb`

**Step 1: Write the failing test**

Add to `spec/models/artifact_index_spec.rb`:

```ruby
describe "#safe_download_path" do
  let(:benchmark_run) { create(:benchmark_run) }

  context "with stored_path" do
    let(:artifact) { create(:artifact_index, benchmark_run: benchmark_run, stored_path: stored_path, path: "/legacy/path") }

    context "when file exists in storage" do
      let(:stored_path) { Rails.root.join("storage", "artifacts", "test.txt").to_s }

      before do
        FileUtils.mkdir_p(File.dirname(stored_path))
        File.write(stored_path, "test content")
      end

      after { FileUtils.rm_f(stored_path) }

      it "returns the stored_path" do
        expect(artifact.safe_download_path).to eq(stored_path)
      end
    end

    context "when stored file does not exist" do
      let(:stored_path) { "/storage/artifacts/nonexistent.txt" }

      it "returns nil" do
        expect(artifact.safe_download_path).to be_nil
      end
    end
  end

  context "with path traversal attempt" do
    let(:artifact) { create(:artifact_index, benchmark_run: benchmark_run, stored_path: "/storage/artifacts/../../../etc/passwd") }

    it "returns nil" do
      expect(artifact.safe_download_path).to be_nil
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/models/artifact_index_spec.rb -e "safe_download_path"`
Expected: FAIL with "undefined method safe_download_path"

**Step 3: Write implementation in model**

Add to `app/models/artifact_index.rb`:

```ruby
# Returns validated path for safe file download
# Prefers stored_path (server-managed) over legacy path
# @return [String, nil] Safe file path or nil if invalid/missing
def safe_download_path
  validate_stored_path || validate_legacy_path
end

private

def validate_stored_path
  return nil if stored_path.blank?

  storage_base = Rails.configuration.x.artifacts_storage_path.presence ||
                 Rails.root.join("storage", "artifacts").to_s

  clean_path = Pathname.new(stored_path).cleanpath.to_s

  return nil unless clean_path.start_with?(storage_base)
  return nil unless File.file?(clean_path)

  clean_path
end

def validate_legacy_path
  return nil if path.blank?

  base_path = Rails.configuration.x.artifacts_base_path
  base_path = "/shared/artifacts" unless base_path.is_a?(String) && base_path.present?

  allowed_base = Pathname.new(base_path).cleanpath.to_s
  clean_path = Pathname.new(path).cleanpath.to_s

  return nil unless clean_path.start_with?(allowed_base + File::SEPARATOR) || clean_path == allowed_base
  return nil unless File.file?(clean_path)

  clean_path
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rspec spec/models/artifact_index_spec.rb -e "safe_download_path"`
Expected: PASS

**Step 5: Update controller to use model method**

Replace in `app/controllers/benchmark_runs_controller.rb` the `download_artifact` action:

```ruby
def download_artifact
  @benchmark_run = BenchmarkRun.find(params[:id])
  @artifact = @benchmark_run.artifact_indices.find(params[:artifact_id])

  safe_path = @artifact.safe_download_path
  unless safe_path
    flash[:alert] = "Artifact file not found on server."
    redirect_to benchmark_run_path(@benchmark_run) and return
  end

  send_file safe_path,
            filename: @artifact.filename,
            type: @artifact.mime_type,
            disposition: "attachment"
end
```

Remove private methods: `validated_artifact_path`, `validate_stored_path`, `validate_legacy_path`

**Step 6: Run controller spec**

Run: `bin/rspec spec/requests/benchmark_runs_spec.rb`
Expected: PASS

**Step 7: Commit**

```bash
git add app/models/artifact_index.rb app/controllers/benchmark_runs_controller.rb spec/models/artifact_index_spec.rb
git commit -m "$(cat <<'EOF'
refactor: move artifact path validation to ArtifactIndex model

Controller was too fat - path validation logic belongs in model.
Added safe_download_path method with security checks.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Extract MIME Type to Model

**Files:**
- Modify: `app/models/artifact_index.rb`
- Modify: `app/controllers/benchmark_runs_controller.rb:136-155`
- Modify: `spec/models/artifact_index_spec.rb`

**Step 1: Write the failing test**

Add to `spec/models/artifact_index_spec.rb`:

```ruby
describe "#mime_type" do
  let(:benchmark_run) { create(:benchmark_run) }

  {
    "txt" => "text/plain",
    "log" => "text/plain",
    "dat" => "text/plain",
    "yaml" => "text/yaml",
    "yml" => "text/yaml",
    "json" => "application/json",
    "csv" => "text/csv",
    "pdf" => "application/pdf",
    "tar" => "application/gzip",
    "gz" => "application/gzip",
    "tgz" => "application/gzip",
    "zip" => "application/zip",
    "unknown" => "application/octet-stream"
  }.each do |file_type, expected_mime|
    it "returns #{expected_mime} for #{file_type}" do
      artifact = build(:artifact_index, benchmark_run: benchmark_run, file_type: file_type)
      expect(artifact.mime_type).to eq(expected_mime)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/models/artifact_index_spec.rb -e "mime_type"`
Expected: FAIL with "undefined method mime_type"

**Step 3: Write implementation**

Add to `app/models/artifact_index.rb`:

```ruby
MIME_TYPES = {
  "txt" => "text/plain",
  "log" => "text/plain",
  "dat" => "text/plain",
  "yaml" => "text/yaml",
  "yml" => "text/yaml",
  "json" => "application/json",
  "csv" => "text/csv",
  "pdf" => "application/pdf",
  "tar" => "application/gzip",
  "gz" => "application/gzip",
  "tgz" => "application/gzip",
  "zip" => "application/zip"
}.freeze

# Returns MIME type based on file_type
# @return [String] MIME type string
def mime_type
  MIME_TYPES[file_type.to_s.downcase] || "application/octet-stream"
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rspec spec/models/artifact_index_spec.rb -e "mime_type"`
Expected: PASS

**Step 5: Remove mime_type_for from controller**

Delete the `mime_type_for` private method (lines 136-155) from `app/controllers/benchmark_runs_controller.rb`

**Step 6: Run all tests**

Run: `bin/rspec spec/models/artifact_index_spec.rb spec/requests/benchmark_runs_spec.rb`
Expected: All PASS

**Step 7: Commit**

```bash
git add app/models/artifact_index.rb app/controllers/benchmark_runs_controller.rb spec/models/artifact_index_spec.rb
git commit -m "$(cat <<'EOF'
refactor: move MIME type mapping to ArtifactIndex model

MIME types are a property of the artifact, not controller concern.
Added MIME_TYPES constant and mime_type instance method.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Add Agent Status Mapping to BenchmarkRun Model

**Files:**
- Modify: `app/models/benchmark_run.rb`
- Modify: `app/controllers/api/v1/benchmark_runs_controller.rb:32-41`
- Modify: `spec/models/benchmark_run_spec.rb`

**Step 1: Write the failing test**

Add to `spec/models/benchmark_run_spec.rb`:

```ruby
describe ".status_from_agent" do
  it "maps PASS to success" do
    expect(BenchmarkRun.status_from_agent("PASS")).to eq(:success)
  end

  it "maps FAIL to failed" do
    expect(BenchmarkRun.status_from_agent("FAIL")).to eq(:failed)
  end

  it "maps ERROR to failed" do
    expect(BenchmarkRun.status_from_agent("ERROR")).to eq(:failed)
  end

  it "maps RUNNING to running" do
    expect(BenchmarkRun.status_from_agent("RUNNING")).to eq(:running)
  end

  it "returns nil for unknown status" do
    expect(BenchmarkRun.status_from_agent("UNKNOWN")).to be_nil
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/models/benchmark_run_spec.rb -e "status_from_agent"`
Expected: FAIL with "undefined method status_from_agent"

**Step 3: Write implementation**

Add to `app/models/benchmark_run.rb` after enum declaration:

```ruby
# Maps agent-reported status strings to model status symbols
AGENT_STATUS_MAP = {
  "PASS" => :success,
  "FAIL" => :failed,
  "ERROR" => :failed,
  "RUNNING" => :running
}.freeze

# Converts agent status string to model status symbol
# @param agent_status [String] Status from agent (PASS, FAIL, ERROR, RUNNING)
# @return [Symbol, nil] Model status symbol or nil if unknown
def self.status_from_agent(agent_status)
  AGENT_STATUS_MAP[agent_status]
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rspec spec/models/benchmark_run_spec.rb -e "status_from_agent"`
Expected: PASS

**Step 5: Update API controller**

In `app/controllers/api/v1/benchmark_runs_controller.rb`, replace the inline status_map:

```ruby
# Before:
status_map = { "PASS" => :success, ... }
new_status = status_map[params[:status]]

# After:
new_status = BenchmarkRun.status_from_agent(params[:status])
```

**Step 6: Run API spec**

Run: `bin/rspec spec/requests/api/v1/benchmark_runs_spec.rb`
Expected: PASS

**Step 7: Commit**

```bash
git add app/models/benchmark_run.rb app/controllers/api/v1/benchmark_runs_controller.rb spec/models/benchmark_run_spec.rb
git commit -m "$(cat <<'EOF'
refactor: move agent status mapping to BenchmarkRun model

Status mapping is domain logic belonging to the model.
Added AGENT_STATUS_MAP constant and status_from_agent class method.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Add Dashboard Scope to BenchmarkRun

**Files:**
- Modify: `app/models/benchmark_run.rb`
- Modify: `app/controllers/dashboard_controller.rb:26-29`
- Modify: `spec/models/benchmark_run_spec.rb`

**Step 1: Write the failing test**

Add to `spec/models/benchmark_run_spec.rb`:

```ruby
describe ".recent_for_dashboard" do
  let!(:node1) { create(:node) }
  let!(:node2) { create(:node) }
  let!(:recipe) { create(:benchmark_recipe) }
  let!(:run1) { create(:benchmark_run, node: node1, benchmark_recipe: recipe, created_at: 1.hour.ago) }
  let!(:run2) { create(:benchmark_run, node: node1, benchmark_recipe: recipe, created_at: 2.hours.ago) }
  let!(:run3) { create(:benchmark_run, node: node2, benchmark_recipe: recipe, created_at: 30.minutes.ago) }

  context "without node filter" do
    it "returns recent runs limited to 10" do
      runs = BenchmarkRun.recent_for_dashboard
      expect(runs).to eq([run3, run1, run2])
    end

    it "includes node and recipe associations" do
      runs = BenchmarkRun.recent_for_dashboard
      expect(runs.first.association(:node).loaded?).to be true
      expect(runs.first.association(:benchmark_recipe).loaded?).to be true
    end
  end

  context "with node filter" do
    it "returns only runs for specified node" do
      runs = BenchmarkRun.recent_for_dashboard(node1)
      expect(runs).to eq([run1, run2])
      expect(runs).not_to include(run3)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/models/benchmark_run_spec.rb -e "recent_for_dashboard"`
Expected: FAIL with "undefined method recent_for_dashboard"

**Step 3: Write implementation**

Add to `app/models/benchmark_run.rb` in scopes section:

```ruby
scope :recent_for_dashboard, ->(node = nil) {
  scope = recent.includes(:node, :benchmark_recipe)
  scope = scope.for_node(node) if node
  scope.limit(10)
}
```

**Step 4: Run test to verify it passes**

Run: `bin/rspec spec/models/benchmark_run_spec.rb -e "recent_for_dashboard"`
Expected: PASS

**Step 5: Update DashboardController**

In `app/controllers/dashboard_controller.rb`, replace lines 26-29:

```ruby
# Before:
runs_scope = BenchmarkRun.recent.includes(:node, :benchmark_recipe)
runs_scope = runs_scope.for_node(@selected_node) if @selected_node
@filtered_runs = runs_scope.limit(10)

# After:
@filtered_runs = BenchmarkRun.recent_for_dashboard(@selected_node)
```

**Step 6: Run dashboard spec**

Run: `bin/rspec spec/requests/dashboard_spec.rb`
Expected: PASS

**Step 7: Commit**

```bash
git add app/models/benchmark_run.rb app/controllers/dashboard_controller.rb spec/models/benchmark_run_spec.rb
git commit -m "$(cat <<'EOF'
refactor: add recent_for_dashboard scope to BenchmarkRun

Query composition belongs in model scopes, not controllers.
New scope handles filtering, eager loading, and limiting.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Final Verification

**Step 1: Run full test suite**

Run: `bin/rspec`
Expected: All tests PASS

**Step 2: Run RuboCop**

Run: `bin/rubocop -f github`
Expected: No offenses

**Step 3: Run Brakeman security scan**

Run: `bin/brakeman`
Expected: No new warnings

**Step 4: Update design document status**

Change status in `docs/plans/2026-01-24-rails-coc-violations-design.md`:
- Status: Review Complete → Implementation Complete

**Step 5: Final commit**

```bash
git add docs/plans/
git commit -m "$(cat <<'EOF'
docs: mark Rails CoC violations implementation complete

All high-priority violations addressed:
- Created RangeOverlap concern (DRY)
- Moved Benchmark::RunForm to app/forms
- Extracted artifact path validation to model
- Extracted MIME type mapping to model
- Added agent status mapping to model
- Added dashboard scope to model

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Summary

| Task | Description | Estimated Complexity |
|------|-------------|---------------------|
| 1 | Extract RangeOverlap concern | Low |
| 2 | Move Benchmark::RunForm | Low |
| 3 | Extract artifact path validation | Medium |
| 4 | Extract MIME type to model | Low |
| 5 | Add agent status mapping | Low |
| 6 | Add dashboard scope | Low |
| 7 | Final verification | Low |

**Not included in this plan (lower priority):**
- Table rename (racks → server_racks) - requires migration, can defer
- Column renames (u_height, desc_units) - requires migration, can defer
- Inconsistent bastion/jump naming - requires coordination with ssh_profiles feature branch
