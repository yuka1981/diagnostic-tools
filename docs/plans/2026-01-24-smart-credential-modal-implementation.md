# Smart Credential Modal Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Skip password prompts when credentials are stored in node or global settings; show modal only for missing fields.

**Architecture:** Add `Agent::CredentialChecker` service to determine which fields are needed. Controllers check this before showing modal. If no fields needed, start operation immediately. Views render only required fields.

**Tech Stack:** Rails 7.2, RSpec, ViewComponent, Turbo

---

## Task 1: Create CredentialChecker Service with Tests

**Files:**
- Create: `spec/services/agent/credential_checker_spec.rb`
- Create: `app/services/agent/credential_checker.rb`

**Step 1: Write the failing tests**

```ruby
# spec/services/agent/credential_checker_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent::CredentialChecker do
  let(:node) { create(:node) }

  describe "#needs_ssh_password?" do
    context "when node has SSH key" do
      before { node.update!(ssh_key: "private-key-content", ssh_key_override: true) }

      it "returns false" do
        checker = described_class.new(node, operation: :install)
        expect(checker.needs_ssh_password?).to be false
      end
    end

    context "when global SSH key is configured" do
      before { SshSetting.current.update!(ssh_key: "global-key") }

      it "returns false" do
        checker = described_class.new(node, operation: :install)
        expect(checker.needs_ssh_password?).to be false
      end
    end

    context "when node has stored SSH password" do
      before { node.update!(ssh_password: "secret", ssh_password_override: true) }

      it "returns false" do
        checker = described_class.new(node, operation: :install)
        expect(checker.needs_ssh_password?).to be false
      end
    end

    context "when no SSH key or password configured" do
      before do
        node.update!(ssh_key: nil, ssh_password: nil, ssh_key_override: false, ssh_password_override: false)
        SshSetting.current.update!(ssh_key: nil)
      end

      it "returns true" do
        checker = described_class.new(node, operation: :install)
        expect(checker.needs_ssh_password?).to be true
      end
    end
  end

  describe "#needs_sudo_credential?" do
    context "when SSH user is root" do
      before { node.update!(ssh_user: "root", ssh_user_override: true) }

      it "returns false" do
        checker = described_class.new(node, operation: :install)
        expect(checker.needs_sudo_credential?).to be false
      end
    end

    context "when global SSH user is root" do
      before do
        node.update!(ssh_user_override: false)
        SshSetting.current.update!(ssh_user: "root")
      end

      it "returns false" do
        checker = described_class.new(node, operation: :install)
        expect(checker.needs_sudo_credential?).to be false
      end
    end

    context "when node has stored sudo credential" do
      before { node.update!(sudo_credential: "sudo-pass", sudo_credential_override: true) }

      it "returns false" do
        checker = described_class.new(node, operation: :install)
        expect(checker.needs_sudo_credential?).to be false
      end
    end

    context "when non-root user without stored credential" do
      before do
        node.update!(ssh_user: "admin", ssh_user_override: true, sudo_credential: nil, sudo_credential_override: false)
        SshSetting.current.update!(ssh_user: nil)
      end

      it "returns true" do
        checker = described_class.new(node, operation: :install)
        expect(checker.needs_sudo_credential?).to be true
      end
    end
  end

  describe "#needs_api_key?" do
    context "for install operation" do
      context "when node has API key assigned" do
        let(:api_key) { create(:api_key) }
        before { node.update!(api_key: api_key) }

        it "returns false" do
          checker = described_class.new(node, operation: :install)
          expect(checker.needs_api_key?).to be false
        end
      end

      context "when node has no API key" do
        before { node.update!(api_key_id: nil) }

        it "returns true" do
          checker = described_class.new(node, operation: :install)
          expect(checker.needs_api_key?).to be true
        end
      end
    end

    context "for update operation" do
      it "returns false regardless of API key" do
        node.update!(api_key_id: nil)
        checker = described_class.new(node, operation: :update)
        expect(checker.needs_api_key?).to be false
      end
    end

    context "for uninstall operation" do
      it "returns false regardless of API key" do
        node.update!(api_key_id: nil)
        checker = described_class.new(node, operation: :uninstall)
        expect(checker.needs_api_key?).to be false
      end
    end
  end

  describe "#needs_server_url?" do
    context "for install operation" do
      context "when global server URL is set" do
        before { SshSetting.current.update!(server_url: "https://example.com") }

        it "returns false" do
          checker = described_class.new(node, operation: :install)
          expect(checker.needs_server_url?).to be false
        end
      end

      context "when global server URL is blank" do
        before { SshSetting.current.update!(server_url: nil) }

        it "returns true" do
          checker = described_class.new(node, operation: :install)
          expect(checker.needs_server_url?).to be true
        end
      end
    end

    context "for update operation" do
      before { SshSetting.current.update!(server_url: nil) }

      it "returns false" do
        checker = described_class.new(node, operation: :update)
        expect(checker.needs_server_url?).to be false
      end
    end
  end

  describe "#needs_modal?" do
    context "when all credentials are configured" do
      let(:api_key) { create(:api_key) }

      before do
        node.update!(
          ssh_key: "key", ssh_key_override: true,
          ssh_user: "root", ssh_user_override: true,
          api_key: api_key
        )
        SshSetting.current.update!(server_url: "https://example.com")
      end

      it "returns false" do
        checker = described_class.new(node, operation: :install)
        expect(checker.needs_modal?).to be false
      end
    end

    context "when any credential is missing" do
      before do
        node.update!(ssh_key: nil, ssh_key_override: false, ssh_password: nil, ssh_password_override: false)
        SshSetting.current.update!(ssh_key: nil)
      end

      it "returns true" do
        checker = described_class.new(node, operation: :install)
        expect(checker.needs_modal?).to be true
      end
    end
  end

  describe "#required_fields" do
    it "returns hash of required fields" do
      checker = described_class.new(node, operation: :install)
      fields = checker.required_fields

      expect(fields).to be_a(Hash)
      expect(fields.keys).to contain_exactly(:ssh_password, :sudo_password, :api_key, :server_url)
    end
  end
end
```

