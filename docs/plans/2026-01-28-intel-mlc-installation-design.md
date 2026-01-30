# Intel MLC Web-Triggered Installation Design

**Date:** 2026-01-28
**Status:** Approved
**Author:** Claude Code

## Overview

Enable web-triggered installation of Intel Memory Latency Checker (MLC) to remote HPC nodes with automatic Lmod module configuration. Supports both fresh installations and version upgrades with side-by-side versioning.

## High-Level Architecture

```
Web UI                          Rails Server                    Target Node(s)
────────                        ────────────                    ──────────────
User uploads tarball        →   Store & extract tarball
User verifies checksum      →   Compute & compare checksum
User selects binary         →   Detect version from binary
User selects nodes          →   Validate node connectivity
User clicks "Install"       →   Queue InstallJob
                                                            →   SSH: qis-agent mlc-install
                                                                  - Extract tarball
                                                                  - Install to /opt/qct/utils/qis/software/mlc-<ver>
                                                                  - Generate modulefile
                                                            ←   Report success/failure
                            ←   Update installation status
UI shows progress/result    ←   Broadcast via Turbo
```

## Key Paths

| Purpose | Path |
|---------|------|
| Binary installation | `/opt/qct/utils/qis/software/mlc-<version>/mlc` |
| Modulefile | `/opt/qct/utils/qis/modulefiles/mlc/<version>` |
| Default symlink | `/opt/qct/utils/qis/software/mlc-latest` → `mlc-<version>` |

## Web Interface

### Step 1: Upload Tarball with Checksum Verification

```
┌─────────────────────────────────────────────────────────────────┐
│  Intel MLC Installation                                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Source:  ○ Upload tarball    ○ Shared storage path             │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │  [Upload Area]                                               ││
│  │  Drag & drop MLC tarball or click to browse                 ││
│  │  mlc_v3.11.tgz (45.2 MB) ✓ Uploaded                         ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  Checksum Verification (optional)                               │
│  ┌──────────────┐  ┌────────────────────────────────┐  ┌──────┐│
│  │ SHA256    ▼  │  │ a3f8c2e1b9d4...                │  │Verify││
│  └──────────────┘  └────────────────────────────────┘  └──────┘│
│                                                                  │
│  ✓ Checksum verified - matches expected value                   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Checksum Verification Behavior:**

| State | UI Feedback |
|-------|-------------|
| No checksum entered | "Verify" button disabled, proceed without verification |
| Verifying | Spinner with "Verifying checksum..." |
| Match | Green checkmark: "✓ Checksum verified" |
| Mismatch | Red alert: "✗ Checksum mismatch - expected: abc123..., got: def456..." |
| Mismatch action | Block installation until user re-uploads or clears checksum field |

**Supported Checksum Algorithms:**
- SHA256 (default, recommended)
- SHA1
- MD5 (legacy support)

### Step 2: Interactive Binary Selection

```
┌─────────────────────────────────────────────────────────────────┐
│  Step 2: Select Binary                                          │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │  📁 mlc_v3.11/                                              ││
│  │  ├── 📁 Linux/                                              ││
│  │  │   └── 📄 mlc (ELF 64-bit, 2.1 MB)          [● Select]   ││
│  │  ├── 📁 Windows/                                            ││
│  │  │   └── 📄 mlc.exe (PE32+, 1.8 MB)           [○ Select]   ││
│  │  ├── 📄 license.txt                                         ││
│  │  └── 📄 README.md                                           ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  Selected: Linux/mlc                                            │
│  Detected version: 3.11                                         │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│  Step 3: Configure Installation                    [Auto-filled]│
│                                                                  │
│  Install path: /opt/qct/utils/qis/software/mlc-3.11/mlc        │
│  Module path:  /opt/qct/utils/qis/modulefiles/mlc/3.11         │
│                                                                  │
│  ✓ Lmod modulefile will be auto-generated                       │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Binary Detection Logic:**

| File Type | Display | Selectable |
|-----------|---------|------------|
| ELF 64-bit (Linux) | `📄 mlc (ELF 64-bit, 2.1 MB)` | Yes |
| PE32+ (Windows) | `📄 mlc.exe (PE32+, 1.8 MB)` | Yes |
| Mach-O (macOS) | `📄 mlc (Mach-O 64-bit, 1.9 MB)` | Yes |
| Non-binary files | Shown but not selectable | No |

**Version Detection:** Run `./mlc --version` on selected binary, parse version string.

**Edge Cases:**

| Scenario | Behavior |
|----------|----------|
| No MLC binary found in tarball | Show error: "No MLC binary detected in tarball" |
| Multiple Linux binaries | Show all, let user choose |
| Version detection fails | Prompt user to manually enter version |
| Selected binary not Linux ELF | Warning: "Selected binary may not be compatible with target nodes" |

