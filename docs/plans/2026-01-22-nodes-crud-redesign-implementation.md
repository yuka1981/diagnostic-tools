# Nodes CRUD UI/UX Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Simplify the node creation form into a 3-step wizard with SSH profiles, agent config defaults, hostname autocomplete, and bulk node creation.

**Architecture:** Rails 7.2 with Hotwire (Turbo + Stimulus), ViewComponents, PostgreSQL. New `SshProfile` model for reusable SSH configs, extend `SshSetting` singleton for agent defaults. Wizard implemented as single-page Stimulus controller with step navigation.

**Tech Stack:** Ruby on Rails 7.2.3, Hotwire (Turbo Streams + Stimulus), ViewComponent, Tailwind CSS, RSpec + FactoryBot

---

## Phase 1: Foundation (SshProfile Model + Agent Config Extension)

### Task 1.1: Create SshProfile Migration

**Files:**
- Create: `db/migrate/TIMESTAMP_create_ssh_profiles.rb`

**Step 1: Generate migration**

Run: `bin/rails generate migration CreateSshProfiles`

**Step 2: Edit migration file**

```ruby
# frozen_string_literal: true

class CreateSshProfiles < ActiveRecord::Migration[7.2]
  def change
    create_table :ssh_profiles do |t|
      t.string :name, null: false, limit: 255
      t.integer :ssh_connect_method, default: 0, null: false
      t.integer :ssh_port, default: 22, null: false
      t.string :ssh_user, limit: 255
      t.string :ssh_password
      t.text :ssh_key
      t.string :sudo_credential
      t.string :jump_host, limit: 255
      t.string :jump_user, limit: 255
      t.integer :jump_port

      t.timestamps
    end

    add_index :ssh_profiles, :name, unique: true
  end
end
```

**Step 3: Run migration**

Run: `bin/rails db:migrate`
Expected: Migration completes successfully

**Step 4: Commit**

```bash
git add db/migrate/*_create_ssh_profiles.rb db/schema.rb
git commit -m "db: add ssh_profiles table"
```

---

### Task 1.2: Create SshProfile Model with Tests

**Files:**
- Create: `app/models/ssh_profile.rb`
- Create: `spec/models/ssh_profile_spec.rb`
- Create: `spec/factories/ssh_profiles.rb`

**Step 1: Write the factory**

```ruby
# spec/factories/ssh_profiles.rb
# frozen_string_literal: true

FactoryBot.define do
  factory :ssh_profile do
    sequence(:name) { |n| "SSH Profile #{n}" }
    ssh_connect_method { :global_bastion }
    ssh_port { 22 }
    ssh_user { "deploy" }

    trait :direct do
      ssh_connect_method { :direct }
    end

    trait :global_bastion do
      ssh_connect_method { :global_bastion }
    end

    trait :custom_bastion do
      ssh_connect_method { :custom_bastion }
      jump_host { "bastion.example.com" }
      jump_user { "bastion_user" }
      jump_port { 22 }
    end

    trait :with_key do
      ssh_key { "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ..." }
    end

    trait :with_password do
      ssh_password { "secret123" }
    end
  end
end
```

**Step 2: Write the failing tests**

```ruby
# spec/models/ssh_profile_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe SshProfile, type: :model do
  describe "validations" do
    subject { build(:ssh_profile) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(255) }
    it { is_expected.to validate_presence_of(:ssh_connect_method) }
    it { is_expected.to validate_numericality_of(:ssh_port).only_integer.is_greater_than(0).is_less_than(65536) }
    it { is_expected.to validate_numericality_of(:jump_port).only_integer.is_greater_than(0).is_less_than(65536).allow_nil }
  end

  describe "enums" do
    it "defines ssh_connect_method enum" do
      expect(SshProfile.ssh_connect_methods).to eq({
        "global_bastion" => 0,
        "custom_bastion" => 1,
        "direct" => 2
      })
    end
  end

  describe "associations" do
    it { is_expected.to have_many(:nodes) }
  end

  describe "factory" do
    it "creates a valid ssh_profile" do
      expect(build(:ssh_profile)).to be_valid
    end

    it "creates valid custom_bastion profile" do
      profile = build(:ssh_profile, :custom_bastion)
      expect(profile).to be_valid
      expect(profile.jump_host).to eq("bastion.example.com")
    end
  end

  describe "#display_connection_method" do
    it "returns human-readable connection method" do
      profile = build(:ssh_profile, :global_bastion)
      expect(profile.display_connection_method).to eq("Global Bastion")
    end
  end
end
```

**Step 3: Run tests to verify they fail**

Run: `bin/rspec spec/models/ssh_profile_spec.rb`
Expected: FAIL - uninitialized constant SshProfile

**Step 4: Write the model**

```ruby
# app/models/ssh_profile.rb
# frozen_string_literal: true

class SshProfile < ApplicationRecord
  # Associations
  has_many :nodes, dependent: :nullify

  # Enums (matches Node model for consistency)
  enum :ssh_connect_method, { global_bastion: 0, custom_bastion: 1, direct: 2 }, default: :global_bastion

  # Validations
  validates :name, presence: true, uniqueness: true, length: { maximum: 255 }
  validates :ssh_connect_method, presence: true
  validates :ssh_port, numericality: { only_integer: true, greater_than: 0, less_than: 65536 }
  validates :ssh_user, length: { maximum: 255 }
  validates :jump_port, numericality: { only_integer: true, greater_than: 0, less_than: 65536 }, allow_nil: true

  # Instance methods
  def display_connection_method
    ssh_connect_method.to_s.titleize
  end
end
```

**Step 5: Run tests to verify they pass**

Run: `bin/rspec spec/models/ssh_profile_spec.rb`
Expected: All tests pass

**Step 6: Run rubocop**

Run: `bin/rubocop app/models/ssh_profile.rb spec/models/ssh_profile_spec.rb spec/factories/ssh_profiles.rb -a`
Expected: No offenses (or auto-fixed)

**Step 7: Commit**

```bash
git add app/models/ssh_profile.rb spec/models/ssh_profile_spec.rb spec/factories/ssh_profiles.rb
git commit -m "feat: add SshProfile model with validations and tests"
```

---

### Task 1.3: Add Node Association to SshProfile

**Files:**
- Create: `db/migrate/TIMESTAMP_add_ssh_profile_to_nodes.rb`
- Modify: `app/models/node.rb:5-12` (associations section)
- Modify: `spec/models/node_spec.rb:286-289` (associations section)

**Step 1: Generate migration**

Run: `bin/rails generate migration AddSshProfileToNodes ssh_profile:references ssh_profile_override:boolean`

**Step 2: Edit migration**

```ruby
# frozen_string_literal: true

class AddSshProfileToNodes < ActiveRecord::Migration[7.2]
  def change
    add_reference :nodes, :ssh_profile, null: true, foreign_key: true
    add_column :nodes, :ssh_profile_override, :boolean, default: false, null: false
  end
end
```

**Step 3: Run migration**

Run: `bin/rails db:migrate`

**Step 4: Write failing test**

Add to `spec/models/node_spec.rb` in the associations describe block:

```ruby
it { is_expected.to belong_to(:ssh_profile).optional }
```

**Step 5: Run test to verify it fails**

Run: `bin/rspec spec/models/node_spec.rb:287`
Expected: FAIL

**Step 6: Update Node model**

Add to `app/models/node.rb` in associations section (after line 11):

```ruby
belongs_to :ssh_profile, optional: true
```

**Step 7: Run test to verify it passes**

Run: `bin/rspec spec/models/node_spec.rb`
Expected: All tests pass

**Step 8: Commit**

```bash
git add db/migrate/*_add_ssh_profile_to_nodes.rb db/schema.rb app/models/node.rb spec/models/node_spec.rb
git commit -m "feat: add ssh_profile association to Node"
```

---

### Task 1.4: Add effective_ssh_* Methods to Node

**Files:**
- Modify: `app/models/node.rb:56-88` (instance methods section)
- Modify: `spec/models/node_spec.rb` (add new describe block)

**Step 1: Write failing tests**

Add to `spec/models/node_spec.rb`:

