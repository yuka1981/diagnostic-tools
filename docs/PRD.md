# **PRD v0.5.2 — HPC System Detection & Benchmark Tool**

Version: 0.5.2  
Status: Draft  
Last Updated: 2025-12-26  
Changes: Added Node Configuration Versioning & History View features.

## **1\. 背景與目標 (Background & Objectives)**

在 HPC Linux 叢集中（x86\_64 \+ aarch64），提供一套工具能達成以下目標：

* **全觀可視化**：以 Web UI 檢視各節點系統資訊（CPU/Memory/Storage/OS+Kernel/Network/IP…）。  
* **節點管理**：以 Web UI 管理節點清單（匯入 CSV）並手動觸發資訊更新。  
* **效能評測**：以 Web UI 檢視 Benchmark Recipes，並透過 CLI/Agent 原生編譯並執行 **HPCG**。  
* **數據追溯**：將評測結果 (Metrics) 與產出檔案 (Artifacts) 上傳至中央系統與共享儲存，確保可追溯性。

## **2\. 使用者與角色 (User Roles)**

* **Requester (一般使用者)**：  
  * **V1**: 可檢視節點狀態、直接建立並執行 Benchmark Run Request (無須審核)。  
  * **V2**: 建立 Request 需經過 Approver 審核流程。  
* **Approver (Ops/Perf Team)** (**V2 新增**)：  
  * 可核准 Request（核准後才能提交 Slurm Job），管理節點清單。  
* **Viewer (唯讀)**：僅能檢視 Dashboard 與報告。

## **3\. 環境與約束 (Environment & Constraints)**

* **HPC Environment**: Linux-based, Heterogeneous Architecture (x86\_64 \+ aarch64).  
* **Network Topology**:  
  * **Web Server**: 位於管理網段 (Management Network) 或外部網路。  
  * **Compute Nodes**: 位於私有網段 (Private Network)，無法由 Web Server 直接連線。  
  * **Admin/Login Node**: 雙網卡 (Dual-homed)，作為 **Bastion Host (跳板機)** 或 **Gateway**，Web Server 需透過此節點管理 Compute Nodes。  
* **Storage**: Shared Storage (NFS/Lustre/GPFS) mounted on all nodes, **writable** by users/agent.  
* **Scheduler**: Slurm (V1 採用 Slurm Job 觸發 srun/sbatch).  
* **Modules**: Lmod / Environment Modules.

### **3.1 技術選型 (Tech Stack Decisions)**

* **Agent**: **Go (Golang) 1.22+**  
  * 使用 **Cobra** 構建 CLI。  
  * 優勢：編譯為 Static Binary，無須在各節點安裝 Runtime，部署極簡。  
* **Web Framework**: **Ruby on Rails 7.1+**  
  * 架構：Server-Side Rendering (Monolith)。  
  * Testing: **RSpec** (Unit, Request, System specs).  
* **Frontend Interaction**: **Hotwire** (Turbo Drive, Turbo Frames, Turbo Streams) \+ Stimulus.js.  
  * 透過 HTML Over The Wire 達成類 SPA 體驗，同時保持開發單純性。  
* **Styling**: **Tailwind CSS**.  
* **Database**: **PostgreSQL 16+**.  
* **Design System**: Apple Human Interface Guidelines (HIG) via Tailwind utility classes.

## **4\. 核心決策 (Core Decisions)**

* **執行模型**: **Hybrid (Push & Pull)**  
  * **Inventory (Pull via Gateway)**: Server 端 Collector 建立 SSH 連線至 **Admin Node**，再由 Admin Node 透過內部網路 (SSH/PDSH/Slurm) 觸發 Compute Node 的 agent collect。  
  * **Inventory (Push)**: Agent 可透過 cron 或啟動腳本執行 agent inventory push 主動回報 (適用於自動註冊/定期更新，需確保 Compute Node 可訪問 Web API)。  
  * **Benchmark (Push)**: Slurm Job 內的 Agent 主動執行並回報 DB，Artifacts 直寫 Shared Storage。  
* **Nodes 來源**: **Web UI 匯入 (CSV)** \+ 靜態清單 \+ Agent 主動註冊。  
* **Benchmark 環境**: **Native Compilation** (on-the-fly compile using modules/toolchain).  
* **Auth**:  
  * **V1 (Standard)**:  
    * **Agent**: Cluster scoped API Token.  
    * **Web UI**: Local Web User Auth (Database-backed sessions).  
  * **V2 (Enterprise)**:  
    * **Web UI**: LDAP/AD Integration.  
* **資料保留**: Node Current State \+ Historical Snapshots (Versioning).  
* **規模**: \< 50 Nodes, 20-200 Runs/day.

## **5\. 功能需求 (Functional Requirements \- V1)**

### **5.1 Inventory Management**

* **Node 匯入 (Web UI)**:  
  * 支援上傳 CSV 檔案。  
  * CSV 格式：hostname, ip (選填), role (compute/login), arch (選填)。  
  * 後端解析並更新 nodes 資料表。  
