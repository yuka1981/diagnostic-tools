# Remove Go Agent Code — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove the Go agent and all its integration (SSH services, agent API endpoints, agent-related DB columns/tables) from the codebase, since Salt custom modules now handle all remote execution.

**Architecture:** Single-pass deletion. Delete the `agent/` directory, remove all SSH/agent models/services/controllers/views, clean up references in remaining files, create a database migration to drop unused tables and columns, and update tests.

**Tech Stack:** Rails 7.2, PostgreSQL, RSpec, FactoryBot

---

### Task 1: Delete the Go agent directory

**Files:**
- Delete: `agent/` (entire directory tree)

**Step 1: Delete the agent directory**

```bash
rm -rf agent/
```

**Step 2: Verify deletion**

```bash
ls agent/ 2>&1 | grep "No such file or directory"
```

Expected: Error confirming directory is gone.

**Step 3: Commit**

```bash
git add -A agent/
git commit -m "chore: remove Go agent directory

Salt custom modules now handle all remote execution.
The Go agent CLI is no longer needed."
```

---

### Task 2: Delete agent/SSH API controllers

**Files:**
- Delete: `app/controllers/api/v1/heartbeats_controller.rb`
- Delete: `app/controllers/api/v1/health_controller.rb`
- Delete: `app/controllers/api/v1/benchmark_runs_controller.rb`
- Delete: `app/controllers/api/v1/mlc_installations_controller.rb`
- Delete: `app/controllers/api/v1/profiling_runs_controller.rb`

**Step 1: Delete the controller files**

```bash
rm app/controllers/api/v1/heartbeats_controller.rb
rm app/controllers/api/v1/health_controller.rb
rm app/controllers/api/v1/benchmark_runs_controller.rb
rm app/controllers/api/v1/mlc_installations_controller.rb
rm app/controllers/api/v1/profiling_runs_controller.rb
```

**Step 2: Update routes**

Edit `config/routes.rb`. Remove agent-facing API routes inside the `namespace :v1` block. Keep only `post "salt/events"`. The block should become:

```ruby
    namespace :v1 do
      post "salt/events", to: "salt_events#create"
    end
```

This removes:
- Line 20: `get "health", to: "health#show"`
- Lines 22-26: heartbeat route block
- Line 27: `resources :benchmark_runs`
- Lines 28-33: `resources :profiling_runs`
- Lines 34-39: `resources :mlc_installations`

**Step 3: Remove SSH defaults route**

In the same `config/routes.rb`, inside the `namespace :settings` block (line 53-63), remove line 54:

```ruby
    resource :ssh_defaults, only: [ :show, :update ], controller: :ssh_defaults
```

The settings block should become:

```ruby
  namespace :settings do
    resource :salt_api, only: [ :show, :update ], controller: :salt_api do
      post :test_connection
    end
    resources :server_products do
      collection do
        post :sync
      end
    end
  end
```

**Step 4: Commit**

```bash
git add -A
git commit -m "chore: remove agent API controllers and routes

Remove heartbeats, health, benchmark_runs, mlc_installations,
profiling_runs API controllers. Remove SSH defaults route.
Salt events endpoint is the only remaining API/v1 route."
```

---

### Task 3: Update controllers and services that reference SSH/agent code, then delete SSH/agent models and services

**Files:**
- Modify: `app/controllers/nodes/benchmark_runs_controller.rb`
- Modify: `app/views/nodes/benchmark_runs/new.html.erb`
- Modify: `app/controllers/benchmark_runs_controller.rb`
- Modify: `app/controllers/tasks_controller.rb`
- Modify: `app/controllers/mlc_installations_controller.rb`
- Modify: `app/controllers/nodes/profiling_runs_controller.rb`
- Modify: `app/services/inventory/process_state_service.rb`
- Delete: `app/models/ssh_setting.rb`
- Delete: `app/models/ssh_config.rb`
- Delete: `app/models/agent_event.rb`
- Delete: `app/services/ssh_execution_service.rb`
- Delete: `app/services/ssh_override_migration_service.rb`
- Delete: `app/services/benchmark/preflight_service.rb`
- Delete: `app/services/benchmark/cancel_run_service.rb`
- Delete: `app/services/mlc/trigger_install_service.rb`

**Step 1: Update `app/controllers/nodes/benchmark_runs_controller.rb`**

This controller references the deleted `Benchmark::PreflightService` (lines 21-25, 60-64) and has an `agent_token` method (lines 85-90). Remove the preflight calls from `new` and `create`, and remove the `agent_token` method.

In the `new` action, remove lines 21-25 (the `@preflight = ...` block). The action becomes:

```ruby
    def new
      @form = Benchmark::RunForm.new
      @benchmark_recipes = BenchmarkRecipe.active.order(:name, :version)
    end
```

In the `create` action's else branch (lines 58-66), remove lines 60-64 (the `@preflight = ...` block). The branch becomes:

```ruby
      else
        # Re-load recipes for re-rendering the form
        @benchmark_recipes = BenchmarkRecipe.active.order(:name, :version)
        render :new, status: :unprocessable_entity
      end
```

Remove the `agent_token` private method (lines 85-90):

```ruby
    def agent_token
      # Prefer per-node token (from direct column or associated ApiKey), fall back to global token
      @node.effective_api_token.presence ||
        Rails.application.credentials.dig(:api, :agent_token) ||
        ENV["API_AGENT_TOKEN"]
    end
```

**Step 2: Update `app/views/nodes/benchmark_runs/new.html.erb`**

This view extensively references `@preflight` (checks, config, success?) and `settings_ssh_defaults_path`. Remove all preflight-gated UI. The view should render the benchmark form directly without preflight checks. Remove:
- All references to `@preflight.checks`, `@preflight.failed_checks`, `@preflight.success?`, `@preflight.config`
- The preflight status cards/sections
- The `settings_ssh_defaults_path` link (line 95) — this route is deleted
- Any conditional form disabling based on `@preflight.success?`

The form should always render enabled with recipe selection and argument overrides.

**Step 3: Update `app/controllers/benchmark_runs_controller.rb`**

The `cancel` action (line 51) references the deleted `Benchmark::CancelRunService`. Replace with a direct status update. Change lines 51-58:

```ruby
    service = Benchmark::CancelRunService.new(@benchmark_run)
    result = service.call

    if result.success?
      flash[:notice] = "Benchmark run cancelled successfully."
    else
      flash[:alert] = "Failed to cancel benchmark run: #{result.error}"
    end
```

to:

```ruby
    @benchmark_run.update!(status: :cancelled, error_message: "Cancelled by user at #{Time.current}")
    flash[:notice] = "Benchmark run cancelled successfully."
```

**Step 4: Update `app/controllers/tasks_controller.rb`**

Lines 30-33 reference the deleted `Benchmark::CancelRunService`. Replace with a direct status update. Change lines 30-33:

```ruby
    if run.is_a?(BenchmarkRun)
      service = Benchmark::CancelRunService.new(run)
      result = service.call
      message = result.success? ? "Task cancelled successfully" : "Failed to cancel: #{result.error}"
    else
```

to:

```ruby
    if run.is_a?(BenchmarkRun)
      run.update!(status: :cancelled, error_message: "Cancelled by user at #{Time.current}")
      message = "Task cancelled successfully"
    else
```

Also remove the `agent_token` private method (lines 103-107):

```ruby
  def agent_token(node)
    node.effective_api_token.presence ||
      Rails.application.credentials.dig(:api, :agent_token) ||
      ENV["API_AGENT_TOKEN"]
  end
```

And update the `rerun` action's profiling branch (lines 69-74). The `agent_token` call must be replaced. Change:

```ruby
      Profiling::TriggerJob.perform_later(
        new_run,
        request.base_url,
        agent_token(new_run.node),
        user_id: current_user.id
      )
```

to:

```ruby
      Profiling::TriggerJob.perform_later(
        new_run,
        request.base_url,
        new_run.node.effective_api_token.presence || "",
        user_id: current_user.id
      )
```

**Step 5: Update `app/controllers/mlc_installations_controller.rb`**

The `enqueue_installation_job` method (lines 134-141) passes `agent_token` as the 3rd argument to `InstallJob.perform_later`, but Task 13 removes that parameter. Remove the `agent_token` argument. Change:

```ruby
  def enqueue_installation_job
    Mlc::InstallJob.perform_later(
      @installation.id,
      server_url,
      agent_token,
      user_id: current_user.id
    )
  end
```

to:

```ruby
  def enqueue_installation_job
    Mlc::InstallJob.perform_later(
      @installation.id,
      server_url,
      user_id: current_user.id
    )
  end
```

Also remove the now-unused `agent_token` private method (lines 147-149):

```ruby
  def agent_token
    ApiKey.active.first&.token || ""
  end
```

**Step 6: Update `app/controllers/nodes/profiling_runs_controller.rb`**

Remove the `agent_token` private method (lines 110-114):

```ruby
    def agent_token
      @node.effective_api_token.presence ||
        Rails.application.credentials.dig(:api, :agent_token) ||
        ENV["API_AGENT_TOKEN"]
    end
```

Update the `create` action (lines 66-71) to inline the token lookup:

```ruby
      Profiling::TriggerJob.perform_later(
        run,
        request.base_url,
        agent_token,
        user_id: current_user.id
      )
```

to:

```ruby
      Profiling::TriggerJob.perform_later(
        run,
        request.base_url,
        @node.effective_api_token.presence || "",
        user_id: current_user.id
      )
```

**Step 7: Update `app/services/inventory/process_state_service.rb`**

Remove the `agent_version` write in `update_node_attributes` (lines 108-109):

```ruby
      # Always update agent_version if provided (even if host_info is blank)
      updates[:agent_version] = @agent_version if @agent_version.present?
```