```ruby
describe "#effective_ssh_user" do
  let(:ssh_profile) { create(:ssh_profile, ssh_user: "profile_user") }

  context "when ssh_profile_override is true" do
    it "returns node's ssh_user" do
      node = build(:node, ssh_profile: ssh_profile, ssh_user: "node_user", ssh_profile_override: true)
      expect(node.effective_ssh_user).to eq("node_user")
    end
  end

  context "when ssh_profile_override is false and profile exists" do
    it "returns profile's ssh_user" do
      node = build(:node, ssh_profile: ssh_profile, ssh_user: "node_user", ssh_profile_override: false)
      expect(node.effective_ssh_user).to eq("profile_user")
    end
  end

  context "when no profile exists" do
    it "returns node's ssh_user" do
      node = build(:node, ssh_profile: nil, ssh_user: "node_user")
      expect(node.effective_ssh_user).to eq("node_user")
    end
  end
end

describe "#effective_ssh_port" do
  let(:ssh_profile) { create(:ssh_profile, ssh_port: 2222) }

  context "when using profile settings" do
    it "returns profile's ssh_port" do
      node = build(:node, ssh_profile: ssh_profile, ssh_port: 22, ssh_profile_override: false)
      expect(node.effective_ssh_port).to eq(2222)
    end
  end

  context "when using node override" do
    it "returns node's ssh_port" do
      node = build(:node, ssh_profile: ssh_profile, ssh_port: 3333, ssh_profile_override: true)
      expect(node.effective_ssh_port).to eq(3333)
    end
  end
end

describe "#effective_ssh_connect_method" do
  let(:ssh_profile) { create(:ssh_profile, :custom_bastion) }

  context "when using profile settings" do
    it "returns profile's connect method" do
      node = build(:node, ssh_profile: ssh_profile, ssh_connect_method: :direct, ssh_profile_override: false)
      expect(node.effective_ssh_connect_method).to eq("custom_bastion")
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rspec spec/models/node_spec.rb -e "effective_ssh"`
Expected: FAIL - undefined method

**Step 3: Implement methods in Node model**

Add to `app/models/node.rb` after `status` method:

```ruby
# Returns effective SSH user (from profile or node override)
def effective_ssh_user
  use_profile_settings? ? ssh_profile.ssh_user : ssh_user
end

# Returns effective SSH port (from profile or node override)
def effective_ssh_port
  use_profile_settings? ? ssh_profile.ssh_port : ssh_port
end

# Returns effective SSH connect method (from profile or node override)
def effective_ssh_connect_method
  use_profile_settings? ? ssh_profile.ssh_connect_method : ssh_connect_method
end

# Returns effective SSH key (from profile or node override)
def effective_ssh_key
  use_profile_settings? ? ssh_profile.ssh_key : ssh_key
end

# Returns effective SSH password (from profile or node override)
def effective_ssh_password
  use_profile_settings? ? ssh_profile.ssh_password : ssh_password
end

# Returns effective sudo credential (from profile or node override)
def effective_sudo_credential
  use_profile_settings? ? ssh_profile.sudo_credential : sudo_credential
end

# Returns effective jump host (from profile or node override)
def effective_jump_host
  use_profile_settings? ? ssh_profile.jump_host : jump_host
end

# Returns effective jump user (from profile or node override)
def effective_jump_user
  use_profile_settings? ? ssh_profile.jump_user : jump_user
end

# Returns effective jump port (from profile or node override)
def effective_jump_port
  use_profile_settings? ? ssh_profile.jump_port : jump_port
end

private

def use_profile_settings?
  ssh_profile.present? && !ssh_profile_override
end
```

**Step 4: Run tests to verify they pass**

Run: `bin/rspec spec/models/node_spec.rb -e "effective_ssh"`
Expected: All pass

**Step 5: Run full node spec**

Run: `bin/rspec spec/models/node_spec.rb`
Expected: All pass

**Step 6: Commit**

```bash
git add app/models/node.rb spec/models/node_spec.rb
git commit -m "feat: add effective_ssh_* methods to Node for profile delegation"
```

---

### Task 1.5: Extend SshSetting for Agent Config

**Files:**
- Create: `db/migrate/TIMESTAMP_add_agent_config_to_ssh_settings.rb`
- Modify: `app/models/ssh_setting.rb`
- Modify: `spec/models/ssh_setting_spec.rb`

**Step 1: Generate migration**

Run: `bin/rails generate migration AddAgentConfigToSshSettings default_agent_path:string`

**Step 2: Edit migration**

```ruby
# frozen_string_literal: true

class AddAgentConfigToSshSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :ssh_settings, :default_agent_path, :string, default: "/usr/local/bin/hpc-agent"
  end
end
```

**Step 3: Run migration**

Run: `bin/rails db:migrate`

**Step 4: Write failing test**

```ruby
# spec/models/ssh_setting_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe SshSetting, type: :model do
  describe ".current" do
    it "returns existing record or creates one" do
      expect { SshSetting.current }.to change(SshSetting, :count).by(1)
      expect { SshSetting.current }.not_to change(SshSetting, :count)
    end

    it "sets default values" do
      setting = SshSetting.current
      expect(setting.bastion_port).to eq(22)
      expect(setting.default_agent_path).to eq("/usr/local/bin/hpc-agent")
    end
  end

  describe "validations" do
    it { is_expected.to validate_numericality_of(:bastion_port).only_integer.is_greater_than(0).is_less_than(65536).allow_blank }
  end
end
```

**Step 5: Run tests**

Run: `bin/rspec spec/models/ssh_setting_spec.rb`
Expected: Some failures on default_agent_path

**Step 6: Update SshSetting model**

```ruby
# app/models/ssh_setting.rb
# frozen_string_literal: true

class SshSetting < ApplicationRecord
  DEFAULT_AGENT_PATH = "/usr/local/bin/hpc-agent"

  validates :bastion_port, numericality: { only_integer: true, greater_than: 0, less_than: 65536 }, allow_blank: true

  def self.current
    first_or_create!(bastion_port: 22, default_agent_path: DEFAULT_AGENT_PATH)
  end
end
```

**Step 7: Run tests to verify they pass**

Run: `bin/rspec spec/models/ssh_setting_spec.rb`
Expected: All pass

**Step 8: Commit**

```bash
git add db/migrate/*_add_agent_config_to_ssh_settings.rb db/schema.rb app/models/ssh_setting.rb spec/models/ssh_setting_spec.rb
git commit -m "feat: add default_agent_path to SshSetting for agent config"
```

---

### Task 1.6: Create SSH Profiles Controller

**Files:**
- Create: `app/controllers/settings/ssh_profiles_controller.rb`
- Create: `spec/requests/settings/ssh_profiles_spec.rb`

**Step 1: Write request spec**

```ruby
# spec/requests/settings/ssh_profiles_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Settings::SshProfiles", type: :request do
  let(:approver) { create(:user, :approver) }
  let(:viewer) { create(:user, :viewer) }

  describe "GET /settings/ssh_profiles" do
    context "as approver" do
      before { sign_in approver }

      it "returns success" do
        get settings_ssh_profiles_path
        expect(response).to have_http_status(:success)
      end

      it "lists all ssh profiles" do
        profiles = create_list(:ssh_profile, 3)
        get settings_ssh_profiles_path
        profiles.each do |profile|
          expect(response.body).to include(profile.name)
        end
      end
    end

    context "as viewer" do
      before { sign_in viewer }

      it "redirects to root" do
        get settings_ssh_profiles_path
        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe "POST /settings/ssh_profiles" do
    before { sign_in approver }

    let(:valid_params) do
      {
        ssh_profile: {
          name: "Test Profile",
          ssh_connect_method: "direct",
          ssh_port: 22,
          ssh_user: "deploy"
        }
      }
    end

    it "creates a new profile" do
      expect {
        post settings_ssh_profiles_path, params: valid_params
      }.to change(SshProfile, :count).by(1)
    end

    it "redirects to index on success" do
      post settings_ssh_profiles_path, params: valid_params
      expect(response).to redirect_to(settings_ssh_profiles_path)
    end

    context "with invalid params" do
      it "renders new with errors" do
        post settings_ssh_profiles_path, params: { ssh_profile: { name: "" } }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "PATCH /settings/ssh_profiles/:id" do
    before { sign_in approver }
    let(:profile) { create(:ssh_profile) }

    it "updates the profile" do
      patch settings_ssh_profile_path(profile), params: { ssh_profile: { name: "Updated Name" } }
      expect(profile.reload.name).to eq("Updated Name")
    end
  end

  describe "DELETE /settings/ssh_profiles/:id" do
    before { sign_in approver }
    let!(:profile) { create(:ssh_profile) }

    it "destroys the profile" do
      expect {
        delete settings_ssh_profile_path(profile)
      }.to change(SshProfile, :count).by(-1)
    end

    context "when profile has associated nodes" do
      let!(:node) { create(:node, ssh_profile: profile) }

      it "nullifies node association and destroys profile" do
        delete settings_ssh_profile_path(profile)
        expect(node.reload.ssh_profile_id).to be_nil
      end
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rspec spec/requests/settings/ssh_profiles_spec.rb`
Expected: FAIL - routing error

