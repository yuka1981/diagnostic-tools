# E2E Test IDs Phase 8: Settings & Admin Module Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `data-testid` attributes to all Settings & Admin views to enable Playwright E2E testing.

**Architecture:** Views add `data-testid` attributes directly to key elements. Test IDs follow the `{module}-{element}-{descriptor}` pattern.

**Tech Stack:** Rails 7, ERB templates

---

## Task 1: SSH Settings Page

**Files:**
- Modify: `app/views/settings/ssh_defaults/show.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Page container | `ssh-settings-container` |
| Form | `ssh-settings-form` |
| Bastion host field | `ssh-settings-input-bastion-host` |
| Bastion user field | `ssh-settings-input-bastion-user` |
| Bastion port field | `ssh-settings-input-bastion-port` |
| SSH user field | `ssh-settings-input-user` |
| SSH port field | `ssh-settings-input-port` |
| SSH key field | `ssh-settings-input-key` |
| SSH password field | `ssh-settings-input-password` |
| Sudo credential field | `ssh-settings-input-sudo` |
| Timeout field | `ssh-settings-input-timeout` |
| Verify host key checkbox | `ssh-settings-checkbox-verify` |
| Submit button | `ssh-settings-button-submit` |

**Commit:** `feat(settings): add testid support to SSH settings page`

---

## Task 2: Agent Configuration Page

**Files:**
- Modify: `app/views/settings/agents/show.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Page container | `agent-config-container` |
| Config form | `agent-config-form` |
| Server URL field | `agent-config-input-url` |
| Agent path field | `agent-config-input-path` |
| Work dir field | `agent-config-input-workdir` |
| Submit button | `agent-config-button-submit` |
| Releases section | `agent-config-releases` |
| New release button | `agent-config-button-new-release` |

**Commit:** `feat(settings): add testid support to agent configuration page`

---

## Task 3: Agent Releases Index Page

**Files:**
- Modify: `app/views/settings/agent_releases/index.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Page container | `agent-releases-container` |
| New release button | `agent-releases-button-new` |
| Releases table | `agent-releases-table` |
| Table header | `agent-releases-table-header` |
| Table body | `agent-releases-table-body` |
| Empty state | `agent-releases-empty` |

**Dynamic row test IDs (by version):**

| Element | Test ID Pattern |
|---------|-----------------|
| Row | `agent-releases-row-{version}` |
| Version cell | `agent-releases-version-{version}` |
| Status badge | `agent-releases-status-{version}` |
| View button | `agent-releases-button-view-{version}` |
| Edit button | `agent-releases-button-edit-{version}` |

**Commit:** `feat(settings): add testid support to agent releases index`

---

## Task 4: Agent Releases Show Page

**Files:**
- Modify: `app/views/settings/agent_releases/show.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Page container | `agent-releases-show-container` |
| Version heading | `agent-releases-show-version` |
| Status badge | `agent-releases-show-status` |
| Latest badge | `agent-releases-show-latest` |
| Edit button | `agent-releases-show-button-edit` |
| Deprecate button | `agent-releases-show-button-deprecate` |
| Activate button | `agent-releases-show-button-activate` |
| Recall button | `agent-releases-show-button-recall` |
| Overview card | `agent-releases-show-overview` |
| Binaries card | `agent-releases-show-binaries` |
| Binaries table | `agent-releases-show-binaries-table` |
| Checksum copy button | `agent-releases-show-copy-checksum` |
| Release notes card | `agent-releases-show-notes` |
| Danger zone | `agent-releases-show-danger` |
| Delete button | `agent-releases-show-button-delete` |

**Dynamic binary row test IDs:**

| Element | Test ID Pattern |
|---------|-----------------|
| Binary row | `agent-releases-binary-{arch}` |
| Download button | `agent-releases-download-{arch}` |

**Commit:** `feat(settings): add testid support to agent releases show page`

---

## Task 5: Agent Releases Form Partial

**Files:**
- Modify: `app/views/settings/agent_releases/_form.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Form | `agent-releases-form` |
| Error container | `agent-releases-form-errors` |
| Version field | `agent-releases-input-version` |
| Status select | `agent-releases-select-status` |
| Binary upload field | `agent-releases-input-binary` |
| Release notes field | `agent-releases-input-notes` |
| Cancel button | `agent-releases-button-cancel` |
| Submit button | `agent-releases-button-submit` |

**Commit:** `feat(settings): add testid support to agent releases form`

---

## Task 6: Server Products Index Page

**Files:**
- Modify: `app/views/settings/server_products/index.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Page container | `server-products-container` |
| Sync button | `server-products-button-sync` |
| Add product button | `server-products-button-new` |
| Last sync timestamp | `server-products-last-sync` |
| Filter form | `server-products-filter-form` |
| Search field | `server-products-filter-search` |
| Series filter | `server-products-filter-series` |
| Form factor filter | `server-products-filter-form-factor` |
| Filter button | `server-products-button-filter` |
| Clear button | `server-products-button-clear` |
| Products table | `server-products-table` |
| Table body | `server-products-table-body` |
| Empty state | `server-products-empty` |
| Pagination | `server-products-pagination` |