Also remove the `agent_version` parameter from `initialize` (line 24). Change:

```ruby
    def initialize(node_id: nil, hostname: nil, uuid: nil, raw_json:, agent_version: nil)
```

to:

```ruby
    def initialize(node_id: nil, hostname: nil, uuid: nil, raw_json:)
```

And remove `@agent_version = agent_version` (line 31).

**Step 8: Delete the service/model files**

```bash
rm app/models/ssh_setting.rb
rm app/models/ssh_config.rb
rm app/models/agent_event.rb
rm app/services/ssh_execution_service.rb
rm app/services/ssh_override_migration_service.rb
rm app/services/benchmark/preflight_service.rb
rm app/services/benchmark/cancel_run_service.rb
rm app/services/mlc/trigger_install_service.rb
```

**Step 9: Commit**

```bash
git add -A
git commit -m "chore: update references and remove SSH/agent models and services

Update controllers to remove PreflightService, CancelRunService,
and agent_token references. Remove SshSetting, SshConfig,
AgentEvent models. Remove SshExecutionService,
SshOverrideMigrationService, PreflightService, CancelRunService,
TriggerInstallService."
```

---

### Task 4: Delete SSH controllers, views, and JS

**Files:**
- Delete: `app/controllers/settings/ssh_defaults_controller.rb`
- Delete: `app/views/settings/ssh_defaults/` (entire directory)
- Delete: `app/javascript/controllers/ssh_override_controller.js`

**Step 1: Delete the files**

```bash
rm app/controllers/settings/ssh_defaults_controller.rb
rm -rf app/views/settings/ssh_defaults/
rm app/javascript/controllers/ssh_override_controller.js
```

**Step 2: Remove SshOverrideController from Stimulus index**

In `app/javascript/controllers/index.js`, remove lines 91-92:

```javascript
import SshOverrideController from "./ssh_override_controller"
application.register("ssh-override", SshOverrideController)
```

Without this, the JS build will break because it imports a deleted file.

**Step 3: Commit**

```bash
git add -A
git commit -m "chore: remove SSH defaults controller, views, and JS controller"
```

---

### Task 5: Delete agent/SSH spec files

**Files:**
- Delete: `spec/factories/agent_events.rb`
- Delete: `spec/models/ssh_setting_spec.rb`
- Delete: `spec/requests/api/v1/heartbeats_spec.rb`
- Delete: `spec/requests/api/v1/health_spec.rb` (if exists)
- Delete: `spec/requests/api/v1/benchmark_runs_spec.rb`
- Delete: `spec/requests/api/v1/mlc_installations_spec.rb`
- Delete: `spec/requests/api/v1/profiling_runs_spec.rb`
- Delete: `spec/requests/settings/ssh_spec.rb`
- Delete: `spec/system/settings/ssh_settings_spec.rb`
- Delete: `spec/services/ssh_override_migration_service_spec.rb`
- Delete: `spec/services/benchmark/preflight_service_spec.rb`
- Delete: `spec/services/benchmark/cancel_run_service_spec.rb`
- Delete: `spec/services/mlc/trigger_install_service_spec.rb`
- Delete: `app/services/benchmark/command_builders/base.rb`
- Delete: `app/services/benchmark/command_builders/hpcg_command_builder.rb`
- Delete: `app/services/benchmark/command_builders/mlc_command_builder.rb`
- Delete: `spec/services/benchmark/command_builders/base_spec.rb`
- Delete: `spec/services/benchmark/command_builders/hpcg_command_builder_spec.rb`
- Delete: `spec/services/benchmark/command_builders/mlc_command_builder_spec.rb`

**Step 1: Delete the spec files and dead agent command builders**

```bash
rm -f spec/factories/agent_events.rb
rm -f spec/models/ssh_setting_spec.rb
rm -f spec/requests/api/v1/heartbeats_spec.rb
rm -f spec/requests/api/v1/health_spec.rb
rm -f spec/requests/api/v1/benchmark_runs_spec.rb
rm -f spec/requests/api/v1/mlc_installations_spec.rb
rm -f spec/requests/api/v1/profiling_runs_spec.rb
rm -f spec/requests/settings/ssh_spec.rb
rm -f spec/system/settings/ssh_settings_spec.rb
rm -f spec/services/ssh_override_migration_service_spec.rb
rm -f spec/services/benchmark/preflight_service_spec.rb
rm -f spec/services/benchmark/cancel_run_service_spec.rb
rm -f spec/services/mlc/trigger_install_service_spec.rb
rm -rf app/services/benchmark/command_builders/
rm -rf spec/services/benchmark/command_builders/
```

**Step 2: Commit**

```bash
git add -A
git commit -m "chore: remove agent/SSH spec files"
```

---

### Task 6: Update Node model — remove SSH/agent code

**Files:**
- Modify: `app/models/node.rb`

**Step 1: Remove agent_events association**