**Step 3: Add routes**

Add to `config/routes.rb` inside `namespace :settings do` block:

```ruby
resources :ssh_profiles
```

**Step 4: Create controller**

```ruby
# app/controllers/settings/ssh_profiles_controller.rb
# frozen_string_literal: true

module Settings
  class SshProfilesController < ApplicationController
    layout "dashboard"
    before_action :authenticate_user!
    before_action :authorize_approver!
    before_action :set_ssh_profile, only: %i[show edit update destroy]

    def index
      @ssh_profiles = SshProfile.order(:name)
    end

    def show; end

    def new
      @ssh_profile = SshProfile.new
    end

    def create
      @ssh_profile = SshProfile.new(ssh_profile_params)

      if @ssh_profile.save
        redirect_to settings_ssh_profiles_path, notice: "SSH profile was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @ssh_profile.update(ssh_profile_params)
        redirect_to settings_ssh_profiles_path, notice: "SSH profile was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @ssh_profile.destroy
      redirect_to settings_ssh_profiles_path, notice: "SSH profile was successfully deleted."
    end

    private

    def set_ssh_profile
      @ssh_profile = SshProfile.find(params[:id])
    end

    def ssh_profile_params
      params.require(:ssh_profile).permit(
        :name, :ssh_connect_method, :ssh_port, :ssh_user,
        :ssh_password, :ssh_key, :sudo_credential,
        :jump_host, :jump_user, :jump_port
      )
    end

    def authorize_approver!
      return if current_user.approver?

      redirect_to root_path, alert: "You are not authorized to access this page."
    end
  end
end
```

**Step 5: Run tests**

Run: `bin/rspec spec/requests/settings/ssh_profiles_spec.rb`
Expected: Failures for missing views

**Step 6: Create views (minimal for now)**

Create `app/views/settings/ssh_profiles/index.html.erb`:

```erb
<%= render "shared/page_header", title: "SSH Profiles" do %>
  <%= link_to "Add Profile", new_settings_ssh_profile_path, class: "btn btn-primary" %>
<% end %>

<div class="card-netbox">
  <table class="table-netbox">
    <thead>
      <tr>
        <th>Name</th>
        <th>Connection Method</th>
        <th>SSH User</th>
        <th>Port</th>
        <th>Nodes</th>
        <th>Actions</th>
      </tr>
    </thead>
    <tbody>
      <% @ssh_profiles.each do |profile| %>
        <tr>
          <td><%= profile.name %></td>
          <td><span class="badge badge-info"><%= profile.display_connection_method %></span></td>
          <td><%= profile.ssh_user %></td>
          <td><%= profile.ssh_port %></td>
          <td><%= profile.nodes.count %></td>
          <td class="actions">
            <%= link_to "Edit", edit_settings_ssh_profile_path(profile), class: "text-teal-600 hover:underline" %>
            <%= button_to "Delete", settings_ssh_profile_path(profile), method: :delete,
                data: { turbo_confirm: "Delete SSH profile '#{profile.name}'?" },
                class: "text-red-600 hover:underline ml-2" %>
          </td>
        </tr>
      <% end %>
    </tbody>
  </table>
</div>
```

Create `app/views/settings/ssh_profiles/new.html.erb`:

```erb
<%= render "shared/page_header", title: "New SSH Profile" %>

<div class="card-netbox max-w-2xl">
  <%= render "form", ssh_profile: @ssh_profile %>
</div>
```

Create `app/views/settings/ssh_profiles/edit.html.erb`:

```erb
<%= render "shared/page_header", title: "Edit SSH Profile: #{@ssh_profile.name}" %>

<div class="card-netbox max-w-2xl">
  <%= render "form", ssh_profile: @ssh_profile %>
</div>
```

Create `app/views/settings/ssh_profiles/_form.html.erb`:

```erb
<%= form_with model: [:settings, ssh_profile], class: "space-y-6" do |f| %>
  <% if ssh_profile.errors.any? %>
    <div class="bg-red-50 border border-red-200 rounded-lg p-4 mb-4">
      <ul class="list-disc list-inside text-red-700">
        <% ssh_profile.errors.full_messages.each do |msg| %>
          <li><%= msg %></li>
        <% end %>
      </ul>
    </div>
  <% end %>

  <div>
    <%= f.label :name, class: "block text-sm font-medium text-slate-700" %>
    <%= f.text_field :name, class: "mt-1 input-netbox w-full", required: true %>
  </div>

  <div>
    <%= f.label :ssh_connect_method, "Connection Method", class: "block text-sm font-medium text-slate-700" %>
    <%= f.select :ssh_connect_method, SshProfile.ssh_connect_methods.keys.map { |k| [k.titleize, k] },
        {}, class: "mt-1 input-netbox w-full", data: { controller: "ssh-settings", action: "change->ssh-settings#toggle" } %>
  </div>

  <div class="grid grid-cols-2 gap-4">
    <div>
      <%= f.label :ssh_user, class: "block text-sm font-medium text-slate-700" %>
      <%= f.text_field :ssh_user, class: "mt-1 input-netbox w-full" %>
    </div>
    <div>
      <%= f.label :ssh_port, class: "block text-sm font-medium text-slate-700" %>
      <%= f.number_field :ssh_port, class: "mt-1 input-netbox w-full", min: 1, max: 65535 %>
    </div>
  </div>

  <div>
    <%= f.label :ssh_password, class: "block text-sm font-medium text-slate-700" %>
    <%= f.password_field :ssh_password, class: "mt-1 input-netbox w-full", autocomplete: "new-password" %>
  </div>

  <div>
    <%= f.label :ssh_key, "SSH Key", class: "block text-sm font-medium text-slate-700" %>
    <%= f.text_area :ssh_key, class: "mt-1 input-netbox w-full font-mono text-sm", rows: 4 %>
  </div>

  <div>
    <%= f.label :sudo_credential, class: "block text-sm font-medium text-slate-700" %>
    <%= f.password_field :sudo_credential, class: "mt-1 input-netbox w-full", autocomplete: "new-password" %>
  </div>

  <div data-ssh-settings-target="bastionFields" class="<%= 'hidden' unless ssh_profile.custom_bastion? %>">
    <h3 class="text-sm font-medium text-slate-700 mb-3">Custom Bastion Settings</h3>
    <div class="grid grid-cols-3 gap-4">
      <div class="col-span-2">
        <%= f.label :jump_host, class: "block text-sm font-medium text-slate-700" %>
        <%= f.text_field :jump_host, class: "mt-1 input-netbox w-full" %>
      </div>
      <div>
        <%= f.label :jump_port, class: "block text-sm font-medium text-slate-700" %>
        <%= f.number_field :jump_port, class: "mt-1 input-netbox w-full", min: 1, max: 65535 %>
      </div>
    </div>
    <div class="mt-4">
      <%= f.label :jump_user, class: "block text-sm font-medium text-slate-700" %>
      <%= f.text_field :jump_user, class: "mt-1 input-netbox w-full" %>
    </div>
  </div>

  <div class="flex justify-end gap-3 pt-4 border-t">
    <%= link_to "Cancel", settings_ssh_profiles_path, class: "btn btn-secondary" %>
    <%= f.submit class: "btn btn-primary" %>
  </div>
<% end %>
```

**Step 7: Run tests**

Run: `bin/rspec spec/requests/settings/ssh_profiles_spec.rb`
Expected: All pass

**Step 8: Run rubocop**

Run: `bin/rubocop app/controllers/settings/ssh_profiles_controller.rb app/views/settings/ssh_profiles/ -a`

**Step 9: Commit**

```bash
git add config/routes.rb app/controllers/settings/ssh_profiles_controller.rb app/views/settings/ssh_profiles/ spec/requests/settings/ssh_profiles_spec.rb
git commit -m "feat: add SSH Profiles settings page with CRUD"
```

---

### Task 1.7: Update Agent Config Page

**Files:**
- Modify: `app/views/settings/agents/show.html.erb`
- Modify: `app/controllers/settings/agents_controller.rb:32-34`