**Dynamic row test IDs (by product name):**

| Element | Test ID Pattern |
|---------|-----------------|
| Row | `server-products-row-{name}` |
| Name cell | `server-products-name-{name}` |
| View button | `server-products-button-view-{name}` |
| Edit button | `server-products-button-edit-{name}` |

**Commit:** `feat(settings): add testid support to server products index`

---

## Task 7: Server Products Form Partial

**Files:**
- Modify: `app/views/settings/server_products/_form.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Form | `server-products-form` |
| Error container | `server-products-form-errors` |
| Name field | `server-products-input-name` |
| Series field | `server-products-input-series` |
| Form factor select | `server-products-select-form-factor` |
| Rack height field | `server-products-input-rack-height` |
| QCT URL field | `server-products-input-url` |
| CPU generations field | `server-products-input-cpu-gen` |
| Socket count select | `server-products-select-sockets` |
| Max TDP field | `server-products-input-tdp` |
| GPU support checkbox | `server-products-checkbox-gpu` |
| Max memory field | `server-products-input-max-memory` |
| DIMM slots field | `server-products-input-dimm-slots` |
| Memory types field | `server-products-input-memory-types` |
| Memory speed field | `server-products-input-memory-speed` |
| Images upload field | `server-products-input-images` |
| Cancel button | `server-products-button-cancel` |
| Submit button | `server-products-button-submit` |

**Commit:** `feat(settings): add testid support to server products form`

---

## Task 8: API Keys Index Page

**Files:**
- Modify: `app/views/api_keys/index.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Page container | `api-keys-container` |
| Generate key button | `api-keys-button-new` |
| Keys table | `api-keys-table` |
| Table header | `api-keys-table-header` |
| Table body | `api-keys-table-body` |
| Empty state | `api-keys-empty` |

**Dynamic row test IDs (by key name):**

| Element | Test ID Pattern |
|---------|-----------------|
| Row | `api-keys-row-{name}` |
| Name cell | `api-keys-name-{name}` |
| Token display | `api-keys-token-{name}` |
| Status badge | `api-keys-status-{name}` |
| Last used | `api-keys-last-used-{name}` |
| Revoke button | `api-keys-button-revoke-{name}` |
| Delete button | `api-keys-button-delete-{name}` |

**Commit:** `feat(settings): add testid support to API keys index`

---

## Task 9: API Keys New Page

**Files:**
- Modify: `app/views/api_keys/new.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Page container | `api-keys-new-container` |
| Form | `api-keys-form` |
| Error container | `api-keys-form-errors` |
| Name field | `api-keys-input-name` |
| Cancel button | `api-keys-button-cancel` |
| Generate button | `api-keys-button-generate` |

**Commit:** `feat(settings): add testid support to API keys new page`

---

## Task 10: Update Test ID Reference Document

**Files:**
- Modify: `docs/testing/test-id-reference.md`

Append the Settings & Admin Module section.

**Commit:** `docs: add settings and admin test IDs to reference document`

---

## Task 11: Run Verification

**Step 1:** Run `bin/rails runner "puts 'Views load OK'"`
**Step 2:** Run `bin/rubocop app/views/settings/ app/views/api_keys/`

---

## Success Criteria

- [ ] All settings view files have data-testid attributes
- [ ] Dynamic test IDs use names/versions (not database IDs)
- [ ] Test ID reference document updated
- [ ] All views load without syntax errors

---

## File Summary

| File | Test IDs |
|------|----------|
| `app/views/settings/ssh_defaults/show.html.erb` | 13 |
| `app/views/settings/agents/show.html.erb` | 8 |
| `app/views/settings/agent_releases/index.html.erb` | 11 (+ dynamic) |
| `app/views/settings/agent_releases/show.html.erb` | 17 (+ dynamic) |
| `app/views/settings/agent_releases/_form.html.erb` | 8 |
| `app/views/settings/server_products/index.html.erb` | 18 (+ dynamic) |
| `app/views/settings/server_products/_form.html.erb` | 18 |
| `app/views/api_keys/index.html.erb` | 13 (+ dynamic) |
| `app/views/api_keys/new.html.erb` | 6 |
