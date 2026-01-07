# **WEB.md — HPC Web Application Development Specification (TDD)**

Version: 0.1.0  
Based on: PRD v0.5.2  
Stack: Ruby on Rails 7.2.3, PostgreSQL 16+, Hotwire, Tailwind CSS  
Testing: RSpec, Capybara, FactoryBot

## **1. 核心開發原則 (Core Principles)**

1. **Strict TDD**: 使用 RSpec 進行開發。先寫 Spec (Red) -> 實作 (Green) -> 重構 (Refactor)。  
2. **Service Objects**: 所有複雜業務邏輯（特別是涉及 I/O、SSH、複雜資料庫操作）必須封裝在 app/services 中，保持 Controller 輕量化 (Skinny Controller)。  
3. **Hotwire First**: 優先使用 Turbo Drive 與 Turbo Frames 處理頁面互動，非必要不撰寫自定義 JavaScript (Stimulus)。  
4. **Component Driven**: 重複的 UI 元素（如 Hero Cards, Status Badges）應使用 ViewComponent 或 Partial 封裝。

## **2. 系統架構設計 (Architecture)**

### **2.1 資料庫設計 (Schema Key Points)**

* **Nodes**: 實體機器清單。  
  * role: enum (compute, login, admin).  
* **NodeStates**: **核心版本控制表**。  
  * node_id: FK.  
  * cpu_info, mem_info, disk_info, net_info: jsonb 欄位。  
  * captured_at: datetime.  
  * *Logic*: 每次回報時，比對 Hash，若變更則 Insert，否則僅更新 Node\#last_seen_at。  
* **BenchmarkRuns**: 執行記錄。  
  * metrics: jsonb (儲存 GFLOPS 等動態結構)。

### **2.2 關鍵服務 (Service Objects)**

```ruby
# app/services/inventory/trigger_collect_service.rb  
module Inventory  
  class TriggerCollectService  
    def initialize(node_ids:, gateway_host: "admin-node")  
      @node_ids = node_ids  
      @gateway = gateway_host  
    end

    def call  
      # 1. SSH to Admin Node (Gateway)  
      # 2. Execute command (pdsh or ssh loop)  
      # 3. Handle output or errors  
    end  
  end  
end
```

## **3. 功能模組規格 (Modules Specs)**

### **3.1 身份驗證 (Authentication) - V1**

* **Gem**: devise  
* **Scope**: Database Authenticatable (Local User).  
* **TDD**: Request Spec 測試登入/登出流程，Model Spec 測試 User 驗證。

### **3.2 節點管理 (Inventory Management)**

#### **A. CSV 匯入 (Import)**

* **UI**: Turbo Frame Modal (\import\modal.html.erb).  
* **Service**: Inventory::ImportCsvService  
* **Test**: 準備 Mock CSV 檔案，驗證 Service 能正確 Upsert (Update or Insert) Node 資料表。

#### **B. SSH 觸發收集 (Trigger Collect)**

* **Service**: Inventory::TriggerCollectService  
* **Logic**: 使用 net-ssh 連線至 Gateway (Admin Node)。  
* **Test**: 使用 double Mock Net::SSH.start，驗證是否送出正確的指令 (e.g., ssh compute-01 hpc-agent collect --json)。  
* **Job**: InventoryCollectJob (Sidekiq/SolidQueue)，負責非同步執行 Service。

#### **C. 版本化資料處理 (Processing & Versioning)**

* **Service**: Inventory::ProcessStateService  
* **Logic**:  
  * Input: node_id, raw_json  
  * Step 1: 找出該 Node 最新的 NodeState。  
  * Step 2: 比較 raw_json 與最新 State 的內容 (Deep Compare or Hash)。  
  * Step 3: 若不同 -> Create NodeState. 若相同 -> Touch Node.  
* **Test**: 建立兩個不同的 JSON payload，驗證 DB 內的 NodeState 數量增加。

### **3.3 儀表板與視覺化 (Dashboard)**

#### **A. 關鍵指標 (Hero Metrics)**

* **Service**: Dashboard::MetricsService  
* **Logic**: 計算 Availability (Online/Total), Success Rate (Last 24h).  
* **Test**: 建立多個 Node 與 BenchmarkRun 假資料，驗證計算結果準確性。

#### **B. 節點熱圖 (Node Heatmap)**

* **UI**: Grid Layout, Tailwind CSS.  
* **Interaction**: Stimulus Controller heatmap_controller.js.  
  * Action: click->heatmap#filter  
  * Logic: 點擊節點 ID，觸發 Turbo Frame 更新下方的 Runs List。  
* **Test**: System Spec (Capybara)，模擬點擊熱圖元素，檢查頁面內容是否過濾。

#### **C. 深色模式 (Dark Mode)**

* **Impl**: Tailwind dark: prefix.  
* **Controller**: Stimulus theme_controller.js 切換 `<html>` class 並寫入 localStorage.

### **3.4 效能評測 (Benchmark Runs)**

#### **A. 列表與過濾 (List & Filter)**

* **UI**: Turbo Frames 用於分頁與過濾器 (Search form).  
* **Backend**: RunsQuery Object (Form Object pattern) 處理 SQL 組合。

#### **B. 詳細面板 (Slide-over Inspector)**

* **UI**: \run\detail.html.erb (Turbo Frame).  
* **CSS**: 使用 CSS Transition 實作滑入效果 (translate-x-0 vs translate-x-full).  
* **Tabs**: 使用 Turbo Frames 切換 Summary/Logs/Artifacts 內容，避免一次載入過大 Log。

### **3.5 Agent API**

* **Controller**: Api::V1::InventoryController  
* **Auth**: Token Authentication (Header Authorization: Bearer `<token>`).  
* **Action**: POST /push  
* **Logic**: 呼叫 Inventory::ProcessStateService。  
* **Test**: Request Spec，驗證 401 (Unauthorized), 400 (Bad Request), 200 (OK)。

## **4. 測試資料 (Factories)**

使用 factory_bot 定義：

* :node (with traits :compute, :login).  
* :node_state (with dynamic json content).  
* :benchmark_run (with traits :success, :failed).