**Step 1: Update agent_params in controller**

Change the `agent_params` method in `app/controllers/settings/agents_controller.rb`:

```ruby
def agent_params
  params.require(:ssh_setting).permit(:server_url, :benchmark_work_dir, :default_agent_path)
end
```

**Step 2: Update the view to include default_agent_path**

Add to the agent config form in `app/views/settings/agents/show.html.erb`:

```erb
<div>
  <%= f.label :default_agent_path, "Default Agent Path", class: "block text-sm font-medium text-slate-700" %>
  <%= f.text_field :default_agent_path, class: "mt-1 input-netbox w-full",
      placeholder: "/usr/local/bin/hpc-agent" %>
  <p class="mt-1 text-sm text-slate-500">Path to the agent binary on nodes. Used as default for new nodes.</p>
</div>
```

**Step 3: Run existing tests**

Run: `bin/rspec spec/requests/settings/`
Expected: All pass

**Step 4: Commit**

```bash
git add app/controllers/settings/agents_controller.rb app/views/settings/agents/show.html.erb
git commit -m "feat: add default_agent_path to agent config page"
```

---

## Phase 2: Node Form Wizard

### Task 2.1: Create Wizard Stimulus Controller

**Files:**
- Create: `app/javascript/controllers/wizard_controller.js`

**Step 1: Create the controller**

```javascript
// app/javascript/controllers/wizard_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["step", "indicator", "backButton", "nextButton", "submitButton"]
  static values = {
    current: { type: Number, default: 1 },
    total: { type: Number, default: 3 }
  }

  connect() {
    this.showStep(this.currentValue)
  }

  next() {
    if (this.validateCurrentStep() && this.currentValue < this.totalValue) {
      this.currentValue++
      this.showStep(this.currentValue)
    }
  }

  back() {
    if (this.currentValue > 1) {
      this.currentValue--
      this.showStep(this.currentValue)
    }
  }

  goToStep(event) {
    const step = parseInt(event.currentTarget.dataset.step)
    if (step < this.currentValue) {
      this.currentValue = step
      this.showStep(this.currentValue)
    }
  }

  showStep(stepNumber) {
    // Hide all steps, show current
    this.stepTargets.forEach((step, index) => {
      step.classList.toggle("hidden", index + 1 !== stepNumber)
    })

    // Update indicators
    this.indicatorTargets.forEach((indicator, index) => {
      const stepNum = index + 1
      indicator.classList.remove("bg-teal-600", "bg-slate-300", "text-white", "text-slate-600")

      if (stepNum < stepNumber) {
        // Completed step
        indicator.classList.add("bg-teal-600", "text-white")
        indicator.innerHTML = `<svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"/></svg>`
      } else if (stepNum === stepNumber) {
        // Current step
        indicator.classList.add("bg-teal-600", "text-white")
        indicator.textContent = stepNum
      } else {
        // Future step
        indicator.classList.add("bg-slate-300", "text-slate-600")
        indicator.textContent = stepNum
      }
    })

    // Update navigation buttons
    if (this.hasBackButtonTarget) {
      this.backButtonTarget.classList.toggle("hidden", stepNumber === 1)
    }
    if (this.hasNextButtonTarget) {
      this.nextButtonTarget.classList.toggle("hidden", stepNumber === this.totalValue)
    }
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.classList.toggle("hidden", stepNumber !== this.totalValue)
    }
  }

  validateCurrentStep() {
    const currentStep = this.stepTargets[this.currentValue - 1]
    const requiredFields = currentStep.querySelectorAll("[required]")
    let valid = true

    requiredFields.forEach(field => {
      if (!field.value.trim()) {
        field.classList.add("border-red-500")
        valid = false
      } else {
        field.classList.remove("border-red-500")
      }
    })

    return valid
  }
}
```

**Step 2: Commit**

```bash
git add app/javascript/controllers/wizard_controller.js
git commit -m "feat: add wizard Stimulus controller for multi-step forms"
```

---

### Task 2.2: Create NodeFormWizardComponent

**Files:**
- Create: `app/components/node_form_wizard_component.rb`
- Create: `app/components/node_form_wizard_component.html.erb`
- Create: `spec/components/node_form_wizard_component_spec.rb`

**Step 1: Write component spec**

```ruby
# spec/components/node_form_wizard_component_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe NodeFormWizardComponent, type: :component do
  let(:node) { build(:node) }
  let(:ssh_profiles) { create_list(:ssh_profile, 2) }
  let(:api_keys) { create_list(:api_key, 2) }

  it "renders wizard with 3 steps" do
    render_inline(described_class.new(node: node, ssh_profiles: ssh_profiles, api_keys: api_keys))

    expect(page).to have_css("[data-wizard-target='step']", count: 3)
    expect(page).to have_css("[data-wizard-target='indicator']", count: 3)
  end

  it "renders step 1: Basic Info" do
    render_inline(described_class.new(node: node, ssh_profiles: ssh_profiles, api_keys: api_keys))

    expect(page).to have_field("node[hostname]")
    expect(page).to have_select("node[role]")
    expect(page).to have_select("node[arch]")
  end

  it "renders step 2: Server & Location" do
    render_inline(described_class.new(node: node, ssh_profiles: ssh_profiles, api_keys: api_keys))

    expect(page).to have_css("[data-controller='server-product-search']")
  end

  it "renders step 3: Connection" do
    render_inline(described_class.new(node: node, ssh_profiles: ssh_profiles, api_keys: api_keys))

    expect(page).to have_select("node[ssh_profile_id]")
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/components/node_form_wizard_component_spec.rb`
Expected: FAIL - uninitialized constant

**Step 3: Create component class**

```ruby
# app/components/node_form_wizard_component.rb
# frozen_string_literal: true

class NodeFormWizardComponent < ViewComponent::Base
  def initialize(node:, ssh_profiles: [], api_keys: [], agent_config: nil)
    @node = node
    @ssh_profiles = ssh_profiles
    @api_keys = api_keys
    @agent_config = agent_config || SshSetting.current
  end

  private

  attr_reader :node, :ssh_profiles, :api_keys, :agent_config

  def roles_for_select
    Node.roles.keys.map { |r| [r.titleize, r] }
  end

  def architectures_for_select
    [["x86_64", "x86_64"], ["ARM64", "aarch64"]]
  end

  def ssh_profiles_for_select
    ssh_profiles.map { |p| [p.name, p.id] }
  end

  def api_keys_for_select
    api_keys.map { |k| [k.name, k.id] }
  end

  def form_url
    node.persisted? ? node_path(node) : nodes_path
  end

  def form_method
    node.persisted? ? :patch : :post
  end

  def default_agent_path
    agent_config.default_agent_path || SshSetting::DEFAULT_AGENT_PATH
  end

  def default_benchmark_work_dir
    agent_config.benchmark_work_dir
  end