In `app/models/node.rb`, remove line 14:

```ruby
  has_many :agent_events, dependent: :destroy
```

**Step 2: Remove SSH enum**

Remove line 25:

```ruby
  enum :ssh_connect_method, { global_bastion: 0, direct: 2 }, default: :global_bastion
```

**Step 3: Remove SSH validations**

Remove lines 33-34:

```ruby
  validates :ssh_port, numericality: { only_integer: true, greater_than: 0, less_than: 65536 }
  validates :ssh_user, length: { maximum: 255 }
```

**Step 4: Remove all effective_ssh_* methods**

Remove lines 86-111 (the comment block and all six methods):

```ruby
  # Simplified effective_* methods using override flags
  # If override flag is true, use node value. Otherwise, use global default.

  def effective_ssh_user
    ssh_user_override? ? ssh_user : SshSetting.current.ssh_user
  end

  def effective_ssh_port
    ssh_port_override? ? ssh_port : SshSetting.current.ssh_port
  end

  def effective_ssh_connect_method
    ssh_connect_method_override? ? ssh_connect_method : "global_bastion"
  end

  def effective_ssh_key
    ssh_key_override? ? ssh_key : SshSetting.current.ssh_key
  end

  def effective_ssh_password
    ssh_password_override? ? ssh_password : SshSetting.current.ssh_password
  end

  def effective_sudo_credential
    sudo_credential_override? ? sudo_credential : SshSetting.current.sudo_credential
  end
```

**Step 5: Commit**

```bash
git add app/models/node.rb
git commit -m "chore: remove SSH/agent code from Node model

Remove agent_events association, ssh_connect_method enum,
SSH validations, and all effective_ssh_* methods."
```

---

### Task 7: Update BenchmarkRun model and Salt service — remove agent status mapping

**Files:**
- Modify: `app/services/salt/benchmark_result_service.rb`
- Modify: `app/models/benchmark_run.rb`

**Step 1: Inline status mapping in Salt::BenchmarkResultService**

`app/services/salt/benchmark_result_service.rb` line 23 calls `BenchmarkRun.status_from_agent(result["status"])` which is about to be removed. This is the **active Salt workflow** — it must keep working. Inline the mapping directly. Change line 23:

```ruby
      status = BenchmarkRun.status_from_agent(result["status"]) || :failed
```

to:

```ruby
      status_map = { "PASS" => :success, "FAIL" => :failed, "ERROR" => :failed, "RUNNING" => :running }
      status = status_map[result["status"]] || :failed
```

**Step 2: Remove AGENT_STATUS_MAP and status_from_agent**

In `app/models/benchmark_run.rb`, remove lines 19-25:

```ruby
  # Maps agent-reported status strings to model status symbols
  AGENT_STATUS_MAP = {
    "PASS" => :success,
    "FAIL" => :failed,
    "ERROR" => :failed,
    "RUNNING" => :running
  }.freeze
```

And remove lines 51-57:

```ruby
  # Class methods
  # Converts agent status string to model status symbol
  # @param agent_status [String] Status from agent (PASS, FAIL, ERROR, RUNNING)
  # @return [Symbol, nil] Model status symbol or nil if unknown
  def self.status_from_agent(agent_status)
    AGENT_STATUS_MAP[agent_status]
  end
```

**Step 3: Commit**

```bash
git add app/models/benchmark_run.rb app/services/salt/benchmark_result_service.rb
git commit -m "chore: remove agent status mapping from BenchmarkRun

Inline the status map into Salt::BenchmarkResultService before
removing AGENT_STATUS_MAP and status_from_agent."
```

---

### Task 8: Update BenchmarkConfig — remove SshSetting dependency

**Files:**
- Modify: `app/models/benchmark_config.rb`

**Step 1: Simplify BenchmarkConfig**

Replace the entire file with a version that doesn't depend on SshSetting. The `global_work_dir` method relied on `SshSetting.current.benchmark_work_dir` which no longer exists. Since `benchmark_work_dir` will also be removed from nodes (Task 14), simplify to just return the default:

```ruby
# frozen_string_literal: true

class BenchmarkConfig
  DEFAULT_WORK_DIR = "hpcg_source"

  # Get the effective benchmark work directory for a node
  def self.work_dir_for(_node = nil)
    DEFAULT_WORK_DIR
  end

  # Get the default work directory constant
  def self.default_work_dir
    DEFAULT_WORK_DIR
  end
end
```

**Step 2: Commit**

```bash
git add app/models/benchmark_config.rb
git commit -m "chore: remove SshSetting dependency from BenchmarkConfig"
```

---

### Task 9: Update API BaseController — remove agent token fallback

**Files:**
- Modify: `app/controllers/api/v1/base_controller.rb`

**Step 1: Remove legacy agent token fallback**

In `app/controllers/api/v1/base_controller.rb`, simplify the `valid_token?` method. Remove the legacy static token fallback (lines 32-36). The method should become:

```ruby
      def valid_token?(token)
        api_key = ApiKey.active.find_by(token: token)

        if api_key
          api_key.touch_last_used
          return true
        end

        false
      end
```

**Step 2: Commit**

```bash
git add app/controllers/api/v1/base_controller.rb
git commit -m "chore: remove legacy agent token fallback from API auth"
```

---

### Task 10: Update sidebar — remove SSH Defaults link

**Files:**
- Modify: `app/views/shared/_sidebar.html.erb`

**Step 1: Remove SSH Defaults link**

In `app/views/shared/_sidebar.html.erb`, remove lines 133-138 (the SSH Defaults link block):

```erb
          <%= link_to settings_ssh_defaults_path,
              data: { turbo_prefetch: false },
              class: "flex items-center gap-3 px-5 py-2 text-sm font-bold rounded transition-colors #{request.path.start_with?('/settings/ssh_defaults') ? 'bg-primary-1 text-primary-6' : 'hover:bg-neutral-4 hover:text-primary-6'}" do %>
            <%= lucide_icon("lock", class: "h-5 w-5 opacity-75") %>
            SSH Defaults
          <% end %>
```

**Step 2: Commit**

```bash
git add app/views/shared/_sidebar.html.erb
git commit -m "chore: remove SSH Defaults link from sidebar"
```

---

### Task 11: Update NodeFormWizardComponent — remove SSH fields

**Files:**
- Modify: `app/components/node_form_wizard_component.rb`
- Modify: `app/components/node_form_wizard_component.html.erb`

**Step 1: Update the Ruby component**

In `app/components/node_form_wizard_component.rb`:

1. Remove `agent_config` parameter from initialize (line 4). Change to:

```ruby
  def initialize(node:, api_keys: [], testid: nil)
    @node = node
    @api_keys = api_keys
    @testid = testid
  end
```

2. Remove `agent_config` from `attr_reader` (line 13). Change to:

```ruby
  attr_reader :node, :api_keys, :testid
```

3. Update `default_benchmark_work_dir` method (lines 42-44). Change to:

```ruby
  def default_benchmark_work_dir
    BenchmarkConfig::DEFAULT_WORK_DIR
  end
```

4. Remove `ssh_connect_methods_for_select` method (lines 52-54).

**Step 2: Update the template — reduce to 2-step wizard**

In `app/components/node_form_wizard_component.html.erb`:

1. Change the wizard total from 3 to 2. Line 1, change `data-wizard-total-value="3"` to `data-wizard-total-value="2"`.

2. Replace the step labels array (line 5). Change:

```erb
      <% ["Basic Info", "Server & Location", "Connection"].each_with_index do |label, index| %>
```

to:

```erb
      <% ["Basic Info", "Server & Location"].each_with_index do |label, index| %>
```

3. Update the end check in the step labels (line 16). Change `unless index == 2` to `unless index == 1`.

4. Delete the entire Step 3 block (lines 156-296). This is the `<%# Step 3: Connection %>` div containing all SSH override fields and the Benchmark Configuration card.

5. Move the API Key select and Benchmark Working Directory fields into Step 2 if they're still needed, OR remove them entirely since `benchmark_work_dir` is being dropped from the nodes table.

