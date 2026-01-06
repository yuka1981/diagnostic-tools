# FEATURE_REQUEST: Node CRUD & SSH Jump Host Support

**Status:** Pending Implementation
**Priority:** High
**Context:** 基於目前的 Rails 8 + Go Agent 架構，增強 Web UI 的節點管理能力，並解決網路隔離環境下的連線問題。

---

## Feature 1: Manual Node CRUD (Web UI)

### 1. 需求描述 (Description)
目前系統僅支援 CSV 匯入或 Agent 主動 Push。使用者需要在 **Nodes Page** 手動新增、修改或刪除單一節點，以便修正錯誤資訊或預先建立節點設定。

### 2. 功能規格 (Specifications)
* **Create**: 在 Nodes 列表頁新增 "Add Node" 按鈕，點擊後彈出 Modal 或 Slide-over 表單。
    * 必要欄位: `Hostname`, `Role` (login/compute), `Arch` (x86_64/arm64).
    * 選填欄位: `IP Address`, `SSH Port` (default: 22), `SSH User`.
* **Update**: 每一列 Node 提供 "Edit" 按鈕，開啟相同表單進行修改。
* **Delete**: 提供 "Delete" 按鈕，需有確認對話框 (Confirmation Dialog)，刪除後透過 Turbo Stream 移除該列。
* **Validation**: Hostname 必須唯一。

### 3. AI Agent Implementation Steps & Prompts

請依序執行以下任務。每個步驟對應一段 AI Prompt：

#### Step 1: Database Schema Update
**Goal**: 更新 `nodes` 資料表，加入 SSH 連線所需的額外欄位。

> **AI Prompt**:
> "Act as a Rails Architect. Create a database migration for the `nodes` table.
> 1. Add columns: `ssh_port` (integer, default 22), `ssh_user` (string, optional).
> 2. Add validation to the `Node` model to ensure `hostname` is unique.
> 3. Update the `Node` model to define enum for `role` (compute, login) if not already defined."

#### Step 2: UI Implementation (Turbo & ViewComponent)
**Goal**: 實作 CRUD 介面，必須使用 Hotwire (Turbo Frames) 避免整頁刷新。

> **AI Prompt**:
> "Act as a Fullstack Rails Developer. Implement CRUD for Nodes:
> 1. Controller: Create/Update `NodesController` with `new`, `create`, `edit`, `update`, `destroy` actions.
> 2. Views: Use **Turbo Frames** for the `new` and `edit` forms so they load inline or in a modal without page refresh.
> 3. Component: Create a reusable `NodeFormComponent` (ViewComponent) that renders the form for both create and update actions.
> 4. UX: Use Tailwind CSS for styling. For the 'Delete' action, use `data-turbo-confirm` for a browser-native confirmation dialog.
> 5. Response: Use **Turbo Streams** to append the new node or replace the updated node row in the list immediately."

---

## Feature 2: SSH via Jump Host (Bastion)

### 1. 需求描述 (Description)
HPC 叢集通常位於防火牆後，Web Server 無法直接 SSH 連線到 Compute Nodes。需支援透過一台 **跳板機 (Jump Host / Bastion Host)** 進行轉發。

### 2. 功能規格 (Specifications)
* **Configuration**: 需新增一個設定介面或環境變數來定義全域的 Jump Host 資訊。
    * `Jump Host Hostname/IP`
    * `Jump Host User`
    * `Jump Host Key Path` (或使用與 Web Server 相同的 SSH Key)
* **Logic**: 當 Rails 觸發 `Agent Collect` 時（原本是直接 SSH），需檢查是否設定了 Jump Host。
    * 若有設定：建立 SSH Tunnel (ProxyJump) -> 連線目標 Node -> 執行 Agent。
    * 若無設定：維持直接連線。

### 3. AI Agent Implementation Steps & Prompts

#### Step 1: Configuration Management
**Goal**: 儲存 Jump Host 設定。MVP 建議使用 Rails Credentials 或 Environment Variables，或者建立一個單例 `SystemSetting` Model。這裡採用 `Rails.application.credentials` 或 ENV 方式最快。

> **AI Prompt**:
> "Act as a Rails Backend Developer.
> 1. Create a logical wrapper class `SshConfig` that retrieves Jump Host settings from Environment Variables (`JUMP_HOST`, `JUMP_USER`, `JUMP_PORT`).
> 2. The class should have a method `use_jump_host?` that returns true if `JUMP_HOST` is present."

#### Step 2: Update SSH Service Logic
**Goal**: 修改負責執行 SSH 的 Service Object (例如 `InventoryCollectionService` 或類似名稱)，加入 `Net::SSH::Gateway` 或 `ProxyCommand` 邏輯。

> **AI Prompt**:
> "Act as a Ruby Expert specializing in Networking.
> 1. Locate the service class responsible for SSHing into nodes (e.g., triggering `agent collect`).
> 2. Refactor the `Net::SSH.start` call to support a Bastion Host.
> 3. Implementation Logic:
>    - If `SshConfig.use_jump_host?` is true:
>      Use `Net::SSH::Gateway` to open a connection to the Jump Host first, then connect to the target node through it.
>      *Example snippet logic*:
>      ```ruby
>      gateway = Net::SSH::Gateway.new(jump_host, jump_user, options)
>      gateway.ssh(target_node_host, target_user) do |ssh|
>        # run command
>      end
>      ```
>    - If false: Use direct `Net::SSH.start`.
> 4. Ensure error handling covers connection timeouts for both the jump host and the target node."

#### Step 3: Test Verification
**Goal**: 確保連線邏輯正確。

> **AI Prompt**:
> "Create an RSpec test for the SSH Service.
> 1. Mock `Net::SSH::Gateway` and `Net::SSH.start`.
> 2. Context 'when jump host is configured': Expect `Net::SSH::Gateway` to be instantiated.
> 3. Context 'when direct connection': Expect standard `Net::SSH.start` to be called directly.
> 4. Verify that the command `agent collect --json` is executed in the final SSH session block."

---

## 總結檢查清單 (Definition of Done)

* [ ] 使用者可以在 UI 點擊 "Add Node" 並成功建立資料。
* [ ] 使用者可以編輯 Node 的 SSH Port 或 User。
* [ ] 設定環境變數後，後端能透過跳板機成功 SSH 到內網節點並取得 JSON 回傳。
* [ ] 原有的 "Collect Now" 功能在新的 SSH 邏輯下依然正常運作。
