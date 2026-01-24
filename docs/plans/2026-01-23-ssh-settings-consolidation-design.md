# SSH Settings Consolidation Design

## Overview

Consolidate SSH configuration from multiple scattered sources into a simplified two-tier model: **Global defaults** → **Node overrides**.

### Goals
- Simplify the mental model (eliminate confusing priority chains)
- Easier administration (single place for global SSH config)

### Current Problems
- Three connection methods (`global_bastion`, `custom_bastion`, `direct`) exist on both profiles AND nodes - unclear which wins
- Settings scattered across `/settings/ssh`, `/settings/ssh_profiles`, and node edit forms
- Unclear fallback chain when values are blank (profile? global? env var?)

## Design

### Data Model

**Expanded `SshSetting` (singleton)**

New fields added to the existing table:

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| bastion_host | string | | existing |
| bastion_user | string | | existing |
| bastion_port | integer | 22 | existing |
| ssh_user | string | | new - default username |
| ssh_port | integer | 22 | new - default port |
| ssh_key | text | | new - default private key |
| ssh_password | string | | new - default password |
| sudo_credential | string | | new - default sudo password |
| timeout | integer | 30 | new - seconds |
| verify_host_key | boolean | false | new |
| server_url | string | | existing, unchanged |
| benchmark_work_dir | string | | existing, unchanged |
| default_agent_path | string | | existing, unchanged |

**Simplified `Node` SSH fields**

Keep existing fields, add explicit override flags:

| Field | Action |
|-------|--------|
| ssh_user | keep |
| ssh_user_override | new boolean, default: false |
| ssh_port | keep |
| ssh_port_override | new boolean, default: false |
| ssh_key | keep |
| ssh_key_override | new boolean, default: false |
| ssh_password | keep |
| ssh_password_override | new boolean, default: false |
| sudo_credential | keep |
| sudo_credential_override | new boolean, default: false |
| ssh_connect_method | keep (direct vs bastion only) |
| ssh_connect_method_override | new boolean, default: false |
| jump_host/user/port | remove |
| ssh_profile_id | remove |
| ssh_profile_override | remove |

**Remove entirely:**
- `ssh_profiles` table
- `SshProfile` model

### Resolution Logic

Simple rule: If override flag is true, use node value. Otherwise, use global default.

```ruby
# Node model - simplified effective_* methods
class Node < ApplicationRecord
  def effective_ssh_user
    ssh_user_override? ? ssh_user : SshSetting.current.ssh_user
  end

  def effective_ssh_port
    ssh_port_override? ? ssh_port : SshSetting.current.ssh_port
  end

  def effective_ssh_key
    ssh_key_override? ? ssh_key : SshSetting.current.ssh_key
  end

  # Same pattern for: ssh_password, sudo_credential

  def effective_ssh_connect_method
    ssh_connect_method_override? ? ssh_connect_method : :global_bastion
  end
end
```

**Connection method simplification:**
- Remove `custom_bastion` option entirely
- Keep only: `global_bastion` (use SshSetting bastion) and `direct` (no bastion)

**SshConfig class changes:**
- Remove Rails credentials lookups
- Remove environment variable fallbacks
- All methods delegate directly to `SshSetting.current`

```ruby
# Simplified SshConfig
class SshConfig
  def self.jump_host     = SshSetting.current.bastion_host
  def self.jump_user     = SshSetting.current.bastion_user
  def self.jump_port     = SshSetting.current.bastion_port
  def self.user          = SshSetting.current.ssh_user
  def self.timeout       = SshSetting.current.timeout
  def self.use_jump_host? = jump_host.present?
end
```

### UI - SSH Defaults Page

**Route:** `/settings/ssh_defaults`

**Layout:** Single form with grouped sections

```
┌─────────────────────────────────────────────────────────┐
│ SSH Defaults                                            │
├─────────────────────────────────────────────────────────┤
│                                                         │
│ BASTION / JUMP HOST                                     │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ Host:  [bastion.example.com_______________]         │ │
│ │ User:  [admin_____]     Port: [22__]                │ │
│ └─────────────────────────────────────────────────────┘ │
│                                                         │
│ DEFAULT AUTHENTICATION                                  │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ SSH User:     [hpc-admin________________________]   │ │
│ │ SSH Port:     [22__]                                │ │
│ │ SSH Key:      [paste private key________________]   │ │
│ │               [__________________________________|▼] │ │
│ │ SSH Password: [••••••••] (optional)                 │ │
│ │ Sudo Password:[••••••••] (optional)                 │ │
│ └─────────────────────────────────────────────────────┘ │
│                                                         │
│ CONNECTION OPTIONS                                      │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ Timeout:           [30_] seconds                    │ │
│ │ Verify Host Key:   ☐ Enabled                        │ │
│ └─────────────────────────────────────────────────────┘ │
│                                                         │
│                              [Save SSH Defaults]        │
└─────────────────────────────────────────────────────────┘
```

**Controller:** `Settings::SshDefaultsController` (replaces `Settings::SshController`)

**Navigation:** Update sidebar - "SSH" link points to `/settings/ssh_defaults`, remove "SSH Profiles" link

### UI - Node Override Form

**Location:** Node edit form (`/nodes/:id/edit`), SSH section

**Collapsed by default:**
```
│ ▶ SSH SETTINGS (2 overrides)        [click to expand]  │
```