end
```

**Step 4: Create component template**

```erb
<%# app/components/node_form_wizard_component.html.erb %>
<div data-controller="wizard" data-wizard-current-value="1" data-wizard-total-value="3">
  <%= form_with model: node, url: form_url, method: form_method, class: "space-y-6" do |f| %>

    <%# Progress Indicators %>
    <div class="flex items-center justify-center mb-8">
      <% ["Basic Info", "Server & Location", "Connection"].each_with_index do |label, index| %>
        <div class="flex items-center">
          <button type="button"
                  data-wizard-target="indicator"
                  data-step="<%= index + 1 %>"
                  data-action="click->wizard#goToStep"
                  class="w-8 h-8 rounded-full flex items-center justify-center text-sm font-medium <%= index == 0 ? 'bg-teal-600 text-white' : 'bg-slate-300 text-slate-600' %>">
            <%= index + 1 %>
          </button>
          <span class="ml-2 text-sm font-medium text-slate-700"><%= label %></span>
          <% unless index == 2 %>
            <div class="w-12 h-0.5 bg-slate-300 mx-4"></div>
          <% end %>
        </div>
      <% end %>
    </div>

    <%# Error Display %>
    <% if node.errors.any? %>
      <div class="bg-red-50 border border-red-200 rounded-lg p-4">
        <ul class="list-disc list-inside text-red-700">
          <% node.errors.full_messages.each do |msg| %>
            <li><%= msg %></li>
          <% end %>
        </ul>
      </div>
    <% end %>

    <%# Step 1: Basic Info %>
    <div data-wizard-target="step" class="">
      <h3 class="text-lg font-medium text-slate-900 mb-4">Basic Information</h3>

      <div class="space-y-4">
        <div data-controller="hostname-autocomplete">
          <%= f.label :hostname, class: "block text-sm font-medium text-slate-700" %>
          <%= f.text_field :hostname,
              class: "mt-1 input-netbox w-full",
              required: true,
              autocomplete: "off",
              data: {
                hostname_autocomplete_target: "input",
                action: "input->hostname-autocomplete#search"
              } %>
          <div data-hostname-autocomplete-target="dropdown" class="hidden absolute z-10 w-full bg-white border border-slate-300 rounded-md shadow-lg mt-1"></div>
          <div data-hostname-autocomplete-target="badge" class="hidden mt-2"></div>
        </div>

        <div class="grid grid-cols-2 gap-4">
          <div>
            <%= f.label :role, class: "block text-sm font-medium text-slate-700" %>
            <%= f.select :role, roles_for_select, {}, class: "mt-1 input-netbox w-full" %>
          </div>
          <div>
            <%= f.label :arch, "Architecture", class: "block text-sm font-medium text-slate-700" %>
            <%= f.select :arch, architectures_for_select, { include_blank: "Select..." }, class: "mt-1 input-netbox w-full" %>
          </div>
        </div>

        <div>
          <%= f.label :ip, "IP Address (optional)", class: "block text-sm font-medium text-slate-700" %>
          <%= f.text_field :ip, class: "mt-1 input-netbox w-full", placeholder: "192.168.1.100" %>
        </div>
      </div>
    </div>

    <%# Step 2: Server & Location %>
    <div data-wizard-target="step" class="hidden">
      <h3 class="text-lg font-medium text-slate-900 mb-4">Server & Location</h3>

      <div class="space-y-4">
        <div data-controller="server-product-search">
          <%= f.label :server_product_id, "Server Model", class: "block text-sm font-medium text-slate-700" %>
          <%= f.hidden_field :server_product_id, data: { server_product_search_target: "hiddenField" } %>
          <input type="text"
                 class="mt-1 input-netbox w-full"
                 placeholder="Search server models..."
                 data-server-product-search-target="input"
                 data-action="input->server-product-search#search">
          <div data-server-product-search-target="results" class="hidden"></div>
          <div data-server-product-search-target="preview" class="mt-2"></div>
        </div>

        <div class="border-t pt-4">
          <h4 class="text-sm font-medium text-slate-700 mb-3">Rack Assignment (Optional)</h4>

          <div class="grid grid-cols-3 gap-4">
            <div>
              <%= f.label :rack_id, "Rack", class: "block text-sm font-medium text-slate-700" %>
              <%= f.collection_select :rack_id, ServerRack.includes(:room).order("rooms.name, racks.name"), :id,
                  ->(r) { "#{r.room.name} / #{r.name}" },
                  { include_blank: "No rack" },
                  class: "mt-1 input-netbox w-full" %>
            </div>
            <div>
              <%= f.label :rack_position, "Position (RU)", class: "block text-sm font-medium text-slate-700" %>
              <%= f.number_field :rack_position, class: "mt-1 input-netbox w-full", min: 1 %>
            </div>
            <div>
              <%= f.label :rack_height, "Height (U)", class: "block text-sm font-medium text-slate-700" %>
              <%= f.number_field :rack_height,
                  class: "mt-1 input-netbox w-full",
                  min: 1,
                  data: { server_product_search_target: "rackHeight" } %>
            </div>
          </div>
        </div>
      </div>
    </div>

    <%# Step 3: Connection %>
    <div data-wizard-target="step" class="hidden">
      <h3 class="text-lg font-medium text-slate-900 mb-4">Connection Settings</h3>

      <div class="space-y-4" data-controller="ssh-profile-select">
        <div>
          <%= f.label :ssh_profile_id, "SSH Profile", class: "block text-sm font-medium text-slate-700" %>
          <div class="flex gap-2">
            <%= f.select :ssh_profile_id, ssh_profiles_for_select,
                { include_blank: "No profile (configure manually)" },
                class: "mt-1 input-netbox flex-1",
                data: {
                  ssh_profile_select_target: "select",
                  action: "change->ssh-profile-select#profileChanged"
                } %>
            <%= link_to "New Profile", new_settings_ssh_profile_path,
                class: "mt-1 btn btn-secondary",
                data: { turbo_frame: "modal" } %>
          </div>
        </div>

        <div data-ssh-profile-select-target="overrideSection" class="<%= node.ssh_profile_id.present? ? '' : 'hidden' %>">
          <label class="flex items-center gap-2 text-sm text-slate-700">
            <%= f.check_box :ssh_profile_override,
                data: {
                  ssh_profile_select_target: "overrideCheckbox",
                  action: "change->ssh-profile-select#toggleOverride"
                } %>
            Customize SSH settings for this node
          </label>
        </div>

        <div data-ssh-profile-select-target="manualFields" class="<%= node.ssh_profile_id.present? && !node.ssh_profile_override ? 'hidden' : '' %> space-y-4 border-t pt-4">
          <div>
            <%= f.label :ssh_connect_method, "Connection Method", class: "block text-sm font-medium text-slate-700" %>
            <%= f.select :ssh_connect_method, Node.ssh_connect_methods.keys.map { |k| [k.titleize, k] },
                {}, class: "mt-1 input-netbox w-full",
                data: { controller: "ssh-settings", action: "change->ssh-settings#toggle" } %>
          </div>

          <div class="grid grid-cols-2 gap-4">
            <div>
              <%= f.label :ssh_user, class: "block text-sm font-medium text-slate-700" %>
              <%= f.text_field :ssh_user, class: "mt-1 input-netbox w-full" %>
            </div>
            <div>
              <%= f.label :ssh_port, class: "block text-sm font-medium text-slate-700" %>
              <%= f.number_field :ssh_port, class: "mt-1 input-netbox w-full", min: 1, max: 65535 %>
            </div>
          </div>

          <div data-ssh-settings-target="bastionFields" class="hidden space-y-4">
            <h4 class="text-sm font-medium text-slate-700">Custom Bastion</h4>
            <div class="grid grid-cols-3 gap-4">
              <div class="col-span-2">
                <%= f.label :jump_host, class: "block text-sm font-medium text-slate-700" %>
                <%= f.text_field :jump_host, class: "mt-1 input-netbox w-full" %>
              </div>
              <div>
                <%= f.label :jump_port, class: "block text-sm font-medium text-slate-700" %>
                <%= f.number_field :jump_port, class: "mt-1 input-netbox w-full", min: 1, max: 65535 %>
              </div>
            </div>
          </div>
        </div>

        <div class="border-t pt-4">
          <h4 class="text-sm font-medium text-slate-700 mb-3">Agent Configuration</h4>

          <div class="grid grid-cols-2 gap-4">
            <div>
              <%= f.label :agent_path, class: "block text-sm font-medium text-slate-700" %>
              <%= f.text_field :agent_path,
                  class: "mt-1 input-netbox w-full",
                  value: node.agent_path.presence || default_agent_path,
                  placeholder: default_agent_path %>
            </div>
            <div>
              <%= f.label :benchmark_work_dir, "Benchmark Directory", class: "block text-sm font-medium text-slate-700" %>
              <%= f.text_field :benchmark_work_dir,
                  class: "mt-1 input-netbox w-full",
                  value: node.benchmark_work_dir.presence || default_benchmark_work_dir %>
            </div>
          </div>

          <div class="mt-4">
            <%= f.label :api_key_id, "API Key", class: "block text-sm font-medium text-slate-700" %>
            <%= f.select :api_key_id, api_keys_for_select,
                { include_blank: "No API key" },
                class: "mt-1 input-netbox w-full" %>
          </div>
        </div>
      </div>
    </div>

    <%# Navigation %>
    <div class="flex justify-between pt-6 border-t">
      <button type="button"
              data-wizard-target="backButton"
              data-action="click->wizard#back"
              class="hidden btn btn-secondary">
        Back
      </button>
      <div class="ml-auto flex gap-3">
        <%= link_to "Cancel", nodes_path, class: "btn btn-secondary" %>
        <button type="button"
                data-wizard-target="nextButton"
                data-action="click->wizard#next"
                class="btn btn-primary">
          Next
        </button>
        <%= f.submit node.persisted? ? "Update Node" : "Create Node",
            class: "hidden btn btn-primary",
            data: { wizard_target: "submitButton" } %>
      </div>
    </div>
  <% end %>
