# **FEATURE REQUEST: HPC Agent Patching & Version Management**

**Status**: Draft
**Priority**: High
**Target Version**: v0.9.x
**Dependencies**: `SshExecutionService`
**Style Guide**: NetBox-inspired (Release Management, Update Buttons, Status Badges)

## **1. Context & Goal**

目前 `diagnostic-tools` 缺乏 Agent 版本更新機制。當 Agent 修正 Bug 或新增功能 (如 PerfSpect 支援) 後，維運人員必須手動 SSH 到每台機器重新安裝，效率極低且易出錯。

**目標**：建立一套從 Web UI 管理 Agent 版本，並能批次或單一推送更新 (Patch) 到節點的機制。

## **2. Database Schema Changes**

### **2.1 New Model: `AgentRelease`**

用於儲存編譯好的 Agent Binary 及其版本資訊。

* **Table**: `agent_releases`
* **Columns**:
  * `version`: string (e.g., "v0.5.2") - Unique, Required.
  * `file`: ActiveStorage Attachment (The compiled binary).
  * `checksum`: string (SHA256 hash of the binary) - Auto-calculated.
  * `release_notes`: text (Markdown).
  * `status`: enum (active, deprecated, recalled).
  * `created_at`: datetime.

### **2.2 Update Model: `Node`**

需記錄節點當前運行的版本，以便 UI 提示更新。

* **Columns**:
  * `agent_version`: string (e.g., "v0.5.0") - Updated via Heartbeat/Inventory.
  * `auto_update`: boolean (default: false) - Future proofing.

## **3. Functional Requirements**

### **3.1 Agent Version Management (Admin UI)**

* **List View**: 顯示所有 Release，標記 "Latest"。
* **Upload Form**: 允許管理員上傳 Linux Binary (`diagnostic-agent`)，系統自動計算 Checksum。

### **3.2 Patch Orchestration (The Update Logic)**

需實作 `Agent::PatchService`，嚴格執行以下步驟：

0. **Pre-flight Safety Check (The Block Mechanism)**:
    * **Check 1: Node Idle State**: 查詢 DB，檢查該 Node 是否有任何狀態為 `pending` 或 `running` 的 `BenchmarkRun`。
        * **Rule**: 只要 `Node` 不處於 `idle` 狀態，**必須拒絕更新**並拋出 `NodeBusyError`。
    * **Check 2: Connectivity**: 簡單 SSH 測試。
    * **Override**: 允許 Admin 勾選 "Force Update" 以忽略 Check 1 (需記錄 Audit Log)。

1. **Transport**: `SCP` binary to `/tmp/diagnostic-agent.<version>`.
2. **Verify**: Remote `sha256sum`.
3. **Install (Atomic Swap)**: `stop` -> `backup` -> `replace` -> `start`.
4. **Verification**: Check systemd status.
5. **Rollback**: If start fails, restore backup.

### **3.3 UI Requirements (NetBox Style)**

* **Node Details**:
  * **Update Button State**:
    * 若 Node 處於 `pending` 或 `running` 狀態，Update 按鈕應**被禁用 (Disabled)** 或點擊後彈出紅色警告 Modal。
    * Tooltip 提示: "Cannot update: Node is busy running tasks."
* **Node List**:
  * 若 `Node.agent_version < LatestRelease.version`，在版本號旁顯示 "Update Available" (黃色箭頭 Icon)。
* **Node Details**:
  * Action Button: "Update Agent"。
  * Modal: 顯示 Release Note，確認更新。
* **Bulk Actions**: 在 Node Index 允許勾選多個節點進行 "Bulk Update"。

## **4. Technical Implementation Strategy**

### **4.1 Agent Changes (Go)**

* 在 `root.go` 或 `main.go` 中定義 `var Version = "dev"`。
* 在 `inventory` 或 `ping` 的 Payload 中包含 `version` 欄位。
* Build Script (`Makefile`) 需支援注入版本號：`-ldflags "-X main.Version=v1.0.0"`.

### **4.2 Rails Backend**

* **`AgentReleasesController`**: CRUD for managing binaries.
* **`Agent::PatchJob`**: 非同步執行更新任務。
* **`Agent::PatchService`**:
  * **Safety Logic**:

        ```ruby
        def ensure_node_idle!
          return if @force
          # 檢查是否有任何未完成的任務
          if @node.benchmark_runs.where(status: [:pending, :running]).exists?
            raise NodeBusyError, "Update blocked: Node has pending or running tasks."
          end
        end
        ```

* **Controller**: `UpdatesController` 需捕捉 `NodeBusyError` 並回傳 422 Unprocessable Entity 或顯示 Flash Error。

### **4.3 Verification Logic**

更新後，Rails 應等待 Agent 的下一次 Heartbeat，或主動發送 `diagnostic-agent --version` 指令確認版本已變更。

## **5. Operations Guide**

* **Building a Release**:

    ```bash
    # Local dev
    go build -ldflags "-X main.Version=v0.6.0" -o diagnostic-agent .
    # Then upload this file via Web UI
    ```