**Step 2: Run tests to verify they fail**

```bash
bin/rspec spec/services/agent/credential_checker_spec.rb
```

Expected: FAIL with `uninitialized constant Agent::CredentialChecker`

**Step 3: Write minimal implementation**

```ruby
# app/services/agent/credential_checker.rb
# frozen_string_literal: true

module Agent
  # Determines which credential fields are needed for agent operations.
  # Used to show modal only when credentials are actually missing.
  class CredentialChecker
    def initialize(node, operation:)
      @node = node
      @operation = operation # :install, :update, :uninstall
    end

    def needs_ssh_password?
      # SSH key available? No password needed
      return false if @node.effective_ssh_key.present?
      return false if SshConfig.ssh_key.present?

      # Has stored password? No prompt needed
      return false if @node.effective_ssh_password.present?

      true
    end

    def needs_sudo_credential?
      # Root user? No sudo needed
      ssh_user = @node.effective_ssh_user.presence || SshConfig.user || "root"
      return false if ssh_user == "root"

      # Has stored credential? No prompt needed
      return false if @node.effective_sudo_credential.present?

      true
    end

    def needs_api_key?
      return false unless @operation == :install

      @node.api_key_id.nil?
    end

    def needs_server_url?
      return false unless @operation == :install

      SshSetting.current.server_url.blank?
    end

    def needs_modal?
      needs_ssh_password? || needs_sudo_credential? ||
        needs_api_key? || needs_server_url?
    end

    def required_fields
      {
        ssh_password: needs_ssh_password?,
        sudo_password: needs_sudo_credential?,
        api_key: needs_api_key?,
        server_url: needs_server_url?
      }
    end
  end
end
```

**Step 4: Run tests to verify they pass**

```bash
bin/rspec spec/services/agent/credential_checker_spec.rb
```

Expected: All tests PASS

**Step 5: Commit**

```bash
git add spec/services/agent/credential_checker_spec.rb app/services/agent/credential_checker.rb
git commit -m "feat: add Agent::CredentialChecker service

Determines which credential fields are needed for agent operations.
Returns false for fields that have stored values in node or global settings."
```

---

## Task 2: Update Installs Controller

**Files:**
- Modify: `app/controllers/nodes/installs_controller.rb`

**Step 1: Update the controller**

