# Smart Credential Modal for Agent Operations

## Overview

When users install, update, or uninstall the HPC agent, the system should use stored credentials (from node or global settings) instead of always prompting. The modal only appears when credentials are actually missing.

## Decision Logic

The system checks what's actually needed based on the node's configuration:

| Field | Show modal field if... |
|-------|------------------------|
| SSH Password | No SSH key configured AND no stored ssh_password |
| Sudo Password | SSH user ≠ root AND no stored sudo_credential |
| API Key | node.api_key_id is nil (install only) |
| Server URL | SshSetting.server_url is blank (install only) |

**If all fields can be skipped → one-click operation, no modal.**

## Credential Checker Service

```ruby
# app/services/agent/credential_checker.rb

class Agent::CredentialChecker
  def initialize(node, operation:)
    @node = node
    @operation = operation  # :install, :update, :uninstall
  end

  def needs_ssh_password?
    return false if @node.effective_ssh_key.present?
    return false if SshConfig.ssh_key.present?
    return false if @node.effective_ssh_password.present?
    true
  end

  def needs_sudo_credential?
    ssh_user = @node.effective_ssh_user.presence || SshConfig.user || "root"
    return false if ssh_user == "root"
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
```

## Controller Flow

```ruby
# app/controllers/nodes/installs_controller.rb

def new
  @node = Node.find_by!(hostname: params[:hostname])
  @checker = Agent::CredentialChecker.new(@node, operation: :install)

  if @checker.needs_modal?
    @required_fields = @checker.required_fields
    @api_keys = ApiKey.active.order(:name)
    render :new
  else
    start_installation
  end
end

private

def start_installation
  cache_key = "lifecycle_#{SecureRandom.hex(8)}"

  Agent::InstallJob.perform_later(
    node_id: @node.id,
    server_url: SshSetting.current.server_url,
    api_key_id: @node.api_key_id,
    cache_key: cache_key
  )

  redirect_to node_path(@node), notice: "Installation started"
end
```

## Dynamic Modal View

The modal only renders fields that are actually needed:

```erb
<%= form_with(url: node_install_index_path, method: :post) do |f| %>
  <%= f.hidden_field :hostname, value: @node.hostname %>

  <div class="space-y-4">
    <% if @required_fields[:ssh_password] %>
      <div>
        <%= f.label :ssh_password, "SSH Password" %>
        <%= f.password_field :ssh_password, required: true %>
        <p class="text-xs text-slate-500">No SSH key configured</p>
      </div>
    <% end %>

    <% if @required_fields[:sudo_password] %>
      <div>
        <%= f.label :sudo_password, "Sudo Password" %>
        <%= f.password_field :sudo_password, required: true %>
        <p class="text-xs text-slate-500">Required for non-root user</p>
      </div>
    <% end %>

    <% if @required_fields[:api_key] %>
      <div>
        <%= f.label :api_key_id, "API Key" %>
        <%= f.collection_select :api_key_id, @api_keys, :id, :name %>
      </div>
    <% end %>

    <% if @required_fields[:server_url] %>
      <div>
        <%= f.label :server_url, "Server URL" %>
        <%= f.text_field :server_url, value: request.base_url %>
      </div>
    <% end %>
  </div>

  <%= f.submit "Install" %>
<% end %>
```

## Operation Differences

| Operation | API Key Needed? | Server URL Needed? |
|-----------|----------------|-------------------|
| Install | If node.api_key_id nil | If global not set |
| Update | No (already installed) | No (already configured) |
| Uninstall | No (removing agent) | No (removing agent) |

## Error Handling

When one-click operation fails due to invalid credentials:

1. Job catches `Net::SSH::AuthenticationFailed`
2. AgentEvent marked as failed with helpful message
3. UI shows error with links to update settings

```
Authentication failed - credentials may be outdated
[ Update Node Settings ]  [ Update Global Settings ]
```

## Files to Change

**New:**
- `app/services/agent/credential_checker.rb`
- `spec/services/agent/credential_checker_spec.rb`

**Modified:**
- `app/controllers/nodes/installs_controller.rb`
- `app/controllers/nodes/updates_controller.rb`
- `app/controllers/nodes/uninstalls_controller.rb`
- `app/views/nodes/installs/new.html.erb`
- `app/views/nodes/updates/new.html.erb`
- `app/views/nodes/uninstalls/new.html.erb`

## Test Scenarios

| Scenario | Expected Result |
|----------|-----------------|
| SSH key + root user + API key + server URL | One-click, no modal |
| SSH key + non-root + no sudo stored | Modal: sudo only |
| No SSH key + root + no password stored | Modal: SSH password only |
| Nothing configured | Modal: all 4 fields |
| Stored password is invalid | Job fails with clear error message |