### Step 3: Node Selection

```
┌─────────────────────────────────────────────────────────────────┐
│  Target Nodes                                                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Select by:  ○ Individual nodes  ○ Node group  ○ All nodes     │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ ☑ node-001.hpc.local    Online   MLC: not installed         ││
│  │ ☑ node-002.hpc.local    Online   MLC: 3.10                  ││
│  │ ☐ node-003.hpc.local    Offline  MLC: 3.10                  ││
│  │ ☑ node-004.hpc.local    Online   MLC: not installed         ││
│  └─────────────────────────────────────────────────────────────┘│
│  3 nodes selected                                               │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│  Installation Options                                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Install path:  /opt/qct/utils/qis/software/mlc-<version>      │
│                 (version auto-detected from binary)             │
│                                                                  │
│  On failure:    ● Stop on first failure (recommended)           │
│                 ○ Continue and report failures at end           │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  ⚠ node-002 has MLC 3.10 installed. New version will be  │  │
│  │    installed side-by-side. Use `module load mlc/<ver>`    │  │
│  │    to switch versions.                                     │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│                                      [ Cancel ]  [ Install ]    │
└─────────────────────────────────────────────────────────────────┘
```

**Node Status Indicators:**

| Current MLC State | Display | Selection Behavior |
|-------------------|---------|-------------------|
| Not installed | "MLC: not installed" (gray) | Selectable |
| Installed (older) | "MLC: 3.10" (yellow) | Selectable, shows upgrade notice |
| Installed (same) | "MLC: 3.11" (green) | Selectable, shows "already installed" warning |
| Node offline | "Offline" (red) | Disabled, cannot select |

**Pre-flight Validation:**
1. SSH connectivity to all selected nodes
2. Sufficient disk space at install path
3. Write permissions to `/opt/qct/utils/qis/`
4. Tarball accessibility (if shared path mode)

## Agent-Side Installation

### Command

```bash
qis-agent mlc-install \
  --tarball /tmp/mlc_upload_abc123.tgz \
  --binary-path Linux/mlc \
  --install-dir /opt/qct/utils/qis/software \
  --module-dir /opt/qct/utils/qis/modulefiles \
  --server http://rails:3000 \
  --token <token> \
  --id <install-job-id>
```

### Installation Steps

```
Step 1: Validate
  ├── Check tarball exists and is readable
  ├── Check install-dir is writable
  └── Check module-dir is writable

Step 2: Extract to temp directory
  └── tar -xzf mlc.tgz -C /tmp/mlc-extract-<uuid>/

Step 3: Detect version
  ├── Find mlc binary at specified binary-path
  ├── Run: ./mlc --version
  └── Extract version string (e.g., "3.11")

Step 4: Install binary
  ├── Create /opt/qct/utils/qis/software/mlc-3.11/
  ├── Copy mlc binary with executable permissions
  ├── Update symlink: mlc-latest → mlc-3.11
  └── Verify: mlc-3.11/mlc --version works

Step 5: Generate modulefile
  ├── Create /opt/qct/utils/qis/modulefiles/mlc/3.11
  ├── Write Lmod modulefile content
  └── Verify: module avail mlc shows new version

Step 6: Cleanup
  └── Remove temp extraction directory

Step 7: Report success
  └── POST result to server API
```

### Generated Modulefile

```lua
-- /opt/qct/utils/qis/modulefiles/mlc/3.11
help([[Intel Memory Latency Checker (MLC) v3.11]])

whatis("Name: Intel MLC")
whatis("Version: 3.11")
whatis("Description: Memory subsystem benchmarking tool")

local base = "/opt/qct/utils/qis/software/mlc-3.11"

prepend_path("PATH", base)
```

### Error Handling

| Failure Point | Action |
|---------------|--------|
| Tarball not found | Report error, exit |
| Extraction fails | Report error, cleanup temp, exit |
| Version detection fails | Report error with "unable to detect version", cleanup, exit |
| Install dir not writable | Report error with permission details, exit |
| Binary copy fails | Report error, cleanup partial install, exit |
| Modulefile creation fails | Report error, keep binary installed, exit |

## Progress Tracking

### Live Progress UI