```ruby
# app/controllers/nodes/installs_controller.rb
# frozen_string_literal: true

require "resolv"

module Nodes
  class InstallsController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_approver!
    before_action :reject_localhost_installation, only: [ :new, :create ]

    def new
      @target_host = params[:hostname]
      @node = Node.find_by(hostname: @target_host)

      # If node doesn't exist yet, we always need the modal for API key at minimum
      unless @node
        setup_modal_variables
        return render :new
      end

      @checker = Agent::CredentialChecker.new(@node, operation: :install)

      if @checker.needs_modal?
        @required_fields = @checker.required_fields
        setup_modal_variables
        render :new
      else
        start_installation_directly
      end
    end

    def create
      # Find or create the node immediately so we have an ID for log streaming
      @node = Node.find_or_initialize_by(hostname: install_params[:hostname])
      @node.arch = install_params[:arch]
      @node.source = :agent_push
      if install_params[:hostname] =~ Regexp.union(Resolv::IPv4::Regex, Resolv::IPv6::Regex)
        @node.ip = install_params[:hostname]
      end

      # For direct connections, save the password to the node record so future collections can use it
      if @node.direct?
        password_to_save = install_params[:bastion_password].presence || install_params[:sudo_password].presence
        @node.sudo_credential = password_to_save if password_to_save
      end

      @node.save!

      # Store sensitive credentials in a short-lived cache to avoid passing them as job arguments
      cache_key = SecureRandom.hex(16)
      credentials = {
        ssh_password: install_params[:bastion_password],
        sudo_password: install_params[:sudo_password]
      }
      Rails.cache.write("install_creds_#{cache_key}", credentials, expires_in: 5.minutes)

      Agent::InstallJob.perform_later(
        node: @node,
        target_host: install_params[:hostname],
        arch: install_params[:arch],
        bastion_host: install_params[:bastion_host],
        bastion_user: install_params[:bastion_user],
        credentials_cache_key: cache_key,
        server_url: install_params[:server_url].presence || SshSetting.current.server_url || request.base_url,
        api_key_id: install_params[:api_key_id],
        user_id: current_user.id
      )

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to nodes_path, notice: "Installation started for #{install_params[:hostname]}" }
      end
    end

    private

    def setup_modal_variables
      # Determine arch: prioritize node's arch, fallback to params, default to x86_64
      raw_arch = @node&.arch.presence || params[:arch]
      @arch = raw_arch == "aarch64" ? "arm64" : raw_arch

      @api_keys = ApiKey.active.order(:name)
      @ssh_setting = SshSetting.current
      @server_url = @ssh_setting.server_url.presence || request.base_url

      # For new nodes or nodes without checker, show all fields
      @required_fields ||= { ssh_password: true, sudo_password: true, api_key: true, server_url: @ssh_setting.server_url.blank? }
    end

    def start_installation_directly
      # One-click install - no modal needed
      cache_key = SecureRandom.hex(16)
      # No credentials to cache - resolve_credentials will use node/global settings

      Agent::InstallJob.perform_later(
        node: @node,
        target_host: @node.hostname,
        arch: @node.arch,
        bastion_host: SshSetting.current.bastion_host,
        bastion_user: SshSetting.current.bastion_user,
        credentials_cache_key: cache_key,
        server_url: SshSetting.current.server_url || request.base_url,
        api_key_id: @node.api_key_id,
        user_id: current_user.id
      )

      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("install_modal", partial: "nodes/installs/started", locals: { node: @node }) }
        format.html { redirect_to node_path(@node), notice: "Installation started for #{@node.hostname}" }
      end
    end

    def authorize_approver!
      return if current_user.approver?

      redirect_to nodes_path, alert: "You are not authorized to install agents."
    end

    def install_params
      params.require(:install).permit(:hostname, :arch, :server_url, :api_key_id, :bastion_host, :bastion_user, :bastion_password, :sudo_password)
    end

    def reject_localhost_installation
      hostname = params[:hostname] || params.dig(:install, :hostname)
      return unless Node.localhost?(hostname)

      @target_host = hostname
      @localhost_error = true

      respond_to do |format|
        format.turbo_stream { render "localhost_not_supported" }
        format.html { render "localhost_not_supported", status: :unprocessable_entity }
      end
    end
  end
end
```

**Step 2: Create the "started" partial for turbo response**