**Expanded state:**
```
│ ▼ SSH SETTINGS (2 overrides)                            │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ ☐ Override SSH User        Default: hpc-admin      │ │
│ │ ☐ Override SSH Port        Default: 22             │ │
│ │ ☑ Override SSH Key         ───────────────────     │ │
│ │   [paste private key______________________|▼]      │ │
│ │ ☐ Override SSH Password    Default: (set)          │ │
│ │ ☐ Override Sudo Password   Default: (set)          │ │
│ │ ☑ Override Connection      ───────────────────     │ │
│ │   ○ Use Bastion  ● Direct                          │ │
│ └─────────────────────────────────────────────────────┘ │
```

**Behavior:**
- Checkbox unchecked → input hidden, shows "Default: {value}"
- Checkbox checked → input appears, default hint disappears
- Password/key defaults show "(set)" or "(not set)" instead of actual value
- Collapsed header shows count of active overrides or "Using defaults"
- Stimulus controller handles show/hide on checkbox toggle

**Validation:** If override is checked, the corresponding value field is required

## Migration Strategy

### Step 1: Expand SshSetting table

```ruby
add_column :ssh_settings, :ssh_user, :string
add_column :ssh_settings, :ssh_port, :integer, default: 22
add_column :ssh_settings, :ssh_key, :text
add_column :ssh_settings, :ssh_password, :string
add_column :ssh_settings, :sudo_credential, :string
add_column :ssh_settings, :timeout, :integer, default: 30
add_column :ssh_settings, :verify_host_key, :boolean, default: false
```

### Step 2: Seed defaults from current sources

```ruby
setting = SshSetting.current
setting.update!(
  ssh_user: Rails.application.credentials.dig(:ssh, :user) || ENV["SSH_USER"],
  timeout: Rails.application.credentials.dig(:ssh, :timeout) || ENV["SSH_TIMEOUT"] || 30,
  verify_host_key: Rails.application.credentials.dig(:ssh, :verify_host_key) || false
  # ssh_key left blank - admin must paste it via UI (can't auto-migrate key file)
)
```

### Step 3: Add override flags to nodes

```ruby
add_column :nodes, :ssh_user_override, :boolean, default: false
add_column :nodes, :ssh_port_override, :boolean, default: false
add_column :nodes, :ssh_key_override, :boolean, default: false
add_column :nodes, :ssh_password_override, :boolean, default: false
add_column :nodes, :sudo_credential_override, :boolean, default: false
add_column :nodes, :ssh_connect_method_override, :boolean, default: false
```

### Step 4: Migrate profile data to nodes

```ruby
Node.where.not(ssh_profile_id: nil).find_each do |node|
  profile = node.ssh_profile
  next unless profile

  if profile.ssh_user.present?
    node.ssh_user = profile.ssh_user
    node.ssh_user_override = true
  end
  if profile.ssh_port.present? && profile.ssh_port != 22
    node.ssh_port = profile.ssh_port
    node.ssh_port_override = true
  end
  if profile.ssh_key.present?
    node.ssh_key = profile.ssh_key
    node.ssh_key_override = true
  end
  if profile.ssh_password.present?
    node.ssh_password = profile.ssh_password
    node.ssh_password_override = true
  end
  if profile.sudo_credential.present?
    node.sudo_credential = profile.sudo_credential
    node.sudo_credential_override = true
  end
  if profile.ssh_connect_method.present? && profile.ssh_connect_method != "global_bastion"
    node.ssh_connect_method = profile.ssh_connect_method == "direct" ? :direct : :global_bastion
    node.ssh_connect_method_override = true
  end

  node.save!
end
```

### Step 5: Remove old columns and table

```ruby
remove_column :nodes, :ssh_profile_id
remove_column :nodes, :ssh_profile_override
remove_column :nodes, :jump_host
remove_column :nodes, :jump_user
remove_column :nodes, :jump_port
drop_table :ssh_profiles
```

## Files Changed

### Create
- `app/controllers/settings/ssh_defaults_controller.rb`
- `app/views/settings/ssh_defaults/edit.html.erb`
- `app/javascript/controllers/ssh_override_controller.js` (toggle visibility)
- `app/javascript/controllers/collapsible_controller.js` (expand/collapse section)
- 3-4 migrations for schema changes

### Modify
- `app/models/ssh_setting.rb` - add new attribute accessors, validations
- `app/models/ssh_config.rb` - simplify to delegate to SshSetting only
- `app/models/node.rb` - simplify `effective_*` methods, remove profile logic
- `app/services/ssh_execution_service.rb` - remove `custom_bastion` handling
- `app/views/nodes/_form.html.erb` - add collapsible SSH overrides section
- `app/views/shared/_sidebar.html.erb` - update navigation links
- `config/routes.rb` - add new route, remove old routes

### Remove
- `app/models/ssh_profile.rb`
- `app/controllers/settings/ssh_controller.rb`
- `app/controllers/settings/ssh_profiles_controller.rb`
- `app/views/settings/ssh/` directory
- `app/views/settings/ssh_profiles/` directory
- Related specs for removed files

### Update specs
- `spec/models/ssh_setting_spec.rb`
- `spec/models/node_spec.rb`
- `spec/services/ssh_execution_service_spec.rb`
- New specs for `SshDefaultsController`