</div>
```

**Step 5: Run component spec**

Run: `bin/rspec spec/components/node_form_wizard_component_spec.rb`
Expected: All pass

**Step 6: Commit**

```bash
git add app/components/node_form_wizard_component.rb app/components/node_form_wizard_component.html.erb spec/components/node_form_wizard_component_spec.rb
git commit -m "feat: add NodeFormWizardComponent with 3-step wizard layout"
```

---

### Task 2.3: Create SSH Profile Select Controller

**Files:**
- Create: `app/javascript/controllers/ssh_profile_select_controller.js`

**Step 1: Create controller**

```javascript
// app/javascript/controllers/ssh_profile_select_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "overrideSection", "overrideCheckbox", "manualFields"]

  profileChanged() {
    const hasProfile = this.selectTarget.value !== ""

    if (this.hasOverrideSectionTarget) {
      this.overrideSectionTarget.classList.toggle("hidden", !hasProfile)
    }

    if (hasProfile && this.hasOverrideCheckboxTarget) {
      // When profile selected, hide manual fields unless override is checked
      const showManual = this.overrideCheckboxTarget.checked
      if (this.hasManualFieldsTarget) {
        this.manualFieldsTarget.classList.toggle("hidden", !showManual)
      }
    } else {
      // No profile - always show manual fields
      if (this.hasManualFieldsTarget) {
        this.manualFieldsTarget.classList.remove("hidden")
      }
    }
  }

  toggleOverride() {
    if (this.hasManualFieldsTarget && this.hasOverrideCheckboxTarget) {
      const showManual = this.overrideCheckboxTarget.checked || this.selectTarget.value === ""
      this.manualFieldsTarget.classList.toggle("hidden", !showManual)
    }
  }
}
```

**Step 2: Commit**

```bash
git add app/javascript/controllers/ssh_profile_select_controller.js
git commit -m "feat: add ssh_profile_select Stimulus controller"
```

---

### Task 2.4: Update NodesController and Views

**Files:**
- Modify: `app/controllers/nodes_controller.rb`
- Modify: `app/views/nodes/new.html.erb`
- Modify: `app/views/nodes/edit.html.erb`

**Step 1: Update controller**

Update `new` action in `app/controllers/nodes_controller.rb`:

```ruby
def new
  @node = Node.new
  @api_keys = ApiKey.active.order(:name)
  @ssh_profiles = SshProfile.order(:name)
end
```

Update `edit` action:

```ruby
def edit
  @api_keys = ApiKey.active.order(:name)
  @ssh_profiles = SshProfile.order(:name)
end
```

Update `node_params` to include new fields:

```ruby
def node_params
  params.require(:node).permit(
    :hostname, :ip, :arch, :ssh_port, :ssh_user, :ssh_key, :ssh_password,
    :sudo_credential, :ssh_connect_method, :jump_host, :jump_user, :jump_port,
    :agent_path, :benchmark_work_dir, :api_key_id, :rack_id, :rack_position,
    :rack_height, :server_product_id, :ssh_profile_id, :ssh_profile_override
  )
end
```

**Step 2: Update new.html.erb**

```erb
<%# app/views/nodes/new.html.erb %>
<%= turbo_frame_tag "node_modal" do %>
  <%= render "shared/modal", title: "Add New Node", max_width: "max-w-3xl" do %>
    <%= render NodeFormWizardComponent.new(
      node: @node,
      ssh_profiles: @ssh_profiles,
      api_keys: @api_keys
    ) %>
  <% end %>
<% end %>
```

**Step 3: Update edit.html.erb**

```erb
<%# app/views/nodes/edit.html.erb %>
<%= turbo_frame_tag "node_modal" do %>
  <%= render "shared/modal", title: "Edit Node: #{@node.hostname}", max_width: "max-w-3xl" do %>
    <%= render NodeFormWizardComponent.new(
      node: @node,
      ssh_profiles: @ssh_profiles,
      api_keys: @api_keys
    ) %>
  <% end %>
<% end %>
```

**Step 4: Run existing tests**

Run: `bin/rspec spec/requests/nodes_spec.rb` (if exists)
Expected: All pass

**Step 5: Commit**

```bash
git add app/controllers/nodes_controller.rb app/views/nodes/new.html.erb app/views/nodes/edit.html.erb
git commit -m "feat: integrate NodeFormWizardComponent into node views"
```

---

## Phase 3: Hostname Autocomplete

### Task 3.1: Create Hostname Suggestions API Endpoint

**Files:**
- Create: `app/controllers/api/nodes_controller.rb`
- Create: `spec/requests/api/nodes_spec.rb`

**Step 1: Write request spec**

```ruby
# spec/requests/api/nodes_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::Nodes", type: :request do
  describe "GET /api/nodes/hostname_suggestions" do
    before do
      create(:node, hostname: "compute-001")
      create(:node, hostname: "compute-002")
      create(:node, hostname: "compute-005")
      create(:node, hostname: "login-001")
    end

    it "returns existing hostnames matching prefix" do
      get api_nodes_hostname_suggestions_path, params: { prefix: "compute" }

      json = JSON.parse(response.body)
      expect(json["existing"]).to contain_exactly("compute-001", "compute-002", "compute-005")
    end

    it "returns suggested next hostnames" do
      get api_nodes_hostname_suggestions_path, params: { prefix: "compute-00" }

      json = JSON.parse(response.body)
      expect(json["suggestions"]).to include("compute-003", "compute-004")
    end

    it "detects bulk pattern and returns conflicts" do
      get api_nodes_hostname_suggestions_path, params: { prefix: "compute-[001-005]" }

      json = JSON.parse(response.body)
      expect(json["bulk"]).to eq(true)
      expect(json["count"]).to eq(5)
      expect(json["conflicts"]).to contain_exactly("compute-001", "compute-002", "compute-005")
    end

    it "returns empty arrays for no matches" do
      get api_nodes_hostname_suggestions_path, params: { prefix: "storage" }

      json = JSON.parse(response.body)
      expect(json["existing"]).to be_empty
      expect(json["suggestions"]).to be_empty
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/requests/api/nodes_spec.rb`
Expected: FAIL - routing error

**Step 3: Add route**

Add to `config/routes.rb` inside `namespace :api do` block:

```ruby
resources :nodes, only: [] do
  collection do
    get :hostname_suggestions
  end
end
```

**Step 4: Create controller**

```ruby
# app/controllers/api/nodes_controller.rb
# frozen_string_literal: true