```erb
<%# app/views/nodes/installs/_started.html.erb %>
<turbo-frame id="install_modal">
  <div class="fixed inset-0 z-50 overflow-y-auto" data-controller="modal">
    <div class="fixed inset-0 bg-slate-900/50 backdrop-blur-sm transition-opacity"></div>
    <div class="flex min-h-full items-center justify-center p-4">
      <div class="card-netbox relative w-full max-w-md transform transition-all shadow-2xl">
        <div class="card-header">
          <h3 class="card-title">Installation Started</h3>
        </div>
        <div class="p-6 bg-white text-center">
          <div class="mx-auto flex items-center justify-center h-12 w-12 rounded-full bg-teal-100 mb-4">
            <%= lucide_icon("rocket", class: "h-6 w-6 text-teal-600") %>
          </div>
          <p class="text-sm text-slate-600 mb-4">
            Agent installation has started for <strong><%= node.hostname %></strong>.
          </p>
          <p class="text-xs text-slate-500">
            Using stored credentials from node and global settings.
          </p>
          <div class="mt-6">
            <%= link_to "View Progress", node_path(node), class: "btn-primary", data: { turbo_frame: "_top" } %>
          </div>
        </div>
      </div>
    </div>
  </div>
</turbo-frame>
```

**Step 3: Run tests**

```bash
bin/rspec spec/controllers/nodes/installs_controller_spec.rb
```

**Step 4: Commit**

```bash
git add app/controllers/nodes/installs_controller.rb app/views/nodes/installs/_started.html.erb
git commit -m "feat: add one-click install when credentials configured

Skip modal when node has all required credentials stored.
Show modal only for missing fields."
```

---

## Task 3: Update Install Modal View

**Files:**
- Modify: `app/views/nodes/installs/new.html.erb`

**Step 1: Update the view to show dynamic fields**

```erb
<%# app/views/nodes/installs/new.html.erb %>
<%= turbo_frame_tag "install_modal" do %>
  <%= render "shared/modal", title: "Install Agent: #{@target_host}", max_width: "max-w-xl" do %>
    <div class="px-2" id="install_modal_body">
      <% fields_needed = @required_fields.values.count(true) %>

      <% if fields_needed > 0 %>
        <div class="rounded-md bg-blue-50 p-4 border border-blue-200 mb-6">
          <div class="flex">
            <div class="flex-shrink-0">
              <%= lucide_icon("info", class: "h-5 w-5 text-blue-400") %>
            </div>
            <div class="ml-3">
              <h3 class="text-sm font-bold text-blue-800">Credentials Required</h3>
              <p class="mt-1 text-xs text-blue-700">
                <% if fields_needed == 1 %>
                  One field is needed for this installation.
                <% else %>
                  Some fields are needed for this installation.
                <% end %>
                Configure in node or global settings to enable one-click installs.
              </p>
            </div>
          </div>
        </div>
      <% end %>

      <%= form_with(url: node_install_index_path, method: :post, class: "space-y-6", scope: :install) do |f| %>
        <%= f.hidden_field :hostname, value: @target_host %>
        <%= f.hidden_field :arch, value: @arch, id: "install_arch" %>
        <%= f.hidden_field :bastion_host, value: @ssh_setting.bastion_host %>
        <%= f.hidden_field :bastion_user, value: @ssh_setting.bastion_user.presence || @node&.effective_ssh_user %>

        <div class="space-y-4">
          <% if @required_fields[:ssh_password] %>
            <div>
              <%= f.label :bastion_password, "SSH Password", class: "block text-sm font-bold text-slate-700 mb-1" %>
              <%= f.password_field :bastion_password,
                  placeholder: "Enter SSH password",
                  class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" %>
              <p class="mt-1 text-xs text-slate-500">No SSH key configured for this node.</p>
            </div>
          <% end %>

          <% if @required_fields[:sudo_password] %>
            <div>
              <%= f.label :sudo_password, "Sudo Password", class: "block text-sm font-bold text-slate-700 mb-1" %>
              <%= f.password_field :sudo_password,
                  required: true,
                  placeholder: "Enter sudo password",
                  class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" %>
              <p class="mt-1 text-xs text-slate-500">Required for non-root SSH user.</p>
            </div>
          <% end %>

          <% if @required_fields[:api_key] %>
            <div>
              <%= f.label :api_key_id, "Agent API Key", class: "block text-sm font-bold text-slate-700 mb-1" %>
              <%= f.collection_select :api_key_id, @api_keys, :id, :name,
                  { prompt: "Select an API key for the agent" },
                  { class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm", required: true } %>
            </div>
          <% end %>

          <% if @required_fields[:server_url] %>
            <div>
              <%= f.label :server_url, "Server URL (Callback)", class: "block text-sm font-bold text-slate-700 mb-1" %>
              <%= f.text_field :server_url, value: @server_url,
                  placeholder: "http://10.0.0.1:3000",
                  required: true,
                  class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm font-mono" %>
              <p class="mt-1 text-xs text-slate-500">The URL the agent will use to connect back to this server.</p>
            </div>
          <% end %>
        </div>

        <div class="flex items-center justify-end gap-3 pt-4 border-t border-slate-100">
          <button type="button" class="btn-secondary" data-action="modal#close">Cancel</button>
          <%= f.submit "Begin Installation", class: "btn-primary" %>
        </div>
      <% end %>
    </div>
  <% end %>
<% end %>
```