Since `benchmark_work_dir` column will be removed and API key association stays, move just the API key select into Step 2. Add it after the Rack Assignment card inside Step 2 (after line 153's closing `</div>`):

```erb
      <div class="card-netbox">
        <div class="card-header">
          <h3 class="card-title">API Configuration</h3>
        </div>
        <div class="p-4">
          <div>
            <%= f.label :api_key_id, "API Token", class: "block text-sm font-bold text-neutral-85 mb-1" %>
            <%= f.select :api_key_id,
                options_for_select([["-- Select API Key --", ""]] + api_keys_for_select, node.api_key_id),
                {},
                class: "block w-full rounded-md border-neutral-15 shadow-sm focus:border-primary-5 focus:ring-primary-5 sm:text-sm" %>
            <p class="mt-1 text-xs text-neutral-45">
              Select an API key for Salt operations. Manage keys in
              <%= link_to "API Keys", api_keys_path, class: "text-primary-6 hover:text-primary-8", data: { turbo_frame: "_top" } %>.
            </p>
          </div>
        </div>
      </div>
```

**Step 3: Commit**

```bash
git add app/components/node_form_wizard_component.rb app/components/node_form_wizard_component.html.erb
git commit -m "chore: remove SSH fields from node form wizard

Reduce to 2-step wizard. Remove all SSH override fields.
Keep API key select, move it to Step 2."
```

---

### Task 12: Update NodesController — remove SSH params

**Files:**
- Modify: `app/controllers/nodes_controller.rb`

**Step 1: Update node_params**

In `app/controllers/nodes_controller.rb`, update the `node_params` method (lines 190-198). Remove all SSH/agent-related params. Change to:

```ruby
  def node_params
    params.require(:node).permit(
      :hostname, :ip, :role, :arch,
      :api_key_id, :rack_id, :rack_position, :rack_height, :server_product_id
    )
  end
```

**Step 2: Commit**

```bash
git add app/controllers/nodes_controller.rb
git commit -m "chore: remove SSH/agent params from NodesController"
```

---

### Task 13: Update Mlc::InstallJob — remove agent_token and SSH service dependency

**Files:**
- Modify: `app/jobs/mlc/install_job.rb`

**Step 1: Remove agent_token parameter and TriggerInstallService usage**

The `TriggerInstallService` was deleted in Task 3. This job needs to be updated to use Salt instead. For now, since the Salt-based replacement service doesn't exist yet, replace the SSH call with a placeholder that raises NotImplementedError:

Update `app/jobs/mlc/install_job.rb`:

1. Remove `agent_token` from the `perform` signature (line 5). Change to:

```ruby
    def perform(installation_id, server_url, user_id: nil)
```

2. Remove `@agent_token = agent_token` (line 8).

3. Update `process_single_node` to remove TriggerInstallService usage. Replace lines 44-49 with:

```ruby
      # TODO: Replace with Salt-based MLC installation service
      raise NotImplementedError, "MLC installation via Salt not yet implemented"
```

**Step 2: Commit**

```bash
git add app/jobs/mlc/install_job.rb
git commit -m "chore: remove agent_token and SSH service from MLC install job

TriggerInstallService was removed. Salt-based replacement TODO."
```

---

### Task 14: Create database migration

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_remove_agent_and_ssh_integration.rb`

**Step 1: Generate the migration**

```bash
bin/rails generate migration RemoveAgentAndSshIntegration
```

**Step 2: Write the migration**

Edit the generated file. Replace its contents with:

```ruby
class RemoveAgentAndSshIntegration < ActiveRecord::Migration[7.2]
  def up
    # Drop agent/SSH tables
    drop_table :agent_events, if_exists: true
    drop_table :agent_binaries, if_exists: true
    drop_table :agent_releases, if_exists: true
    drop_table :ssh_settings, if_exists: true

    # Remove agent columns from nodes
    remove_column :nodes, :agent_path, if_exists: true
    remove_column :nodes, :agent_version, if_exists: true
    remove_column :nodes, :agent_status, if_exists: true
    remove_column :nodes, :last_heartbeat_at, if_exists: true

    # Remove SSH columns from nodes
    remove_column :nodes, :ssh_port, if_exists: true
    remove_column :nodes, :ssh_user, if_exists: true
    remove_column :nodes, :ssh_key, if_exists: true
    remove_column :nodes, :ssh_password, if_exists: true
    remove_column :nodes, :ssh_connect_method, if_exists: true
    remove_column :nodes, :sudo_credential, if_exists: true
    remove_column :nodes, :benchmark_work_dir, if_exists: true

    # Remove SSH override flags from nodes
    remove_column :nodes, :ssh_user_override, if_exists: true
    remove_column :nodes, :ssh_port_override, if_exists: true
    remove_column :nodes, :ssh_key_override, if_exists: true
    remove_column :nodes, :ssh_password_override, if_exists: true
    remove_column :nodes, :sudo_credential_override, if_exists: true
    remove_column :nodes, :ssh_connect_method_override, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
```

**Step 3: Run the migration**

```bash
bin/rails db:migrate
```

Expected: Migration runs successfully, `db/schema.rb` is updated.

**Step 4: Verify schema**

Check `db/schema.rb` no longer contains `agent_binaries`, `agent_events`, `agent_releases`, `ssh_settings` tables, and that the `nodes` table no longer has `ssh_*`, `agent_*`, `sudo_credential`, or `benchmark_work_dir` columns.

**Step 5: Commit**

```bash
git add db/migrate/*_remove_agent_and_ssh_integration.rb db/schema.rb
git commit -m "chore: drop agent/SSH tables and columns from database"
```

---

### Task 15: Update spec files — node model spec and benchmark_run spec

**Files:**
- Modify: `spec/models/node_spec.rb`
- Modify: `spec/models/benchmark_run_spec.rb`

**Step 1: Remove effective_ssh_* tests**

Remove the entire `describe "#effective_ssh_user"` block (lines 335-354).
Remove the entire `describe "#effective_ssh_port"` block (lines 356-374).
Remove the entire `describe "#effective_ssh_connect_method"` block (lines 376-390).

**Step 2: Remove agent_events association test**

In the `describe "dependent destroy associations"` block (lines 396-413), remove:

```ruby
    it { is_expected.to have_many(:agent_events).dependent(:destroy) }
```

And in the integration test (lines 403-412), remove the `create(:agent_event, node: node)` line.

**Step 3: Remove status_from_agent tests from benchmark_run spec**

In `spec/models/benchmark_run_spec.rb`, remove the entire `describe ".status_from_agent"` block (lines 204-224):

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

**Step 4: Commit**

```bash
git add spec/models/node_spec.rb spec/models/benchmark_run_spec.rb
git commit -m "test: remove SSH/agent tests from node and benchmark_run model specs"
```

---

### Task 16: Update spec files — benchmark_config_spec

**Files:**
- Modify: `spec/models/benchmark_config_spec.rb`

**Step 1: Rewrite to match simplified BenchmarkConfig**

Replace `spec/models/benchmark_config_spec.rb` with:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe BenchmarkConfig do
  describe ".work_dir_for" do
    it "returns the default work directory" do
      expect(described_class.work_dir_for(nil)).to eq(BenchmarkConfig::DEFAULT_WORK_DIR)
    end

    it "returns the default work directory regardless of node" do
      node = create(:node)
      expect(described_class.work_dir_for(node)).to eq(BenchmarkConfig::DEFAULT_WORK_DIR)
    end
  end

  describe ".default_work_dir" do
    it "returns the default constant" do
      expect(described_class.default_work_dir).to eq("hpcg_source")
    end
  end
end
```

**Step 2: Commit**

```bash
git add spec/models/benchmark_config_spec.rb
git commit -m "test: update benchmark_config_spec for simplified BenchmarkConfig"
```

---

### Task 17: Update spec files — node form wizard component spec

**Files:**
- Modify: `spec/components/node_form_wizard_component_spec.rb`

**Step 1: Update for 2-step wizard**

1. Remove `agent_config` from the let block (line 8) and the component constructor (lines 10-15).

2. Update step count assertions: change `3` to `2` everywhere (lines 21, 26, 32).

3. Remove the entire `context "step 3 (Connection)"` block (lines 74-91).

4. Update the component constructor throughout:

```ruby
  subject(:component) do
    described_class.new(
      node: node,
      api_keys: api_keys
    )
  end
```

**Step 2: Commit**

```bash
git add spec/components/node_form_wizard_component_spec.rb
git commit -m "test: update node form wizard spec for 2-step wizard"
```

---

### Task 18: Update spec files — nodes request spec

**Files:**
- Modify: `spec/requests/nodes_spec.rb`

**Step 1: Remove SSH-specific tests**

1. In `POST /nodes` valid_params (lines 40-51), remove `ssh_port`, `ssh_user`, `ssh_key`, `password` from params. Change to:

```ruby
    let(:valid_params) do
      {
        node: {
          hostname: "new-node",
          role: "compute",
          arch: "x86_64"
        }
      }
    end
```

2. In `PATCH /nodes/:id` (line 80), change `update_params` to not use `ssh_port`:

```ruby
    let(:update_params) { { node: { arch: "aarch64" } } }
```

3. Update the assertion on line 84 to match:

```ruby
      expect(node.reload.arch).to eq("aarch64")
```

4. Remove the `ssh_password` and `sudo_credential` tests (lines 104-114).

**Step 2: Commit**

```bash
git add spec/requests/nodes_spec.rb
git commit -m "test: remove SSH params from nodes request spec"
```

---

### Task 19: Update spec files — node factory

**Files:**
- Modify: `spec/factories/nodes.rb`

**Step 1: Remove SSH-related factory attributes and traits**

1. Remove `ssh_port { 22 }` from the base factory (line 11).

2. Remove these traits entirely:
   - `:direct` (lines 64-67)
   - `:global_bastion` (lines 69-71)
   - `:custom_bastion` (lines 73-76)
   - `:with_ssh_user_override` (lines 79-82)
   - `:with_ssh_port_override` (lines 84-87)

**Step 2: Commit**

```bash
git add spec/factories/nodes.rb
git commit -m "test: remove SSH traits from node factory"
```

---

### Task 20: Update spec files — benchmark and system specs

**Files:**
- Modify: `spec/requests/nodes/benchmark_runs_spec.rb`
- Modify: `spec/requests/mlc_installations_spec.rb`
- Modify: `spec/system/benchmark_run_feature_spec.rb`
- Modify: `spec/system/benchmark_progress_spec.rb`
- Modify: `spec/system/node_management_spec.rb`
- Modify: `spec/jobs/mlc/install_job_spec.rb`

**Step 1: Update benchmark_runs request spec**

In `spec/requests/nodes/benchmark_runs_spec.rb`, remove the entire `before` block (lines 9-34) that mocks `Benchmark::PreflightService`. The `PreflightService` class no longer exists, so these references will cause errors. Replace with just `sign_in user`:

```ruby
  before do
    sign_in user
  end
```

**Step 2: Update benchmark_run_feature system spec**

In `spec/system/benchmark_run_feature_spec.rb`, remove the `Benchmark::PreflightService` mock from the `before` block (lines 14-35). Keep just:

```ruby
  before do
    sign_in approver
    driven_by(:rack_test)
  end
```

**Step 3: Update benchmark_progress system spec**

In `spec/system/benchmark_progress_spec.rb`, remove the `Benchmark::PreflightService` mock from the `before` block (lines 14-35). Keep just:

```ruby
  before do
    sign_in approver
  end
```

**Step 4: Update node_management system spec**

In `spec/system/node_management_spec.rb`, the test creates a node with SSH settings. The form no longer has SSH fields. Rewrite the test to use the 2-step wizard:

```ruby
  it "allows an approver to add a new node" do
    visit nodes_path
    click_link "Add Node"

    within "turbo-frame#node_modal" do
      # Step 1: Basic Information
      fill_in "Hostname", with: "compute-001"
      fill_in "IP Address", with: "192.168.1.100"
      select "Compute", from: "Role"
      select "x86_64", from: "Architecture"
      click_button "Next"

      # Step 2: Server & Location
      click_button "Save Node"
    end

    expect(page).to have_content("compute-001")
    expect(page).to have_content("192.168.1.100")

    node = Node.find_by(hostname: "compute-001")
    expect(node).to be_present

    # Ensure modal is closed
    expect(page).not_to have_selector("turbo-frame#node_modal .card-netbox")
  end
```

**Step 5: Update mlc_installations request spec**

In `spec/requests/mlc_installations_spec.rb`, the `POST /mlc_installations` context (line 25) creates a node with the `:direct` trait which is removed in Task 19. Change:

```ruby
    let(:node) { create(:node, :online, :direct) }
```

to:

```ruby
    let(:node) { create(:node, :online) }
```

**Step 6: Update MLC install job spec**

In `spec/jobs/mlc/install_job_spec.rb`:

1. Remove `:direct` trait from node creation (line 5). Change to:

```ruby
  let(:node) { create(:node, :online) }
```

2. Replace all `SshExecutionService::Result` references since the class no longer exists. Since the job now raises `NotImplementedError`, update the tests to expect that:

```ruby
RSpec.describe Mlc::InstallJob, type: :job do
  let(:installation) { create(:mlc_installation) }
  let(:node) { create(:node, :online) }
  let!(:installation_node) { create(:mlc_installation_node, mlc_installation: installation, node: node) }

  describe "#perform" do
    it "sets started_at timestamp and raises NotImplementedError" do
      expect {
        described_class.perform_now(installation.id, "http://localhost:3000")
      }.to raise_error(NotImplementedError)

      installation.reload
      expect(installation.started_at).to be_present
    end
  end
end
```

**Step 7: Commit**

```bash
git add spec/requests/nodes/benchmark_runs_spec.rb \
        spec/requests/mlc_installations_spec.rb \
        spec/system/benchmark_run_feature_spec.rb \
        spec/system/benchmark_progress_spec.rb \
        spec/system/node_management_spec.rb \
        spec/jobs/mlc/install_job_spec.rb
git commit -m "test: update benchmark, MLC, and system specs for agent removal

Remove PreflightService mocks, SshExecutionService references,
:direct trait usage, SSH form assertions, and update MLC install job spec."
```

---

### Task 21: Run tests and fix remaining failures

**Step 1: Run rubocop**

```bash
bin/rubocop -f github
```

Expected: No offenses. Fix any issues found.

**Step 2: Run all tests**

```bash
bin/rspec
```

Expected: All green. If failures occur, read the error output carefully and fix:

- Missing constant errors → grep for the deleted class name and remove/update references
- Missing column errors → grep for the column name and remove/update references
- Missing route errors → grep for the route helper and remove/update references

**Step 3: Search for remaining references**

```bash
grep -r "SshSetting\|SshConfig\|AgentEvent\|SshExecutionService\|PreflightService\|CancelRunService\|TriggerInstallService\|CommandBuilder\|agent_events\|agent_path\|agent_version\|agent_status\|last_heartbeat_at\|ssh_user_override\|ssh_port_override\|ssh_key_override\|ssh_password_override\|sudo_credential_override\|ssh_connect_method_override\|effective_ssh\|ssh_defaults\|qis-agent\|hpc-agent\|status_from_agent\|AGENT_STATUS_MAP\|ssh_override\|agent_token" --include="*.rb" --include="*.erb" --include="*.js" app/ spec/ config/
```

Expected: No matches (or only matches in migration files, which are fine).

**Step 4: Fix any remaining issues and commit**

```bash
git add -A
git commit -m "fix: resolve remaining agent/SSH references after removal"
```

---

### Task 22: Final verification and commit

**Step 1: Run full quality gate**

```bash
bin/rubocop -f github && bin/rspec
```

Expected: Both pass cleanly.

**Step 2: Verify no stale references**

```bash
grep -r "SshSetting\|agent_events\|effective_ssh\|PreflightService\|qis-agent" --include="*.rb" --include="*.erb" app/ spec/ config/ | grep -v "db/migrate"
```

Expected: No output.

**Step 3: Verify database schema**

```bash
bin/rails db:migrate:status
```

Expected: All migrations show `up` status.