*   **主動收集 (Agent Push)**:
    *   Command: `hpc-agent inventory push`。
    *   行為：Agent 收集本機資訊 -> POST 到 API Server -> 更新 DB。
*   **被動觸發 (Server Pull via Admin Node)**:
    *   Action: Web UI 點擊 "Collect Now" (單一節點或批次)。
    *   Backend Flow:
        1.  Rails (Sidekiq) 建立 SSH 連線至 **Admin Node**。
        2.  在 Admin Node 上執行遠端指令 (e.g., `ssh <compute_node> hpc-agent collect --json` 或 `pdsh`)。
        3.  取得 JSON 輸出並解析更新 DB。  
* **配置版本控制 (Configuration Versioning)**:  
  * 系統需保留節點的歷史狀態 (History)。  
  * 每次收集 (Push/Pull) 若偵測到硬體或系統資訊變更（如 Kernel 更新、記憶體增減），應建立新的 node\_state 版本記錄，而非僅覆蓋舊資料。  
* **資料欄位**:  
  * Host (Hostname, Arch, OS, Kernel)  
  * CPU (Model, Cores, Threads, Flags)  
  * Memory (Total, Free)  
  * Storage (Disk usage, Mountpoints)  
  * Network (Interfaces, IP, MAC)

### **5.2 Benchmarks Repository**

* UI 顯示 Released Recipes：  
  * **HPCG (High Performance Conjugate Gradients)**  
* 資訊包含：Version, Profiles (Module stack, Flags, Parameters), Supported Arch.

### **5.3 Benchmark Runs (Slurm-first)**

* 流程：使用者提交 Slurm Script \-\> Job 啟動 Agent \-\> Agent 執行評測。  
* Agent 職責 (Go Binary)：  
  1. **Environment Setup**: Load Modules, Check Fingerprint.  
  2. **Build**: Compile xhpcg (Native).  
  3. **Config**: 自動生成 hpcg.dat。  
  4. **Run**: 執行 srun ./xhpcg。  
  5. **Parse**: 解析 Log 取得 GFLOPS, Time, Residual, Pass/Fail。  
  6. **Upload**: 更新 DB 狀態 (API)，上傳 Artifact Index。

### **5.4 Artifacts Management**

* **儲存位置**：預設位於專案資料夾下的 /artifacts/\<cluster\_id\>/\<run\_id\>/，可透過 config.yaml 設定覆寫路徑（通常指向 Shared Storage）。  
* **寫入機制**：原子性寫入 (Atomic Write)。先寫入 \<run\_id\>.tmp/，完成後 Rename 為 \<run\_id\>/。  
* **必要檔案**：MANIFEST.json, run-meta.json, Logs, Raw Results.

### **5.5 Web UI Features (Rails \+ Hotwire)**

整合 dashboard.md 設計規範，採用單體式架構 (Monolith) 實作。

#### **5.5.1 全域導航與佈局 (Global Layout)**

* **Sidebar Navigation**:  
  * **位置**: 固定左側 (Fixed Left, 240px\~280px)。  
  * **風格**: Glassmorphism (半透明磨砂玻璃效果, Backdrop Filter)。  
  * **選單項目**:  
    * Dashboard (Home icon)  
    * Nodes (Server icon)  
    * Runs (Play icon)  
    * Settings (Gear icon)  
  * **功能**: 包含 Dark/Light Mode 手動切換按鈕。

#### **5.5.2 總覽儀表板 (Overview Dashboard)**

* **關鍵指標 (Hero Metrics Cards)**:  
  1. **Node Availability**: 線上節點數/總數 (Green/Red 指示燈)。  
  2. **Benchmark Health**: 過去 24 小時成功率 (Success Rate)。  
  3. **Queue Status**: Running / Pending 作業數量。  
  4. **Storage Usage**: 使用量/總量 (TB)，搭配進度條視覺化。  
* **節點熱圖 (Visual Node Grid)**:  
  * **呈現**: 方形網格 (Square Grid)，顯示 Node ID。  
  * **狀態顏色**: Green (Idle/OK), Blue (Running), Red (Down/Error), Gray (Unknown)。  
  * **互動 (Interaction)**: 點擊節點可切換「過濾模式 (Filter Mode)」，下方列表僅顯示該節點的 Runs。  
* **近期活動 (Recent Runs List)**:  
  * **風格**: Rich Row (Apple HIG 風格)。  
  * **內容**: 狀態圖示 (Spinner/Check/X)、Benchmark 名稱、GFLOPS (Bold)、執行時間。  
  * **互動**: 點擊列 (Row) 開啟右側滑出詳細面板。

#### **5.5.3 詳細檢測面板 (Run Detail Inspector)**

* **元件**: **Slide-over Panel** (右側滑出, 覆蓋式或推擠式)。  
* **內容結構**:  
  * **Header**: Run ID, Status, Timestamp.  
  * **Tabs**:  
    1. **Summary**: 輸入參數 (nx, ny, nz 等)、結果指標 (GFLOPS, Time)。  
    2. **Logs**: 完整執行日誌 (Monospace font, scrollable)。  
    3. **Artifacts**: 產出檔案下載連結 (e.g., HPCG.txt, HPCG.dat)。