module Api
  class NodesController < ApplicationController
    skip_before_action :verify_authenticity_token

    def hostname_suggestions
      prefix = params[:prefix].to_s.strip

      result = if bulk_pattern?(prefix)
                 bulk_suggestions(prefix)
               else
                 single_suggestions(prefix)
               end

      render json: result
    end

    private

    def bulk_pattern?(prefix)
      prefix.match?(/\[(\d+)-(\d+)\]/)
    end

    def bulk_suggestions(prefix)
      match = prefix.match(/(.+)\[(\d+)-(\d+)\]/)
      return { bulk: false, error: "Invalid pattern" } unless match

      base = match[1]
      start_num = match[2].to_i
      end_num = match[3].to_i
      padding = match[2].length

      hostnames = (start_num..end_num).map { |n| "#{base}#{n.to_s.rjust(padding, '0')}" }
      existing = Node.where(hostname: hostnames).pluck(:hostname)

      {
        bulk: true,
        count: hostnames.length,
        hostnames: hostnames,
        conflicts: existing,
        valid: existing.empty?
      }
    end

    def single_suggestions(prefix)
      return { existing: [], suggestions: [] } if prefix.blank?

      existing = Node.where("hostname LIKE ?", "#{sanitize_like(prefix)}%")
                     .order(:hostname)
                     .limit(10)
                     .pluck(:hostname)

      suggestions = calculate_suggestions(prefix, existing)

      {
        bulk: false,
        existing: existing,
        suggestions: suggestions
      }
    end

    def calculate_suggestions(prefix, existing)
      return [] unless prefix.match?(/\d+$/)

      # Extract base and number pattern
      match = prefix.match(/^(.+?)(\d+)$/)
      return [] unless match

      base = match[1]
      num_str = match[2]
      padding = num_str.length
      current_num = num_str.to_i

      # Find existing numbers with this base
      existing_nums = existing.filter_map do |h|
        m = h.match(/^#{Regexp.escape(base)}(\d+)$/)
        m[1].to_i if m
      end.to_set

      # Suggest next available numbers (gaps and sequential)
      suggestions = []

      # Find gaps
      if existing_nums.any?
        (1..existing_nums.max + 5).each do |n|
          break if suggestions.length >= 5
          suggestions << "#{base}#{n.to_s.rjust(padding, '0')}" unless existing_nums.include?(n)
        end
      else
        # No existing, suggest sequential from current
        (current_num..(current_num + 4)).each do |n|
          suggestions << "#{base}#{n.to_s.rjust(padding, '0')}"
        end
      end

      suggestions.first(5)
    end

    def sanitize_like(str)
      str.gsub(/[%_]/, '\\\\\0')
    end
  end
end
```

**Step 5: Run tests**

Run: `bin/rspec spec/requests/api/nodes_spec.rb`
Expected: All pass

**Step 6: Commit**

```bash
git add config/routes.rb app/controllers/api/nodes_controller.rb spec/requests/api/nodes_spec.rb
git commit -m "feat: add hostname suggestions API endpoint"
```

---

### Task 3.2: Create Hostname Autocomplete Controller

**Files:**
- Create: `app/javascript/controllers/hostname_autocomplete_controller.js`

**Step 1: Create controller**

```javascript
// app/javascript/controllers/hostname_autocomplete_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "dropdown", "badge"]
  static values = { url: { type: String, default: "/api/nodes/hostname_suggestions" } }

  connect() {
    this.timeout = null
    this.abortController = null
  }

  disconnect() {
    if (this.timeout) clearTimeout(this.timeout)
    if (this.abortController) this.abortController.abort()
  }

  search() {
    if (this.timeout) clearTimeout(this.timeout)

    this.timeout = setTimeout(() => this.fetchSuggestions(), 300)
  }

  async fetchSuggestions() {
    const prefix = this.inputTarget.value.trim()

    if (prefix.length < 2) {
      this.hideDropdown()
      this.hideBadge()
      return
    }

    if (this.abortController) this.abortController.abort()
    this.abortController = new AbortController()

    try {
      const response = await fetch(`${this.urlValue}?prefix=${encodeURIComponent(prefix)}`, {
        signal: this.abortController.signal
      })
      const data = await response.json()

      if (data.bulk) {
        this.showBulkBadge(data)
        this.hideDropdown()
      } else {
        this.showDropdown(data)
        this.hideBadge()
      }
    } catch (e) {
      if (e.name !== 'AbortError') console.error(e)
    }
  }

  showDropdown(data) {
    if (!this.hasDropdownTarget) return

    const { existing, suggestions } = data

    if (existing.length === 0 && suggestions.length === 0) {
      this.hideDropdown()
      return
    }

    let html = ''

    if (suggestions.length > 0) {
      html += '<div class="px-3 py-2 text-xs font-medium text-slate-500 bg-slate-50">Suggestions</div>'
      suggestions.forEach(hostname => {
        html += `<button type="button"
                         class="w-full px-3 py-2 text-left text-sm hover:bg-teal-50 text-teal-700 flex items-center justify-between"
                         data-action="click->hostname-autocomplete#select"
                         data-hostname="${hostname}">
                   ${hostname}
                   <span class="text-xs text-teal-500">(next available)</span>
                 </button>`
      })
    }

    if (existing.length > 0) {
      html += '<div class="px-3 py-2 text-xs font-medium text-slate-500 bg-slate-50 border-t">Existing (avoid duplicates)</div>'
      existing.forEach(hostname => {
        html += `<div class="px-3 py-2 text-sm text-slate-400 flex items-center justify-between">
                   ${hostname}
                   <span class="text-xs">(exists)</span>
                 </div>`
      })
    }

    this.dropdownTarget.innerHTML = html
    this.dropdownTarget.classList.remove("hidden")
  }

  hideDropdown() {
    if (this.hasDropdownTarget) {
      this.dropdownTarget.classList.add("hidden")
    }
  }

  showBulkBadge(data) {
    if (!this.hasBadgeTarget) return

    const { count, conflicts, valid } = data

    let html = `<span class="inline-flex items-center px-3 py-1 rounded-full text-sm font-medium ${valid ? 'bg-teal-100 text-teal-800' : 'bg-amber-100 text-amber-800'}">
                  ${count} nodes will be created`

    if (!valid && conflicts.length > 0) {
      html += `<span class="ml-2">| ${conflicts.length} conflict${conflicts.length > 1 ? 's' : ''}: ${conflicts.slice(0, 3).join(', ')}${conflicts.length > 3 ? '...' : ''}</span>`
    }

    html += '</span>'

    this.badgeTarget.innerHTML = html
    this.badgeTarget.classList.remove("hidden")
  }

  hideBadge() {
    if (this.hasBadgeTarget) {
      this.badgeTarget.classList.add("hidden")
    }
  }

  select(event) {
    const hostname = event.currentTarget.dataset.hostname
    this.inputTarget.value = hostname
    this.hideDropdown()
    this.inputTarget.focus()
  }

  clickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.hideDropdown()
    }
  }
}
```

**Step 2: Commit**

```bash
git add app/javascript/controllers/hostname_autocomplete_controller.js
git commit -m "feat: add hostname_autocomplete Stimulus controller"
```

---

## Phase 4: Bulk Node Creation

### Task 4.1: Add Bulk Create Service

**Files:**
- Create: `app/services/nodes/bulk_create_service.rb`
- Create: `spec/services/nodes/bulk_create_service_spec.rb`

**Step 1: Write service spec**

```ruby
# spec/services/nodes/bulk_create_service_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nodes::BulkCreateService do
  describe "#call" do
    let(:base_params) do
      {
        role: "compute",
        arch: "x86_64",
        ssh_port: 22
      }
    end

    context "with valid pattern" do
      it "creates multiple nodes" do
        service = described_class.new("compute-[001-003]", base_params)

        expect { service.call }.to change(Node, :count).by(3)
      end

      it "returns success result with created nodes" do
        service = described_class.new("compute-[001-003]", base_params)
        result = service.call

        expect(result.success?).to be true
        expect(result.nodes.length).to eq(3)
        expect(result.nodes.map(&:hostname)).to contain_exactly("compute-001", "compute-002", "compute-003")
      end
    end

    context "with conflicts" do
      before { create(:node, hostname: "compute-002") }

      it "does not create any nodes" do
        service = described_class.new("compute-[001-003]", base_params)

        expect { service.call }.not_to change(Node, :count)
      end

      it "returns failure result with conflicts" do
        service = described_class.new("compute-[001-003]", base_params)
        result = service.call

        expect(result.success?).to be false
        expect(result.conflicts).to eq(["compute-002"])
      end
    end

    context "with per-node overrides" do
      let(:overrides) do
        {
          "compute-001" => { role: "login" },
          "compute-003" => { arch: "aarch64" }
        }
      end

      it "applies overrides to specific nodes" do
        service = described_class.new("compute-[001-003]", base_params, overrides)
        result = service.call

        expect(result.nodes.find { |n| n.hostname == "compute-001" }.role).to eq("login")
        expect(result.nodes.find { |n| n.hostname == "compute-002" }.role).to eq("compute")
        expect(result.nodes.find { |n| n.hostname == "compute-003" }.arch).to eq("aarch64")
      end
    end

    context "with invalid pattern" do
      it "returns failure" do
        service = described_class.new("invalid", base_params)
        result = service.call

        expect(result.success?).to be false
        expect(result.error).to include("Invalid pattern")
      end
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/services/nodes/bulk_create_service_spec.rb`
Expected: FAIL - uninitialized constant

**Step 3: Create service**

```ruby
# app/services/nodes/bulk_create_service.rb
# frozen_string_literal: true