```
┌─────────────────────────────────────────────────────────────────┐
│  MLC Installation Progress                              [Cancel]│
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Version detected: 3.11                                         │
│  Overall: 2 of 3 nodes complete                                 │
│  ████████████████████░░░░░░░░░░ 66%                            │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ ✓ node-001.hpc.local    Success    12s                      ││
│  │ ✓ node-002.hpc.local    Success    14s                      ││
│  │ ◐ node-004.hpc.local    Installing... (Step 4/7)            ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  Current: Installing binary to /opt/qct/utils/qis/software/... │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Failure Scenarios

**Stop on first failure mode:**
```
✓ node-001    Success
✗ node-002    Failed: Permission denied writing to /opt/qct/utils/qis/
⊘ node-004    Skipped (installation stopped due to failure)
```

**Continue on failure mode:**
```
✓ node-001    Success
✗ node-002    Failed: Permission denied writing to /opt/qct/utils/qis/
✓ node-004    Success

Summary: 2 succeeded, 1 failed
```

## Data Models

### MlcInstallation

```ruby
class MlcInstallation < ApplicationRecord
  belongs_to :created_by, class_name: "User"
  has_many :mlc_installation_nodes, dependent: :destroy
  has_many :nodes, through: :mlc_installation_nodes

  enum :status, { pending: 0, running: 1, completed: 2, failed: 3, cancelled: 4 }
  enum :source_type, { upload: 0, shared_path: 1 }
  enum :failure_mode, { stop_on_first: 0, continue_on_failure: 1 }
end
```

**Attributes:**
- `source_path` - tarball location on server
- `binary_path` - selected binary within tarball (e.g., "Linux/mlc")
- `checksum_algorithm` - sha256, sha1, md5
- `checksum_value` - expected checksum
- `checksum_verified` - boolean
- `detected_version` - version string
- `install_dir` - default: /opt/qct/utils/qis/software
- `module_dir` - default: /opt/qct/utils/qis/modulefiles

### MlcInstallationNode

```ruby
class MlcInstallationNode < ApplicationRecord
  belongs_to :mlc_installation
  belongs_to :node

  enum :status, { pending: 0, running: 1, success: 2, failed: 3, skipped: 4 }
end
```

**Attributes:**
- `step_current` - current step number
- `step_total` - total steps (7)
- `step_name` - current step description
- `error_message` - failure details
- `started_at` - timestamp
- `completed_at` - timestamp

## API Endpoints

### Agent Callbacks

```
POST /api/v1/mlc_installations/:id/progress
```
Agent reports step progress during installation:
```json
{
  "node_id": "node-uuid",
  "step": 4,
  "total_steps": 7,
  "step_name": "Installing binary",
  "status": "running"
}
```

```
POST /api/v1/mlc_installations/:id/complete
```
Agent reports final success/failure:
```json
{
  "node_id": "node-uuid",
  "status": "success",
  "detected_version": "3.11",
  "install_path": "/opt/qct/utils/qis/software/mlc-3.11/mlc",
  "module_path": "/opt/qct/utils/qis/modulefiles/mlc/3.11"
}
```

### Web UI

```
GET /mlc_installations/:id
```
Turbo Frame for live status updates.

## Implementation Components

### Rails

**Models & Migrations:**
- `MlcInstallation` model
- `MlcInstallationNode` model
- Database migrations

**Controllers:**
- `MlcInstallationsController` - CRUD + progress view
- `Api::V1::MlcInstallationsController` - Agent callbacks

**Services:**
- `Mlc::UploadService` - Handle tarball upload, extraction, checksum
- `Mlc::BinaryDetectionService` - Scan extracted files, detect version
- `Mlc::TriggerInstallService` - SSH command builder, remote execution

**Jobs:**
- `Mlc::InstallJob` - Background job to trigger SSH installs

**Views:**
- Upload view with checksum verification
- Binary selection tree view
- Node selection with groups
- Progress view with Turbo updates

### Go Agent

**Commands:**
- `cmd/mlc_install.go` - CLI command entry point

**MLC Package:**
- `mlc/install_workflow.go` - Installation orchestration
- `mlc/modulefile.go` - Lmod file generation
- `mlc/version_detector.go` - Parse version from binary

### Stimulus Controllers

- `mlc_upload_controller.js` - File upload + checksum verify
- `binary_selection_controller.js` - Tree view selection
- `node_selection_controller.js` - Multi-select with groups

## File Structure

```
# Rails
app/
├── models/
│   ├── mlc_installation.rb
│   └── mlc_installation_node.rb
├── controllers/
│   ├── mlc_installations_controller.rb
│   └── api/v1/mlc_installations_controller.rb
├── services/mlc/
│   ├── upload_service.rb
│   ├── binary_detection_service.rb
│   └── trigger_install_service.rb
├── jobs/mlc/
│   └── install_job.rb
└── views/mlc_installations/
    ├── new.html.erb
    ├── show.html.erb
    └── _node_status.html.erb

# Agent
agent/
├── cmd/
│   └── mlc_install.go
└── mlc/
    ├── install_workflow.go
    ├── modulefile.go
    └── version_detector.go
```