#### **5.5.4 Nodes & Runs Pages**

* **Nodes Page (List)**:  
  * 列表與卡片切換檢視。  
  * **Import CSV Dialog**: 使用 Turbo Frame 實作 Modal。  
  * **Trigger Collect**: 批次操作按鈕。  
* **Node Detail View (新增)**:  
  * **功能**: 檢視單一節點的詳細硬體資訊。  
  * **Version History (版本歷史)**:  
    * 提供下拉選單或時間軸 (Timeline)，列出該節點所有歷史快照 (captured\_at)。  
    * 切換版本時，下方資訊面板應透過 Turbo Frame 即時更新為該時間點的硬體狀態（例如檢視上個月 Kernel 升級前的配置）。  
    * 標示「Current」版本。  
* **Runs Page**:  
  * 完整列表，支援進階過濾 (Time, Node, Status)。

### **5.6 Agent V1 Scope (Go)**

V1 Agent 功能定義：

1. **Collect**:  
   * `hpc-agent collect`: 輸出系統資訊 (CPU/Mem/Disk/Net) JSON 到 stdout。
   * `hpc-agent inventory push`: 收集資訊並主動 POST 至 API。
2. **HPCG Run (Single-node)**: 完整 Build/Run/Parse 流程。
* **Non-Goals**: Build Cache, Multi-node orchestration (Rank0 leader), HPL support.  
* **Deploy**: 單一靜態編譯執行檔 (Single Static Binary)。

## **6\. 資料模型 (Data Schema \- V1)**

* nodes: id, hostname, ip, role, arch, source (csv/manual/agent\_push).  
* node\_states: **(Versioned Data)**  
  * id: PK  
  * node\_id: FK  
  * cpu\_json, mem\_json, disk\_json, net\_json: 系統資訊快照。  
  * captured\_at: 此版本建立時間 (Timestamp)。  
  * 說明：One Node has\_many NodeStates。最新的一筆即為 Current State。  
* benchmark\_recipes: id, name (hpcg), version, default\_profile\_json.  
* benchmark\_runs: id, node\_id, recipe\_id, start\_time, end\_time, status, metrics\_json (gflops).  
* artifact\_indices: run\_id, path, file\_type, size.

## **7\. 非功能需求 (Non-Functional Requirements)**

* **Performance**: Agent collect \< 1s.  
* **Reliability**: API Idempotency.  
* **Security**: HTTPS only, Token-based Agent Auth.  
* **UX**: 符合 Apple HIG，支援 Dark/Light Mode 自動切換 (Tailwind dark: variant)，並於 Navigation Bar 提供手動切換按鈕。  
* **Color System**: 使用 Tailwind 語意化命名 (bg-app, bg-surface, status-success 等) 以支援主題切換。

## **8\. 系統架構圖 (System Architecture)**

```
flowchart LR  
  %% \=========================  
  %% HPC System Detection & Benchmark Tool \- System Architecture (v0.5.2)  
  %% \=========================

  subgraph USERS\["Users"\]  
    U1\["Requester / Viewer"\]  
    U2\["Approver (ops/perf)"\]  
  end

  subgraph WEB\["Web Application"\]  
    RAILS\["Ruby on Rails\<br/\>(Hotwire \+ Tailwind)"\]  
    JOBS\["Solid Queue / Sidekiq\<br/\>(Async Jobs)"\]  
  end

  subgraph DB\["Database"\]  
    PG\[("PostgreSQL 16+")\]  
  end

  subgraph STORAGE\["Shared Storage"\]  
    ART\[/"\\/artifacts\\/\<run\_id\>"/\]  
  end

  subgraph HPC\["HPC Cluster"\]  
    subgraph NODES\["Compute Nodes (Private Network)"\]  
      AG\["HPC Agent CLI (Go)\<br/\>collect / push / hpcg"\]  
    end  
    subgraph LOGIN\["Admin / Login Node (Gateway)"\]  
      COL\["Proxy Command / SSH Jump\<br/\>(SSH Trigger Endpoint)"\]  
      SLURM\["Slurm Scheduler"\]  
    end  
  end

  %% Interactions  
  U1 \--\> RAILS  
  U2 \--\> RAILS  
    
  RAILS \-- "Read/Write" \--\> PG  
  RAILS \-- "Enqueue" \--\> JOBS  
    
  JOBS \-- "SSH to Admin Node" \--\> COL  
  COL \-- "Internal SSH / srun" \--\> AG  
  AG \-- "Return JSON" \--\> COL  
  COL \-- "Update" \--\> RAILS

  %% Active Push Inventory  
  AG \-- "Push Inventory (API)" \--\> RAILS

  SLURM \-- "Start Job" \--\> AG  
  AG \-- "Write" \--\> ART  
  AG \-- "Upload Meta (API)" \--\> RAILS  
```