**Step 2: Commit**

```bash
git add app/views/nodes/installs/new.html.erb
git commit -m "feat: show only required fields in install modal

Dynamic form that hides fields when credentials are already configured."
```

---

## Task 4: Update Updates Controller

**Files:**
- Modify: `app/controllers/nodes/updates_controller.rb`

**Step 1: Update the controller**

```ruby
# app/controllers/nodes/updates_controller.rb
# frozen_string_literal: true

module Nodes
  class UpdatesController < ApplicationController
    layout "dashboard"
    before_action :authenticate_user!
    before_action :authorize_approver!
    before_action :set_node
    before_action :set_agent_release, only: :create

    def new
      @checker = Agent::CredentialChecker.new(@node, operation: :update)

      if @checker.needs_modal?
        @required_fields = @checker.required_fields
        @agent_releases = AgentRelease.active.latest_first
        @latest_release = AgentRelease.latest
        render :new
      else
        # Still need to select a release, so show minimal modal
        @required_fields = { ssh_password: false, sudo_password: false, api_key: false, server_url: false }
        @agent_releases = AgentRelease.active.latest_first
        @latest_release = AgentRelease.latest
        render :new
      end
    end

    def create
      # Store credentials in cache for the job to retrieve
      credentials_cache_key = SecureRandom.hex(16)
      credentials = {}
      credentials[:sudo_password] = params[:sudo_password] if params[:sudo_password].present?
      credentials[:ssh_password] = params[:ssh_password] if params[:ssh_password].present?

      if credentials.any?
        Rails.cache.write(
          "update_creds_#{credentials_cache_key}",
          credentials,
          expires_in: 5.minutes
        )
      end

      # Enqueue the update job
      Agent::UpdateJob.perform_later(
        node: @node,
        agent_release: @agent_release,
        force: params[:force] == "true",
        credentials_cache_key: credentials.any? ? credentials_cache_key : nil,
        user_id: current_user.id
      )

      # Respond with turbo_stream to show progress UI
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to node_path(@node), notice: "Agent update started" }
      end
    end

    private

    def set_node
      @node = Node.find(params[:node_id])
    end

    def set_agent_release
      @agent_release = AgentRelease.find(params[:agent_release_id])
    end

    def authorize_approver!
      return if current_user.approver?

      redirect_to nodes_path, alert: "You are not authorized to update agents."
    end
  end
end
```

**Step 2: Commit**

```bash
git add app/controllers/nodes/updates_controller.rb
git commit -m "feat: use CredentialChecker in updates controller

Check which credential fields are needed before showing modal."
```

---

## Task 5: Update Update Modal View

**Files:**
- Modify: `app/views/nodes/updates/new.html.erb`

**Step 1: Update the view**

