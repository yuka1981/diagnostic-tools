# Intel PerfSPECT Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Integrate Intel PerfSPECT system profiling via Ansible playbooks, with quick profiles on node details page and full recipe support.

**Architecture:** Rails triggers Ansible playbooks via SSH to an admin node, which executes PerfSPECT on target compute nodes. Results flow back via API callbacks and shared filesystem.

**Tech Stack:** Rails 7.2, PostgreSQL, Hotwire/Turbo, Ansible, Intel PerfSPECT (Lmodules)

---

## Phase 1: Foundation (Models & Migrations)

### Task 1.1: Create ProfilingRecipe Migration

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_create_profiling_recipes.rb`

**Step 1: Generate migration**

Run: `bin/rails generate migration CreateProfilingRecipes`

**Step 2: Edit migration file**

```ruby
# frozen_string_literal: true

class CreateProfilingRecipes < ActiveRecord::Migration[7.2]
  def change
    create_table :profiling_recipes do |t|
      t.string :name, null: false, limit: 100
      t.string :slug, null: false
      t.text :description
      t.string :tool, null: false, default: "perfspect"
      t.string :subcommand, null: false
      t.string :module_name, null: false, default: "perfspect/3.13.0"
      t.jsonb :default_options, default: {}
      t.integer :timeout_seconds, default: 300
      t.integer :status, default: 0, null: false

      t.timestamps
    end

    add_index :profiling_recipes, :slug, unique: true
    add_index :profiling_recipes, :tool
    add_index :profiling_recipes, :status
  end
