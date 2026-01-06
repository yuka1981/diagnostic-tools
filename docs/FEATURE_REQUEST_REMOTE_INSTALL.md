# FEATURE_REQUEST: Remote Agent Installation & Cross-Compilation Deployment

**Status:** Pending Implementation
**Priority:** High
**Context:** 實作從 Web UI 觸發遠端節點的 Agent 安裝流程。考量到 HPC 環境的多架構特性 (x86/ARM) 與跳板機網路拓撲，此功能需包含「伺服器端交叉編譯」與「多層級 SSH 部署」邏輯。

---

## 1. 架構決策紀錄 (Architectural Decisions Q&A)

為了讓開發 Agent 理解實作脈絡，以下是關鍵技術決策的問答紀錄：

**Q1: 如何解決 x86 與 aarch64 (ARM) 的多平台支援問題？需要在遠端編譯嗎？**

* **A:** **不需要在遠端編譯**。採用 **Server-side Cross-Compilation (伺服器端交叉編譯)** 策略。
* **邏輯:** Web Server (Running on x86) 負責執行 Go Compiler，根據目標節點架構產出對應的 Binary (`GOOS=linux GOARCH=amd64` 或 `arm64`)，再將編譯好的檔案上傳至目標機器。這免除了在運算節點安裝 Go 環境的需求。

**Q2: 預設的安裝路徑與執行權限為何？**

* **A:** **System-level Installation**。
* **路徑:** `/usr/local/bin/agent`。
* **機制:** 註冊 systemd service 實現開機自啟 (Auto-start)。
* **權限:** 需要 Root 權限寫入檔案與設定服務。

**Q3: 網路拓撲複雜，如何連線至目標節點？**

* **A:** 透過 **Admin Node (Bastion)** 進行跳板連線，且包含權限提昇 (Privilege Escalation)。
* **流程:** `Rails (User)` -> SSH -> `Admin Node (Normal User)` -> `sudo` (Switch to Root) -> SSH -> `Target Node (Root)`.

**Q4: Admin Node 的 sudo 權限是否需要密碼？**

* **A:** **需要密碼**。
* **實作:** Rails 後端需在執行 sudo 指令時，透過 STDIN 或 PTY 傳遞 sudo 密碼 (此密碼需由 Web UI 輸入或儲存)。

**Q5: Admin Node (Root) 到 Target Node 的連線如何認證？**

* **A:** **SSH Key (Pre-configured)**。
* **設定:** 假設環境中 Admin Node 的 Root 使用者已設定好通往所有 Target Nodes 的 SSH Key 信任。Web UI **不需要** 額外設定這段的 Key。

---

## 2. 功能規格 (Functional Specifications)

### 2.1 Web UI (Installation Wizard)

* **Entry Point**: 在 Nodes 列表頁或 "Add Node" 流程中提供 "Install Agent" 選項。
* **Form Inputs**:
  * **Target Hostname/IP**: 目標節點位址。
  * **Target Architecture**: 下拉選單 `x86_64` | `arm64` (預設 x86_64)。
  * **Bastion User**: 登入 Admin Node 的使用者帳號。
  * **Bastion Password**: 登入 Admin Node 的密碼 (若使用 Password Auth)。
  * **Bastion Sudo Password**: 在 Admin Node 執行 sudo 所需的密碼。
  * *(隱藏設定)*: Bastion Host IP 應讀取自全域設定 (ENV)。

### 2.2 Backend Logic (Rails Service)

* **Compilation**: 呼叫 Go Toolchain 編譯出暫存 Binary。
* **File Transfer Chain**:
    1. **Step 1**: `scp` Local Binary -> Admin Node (`/tmp/agent_pkg`).
    2. **Step 2**: `ssh` to Admin Node, execute `sudo scp` -> Target Node (`/usr/local/bin/agent`).
* **Installation Command**:
    1. `ssh` to Admin Node, execute `sudo ssh root@target` to run setup script.
    2. Setup script actions: `chmod +x`, generate `systemd` unit file, `systemctl enable --now agent`.

---

## 3. AI Agent Implementation Steps & Prompts

請依序執行以下實作步驟：

### Step 1: Cross-Compilation Service

**Goal**: 在 Rails 端實作編譯邏輯。

> **AI Prompt**:
> "Act as a Rails Backend Developer. Create a Service class `AgentCompilerService`.
>
> 1. It accepts `arch` (amd64/arm64) as an argument.
> 2. It executes a shell command to cross-compile the Go agent code located in `../agent`.
>    * Command: `GOOS=linux GOARCH=<arch> go build -o <temp_path> ../agent/cmd/agent`
> 3. Return the path to the compiled binary.
> 4. Ensure error handling if `go build` fails."

### Step 2: Complex SSH Deployment Service

**Goal**: 實作 `Rails -> Admin -> Sudo -> Target` 的檔案傳輸與指令執行。這是最困難的部分，需處理密碼輸入。

> **AI Prompt**:
> "Act as a Ruby/DevOps Expert. Create a Service class `RemoteInstallService`.
>
> 1. Inputs: `target_host`, `arch`, `bastion_user`, `bastion_password`, `sudo_password`.
> 2. **Phase 1 (Upload to Bastion)**: Use `Net::SCP` to upload the compiled binary to `/tmp/agent_bin` on the Bastion Host.
> 3. **Phase 2 (Bastion to Target)**: Use `Net::SSH` to connect to Bastion.
>    * Execute a command that uses `sudo` to SCP the file from Bastion to Target.
>    * Pattern: `echo '<sudo_password>' | sudo -S scp -i /root/.ssh/id_rsa /tmp/agent_bin root@<target_host>:/usr/local/bin/agent`
>    * *Note*: Handle the `-S` flag for sudo to read password from stdin.
> 4. **Phase 3 (Remote Config)**: Similarly, use `sudo ssh` to execute installation commands on Target:
>    * `chmod +x /usr/local/bin/agent`
>    * Create `/etc/systemd/system/hpc-agent.service` content.
>    * `systemctl daemon-reload && systemctl enable --now hpc-agent`"

### Step 3: Web UI Integration

**Goal**: 建立前端表單並串接後端 Job。

> **AI Prompt**:
> "Act as a Fullstack Rails Developer.
>
> 1. Create a Controller Action `POST /nodes/install`.
> 2. Create a View (Modal) with fields: `Hostname`, `Arch`, `Sudo Password` (for Bastion).
> 3. Controller should enqueue a Background Job `AgentInstallJob` to prevent blocking the web request.
> 4. Use Turbo Stream to update the UI with 'Installing...' status and finally 'Installed' or 'Error'."

---

## 4. Definition of Done (驗收標準)

* [ ] 可以在 Rails Server 上成功編譯出 ARM64 的 Binary。
* [ ] 透過 Web UI 輸入 Admin Node 的 Sudo 密碼後，能成功將檔案部署到 Target Node。
* [ ] Target Node 的 Systemd Service 成功啟動，且 Agent 開始回報資訊 (Heartbeat)。