```erb
<%# app/views/nodes/updates/new.html.erb %>
<%= turbo_frame_tag "update_modal" do %>
  <%= render "shared/modal", title: "Update Agent: #{@node.hostname}" do %>
    <div class="px-2" id="update_modal_body">
      <% if @node.busy? %>
        <div class="rounded-md bg-red-50 p-4 border border-red-200 mb-6">
          <div class="flex">
            <div class="flex-shrink-0">
              <%= lucide_icon("circle-x", class: "h-5 w-5 text-red-400") %>
            </div>
            <div class="ml-3">
              <h3 class="text-sm font-bold text-red-800">Node is Busy</h3>
              <p class="mt-1 text-xs text-red-700">
                This node has pending or running benchmark tasks. Updating the agent now may cause data loss or corruption.
                You can force the update if necessary, but this is not recommended.
              </p>
            </div>
          </div>
        </div>
      <% elsif @required_fields.values.none? %>
        <div class="rounded-md bg-teal-50 p-4 border border-teal-200 mb-6">
          <div class="flex">
            <div class="flex-shrink-0">
              <%= lucide_icon("check-circle", class: "h-5 w-5 text-teal-400") %>
            </div>
            <div class="ml-3">
              <h3 class="text-sm font-bold text-teal-800">Credentials Configured</h3>
              <p class="mt-1 text-xs text-teal-700">
                Using stored credentials. Just select a release version to proceed.
              </p>
            </div>
          </div>
        </div>
      <% else %>
        <div class="rounded-md bg-blue-50 p-4 border border-blue-200 mb-6">
          <div class="flex">
            <div class="flex-shrink-0">
              <%= lucide_icon("info", class: "h-5 w-5 text-blue-400") %>
            </div>
            <div class="ml-3">
              <h3 class="text-sm font-bold text-blue-800">Agent Update</h3>
              <p class="mt-1 text-xs text-blue-700">
                Select a release version to deploy to this node. The agent service will be stopped during the update.
              </p>
            </div>
          </div>
        </div>
      <% end %>

      <% is_localhost = @node.ip == "127.0.0.1" || @node.ip == "localhost" || @node.ip == "::1" ||
                        @node.hostname == "127.0.0.1" || @node.hostname == "localhost" || @node.hostname == "::1" %>

      <%= form_with(url: node_update_path(@node), method: :post, class: "space-y-6") do |f| %>
        <% if @required_fields[:ssh_password] && !is_localhost %>
          <div>
            <%= f.label :ssh_password, "SSH Password", class: "block text-sm font-bold text-slate-700 mb-1" %>
            <%= f.password_field :ssh_password,
                placeholder: "Enter SSH password",
                class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" %>
            <p class="mt-1 text-xs text-slate-500">No SSH key configured for this node.</p>
          </div>
        <% end %>

        <% if @required_fields[:sudo_password] %>
          <div>
            <%= f.label :sudo_password, "Sudo Password", class: "block text-sm font-bold text-slate-700 mb-1" %>
            <%= f.password_field :sudo_password,
                placeholder: "Enter sudo password",
                class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" %>
            <p class="mt-1 text-xs text-slate-500">Required for non-root SSH user.</p>
          </div>
        <% end %>

        <div>
          <%= f.label :agent_release_id, "Agent Release", class: "block text-sm font-bold text-slate-700 mb-1" %>
          <% if @agent_releases.any? %>
            <div class="space-y-2">
              <% @agent_releases.each do |release| %>
                <label class="flex items-center p-3 border rounded-md cursor-pointer hover:bg-slate-50 <%= release == @latest_release ? 'border-teal-500 bg-teal-50' : 'border-slate-200' %>">
                  <%= f.radio_button :agent_release_id, release.id,
                      checked: release == @latest_release,
                      class: "h-4 w-4 text-teal-600 border-slate-300 focus:ring-teal-500" %>
                  <div class="ml-3 flex-1">
                    <div class="flex items-center gap-2">
                      <span class="text-sm font-medium text-slate-900"><%= release.version %></span>
                      <% if release == @latest_release %>
                        <span class="inline-flex items-center rounded-sm px-1.5 py-0.5 text-xs font-medium bg-teal-100 text-teal-800">Latest</span>
                      <% end %>
                      <% if release.deprecated? %>
                        <span class="inline-flex items-center rounded-sm px-1.5 py-0.5 text-xs font-medium bg-amber-100 text-amber-800">Deprecated</span>
                      <% end %>
                    </div>
                    <p class="text-xs text-slate-500 mt-0.5">
                      Uploaded <%= time_ago_in_words(release.created_at) %> ago
                      <span class="text-slate-400">•</span>
                      <%= release.formatted_size %>
                    </p>
                  </div>
                </label>
              <% end %>
            </div>
          <% else %>
            <div class="text-sm text-slate-500 italic">
              No agent releases available. <%= link_to "Upload a release", new_settings_agent_release_path, class: "text-teal-600 hover:text-teal-700", data: { turbo_frame: "_top" } %> first.
            </div>
          <% end %>
        </div>

        <% if @node.busy? %>
          <div class="flex items-center">
            <label class="flex items-center cursor-pointer">
              <%= f.check_box :force, { class: "h-4 w-4 text-red-600 border-slate-300 rounded focus:ring-red-500" }, "true", "false" %>
              <span class="ml-2 text-sm text-red-700 font-medium">Force update (not recommended)</span>
            </label>
          </div>
        <% end %>

        <div class="flex items-center justify-end gap-3 pt-4 border-t border-slate-100">
          <button type="button" class="btn-secondary" data-action="modal#close">Cancel</button>
          <%= f.submit "Update Agent", class: "btn-primary", disabled: @agent_releases.empty? %>
        </div>
      <% end %>
    </div>
  <% end %>
<% end %>
```