end
```

**Step 3: Run migration**

Run: `bin/rails db:migrate`
Expected: Migration succeeds, schema.rb updated

**Step 4: Commit**

```bash
git add db/migrate/*_create_profiling_recipes.rb db/schema.rb
git commit -m "feat(profiling): add profiling_recipes table"
```

---

### Task 1.2: Create ProfilingRun Migration

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_create_profiling_runs.rb`

**Step 1: Generate migration**

Run: `bin/rails generate migration CreateProfilingRuns`

**Step 2: Edit migration file**

```ruby
# frozen_string_literal: true

class CreateProfilingRuns < ActiveRecord::Migration[7.2]
  def change
    create_table :profiling_runs do |t|
      t.uuid :uuid, default: -> { "gen_random_uuid()" }, null: false
      t.references :node, null: false, foreign_key: true
      t.references :profiling_recipe, foreign_key: true
      t.references :user, foreign_key: true
      t.integer :status, default: 0, null: false
      t.string :subcommand, null: false
      t.jsonb :options, default: {}
      t.jsonb :metrics, default: {}
      t.datetime :started_at
      t.datetime :finished_at
      t.text :log_content
      t.text :error_message
      t.string :artifact_path

      t.timestamps
    end

    add_index :profiling_runs, :uuid, unique: true
    add_index :profiling_runs, :status
    add_index :profiling_runs, [:node_id, :created_at], order: { created_at: :desc }
  end
end
```

**Step 3: Run migration**

Run: `bin/rails db:migrate`
Expected: Migration succeeds

**Step 4: Commit**

```bash
git add db/migrate/*_create_profiling_runs.rb db/schema.rb
git commit -m "feat(profiling): add profiling_runs table"
```

---

### Task 1.3: Create ProfilingArtifact Migration

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_create_profiling_artifacts.rb`

**Step 1: Generate migration**

Run: `bin/rails generate migration CreateProfilingArtifacts`

**Step 2: Edit migration file**

```ruby
# frozen_string_literal: true

class CreateProfilingArtifacts < ActiveRecord::Migration[7.2]
  def change
    create_table :profiling_artifacts do |t|
      t.references :profiling_run, null: false, foreign_key: true
      t.string :filename, null: false
      t.string :file_type
      t.string :file_path
      t.bigint :file_size

      t.timestamps
    end

    add_index :profiling_artifacts, [:profiling_run_id, :filename], unique: true
  end
end
```

**Step 3: Run migration**

Run: `bin/rails db:migrate`
Expected: Migration succeeds

**Step 4: Commit**

```bash
git add db/migrate/*_create_profiling_artifacts.rb db/schema.rb
git commit -m "feat(profiling): add profiling_artifacts table"
```

---

### Task 1.4: Create ProfilingRecipe Model

**Files:**
- Create: `app/models/profiling_recipe.rb`
- Test: `spec/models/profiling_recipe_spec.rb`
- Create: `spec/factories/profiling_recipes.rb`

**Step 1: Write the failing test**

Create `spec/models/profiling_recipe_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProfilingRecipe, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:profiling_runs).dependent(:restrict_with_error) }
  end

  describe "validations" do
    subject { build(:profiling_recipe) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:subcommand) }
    it { is_expected.to validate_presence_of(:module_name) }
    it { is_expected.to validate_uniqueness_of(:slug) }
    it { is_expected.to validate_inclusion_of(:subcommand).in_array(%w[report telemetry flame]) }
  end

  describe "enums" do
    it "defines active and archived statuses" do
      expect(ProfilingRecipe.statuses).to eq({ "active" => 0, "archived" => 1 })
    end
  end

  describe "callbacks" do
    it "generates slug from name if blank" do
      recipe = create(:profiling_recipe, name: "Quick System Report", slug: nil)
      expect(recipe.slug).to eq("quick-system-report")
    end
  end

  describe "#display_name" do
    it "returns formatted name with tool" do
      recipe = build(:profiling_recipe, name: "System Report", tool: "perfspect")
      expect(recipe.display_name).to eq("System Report (perfspect)")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/models/profiling_recipe_spec.rb`
Expected: FAIL with "uninitialized constant ProfilingRecipe"

**Step 3: Create factory**

Create `spec/factories/profiling_recipes.rb`:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :profiling_recipe do
    sequence(:name) { |n| "profiling-recipe-#{n}" }
    sequence(:slug) { |n| "profiling-recipe-#{n}" }
    tool { "perfspect" }
    subcommand { "report" }
    module_name { "perfspect/3.13.0" }
    default_options { {} }
    timeout_seconds { 300 }
    status { :active }

    trait :report do
      name { "Quick System Report" }
      slug { "quick-system-report" }
      subcommand { "report" }
      description { "Collect system configuration snapshot" }
    end

    trait :telemetry do
      name { "Performance Telemetry" }
      slug { "performance-telemetry" }
      subcommand { "telemetry" }
      description { "Collect live performance metrics" }
      default_options { { "duration" => 60 } }
    end

    trait :flame do
      name { "CPU Flame Graph" }
      slug { "cpu-flame-graph" }
      subcommand { "flame" }
      description { "Generate CPU flame graph" }
      default_options { { "duration" => 30 } }
    end

    trait :archived do
      status { :archived }
    end
  end
end
```

**Step 4: Write model implementation**

Create `app/models/profiling_recipe.rb`:

```ruby
# frozen_string_literal: true

class ProfilingRecipe < ApplicationRecord
  # Associations
  has_many :profiling_runs, dependent: :restrict_with_error

  # Enums
  enum :status, { active: 0, archived: 1 }, default: :active

  # Validations
  validates :name, presence: true, length: { maximum: 100 }
  validates :subcommand, presence: true, inclusion: { in: %w[report telemetry flame] }
  validates :module_name, presence: true
  validates :slug, uniqueness: true

  # Callbacks
  before_validation :generate_slug, if: -> { slug.blank? }

  # Scopes
  scope :by_tool, ->(tool) { where(tool: tool) }

  # Instance methods
  def display_name
    "#{name} (#{tool})"
  end

  private

  def generate_slug
    self.slug = name.parameterize if name.present?
  end
end
```

**Step 5: Run test to verify it passes**

Run: `bin/rspec spec/models/profiling_recipe_spec.rb`
Expected: All tests pass

**Step 6: Commit**

```bash
git add app/models/profiling_recipe.rb spec/models/profiling_recipe_spec.rb spec/factories/profiling_recipes.rb
git commit -m "feat(profiling): add ProfilingRecipe model with validations"
```

---

### Task 1.5: Create ProfilingRun Model

**Files:**
- Create: `app/models/profiling_run.rb`
- Test: `spec/models/profiling_run_spec.rb`
- Create: `spec/factories/profiling_runs.rb`

**Step 1: Write the failing test**

Create `spec/models/profiling_run_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProfilingRun, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:node) }
    it { is_expected.to belong_to(:profiling_recipe).optional }
    it { is_expected.to belong_to(:user).optional }
    it { is_expected.to have_many(:profiling_artifacts).dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_presence_of(:subcommand) }
    it { is_expected.to validate_presence_of(:uuid) }
  end

  describe "enums" do
    it "defines status values" do
      expect(ProfilingRun.statuses).to eq({
        "pending" => 0,
        "running" => 1,
        "success" => 2,
        "failed" => 3,
        "cancelled" => 4
      })
    end
  end

  describe "scopes" do
    let(:node) { create(:node) }

    describe ".recent" do
      it "orders by created_at descending" do
        old_run = create(:profiling_run, node: node, created_at: 1.hour.ago)
        new_run = create(:profiling_run, node: node, created_at: 1.minute.ago)
        expect(ProfilingRun.recent.first).to eq(new_run)
      end
    end

    describe ".for_node" do
      it "returns runs for specified node" do
        run = create(:profiling_run, node: node)
        other_run = create(:profiling_run)
        expect(ProfilingRun.for_node(node)).to contain_exactly(run)
      end
    end
  end

  describe "#duration" do
    it "returns nil when not completed" do
      run = build(:profiling_run, :running)
      expect(run.duration).to be_nil
    end

    it "returns duration in seconds when completed" do
      run = build(:profiling_run, started_at: 1.hour.ago, finished_at: Time.current)
      expect(run.duration).to be_within(1).of(3600)
    end
  end

  describe "#completed?" do
    it "returns true for success" do
      expect(build(:profiling_run, status: :success).completed?).to be true
    end

    it "returns true for failed" do
      expect(build(:profiling_run, status: :failed).completed?).to be true
    end

    it "returns false for running" do
      expect(build(:profiling_run, status: :running).completed?).to be false
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/models/profiling_run_spec.rb`
Expected: FAIL

**Step 3: Create factory**

Create `spec/factories/profiling_runs.rb`:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :profiling_run do
    association :node
    association :profiling_recipe, factory: [:profiling_recipe, :report]
    subcommand { "report" }
    status { :pending }
    options { {} }

    trait :running do
      status { :running }
      started_at { 5.minutes.ago }
    end

    trait :success do
      status { :success }
      started_at { 10.minutes.ago }
      finished_at { 5.minutes.ago }
      metrics do
        {
          "cpu_model" => "Intel Xeon Gold 6248",
          "cores" => 40,
          "turbo_enabled" => true
        }
      end
    end

    trait :failed do
      status { :failed }
      started_at { 10.minutes.ago }
      finished_at { 9.minutes.ago }
      error_message { "Module perfspect/3.13.0 not found" }
    end

    trait :cancelled do
      status { :cancelled }
      started_at { 10.minutes.ago }
      finished_at { 8.minutes.ago }
    end

    trait :telemetry do
      subcommand { "telemetry" }
      options { { "duration" => 60 } }
    end

    trait :flame do
      subcommand { "flame" }
      options { { "duration" => 30 } }
    end

    trait :custom do
      profiling_recipe { nil }
    end
  end
end
```

**Step 4: Write model implementation**

Create `app/models/profiling_run.rb`:

```ruby
# frozen_string_literal: true

class ProfilingRun < ApplicationRecord
  # Associations
  belongs_to :node
  belongs_to :profiling_recipe, optional: true
  belongs_to :user, optional: true
  has_many :profiling_artifacts, dependent: :destroy

  # Enums
  enum :status, {
    pending: 0,
    running: 1,
    success: 2,
    failed: 3,
    cancelled: 4
  }, default: :pending

  # Validations
  validates :status, presence: true
  validates :subcommand, presence: true
  validates :uuid, presence: true, uniqueness: true

  # Callbacks
  before_validation :generate_uuid, on: :create
  after_create_commit :broadcast_new_run
  after_update_commit :broadcast_status_update

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :completed, -> { where(status: %i[success failed cancelled]) }
  scope :for_node, ->(node) { where(node: node) }

  # Instance methods
  def duration
    return nil unless finished_at && started_at

    finished_at - started_at
  end

  def completed?
    success? || failed? || cancelled?
  end

  private

  def generate_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def broadcast_new_run
    broadcast_prepend_to(
      node,
      target: "profiling_runs_tbody",
      partial: "profiling_runs/run_row",
      locals: { run: self }
    )
  end

  def broadcast_status_update
    broadcast_replace_to(
      node,
      target: "profiling_run_#{id}",
      partial: "profiling_runs/run_row",
      locals: { run: self }
    )
  end
end
```

**Step 5: Run test to verify it passes**

Run: `bin/rspec spec/models/profiling_run_spec.rb`
Expected: All tests pass

**Step 6: Commit**

```bash
git add app/models/profiling_run.rb spec/models/profiling_run_spec.rb spec/factories/profiling_runs.rb
git commit -m "feat(profiling): add ProfilingRun model with validations"
```

---

### Task 1.6: Create ProfilingArtifact Model

**Files:**
- Create: `app/models/profiling_artifact.rb`
- Test: `spec/models/profiling_artifact_spec.rb`
- Create: `spec/factories/profiling_artifacts.rb`

**Step 1: Write the failing test**

Create `spec/models/profiling_artifact_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProfilingArtifact, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:profiling_run) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:filename) }
  end

  describe "#downloadable?" do
    it "returns true when file exists" do
      artifact = build(:profiling_artifact, file_path: __FILE__)
      expect(artifact.downloadable?).to be true
    end

    it "returns false when file does not exist" do
      artifact = build(:profiling_artifact, file_path: "/nonexistent/file.html")
      expect(artifact.downloadable?).to be false
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/models/profiling_artifact_spec.rb`
Expected: FAIL

**Step 3: Create factory**

Create `spec/factories/profiling_artifacts.rb`:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :profiling_artifact do
    association :profiling_run
    sequence(:filename) { |n| "report_#{n}.html" }
    file_type { "html" }
    file_path { "/shared/profiling/#{SecureRandom.uuid}/report.html" }
    file_size { 12345 }

    trait :html_report do
      filename { "system_report.html" }
      file_type { "html" }
    end

    trait :json_data do
      filename { "metrics.json" }
      file_type { "json" }
    end

    trait :flame_graph do
      filename { "flamegraph.svg" }
      file_type { "svg" }
    end
  end
end
```

**Step 4: Write model implementation**

Create `app/models/profiling_artifact.rb`:

```ruby
# frozen_string_literal: true

class ProfilingArtifact < ApplicationRecord
  belongs_to :profiling_run

  validates :filename, presence: true

  def downloadable?
    file_path.present? && File.exist?(file_path)
  end

  def content_type
    case file_type
    when "html" then "text/html"
    when "json" then "application/json"
    when "svg" then "image/svg+xml"
    else "application/octet-stream"
    end
  end
end
```

**Step 5: Run test to verify it passes**

Run: `bin/rspec spec/models/profiling_artifact_spec.rb`
Expected: All tests pass

**Step 6: Commit**

```bash
git add app/models/profiling_artifact.rb spec/models/profiling_artifact_spec.rb spec/factories/profiling_artifacts.rb
git commit -m "feat(profiling): add ProfilingArtifact model"
```

---

### Task 1.7: Add Node Association

**Files:**
- Modify: `app/models/node.rb`

**Step 1: Write the failing test**

Add to existing `spec/models/node_spec.rb`:

```ruby
describe "profiling associations" do
  it { is_expected.to have_many(:profiling_runs).dependent(:destroy) }
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/models/node_spec.rb -e "profiling associations"`
Expected: FAIL

**Step 3: Add association to Node model**

In `app/models/node.rb`, add inside the class after other `has_many` declarations:

```ruby
has_many :profiling_runs, dependent: :destroy
```

**Step 4: Run test to verify it passes**

Run: `bin/rspec spec/models/node_spec.rb -e "profiling associations"`
Expected: PASS

**Step 5: Commit**

```bash
git add app/models/node.rb spec/models/node_spec.rb
git commit -m "feat(profiling): add profiling_runs association to Node"
```

---

## Phase 2: Ansible Infrastructure

### Task 2.1: Create Ansible Directory Structure

**Files:**
- Create: `ansible/inventory/.gitkeep`
- Create: `ansible/playbooks/perfspect/.gitkeep`
- Create: `ansible/roles/perfspect/tasks/main.yml`
- Create: `ansible/roles/perfspect/defaults/main.yml`
- Create: `ansible/callback_plugins/.gitkeep`

**Step 1: Create directory structure**

Run:
```bash
mkdir -p ansible/{inventory,playbooks/perfspect,roles/perfspect/{tasks,defaults,templates},callback_plugins}
touch ansible/inventory/.gitkeep
touch ansible/callback_plugins/.gitkeep
```

**Step 2: Create defaults file**

Create `ansible/roles/perfspect/defaults/main.yml`:

```yaml
---
# Default module name for PerfSPECT
perfspect_module: "perfspect/3.13.0"

# Default output directory on target node
perfspect_output_dir: "/tmp/perfspect_output"

# Default timeout for commands (in seconds)
perfspect_timeout: 300

# API callback settings (overridden by extra vars)
api_server: ""
api_token: ""
run_uuid: ""
```

**Step 3: Create main tasks file**

Create `ansible/roles/perfspect/tasks/main.yml`:

```yaml
---
- name: Include setup tasks
  ansible.builtin.include_tasks: setup.yml

- name: Include execute tasks
  ansible.builtin.include_tasks: execute.yml

- name: Include collect tasks
  ansible.builtin.include_tasks: collect.yml
```

**Step 4: Commit**

```bash
git add ansible/
git commit -m "feat(ansible): create directory structure for perfspect playbooks"
```

---

### Task 2.2: Create PerfSPECT Setup Tasks

**Files:**
- Create: `ansible/roles/perfspect/tasks/setup.yml`

**Step 1: Create setup tasks**

Create `ansible/roles/perfspect/tasks/setup.yml`:

```yaml
---
- name: Create output directory
  ansible.builtin.file:
    path: "{{ perfspect_output_dir }}"
    state: directory
    mode: "0755"

- name: Verify module is available
  ansible.builtin.shell: |
    source /etc/profile.d/lmod.sh 2>/dev/null || source /etc/profile.d/modules.sh 2>/dev/null || true
    module avail {{ perfspect_module }} 2>&1
  register: module_check
  changed_when: false
  failed_when: perfspect_module not in module_check.stderr

- name: Send RUNNING status to API
  ansible.builtin.uri:
    url: "{{ api_server }}/api/v1/profiling_runs/{{ run_uuid }}/status"
    method: POST
    body_format: json
    body:
      status: "running"
      message: "Setting up PerfSPECT environment"
    headers:
      Authorization: "Bearer {{ api_token }}"
      Content-Type: "application/json"
    status_code: [200, 201, 204]
  when: api_server | length > 0
  ignore_errors: true
```

**Step 2: Commit**

```bash
git add ansible/roles/perfspect/tasks/setup.yml
git commit -m "feat(ansible): add perfspect setup tasks"
```

---

### Task 2.3: Create PerfSPECT Execute Tasks

**Files:**
- Create: `ansible/roles/perfspect/tasks/execute.yml`

**Step 1: Create execute tasks**

Create `ansible/roles/perfspect/tasks/execute.yml`:

```yaml
---
- name: Build perfspect command
  ansible.builtin.set_fact:
    perfspect_cmd: >-
      source /etc/profile.d/lmod.sh 2>/dev/null || source /etc/profile.d/modules.sh 2>/dev/null || true &&
      module load {{ perfspect_module }} &&
      perfspect {{ perfspect_subcommand }}
      {% if perfspect_subcommand == 'telemetry' and perfspect_options.duration is defined %}
      --duration {{ perfspect_options.duration }}
      {% endif %}
      {% if perfspect_subcommand == 'flame' and perfspect_options.duration is defined %}
      --duration {{ perfspect_options.duration }}
      {% endif %}
      --output {{ perfspect_output_dir }}

- name: Execute perfspect command
  ansible.builtin.shell: "{{ perfspect_cmd }}"
  args:
    chdir: "{{ perfspect_output_dir }}"
  register: perfspect_result
  async: "{{ perfspect_timeout }}"
  poll: 10
  ignore_errors: true

- name: Record execution result
  ansible.builtin.set_fact:
    perfspect_success: "{{ perfspect_result.rc == 0 }}"
    perfspect_stdout: "{{ perfspect_result.stdout | default('') }}"
    perfspect_stderr: "{{ perfspect_result.stderr | default('') }}"
```

**Step 2: Commit**

```bash
git add ansible/roles/perfspect/tasks/execute.yml
git commit -m "feat(ansible): add perfspect execute tasks"
```

---

### Task 2.4: Create PerfSPECT Collect Tasks

**Files:**
- Create: `ansible/roles/perfspect/tasks/collect.yml`

**Step 1: Create collect tasks**

Create `ansible/roles/perfspect/tasks/collect.yml`:

```yaml
---
- name: Find generated artifacts
  ansible.builtin.find:
    paths: "{{ perfspect_output_dir }}"
    patterns:
      - "*.html"
      - "*.json"
      - "*.svg"
      - "*.txt"
  register: artifact_files

- name: Copy artifacts to shared filesystem
  ansible.builtin.copy:
    src: "{{ item.path }}"
    dest: "{{ shared_artifacts_path }}/{{ run_uuid }}/{{ item.path | basename }}"
    remote_src: true
    mode: "0644"
  loop: "{{ artifact_files.files }}"
  when: shared_artifacts_path is defined

- name: Build artifacts list for API
  ansible.builtin.set_fact:
    artifacts_payload: >-
      {{ artifact_files.files | map(attribute='path') | map('basename') | map('community.general.dict_kv', 'filename') | list }}

- name: Send completion status to API
  ansible.builtin.uri:
    url: "{{ api_server }}/api/v1/profiling_runs/{{ run_uuid }}/complete"
    method: POST
    body_format: json
    body:
      status: "{{ 'success' if perfspect_success else 'failed' }}"
      log_content: "{{ perfspect_stdout }}\n{{ perfspect_stderr }}"
      error_message: "{{ perfspect_stderr if not perfspect_success else omit }}"
      artifacts: >-
        {{ artifact_files.files | map('combine', {'file_path': shared_artifacts_path ~ '/' ~ run_uuid ~ '/' ~ item.path | basename}) | list }}
    headers:
      Authorization: "Bearer {{ api_token }}"
      Content-Type: "application/json"
    status_code: [200, 201, 204]
  when: api_server | length > 0
  ignore_errors: true

- name: Cleanup temporary output directory
  ansible.builtin.file:
    path: "{{ perfspect_output_dir }}"
    state: absent
  when: perfspect_cleanup | default(true) | bool
```

**Step 2: Commit**

```bash
git add ansible/roles/perfspect/tasks/collect.yml
git commit -m "feat(ansible): add perfspect collect tasks"
```

---

### Task 2.5: Create Report Playbook

**Files:**
- Create: `ansible/playbooks/perfspect/report.yml`

**Step 1: Create playbook**

Create `ansible/playbooks/perfspect/report.yml`:

```yaml
---
- name: Run PerfSPECT System Report
  hosts: "{{ target_host }}"
  gather_facts: false
  vars:
    perfspect_subcommand: report
    perfspect_output_dir: "/tmp/perfspect_{{ run_uuid }}"

  roles:
    - role: perfspect
      perfspect_options: "{{ options | default({}) }}"
```

**Step 2: Commit**

```bash
git add ansible/playbooks/perfspect/report.yml
git commit -m "feat(ansible): add perfspect report playbook"
```

---

### Task 2.6: Create Telemetry Playbook

**Files:**
- Create: `ansible/playbooks/perfspect/telemetry.yml`

**Step 1: Create playbook**

Create `ansible/playbooks/perfspect/telemetry.yml`:

```yaml
---
- name: Run PerfSPECT Telemetry Collection
  hosts: "{{ target_host }}"
  gather_facts: false
  vars:
    perfspect_subcommand: telemetry
    perfspect_output_dir: "/tmp/perfspect_{{ run_uuid }}"

  roles:
    - role: perfspect
      perfspect_options: "{{ options | default({'duration': 60}) }}"
```

**Step 2: Commit**

```bash
git add ansible/playbooks/perfspect/telemetry.yml
git commit -m "feat(ansible): add perfspect telemetry playbook"
```

---

### Task 2.7: Create Flame Graph Playbook

**Files:**
- Create: `ansible/playbooks/perfspect/flame.yml`

**Step 1: Create playbook**

Create `ansible/playbooks/perfspect/flame.yml`:

```yaml
---
- name: Run PerfSPECT Flame Graph
  hosts: "{{ target_host }}"
  gather_facts: false
  vars:
    perfspect_subcommand: flame
    perfspect_output_dir: "/tmp/perfspect_{{ run_uuid }}"

  roles:
    - role: perfspect
      perfspect_options: "{{ options | default({'duration': 30}) }}"
```

**Step 2: Commit**

```bash
git add ansible/playbooks/perfspect/flame.yml
git commit -m "feat(ansible): add perfspect flame playbook"
```

---

## Phase 3: Rails Services & Jobs

### Task 3.1: Create Ansible ExecutorService

**Files:**
- Create: `app/services/ansible/executor_service.rb`
- Test: `spec/services/ansible/executor_service_spec.rb`

**Step 1: Write the failing test**

Create `spec/services/ansible/executor_service_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ansible::ExecutorService do
  let(:admin_config) do
    {
      host: "admin.example.com",
      user: "ansible",
      playbooks_path: "/opt/playbooks"
    }
  end

  let(:service) do
    described_class.new(
      admin_config: admin_config,
      playbook: "perfspect/report.yml",
      extra_vars: { target_host: "compute-001", run_uuid: "abc-123" }
    )
  end

  describe "#call" do
    context "when SSH execution succeeds" do
      before do
        allow_any_instance_of(SshExecutionService).to receive(:execute_ssh_command)
          .and_return(SshExecutionService::Result.new(success: true, output: "ok", exit_code: 0))
      end

      it "returns success result" do
        result = service.call
        expect(result.success?).to be true
      end
    end

    context "when SSH execution fails" do
      before do
        allow_any_instance_of(SshExecutionService).to receive(:execute_ssh_command)
          .and_return(SshExecutionService::Result.new(success: false, error: "Connection refused", exit_code: 1))
      end

      it "returns failure result" do
        result = service.call
        expect(result.success?).to be false
        expect(result.error).to include("Connection refused")
      end
    end
  end

  describe "#build_command" do
    it "builds ansible-playbook command with extra vars" do
      cmd = service.send(:build_command)
      expect(cmd).to include("ansible-playbook")
      expect(cmd).to include("perfspect/report.yml")
      expect(cmd).to include("--extra-vars")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/services/ansible/executor_service_spec.rb`
Expected: FAIL

**Step 3: Create service directory**

Run: `mkdir -p app/services/ansible`

**Step 4: Write service implementation**

Create `app/services/ansible/executor_service.rb`:

```ruby
# frozen_string_literal: true

module Ansible
  class ExecutorService
    Result = Struct.new(:success, :output, :error, keyword_init: true) do
      def success?
        success
      end
    end

    def initialize(admin_config:, playbook:, extra_vars: {})
      @admin_config = admin_config
      @playbook = playbook
      @extra_vars = extra_vars
    end

    def call
      ssh_result = execute_on_admin_node(build_command)

      if ssh_result.success?
        Result.new(success: true, output: ssh_result.output)
      else
        Result.new(success: false, error: ssh_result.error || ssh_result.output)
      end
    rescue StandardError => e
      Result.new(success: false, error: "Ansible execution failed: #{e.message}")
    end

    private

    def build_command
      playbooks_path = @admin_config[:playbooks_path] || "/opt/ansible"
      extra_vars_json = @extra_vars.to_json.gsub("'", "'\\''")

      <<~CMD.squish
        cd #{Shellwords.escape(playbooks_path)} &&
        ansible-playbook
        playbooks/#{Shellwords.escape(@playbook)}
        --extra-vars '#{extra_vars_json}'
        -v
      CMD
    end

    def execute_on_admin_node(command)
      admin_node = build_admin_node
      ssh_service = SshAdminExecutor.new(admin_node)
      ssh_service.execute(command)
    end

    def build_admin_node
      OpenStruct.new(
        hostname: @admin_config[:host],
        ip: @admin_config[:host],
        ssh_user: @admin_config[:user],
        ssh_port: @admin_config[:port] || 22,
        ssh_connect_method: :direct
      )
    end

    # Lightweight SSH executor for admin node
    class SshAdminExecutor < SshExecutionService
      def initialize(admin_node)
        super(admin_node)
      end

      def execute(command)
        execute_ssh_command(command)
      end

      private

      def direct_connection_required?
        true
      end
    end
  end
end
```

**Step 5: Run test to verify it passes**

Run: `bin/rspec spec/services/ansible/executor_service_spec.rb`
Expected: All tests pass

**Step 6: Commit**

```bash
git add app/services/ansible/executor_service.rb spec/services/ansible/executor_service_spec.rb
git commit -m "feat(profiling): add Ansible::ExecutorService for playbook execution"
```

---

### Task 3.2: Create Profiling TriggerService

**Files:**
- Create: `app/services/profiling/trigger_service.rb`
- Test: `spec/services/profiling/trigger_service_spec.rb`

**Step 1: Write the failing test**

Create `spec/services/profiling/trigger_service_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Profiling::TriggerService do
  let(:node) { create(:node) }
  let(:run) { create(:profiling_run, node: node, subcommand: "report") }
  let(:service) { described_class.new(run, server_url: "http://localhost:3000", api_token: "secret") }

  describe "#call" do
    context "when Ansible execution succeeds" do
      before do
        allow_any_instance_of(Ansible::ExecutorService).to receive(:call)
          .and_return(Ansible::ExecutorService::Result.new(success: true, output: "Playbook completed"))
      end

      it "returns success" do
        result = service.call
        expect(result.success?).to be true
      end

      it "logs output" do
        result = service.call
        expect(result.output).to include("Playbook completed")
      end
    end

    context "when Ansible execution fails" do
      before do
        allow_any_instance_of(Ansible::ExecutorService).to receive(:call)
          .and_return(Ansible::ExecutorService::Result.new(success: false, error: "Module not found"))
      end

      it "returns failure" do
        result = service.call
        expect(result.success?).to be false
      end

      it "includes error message" do
        result = service.call
        expect(result.error).to include("Module not found")
      end
    end
  end

  describe "#playbook_for_subcommand" do
    it "maps report to report.yml" do
      expect(service.send(:playbook_for_subcommand, "report")).to eq("perfspect/report.yml")
    end

    it "maps telemetry to telemetry.yml" do
      expect(service.send(:playbook_for_subcommand, "telemetry")).to eq("perfspect/telemetry.yml")
    end

    it "maps flame to flame.yml" do
      expect(service.send(:playbook_for_subcommand, "flame")).to eq("perfspect/flame.yml")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/services/profiling/trigger_service_spec.rb`
Expected: FAIL

**Step 3: Create service directory**

Run: `mkdir -p app/services/profiling`

**Step 4: Write service implementation**

Create `app/services/profiling/trigger_service.rb`:

```ruby
# frozen_string_literal: true

module Profiling
  class TriggerService
    Result = Struct.new(:success, :output, :error, keyword_init: true) do
      def success?
        success
      end
    end

    def initialize(profiling_run, server_url:, api_token:)
      @run = profiling_run
      @server_url = server_url
      @api_token = api_token
    end

    def call
      extra_vars = build_extra_vars
      playbook = playbook_for_subcommand(@run.subcommand)

      result = Ansible::ExecutorService.new(
        admin_config: ansible_admin_config,
        playbook: playbook,
        extra_vars: extra_vars
      ).call

      if result.success?
        Result.new(success: true, output: result.output)
      else
        Result.new(success: false, error: result.error, output: result.output)
      end
    end

    private

    def build_extra_vars
      {
        target_host: @run.node.hostname,
        run_uuid: @run.uuid,
        api_server: @server_url,
        api_token: @api_token,
        shared_artifacts_path: profiling_artifacts_path,
        options: @run.options,
        perfspect_module: @run.profiling_recipe&.module_name || default_module
      }
    end

    def playbook_for_subcommand(subcommand)
      case subcommand
      when "report" then "perfspect/report.yml"
      when "telemetry" then "perfspect/telemetry.yml"
      when "flame" then "perfspect/flame.yml"
      else raise ArgumentError, "Unknown subcommand: #{subcommand}"
      end
    end

    def ansible_admin_config
      {
        host: profiling_settings[:ansible_admin_host],
        user: profiling_settings[:ansible_admin_user],
        playbooks_path: profiling_settings[:playbooks_path]
      }
    end

    def profiling_settings
      @profiling_settings ||= {
        ansible_admin_host: ENV.fetch("ANSIBLE_ADMIN_HOST", "localhost"),
        ansible_admin_user: ENV.fetch("ANSIBLE_ADMIN_USER", "ansible"),
        playbooks_path: ENV.fetch("ANSIBLE_PLAYBOOKS_PATH", Rails.root.join("ansible").to_s)
      }
    end

    def profiling_artifacts_path
      ENV.fetch("PROFILING_ARTIFACTS_PATH", "/shared/profiling_artifacts")
    end

    def default_module
      ENV.fetch("DEFAULT_PERFSPECT_MODULE", "perfspect/3.13.0")
    end
  end
end
```

**Step 5: Run test to verify it passes**

Run: `bin/rspec spec/services/profiling/trigger_service_spec.rb`
Expected: All tests pass

**Step 6: Commit**

```bash
git add app/services/profiling/trigger_service.rb spec/services/profiling/trigger_service_spec.rb
git commit -m "feat(profiling): add Profiling::TriggerService for orchestrating runs"
```

---

### Task 3.3: Create Profiling TriggerJob

**Files:**
- Create: `app/jobs/profiling/trigger_job.rb`
- Test: `spec/jobs/profiling/trigger_job_spec.rb`

**Step 1: Write the failing test**

Create `spec/jobs/profiling/trigger_job_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Profiling::TriggerJob, type: :job do
  let(:node) { create(:node) }
  let(:run) { create(:profiling_run, node: node, status: :pending) }
  let(:user) { create(:user) }

  describe "#perform" do
    context "when trigger succeeds" do
      before do
        allow_any_instance_of(Profiling::TriggerService).to receive(:call)
          .and_return(Profiling::TriggerService::Result.new(success: true, output: "ok"))
      end

      it "updates run to running status" do
        described_class.perform_now(run, "http://localhost:3000", "token", user_id: user.id)
        run.reload
        expect(run.status).to eq("running")
      end

      it "sets started_at" do
        described_class.perform_now(run, "http://localhost:3000", "token", user_id: user.id)
        run.reload
        expect(run.started_at).to be_present
      end
    end

    context "when trigger fails" do
      before do
        allow_any_instance_of(Profiling::TriggerService).to receive(:call)
          .and_return(Profiling::TriggerService::Result.new(success: false, error: "SSH failed"))
      end

      it "updates run to failed status" do
        described_class.perform_now(run, "http://localhost:3000", "token", user_id: user.id)
        run.reload
        expect(run.status).to eq("failed")
      end

      it "stores error message" do
        described_class.perform_now(run, "http://localhost:3000", "token", user_id: user.id)
        run.reload
        expect(run.error_message).to include("SSH failed")
      end
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/jobs/profiling/trigger_job_spec.rb`
Expected: FAIL

**Step 3: Create job directory**

Run: `mkdir -p app/jobs/profiling`

**Step 4: Write job implementation**

Create `app/jobs/profiling/trigger_job.rb`:

```ruby
# frozen_string_literal: true

module Profiling
  class TriggerJob < ApplicationJob
    queue_as :default

    def perform(run, server_url, api_token, user_id: nil)
      notification = create_notification(run, user_id)

      service = Profiling::TriggerService.new(run, server_url: server_url, api_token: api_token)
      result = service.call

      run.reload
      return if run.status != "pending"

      if result.success?
        run.update!(status: :running, started_at: Time.current, log_content: result.output)
        complete_notification(notification, success: true, message: "Profiling started successfully")
      else
        run.update!(status: :failed, error_message: result.error, log_content: result.output)
        complete_notification(notification, success: false, message: result.error)
      end
    rescue StandardError => e
      complete_notification(notification, success: false, message: e.message)
      raise
    end

    private

    def create_notification(run, user_id)
      return nil unless user_id.present?

      user = User.find_by(id: user_id)
      return nil unless user

      notification = NotificationService.create(
        user: user,
        type: "profiling",
        title: "Running profiling on #{run.node.hostname}",
        resource: run
      )
      NotificationService.start(notification)
      notification
    end

    def complete_notification(notification, success:, message:)
      return unless notification

      NotificationService.complete(notification, success: success, message: message)
    end
  end
end
```

**Step 5: Run test to verify it passes**

Run: `bin/rspec spec/jobs/profiling/trigger_job_spec.rb`
Expected: All tests pass

**Step 6: Commit**

```bash
git add app/jobs/profiling/trigger_job.rb spec/jobs/profiling/trigger_job_spec.rb
git commit -m "feat(profiling): add Profiling::TriggerJob background job"
```

---

## Phase 4: API Endpoints

### Task 4.1: Create Profiling Runs API Controller

**Files:**
- Create: `app/controllers/api/v1/profiling_runs_controller.rb`
- Test: `spec/requests/api/v1/profiling_runs_spec.rb`

**Step 1: Write the failing test**

Create `spec/requests/api/v1/profiling_runs_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::ProfilingRuns", type: :request do
  let(:api_key) { create(:api_key) }
  let(:headers) { { "Authorization" => "Bearer #{api_key.token}" } }
  let(:node) { create(:node) }
  let!(:run) { create(:profiling_run, node: node, status: :running) }

  describe "POST /api/v1/profiling_runs/:uuid/status" do
    it "updates run status" do
      post "/api/v1/profiling_runs/#{run.uuid}/status",
           params: { status: "running", message: "Executing perfspect" },
           headers: headers,
           as: :json

      expect(response).to have_http_status(:ok)
      run.reload
      expect(run.log_content).to include("Executing perfspect")
    end
  end

  describe "POST /api/v1/profiling_runs/:uuid/complete" do
    it "marks run as success with artifacts" do
      post "/api/v1/profiling_runs/#{run.uuid}/complete",
           params: {
             status: "success",
             metrics: { "cpu_model" => "Intel Xeon" },
             artifacts: [
               { filename: "report.html", file_path: "/shared/abc/report.html", file_type: "html" }
             ]
           },
           headers: headers,
           as: :json

      expect(response).to have_http_status(:ok)
      run.reload
      expect(run.status).to eq("success")
      expect(run.metrics["cpu_model"]).to eq("Intel Xeon")
      expect(run.profiling_artifacts.count).to eq(1)
    end

    it "marks run as failed with error message" do
      post "/api/v1/profiling_runs/#{run.uuid}/complete",
           params: { status: "failed", error_message: "Module not found" },
           headers: headers,
           as: :json

      expect(response).to have_http_status(:ok)
      run.reload
      expect(run.status).to eq("failed")
      expect(run.error_message).to eq("Module not found")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/requests/api/v1/profiling_runs_spec.rb`
Expected: FAIL

**Step 3: Write controller implementation**

Create `app/controllers/api/v1/profiling_runs_controller.rb`:

```ruby
# frozen_string_literal: true

module Api
  module V1
    class ProfilingRunsController < BaseController
      before_action :set_run

      def status
        @run.update!(log_content: [@run.log_content, params[:message]].compact.join("\n"))
        render json: { success: true }
      end

      def complete
        status_map = { "success" => :success, "failed" => :failed }
        new_status = status_map[params[:status]] || @run.status

        update_params = {
          status: new_status,
          metrics: params[:metrics],
          finished_at: Time.current,
          log_content: params[:log_content],
          error_message: params[:error_message]
        }.compact

        if @run.update(update_params)
          process_artifacts if params[:artifacts].present?
          render json: { success: true, uuid: @run.uuid }
        else
          render json: { error: @run.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      private

      def set_run
        @run = ProfilingRun.find_by!(uuid: params[:uuid])
      end

      def process_artifacts
        params[:artifacts].each do |artifact_data|
          @run.profiling_artifacts.find_or_create_by!(filename: artifact_data[:filename]) do |artifact|
            artifact.file_path = artifact_data[:file_path]
            artifact.file_type = artifact_data[:file_type]
            artifact.file_size = artifact_data[:file_size]
          end
        end
      end
    end
  end
end
```

**Step 4: Add routes**

In `config/routes.rb`, inside the `namespace :api do namespace :v1 do` block, add:

```ruby
resources :profiling_runs, param: :uuid, only: [] do
  member do
    post :status
    post :complete
  end
end
```

**Step 5: Run test to verify it passes**

Run: `bin/rspec spec/requests/api/v1/profiling_runs_spec.rb`
Expected: All tests pass

**Step 6: Commit**

```bash
git add app/controllers/api/v1/profiling_runs_controller.rb config/routes.rb spec/requests/api/v1/profiling_runs_spec.rb
git commit -m "feat(profiling): add API endpoints for profiling run callbacks"
```

---

## Phase 5: User Interface

### Task 5.1: Add Profiling Tab to Node Show

**Files:**
- Modify: `app/views/nodes/show.html.erb`
- Create: `app/views/nodes/_profiling.html.erb`

**Step 1: Add tab navigation**

In `app/views/nodes/show.html.erb`, add a new tab after "Logs" tab (around line 124):

```erb
<a href="#"
   data-tabs-target="tab"
   data-action="click->tabs#select"
   class="border-transparent text-slate-500 hover:border-slate-300 hover:text-slate-700 whitespace-nowrap border-b-2 py-4 px-1 text-sm font-bold uppercase transition-colors">
  Profiling
</a>
```

**Step 2: Add tab panel**

Add after the Logs panel (around line 161):

```erb
<%# Panel 5: Profiling %>
<div data-tabs-target="panel" class="hidden col-span-12 outline-none" role="tabpanel" tabindex="0">
  <%= render "nodes/profiling", node: @node %>
</div>
```

**Step 3: Create profiling partial**

Create `app/views/nodes/_profiling.html.erb`:

```erb
<div class="space-y-6">
  <%# Quick Profiles %>
  <div class="card-netbox">
    <div class="card-header">
      <h3 class="card-title text-xs font-bold text-slate-500 uppercase">Quick Profiles</h3>
    </div>
    <div class="p-4">
      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <%# System Report %>
        <div class="border border-slate-200 rounded-lg p-4 hover:border-teal-300 transition-colors">
          <div class="flex items-center gap-3 mb-2">
            <svg class="h-8 w-8 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
            </svg>
            <div>
              <h4 class="font-bold text-slate-800">System Report</h4>
              <p class="text-xs text-slate-500">Hardware & BIOS config</p>
            </div>
          </div>
          <% if current_user&.approver? %>
            <%= button_to "Run", node_profiling_runs_path(node, profiling_run: { subcommand: "report" }),
                method: :post,
                class: "btn-primary btn-sm w-full mt-2",
                data: { turbo_submits_with: "Starting..." } %>
          <% end %>
        </div>

        <%# Telemetry %>
        <div class="border border-slate-200 rounded-lg p-4 hover:border-teal-300 transition-colors">
          <div class="flex items-center gap-3 mb-2">
            <svg class="h-8 w-8 text-green-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
            </svg>
            <div>
              <h4 class="font-bold text-slate-800">Telemetry</h4>
              <p class="text-xs text-slate-500">60s performance metrics</p>
            </div>
          </div>
          <% if current_user&.approver? %>
            <%= button_to "Run", node_profiling_runs_path(node, profiling_run: { subcommand: "telemetry", options: { duration: 60 } }),
                method: :post,
                class: "btn-primary btn-sm w-full mt-2",
                data: { turbo_submits_with: "Starting..." } %>
          <% end %>
        </div>

        <%# Flame Graph %>
        <div class="border border-slate-200 rounded-lg p-4 hover:border-teal-300 transition-colors">
          <div class="flex items-center gap-3 mb-2">
            <svg class="h-8 w-8 text-orange-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 18.657A8 8 0 016.343 7.343S7 9 9 10c0-2 .5-5 2.986-7C14 5 16.09 5.777 17.656 7.343A7.975 7.975 0 0120 13a7.975 7.975 0 01-2.343 5.657z" />
            </svg>
            <div>
              <h4 class="font-bold text-slate-800">Flame Graph</h4>
              <p class="text-xs text-slate-500">CPU profiling visualization</p>
            </div>
          </div>
          <% if current_user&.approver? %>
            <%= button_to "Run", node_profiling_runs_path(node, profiling_run: { subcommand: "flame", options: { duration: 30 } }),
                method: :post,
                class: "btn-primary btn-sm w-full mt-2",
                data: { turbo_submits_with: "Starting..." } %>
          <% end %>
        </div>
      </div>

      <% if current_user&.approver? %>
        <div class="mt-4 pt-4 border-t border-slate-100">
          <%= link_to new_node_profiling_run_path(node),
              class: "text-sm text-teal-600 hover:text-teal-800 font-medium",
              data: { turbo_frame: "profiling_modal" } do %>
            + Custom Profile...
          <% end %>
        </div>
      <% end %>
    </div>
  </div>

  <%# Recent Profiling Runs %>
  <div class="card-netbox">
    <div class="card-header">
      <h3 class="card-title text-xs font-bold text-slate-500 uppercase">Recent Profiling Runs</h3>
    </div>
    <div class="overflow-x-auto">
      <% if node.profiling_runs.any? %>
        <table class="min-w-full divide-y divide-slate-200">
          <thead class="bg-slate-50">
            <tr>
              <th class="px-4 py-2 text-left text-xs font-medium text-slate-500 uppercase">Type</th>
              <th class="px-4 py-2 text-left text-xs font-medium text-slate-500 uppercase">Status</th>
              <th class="px-4 py-2 text-left text-xs font-medium text-slate-500 uppercase">Started</th>
              <th class="px-4 py-2 text-left text-xs font-medium text-slate-500 uppercase">Duration</th>
              <th class="px-4 py-2 text-left text-xs font-medium text-slate-500 uppercase">Actions</th>
            </tr>
          </thead>
          <tbody id="profiling_runs_tbody" class="divide-y divide-slate-100">
            <% node.profiling_runs.recent.limit(10).each do |run| %>
              <%= render "profiling_runs/run_row", run: run %>
            <% end %>
          </tbody>
        </table>
      <% else %>
        <div class="p-8 text-center text-slate-500">No profiling runs recorded.</div>
      <% end %>
    </div>
  </div>
</div>

<%= turbo_frame_tag "profiling_modal" %>
```

**Step 4: Commit**

```bash
git add app/views/nodes/show.html.erb app/views/nodes/_profiling.html.erb
git commit -m "feat(ui): add Profiling tab to node details page"
```

---

### Task 5.2: Create Profiling Run Row Partial

**Files:**
- Create: `app/views/profiling_runs/_run_row.html.erb`

**Step 1: Create partial**

Run: `mkdir -p app/views/profiling_runs`

Create `app/views/profiling_runs/_run_row.html.erb`:

```erb
<tr id="profiling_run_<%= run.id %>">
  <td class="px-4 py-3 text-sm">
    <span class="font-medium text-slate-800"><%= run.subcommand.capitalize %></span>
    <% if run.profiling_recipe %>
      <span class="text-xs text-slate-500 block"><%= run.profiling_recipe.name %></span>
    <% end %>
  </td>
  <td class="px-4 py-3">
    <% case run.status %>
    <% when "pending" %>
      <span class="inline-flex items-center rounded-full bg-slate-100 px-2.5 py-0.5 text-xs font-medium text-slate-600">
        Pending
      </span>
    <% when "running" %>
      <span class="inline-flex items-center rounded-full bg-blue-100 px-2.5 py-0.5 text-xs font-medium text-blue-700">
        <svg class="animate-spin -ml-0.5 mr-1.5 h-3 w-3" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
        </svg>
        Running
      </span>
    <% when "success" %>
      <span class="inline-flex items-center rounded-full bg-green-100 px-2.5 py-0.5 text-xs font-medium text-green-700">
        Success
      </span>
    <% when "failed" %>
      <span class="inline-flex items-center rounded-full bg-red-100 px-2.5 py-0.5 text-xs font-medium text-red-700">
        Failed
      </span>
    <% when "cancelled" %>
      <span class="inline-flex items-center rounded-full bg-amber-100 px-2.5 py-0.5 text-xs font-medium text-amber-700">
        Cancelled
      </span>
    <% end %>
  </td>
  <td class="px-4 py-3 text-sm text-slate-500">
    <% if run.started_at %>
      <%= time_ago_in_words(run.started_at) %> ago
    <% else %>
      -
    <% end %>
  </td>
  <td class="px-4 py-3 text-sm text-slate-500">
    <% if run.duration %>
      <%= distance_of_time_in_words(run.duration) %>
    <% elsif run.running? && run.started_at %>
      <span class="text-blue-600"><%= distance_of_time_in_words(Time.current - run.started_at) %></span>
    <% else %>
      -
    <% end %>
  </td>
  <td class="px-4 py-3 text-sm">
    <%= link_to "View", node_profiling_run_path(run.node, run),
        class: "text-teal-600 hover:text-teal-800 font-medium" %>
    <% if run.profiling_artifacts.any? %>
      <span class="ml-2 text-xs text-slate-400">
        (<%= run.profiling_artifacts.count %> files)
      </span>
    <% end %>
  </td>
</tr>
```

**Step 2: Commit**

```bash
git add app/views/profiling_runs/_run_row.html.erb
git commit -m "feat(ui): add profiling run row partial"
```

---

### Task 5.3: Create Profiling Runs Controller

**Files:**
- Create: `app/controllers/nodes/profiling_runs_controller.rb`

**Step 1: Create controller**

Create `app/controllers/nodes/profiling_runs_controller.rb`:

```ruby
# frozen_string_literal: true

module Nodes
  class ProfilingRunsController < ApplicationController
    layout "dashboard"
    before_action :authenticate_user!
    before_action :set_node
    before_action :authorize_approver!, only: %i[new create]

    def index
      @profiling_runs = @node.profiling_runs
                              .includes(:profiling_recipe, :profiling_artifacts)
                              .order(created_at: :desc)
                              .page(params[:page])
                              .per(20)
    end

    def show
      @run = @node.profiling_runs.find(params[:id])
    end

    def new
      @form = Profiling::RunForm.new
      @profiling_recipes = ProfilingRecipe.active.order(:name)
    end

    def create
      run_params = profiling_run_params

      run = @node.profiling_runs.create!(
        subcommand: run_params[:subcommand],
        options: run_params[:options] || {},
        profiling_recipe_id: run_params[:profiling_recipe_id],
        user: current_user,
        status: :pending
      )

      Profiling::TriggerJob.perform_later(
        run,
        request.base_url,
        agent_token,
        user_id: current_user.id
      )

      redirect_to node_path(@node, anchor: "profiling"), notice: "Profiling run started."
    end

    private

    def set_node
      @node = Node.find(params[:node_id])
    end

    def authorize_approver!
      return if current_user.approver?

      redirect_to node_path(@node), alert: "You are not authorized to run profiling."
    end

    def profiling_run_params
      params.require(:profiling_run).permit(:subcommand, :profiling_recipe_id, options: {})
    end

    def agent_token
      @node.effective_api_token.presence ||
        Rails.application.credentials.dig(:api, :agent_token) ||
        ENV["API_AGENT_TOKEN"]
    end
  end
end
```

**Step 2: Add routes**

In `config/routes.rb`, add inside `resources :nodes`:

```ruby
resources :profiling_runs, controller: "nodes/profiling_runs", only: %i[index show new create]
```

**Step 3: Commit**

```bash
git add app/controllers/nodes/profiling_runs_controller.rb config/routes.rb
git commit -m "feat(profiling): add ProfilingRunsController for node profiling UI"
```

---

### Task 5.4: Create Custom Profile Form

**Files:**
- Create: `app/forms/profiling/run_form.rb`
- Create: `app/views/nodes/profiling_runs/new.html.erb`

**Step 1: Create form object**

Run: `mkdir -p app/forms/profiling`

Create `app/forms/profiling/run_form.rb`:

```ruby
# frozen_string_literal: true

module Profiling
  class RunForm
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :subcommand, :string
    attribute :profiling_recipe_id, :integer
    attribute :options_json, :string
    attribute :module_name, :string, default: "perfspect/3.13.0"
    attribute :duration, :integer, default: 60

    validates :subcommand, presence: true, inclusion: { in: %w[report telemetry flame] }

    def options
      return { "duration" => duration } if %w[telemetry flame].include?(subcommand)

      {}
    end

    def profiling_recipe
      return nil if profiling_recipe_id.blank?

      ProfilingRecipe.find_by(id: profiling_recipe_id)
    end
  end
end
```

**Step 2: Create form view**

Create `app/views/nodes/profiling_runs/new.html.erb`:

```erb
<%= turbo_frame_tag "profiling_modal" do %>
  <%= render "shared/modal", title: "Custom PerfSPECT Profile: #{@node.hostname}", max_width: 'max-w-lg' do %>
    <%= form_with model: @form, url: node_profiling_runs_path(@node), method: :post,
        data: { turbo_frame: "_top" },
        class: "space-y-4" do |f| %>

      <div>
        <%= f.label :subcommand, "Profile Type", class: "block text-sm font-bold text-slate-700 mb-2" %>
        <div class="space-y-2">
          <label class="flex items-center gap-3 p-3 border rounded-lg cursor-pointer hover:border-teal-300">
            <%= f.radio_button :subcommand, "report", class: "text-teal-600" %>
            <div>
              <span class="font-medium text-slate-800">System Report</span>
              <p class="text-xs text-slate-500">Collect hardware and BIOS configuration</p>
            </div>
          </label>
          <label class="flex items-center gap-3 p-3 border rounded-lg cursor-pointer hover:border-teal-300">
            <%= f.radio_button :subcommand, "telemetry", class: "text-teal-600" %>
            <div>
              <span class="font-medium text-slate-800">Telemetry</span>
              <p class="text-xs text-slate-500">Collect live performance metrics</p>
            </div>
          </label>
          <label class="flex items-center gap-3 p-3 border rounded-lg cursor-pointer hover:border-teal-300">
            <%= f.radio_button :subcommand, "flame", class: "text-teal-600" %>
            <div>
              <span class="font-medium text-slate-800">Flame Graph</span>
              <p class="text-xs text-slate-500">Generate CPU flame graph visualization</p>
            </div>
          </label>
        </div>
      </div>

      <div>
        <%= f.label :module_name, "Module Name", class: "block text-sm font-bold text-slate-700 mb-1" %>
        <%= f.text_field :module_name,
            class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm font-mono",
            placeholder: "perfspect/3.13.0" %>
        <p class="mt-1 text-[10px] text-slate-500 italic">
          Lmod module to load on target node
        </p>
      </div>

      <div>
        <%= f.label :duration, "Duration (seconds)", class: "block text-sm font-bold text-slate-700 mb-1" %>
        <%= f.number_field :duration,
            class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm",
            min: 10, max: 600, step: 10 %>
        <p class="mt-1 text-[10px] text-slate-500 italic">
          For telemetry and flame graph profiles only
        </p>
      </div>

      <div class="flex items-center justify-end gap-3 pt-4 border-t border-slate-100">
        <button type="button" class="btn-secondary" data-action="modal#close">Cancel</button>
        <%= f.submit "Run Profile", class: "btn-primary" %>
      </div>
    <% end %>
  <% end %>
<% end %>
```

**Step 3: Commit**

```bash
git add app/forms/profiling/run_form.rb app/views/nodes/profiling_runs/new.html.erb
git commit -m "feat(ui): add custom profile form for PerfSPECT"
```

---

### Task 5.5: Create Profiling Run Show View

**Files:**
- Create: `app/views/nodes/profiling_runs/show.html.erb`

**Step 1: Create show view**

Create `app/views/nodes/profiling_runs/show.html.erb`:

```erb
<% content_for(:page_title) { "Profiling Run: #{@run.subcommand.capitalize}" } %>
<% content_for(:breadcrumbs) do %>
  <span class="mx-2">/</span>
  <%= link_to "Nodes", nodes_path, class: "hover:text-teal-600 font-bold" %>
  <span class="mx-2">/</span>
  <%= link_to @node.hostname, node_path(@node), class: "hover:text-teal-600 font-bold" %>
  <span class="mx-2">/</span>
  <span class="font-medium text-slate-700">Profiling Run</span>
<% end %>

<div class="space-y-6">
  <%# Header %>
  <div class="flex items-center justify-between">
    <div>
      <h1 class="text-2xl font-bold text-slate-900">
        <%= @run.subcommand.capitalize %> Profile
      </h1>
      <p class="text-sm text-slate-500 mt-1">
        Node: <%= @node.hostname %> &bull;
        Started: <%= @run.started_at ? l(@run.started_at, format: :long) : "Pending" %>
      </p>
    </div>
    <div>
      <% case @run.status %>
      <% when "success" %>
        <span class="inline-flex items-center rounded-full bg-green-100 px-3 py-1 text-sm font-medium text-green-700">
          Success
        </span>
      <% when "failed" %>
        <span class="inline-flex items-center rounded-full bg-red-100 px-3 py-1 text-sm font-medium text-red-700">
          Failed
        </span>
      <% when "running" %>
        <span class="inline-flex items-center rounded-full bg-blue-100 px-3 py-1 text-sm font-medium text-blue-700">
          Running
        </span>
      <% else %>
        <span class="inline-flex items-center rounded-full bg-slate-100 px-3 py-1 text-sm font-medium text-slate-600">
          <%= @run.status.capitalize %>
        </span>
      <% end %>
    </div>
  </div>

  <%# Error Message %>
  <% if @run.error_message.present? %>
    <div class="rounded-md bg-red-50 p-4 border border-red-200">
      <h3 class="text-sm font-bold text-red-800">Error</h3>
      <p class="mt-1 text-sm text-red-700"><%= @run.error_message %></p>
    </div>
  <% end %>

  <%# Metrics %>
  <% if @run.metrics.present? %>
    <div class="card-netbox">
      <div class="card-header">
        <h3 class="card-title text-xs font-bold text-slate-500 uppercase">Metrics</h3>
      </div>
      <div class="p-4">
        <pre class="text-sm font-mono text-slate-700 bg-slate-50 p-3 rounded overflow-x-auto"><%= JSON.pretty_generate(@run.metrics) %></pre>
      </div>
    </div>
  <% end %>

  <%# Artifacts %>
  <% if @run.profiling_artifacts.any? %>
    <div class="card-netbox">
      <div class="card-header">
        <h3 class="card-title text-xs font-bold text-slate-500 uppercase">Artifacts</h3>
      </div>
      <div class="divide-y divide-slate-100">
        <% @run.profiling_artifacts.each do |artifact| %>
          <div class="p-4 flex items-center justify-between">
            <div class="flex items-center gap-3">
              <% case artifact.file_type %>
              <% when "html" %>
                <svg class="h-6 w-6 text-orange-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                </svg>
              <% when "svg" %>
                <svg class="h-6 w-6 text-purple-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
                </svg>
              <% else %>
                <svg class="h-6 w-6 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 21h10a2 2 0 002-2V9.414a1 1 0 00-.293-.707l-5.414-5.414A1 1 0 0012.586 3H7a2 2 0 00-2 2v14a2 2 0 002 2z" />
                </svg>
              <% end %>
              <div>
                <p class="font-medium text-slate-800"><%= artifact.filename %></p>
                <p class="text-xs text-slate-500">
                  <%= number_to_human_size(artifact.file_size || 0) %>
                </p>
              </div>
            </div>
            <% if artifact.downloadable? %>
              <%= link_to "Download", download_node_profiling_run_artifact_path(@node, @run, artifact),
                  class: "btn-secondary btn-sm" %>
            <% else %>
              <span class="text-xs text-slate-400">Not available</span>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
  <% end %>

  <%# Log Output %>
  <% if @run.log_content.present? %>
    <div class="card-netbox">
      <div class="card-header">
        <h3 class="card-title text-xs font-bold text-slate-500 uppercase">Log Output</h3>
      </div>
      <div class="p-4">
        <pre class="text-xs font-mono text-slate-600 bg-slate-900 text-slate-100 p-4 rounded overflow-x-auto max-h-96"><%= @run.log_content %></pre>
      </div>
    </div>
  <% end %>
</div>
```

**Step 2: Commit**

```bash
git add app/views/nodes/profiling_runs/show.html.erb
git commit -m "feat(ui): add profiling run show page with artifacts display"
```

---

## Phase 6: Seeds & Configuration

### Task 6.1: Add Default Profiling Recipes

**Files:**
- Create: `db/seeds/profiling_recipes.rb`
- Modify: `db/seeds.rb`

**Step 1: Create seeds file**

Create `db/seeds/profiling_recipes.rb`:

```ruby
# frozen_string_literal: true

puts "Seeding profiling recipes..."

recipes = [
  {
    name: "Quick System Report",
    slug: "quick-system-report",
    description: "Collect system hardware and BIOS configuration snapshot using Intel PerfSPECT",
    tool: "perfspect",
    subcommand: "report",
    module_name: "perfspect/3.13.0",
    default_options: {},
    timeout_seconds: 300
  },
  {
    name: "Performance Telemetry (60s)",
    slug: "performance-telemetry-60s",
    description: "Collect 60 seconds of live CPU performance metrics",
    tool: "perfspect",
    subcommand: "telemetry",
    module_name: "perfspect/3.13.0",
    default_options: { "duration" => 60 },
    timeout_seconds: 120
  },
  {
    name: "Performance Telemetry (5min)",
    slug: "performance-telemetry-5min",
    description: "Collect 5 minutes of live CPU performance metrics",
    tool: "perfspect",
    subcommand: "telemetry",
    module_name: "perfspect/3.13.0",
    default_options: { "duration" => 300 },
    timeout_seconds: 420
  },
  {
    name: "CPU Flame Graph",
    slug: "cpu-flame-graph",
    description: "Generate CPU flame graph visualization for 30 seconds",
    tool: "perfspect",
    subcommand: "flame",
    module_name: "perfspect/3.13.0",
    default_options: { "duration" => 30 },
    timeout_seconds: 120
  }
]

recipes.each do |attrs|
  ProfilingRecipe.find_or_create_by!(slug: attrs[:slug]) do |recipe|
    recipe.assign_attributes(attrs)
  end
end

puts "Created #{recipes.size} profiling recipes"
```

**Step 2: Update main seeds file**

Add to `db/seeds.rb`:

```ruby
load Rails.root.join("db/seeds/profiling_recipes.rb")
```

**Step 3: Run seeds**

Run: `bin/rails db:seed`
Expected: Profiling recipes created

**Step 4: Commit**

```bash
git add db/seeds/profiling_recipes.rb db/seeds.rb
git commit -m "feat(profiling): add default profiling recipe seeds"
```

---

## Phase 7: Quality Gates

### Task 7.1: Run Full Test Suite

**Step 1: Run RSpec**

Run: `bin/rspec`
Expected: All tests pass

**Step 2: Run Rubocop**

Run: `bin/rubocop -f github`
Expected: No offenses

**Step 3: Fix any issues found**

If lint errors exist, run: `bin/rubocop -a`

**Step 4: Commit any fixes**

```bash
git add -A
git commit -m "fix: address linting issues"
```

---

### Task 7.2: Final Integration Test

**Step 1: Start development server**

Run: `bin/dev`

**Step 2: Manual verification checklist**

- [ ] Navigate to a node's detail page
- [ ] Verify "Profiling" tab appears
- [ ] Click "Run" on Quick System Report card
- [ ] Verify run appears in Recent Profiling Runs table
- [ ] Click "Custom Profile..." link
- [ ] Verify modal opens with form options
- [ ] Submit custom profile form
- [ ] View profiling run details page

**Step 3: Commit final changes**

```bash
git add -A
git commit -m "feat(profiling): complete Intel PerfSPECT integration"
```

---

## Summary

This plan implements Intel PerfSPECT integration in 7 phases:

1. **Foundation**: 7 tasks - Models, migrations, and associations
2. **Ansible**: 7 tasks - Playbook structure and role tasks
3. **Services & Jobs**: 3 tasks - ExecutorService, TriggerService, TriggerJob
4. **API**: 1 task - Callback endpoints for Ansible
5. **UI**: 5 tasks - Node profiling tab, forms, run display
6. **Seeds**: 1 task - Default profiling recipes
7. **Quality**: 2 tasks - Tests and integration verification

Total: ~26 discrete tasks with TDD approach throughout.