module Nodes
  class BulkCreateService
    Result = Struct.new(:success?, :nodes, :conflicts, :error, keyword_init: true)

    def initialize(pattern, base_params, overrides = {})
      @pattern = pattern
      @base_params = base_params.to_h.symbolize_keys
      @overrides = overrides.transform_keys(&:to_s)
    end

    def call
      hostnames = parse_pattern
      return Result.new(success?: false, error: "Invalid pattern") if hostnames.nil?

      conflicts = find_conflicts(hostnames)
      return Result.new(success?: false, conflicts: conflicts, error: "Hostname conflicts") if conflicts.any?

      nodes = create_nodes(hostnames)
      Result.new(success?: true, nodes: nodes)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, error: e.message)
    end

    private

    def parse_pattern
      match = @pattern.match(/(.+)\[(\d+)-(\d+)\]/)
      return nil unless match

      base = match[1]
      start_num = match[2].to_i
      end_num = match[3].to_i
      padding = match[2].length

      return nil if start_num > end_num

      (start_num..end_num).map { |n| "#{base}#{n.to_s.rjust(padding, '0')}" }
    end

    def find_conflicts(hostnames)
      Node.where(hostname: hostnames).pluck(:hostname)
    end

    def create_nodes(hostnames)
      Node.transaction do
        hostnames.map do |hostname|
          params = @base_params.merge(hostname: hostname, source: :manual)
          params.merge!(@overrides[hostname].symbolize_keys) if @overrides[hostname]
          Node.create!(params)
        end
      end
    end
  end
end
```

**Step 4: Run tests**

Run: `bin/rspec spec/services/nodes/bulk_create_service_spec.rb`
Expected: All pass

**Step 5: Commit**

```bash
git add app/services/nodes/bulk_create_service.rb spec/services/nodes/bulk_create_service_spec.rb
git commit -m "feat: add Nodes::BulkCreateService for bulk node creation"
```

---

### Task 4.2: Update NodesController for Bulk Create

**Files:**
- Modify: `app/controllers/nodes_controller.rb:97-109`
- Create: `app/views/nodes/create_bulk.turbo_stream.erb`

**Step 1: Update create action**

Replace `create` action in `app/controllers/nodes_controller.rb`:

```ruby
def create
  if bulk_pattern?(params[:node][:hostname])
    create_bulk
  else
    create_single
  end
end

private

def create_single
  @node = Node.new(node_params)
  set_sensitive_params
  @node.source = :manual

  if @node.save
    respond_to do |format|
      format.html { redirect_to nodes_path, notice: "Node was successfully created." }
      format.turbo_stream
    end
  else
    @api_keys = ApiKey.active.order(:name)
    @ssh_profiles = SshProfile.order(:name)
    render :new, status: :unprocessable_entity
  end
end

def create_bulk
  service = Nodes::BulkCreateService.new(
    params[:node][:hostname],
    node_params.except(:hostname),
    params[:node_overrides] || {}
  )
  result = service.call

  if result.success?
    @nodes = result.nodes
    respond_to do |format|
      format.html { redirect_to nodes_path, notice: "#{@nodes.count} nodes were successfully created." }
      format.turbo_stream { render :create_bulk }
    end
  else
    @node = Node.new(node_params)
    @node.errors.add(:hostname, result.error || "has conflicts: #{result.conflicts.join(', ')}")
    @api_keys = ApiKey.active.order(:name)
    @ssh_profiles = SshProfile.order(:name)
    render :new, status: :unprocessable_entity
  end
end

def bulk_pattern?(hostname)
  hostname.to_s.match?(/\[(\d+)-(\d+)\]/)
end
```

**Step 2: Create bulk turbo stream template**

```erb
<%# app/views/nodes/create_bulk.turbo_stream.erb %>
<%= turbo_stream.replace "node_modal" do %>
  <%= turbo_frame_tag "node_modal" %>
<% end %>

<%= turbo_stream.update "flash_messages" do %>
  <%= render "shared/flash", notice: "#{@nodes.count} nodes were successfully created." %>
<% end %>

<% @nodes.each do |node| %>
  <%= turbo_stream.append "nodes_tbody" do %>
    <%= render "node", node: node %>
  <% end %>
<% end %>
```

**Step 3: Run tests**

Run: `bin/rspec spec/requests/nodes_spec.rb` (if exists)
Expected: All pass

**Step 4: Commit**

```bash
git add app/controllers/nodes_controller.rb app/views/nodes/create_bulk.turbo_stream.erb
git commit -m "feat: add bulk node creation to NodesController"
```

---

### Task 4.3: Create Bulk Review Controller

**Files:**
- Create: `app/javascript/controllers/bulk_review_controller.js`

**Step 1: Create controller**

```javascript
// app/javascript/controllers/bulk_review_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["row", "editForm", "displayRow", "overridesField"]
  static values = { overrides: { type: Object, default: {} } }

  connect() {
    this.editing = null
  }

  edit(event) {
    const hostname = event.currentTarget.dataset.hostname
    const row = this.rowTargets.find(r => r.dataset.hostname === hostname)

    if (!row) return

    // Close any existing edit
    if (this.editing) {
      this.cancelEdit({ currentTarget: { dataset: { hostname: this.editing } } })
    }

    // Show edit form, hide display
    const editForm = row.querySelector("[data-bulk-review-target='editForm']")
    const displayRow = row.querySelector("[data-bulk-review-target='displayRow']")

    if (editForm) editForm.classList.remove("hidden")
    if (displayRow) displayRow.classList.add("hidden")

    this.editing = hostname
  }

  saveEdit(event) {
    const hostname = event.currentTarget.dataset.hostname
    const row = this.rowTargets.find(r => r.dataset.hostname === hostname)

    if (!row) return

    // Collect form values
    const override = {}
    row.querySelectorAll("[data-override-field]").forEach(field => {
      const key = field.dataset.overrideField
      const value = field.value
      if (value) override[key] = value
    })

    // Store override
    this.overridesValue = { ...this.overridesValue, [hostname]: override }
    this.updateOverridesField()

    // Update display and close edit
    this.updateRowDisplay(row, override)
    this.cancelEdit(event)
  }

  cancelEdit(event) {
    const hostname = event.currentTarget.dataset.hostname
    const row = this.rowTargets.find(r => r.dataset.hostname === hostname)

    if (!row) return

    const editForm = row.querySelector("[data-bulk-review-target='editForm']")
    const displayRow = row.querySelector("[data-bulk-review-target='displayRow']")

    if (editForm) editForm.classList.add("hidden")
    if (displayRow) displayRow.classList.remove("hidden")

    this.editing = null
  }

  updateRowDisplay(row, override) {
    // Update display cells with override values
    Object.entries(override).forEach(([key, value]) => {
      const cell = row.querySelector(`[data-display-field="${key}"]`)
      if (cell) cell.textContent = value
    })
  }

  updateOverridesField() {
    if (this.hasOverridesFieldTarget) {
      this.overridesFieldTarget.value = JSON.stringify(this.overridesValue)
    }
  }
}
```

**Step 2: Commit**

```bash
git add app/javascript/controllers/bulk_review_controller.js
git commit -m "feat: add bulk_review Stimulus controller for inline editing"
```

---

### Task 4.4: Add Sidebar Link for SSH Profiles

**Files:**
- Modify: `app/views/shared/_sidebar.html.erb` (or equivalent)

**Step 1: Add SSH Profiles to Settings section**

Add to the Settings section of the sidebar:

```erb
<%= link_to settings_ssh_profiles_path, class: "sidebar-link" do %>
  <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 7a2 2 0 012 2m4 0a6 6 0 01-7.743 5.743L11 17H9v2H7v2H4a1 1 0 01-1-1v-2.586a1 1 0 01.293-.707l5.964-5.964A6 6 0 1121 9z"/>
  </svg>
  <span>SSH Profiles</span>
<% end %>
```

**Step 2: Commit**

```bash
git add app/views/shared/_sidebar.html.erb
git commit -m "feat: add SSH Profiles link to sidebar"
```

---

## Final: Run Full Test Suite and Lint

### Task F.1: Run All Tests

**Step 1: Run full test suite**

Run: `bin/rspec spec/models spec/services spec/requests spec/components`
Expected: All pass

**Step 2: Run rubocop**

Run: `bin/rubocop -a`
Expected: No offenses (or auto-fixed)

**Step 3: Final commit if needed**

```bash
git add -A
git commit -m "chore: fix any remaining lint issues"
```

---

## Summary

This plan implements:

1. **Phase 1 (Foundation):** SshProfile model, Node association, effective_ssh_* methods, agent config extension, SSH Profiles settings page
2. **Phase 2 (Wizard):** 3-step wizard component, wizard Stimulus controller, SSH profile selection
3. **Phase 3 (Autocomplete):** Hostname suggestions API, autocomplete Stimulus controller with bulk pattern detection
4. **Phase 4 (Bulk Create):** BulkCreateService, controller integration, bulk review controller

Each task follows TDD with explicit test-first steps, exact file paths, and commit checkpoints.