**Step 2: Commit**

```bash
git add app/views/nodes/updates/new.html.erb
git commit -m "feat: show only required fields in update modal

Hide credential fields when stored in node or global settings."
```

---

## Task 6: Update Uninstalls Controller

**Files:**
- Modify: `app/controllers/nodes/uninstalls_controller.rb`

**Step 1: Update the controller**

```ruby
# app/controllers/nodes/uninstalls_controller.rb
# frozen_string_literal: true

module Nodes
  class UninstallsController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_approver!

    def new
      @target_host = params[:hostname]
      @node = Node.find_by(hostname: @target_host)

      unless @node
        redirect_to nodes_path, alert: "Node not found"
        return
      end

      @checker = Agent::CredentialChecker.new(@node, operation: :uninstall)

      if @checker.needs_modal?
        @required_fields = @checker.required_fields
        @ssh_setting = SshSetting.current
        render :new
      else
        start_uninstall_directly
      end
    end

    def create
      @node = Node.find_by!(hostname: uninstall_params[:hostname])

      # Store sensitive credentials in a short-lived cache
      cache_key = SecureRandom.hex(16)
      credentials = {
        ssh_password: uninstall_params[:bastion_password],
        sudo_password: uninstall_params[:sudo_password]
      }
      Rails.cache.write("install_creds_#{cache_key}", credentials, expires_in: 5.minutes)

      Agent::UninstallJob.perform_later(
        target_host: uninstall_params[:hostname],
        bastion_host: uninstall_params[:bastion_host],
        bastion_user: uninstall_params[:bastion_user],
        credentials_cache_key: cache_key,
        user_id: current_user.id
      )

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to nodes_path, notice: "Uninstallation started for #{uninstall_params[:hostname]}" }
      end
    end

    private

    def start_uninstall_directly
      cache_key = SecureRandom.hex(16)
      # No credentials to cache - will use stored credentials

      Agent::UninstallJob.perform_later(
        target_host: @node.hostname,
        bastion_host: SshSetting.current.bastion_host,
        bastion_user: SshSetting.current.bastion_user,
        credentials_cache_key: cache_key,
        user_id: current_user.id
      )

      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("uninstall_modal", partial: "nodes/uninstalls/started", locals: { node: @node }) }
        format.html { redirect_to node_path(@node), notice: "Uninstallation started for #{@node.hostname}" }
      end
    end

    def authorize_approver!
      return if current_user.approver?

      redirect_to nodes_path, alert: "You are not authorized to manage agents."
    end

    def uninstall_params
      params.require(:uninstall).permit(:hostname, :bastion_host, :bastion_user, :bastion_password, :sudo_password)
    end
  end
end
```

**Step 2: Create the "started" partial**

```erb
<%# app/views/nodes/uninstalls/_started.html.erb %>
<turbo-frame id="uninstall_modal">
  <div class="fixed inset-0 z-50 overflow-y-auto" data-controller="modal">
    <div class="fixed inset-0 bg-slate-900/50 backdrop-blur-sm transition-opacity"></div>
    <div class="flex min-h-full items-center justify-center p-4">
      <div class="card-netbox relative w-full max-w-md transform transition-all shadow-2xl">
        <div class="card-header">
          <h3 class="card-title">Uninstallation Started</h3>
        </div>
        <div class="p-6 bg-white text-center">
          <div class="mx-auto flex items-center justify-center h-12 w-12 rounded-full bg-red-100 mb-4">
            <%= lucide_icon("trash-2", class: "h-6 w-6 text-red-600") %>
          </div>
          <p class="text-sm text-slate-600 mb-4">
            Agent uninstallation has started for <strong><%= node.hostname %></strong>.
          </p>
          <p class="text-xs text-slate-500">
            Using stored credentials from node and global settings.
          </p>
          <div class="mt-6">
            <%= link_to "View Progress", node_path(node), class: "btn-primary", data: { turbo_frame: "_top" } %>
          </div>
        </div>
      </div>
    </div>
  </div>
</turbo-frame>
```

**Step 3: Commit**

```bash
git add app/controllers/nodes/uninstalls_controller.rb app/views/nodes/uninstalls/_started.html.erb
git commit -m "feat: add one-click uninstall when credentials configured

Skip modal when node has all required credentials stored."
```

---

## Task 7: Update Uninstall Modal View

**Files:**
- Modify: `app/views/nodes/uninstalls/new.html.erb`

**Step 1: Update the view**

```erb
<%# app/views/nodes/uninstalls/new.html.erb %>
<%= turbo_frame_tag "uninstall_modal" do %>
  <%= render "shared/modal", title: "Uninstall Agent: #{@target_host}" do %>
    <div class="px-2" id="uninstall_modal_body">
      <div class="rounded-md bg-red-50 p-4 border border-red-200 mb-6">
        <div class="flex">
          <div class="flex-shrink-0">
            <%= lucide_icon("circle-x", class: "h-5 w-5 text-red-400") %>
          </div>
          <div class="ml-3">
            <h3 class="text-sm font-bold text-red-800">Uninstall Confirmation</h3>
            <p class="mt-1 text-xs text-red-700">
              This will stop the agent service and remove all related files from the target node.
            </p>
          </div>
        </div>
      </div>

      <%= form_with(url: node_uninstall_index_path, method: :post, class: "space-y-6", scope: :uninstall) do |f| %>
        <%= f.hidden_field :hostname, value: @target_host %>
        <%= f.hidden_field :bastion_host, value: @ssh_setting.bastion_host %>
        <%= f.hidden_field :bastion_user, value: @ssh_setting.bastion_user.presence || @node&.effective_ssh_user %>

        <% if @required_fields.values.any? %>
          <div class="space-y-4">
            <% if @required_fields[:ssh_password] %>
              <div>
                <%= f.label :bastion_password, "SSH Password", class: "block text-sm font-bold text-slate-700 mb-1" %>
                <%= f.password_field :bastion_password,
                    placeholder: "Enter SSH password",
                    class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" %>
                <p class="mt-1 text-xs text-slate-500">No SSH key configured for this node.</p>
              </div>
            <% end %>

            <% if @required_fields[:sudo_password] %>
              <div>
                <%= f.label :sudo_password, "Sudo Password", class: "block text-sm font-bold text-slate-700 mb-1" %>
                <%= f.password_field :sudo_password,
                    required: true,
                    placeholder: "Enter sudo password",
                    class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" %>
                <p class="mt-1 text-xs text-slate-500">Required for non-root SSH user.</p>
              </div>
            <% end %>
          </div>
        <% else %>
          <div class="rounded-md bg-teal-50 p-4 border border-teal-200">
            <p class="text-sm text-teal-700">
              Using stored credentials. Click below to confirm uninstallation.
            </p>
          </div>
        <% end %>

        <div class="flex items-center justify-end gap-3 pt-4 border-t border-slate-100">
          <button type="button" class="btn-secondary" data-action="modal#close">Cancel</button>
          <%= f.submit "Begin Uninstallation", class: "btn-danger" %>
        </div>
      <% end %>
    </div>
  <% end %>
<% end %>
```

**Step 2: Commit**

```bash
git add app/views/nodes/uninstalls/new.html.erb
git commit -m "feat: show only required fields in uninstall modal

Hide credential fields when stored in node or global settings."
```

---

## Task 8: Run Full Test Suite and Final Commit

**Step 1: Run all tests**

```bash
bin/rspec spec/services/agent/credential_checker_spec.rb
bin/rspec spec/controllers
bin/rubocop -a
```

**Step 2: Fix any issues**

Address any failing tests or linting errors.

**Step 3: Final commit if needed**

```bash
git add -A
git commit -m "fix: address test failures and linting issues"
```

**Step 4: Push changes**

```bash
git push
```
