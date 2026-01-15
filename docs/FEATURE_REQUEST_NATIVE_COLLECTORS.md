# **FEATURE REQUEST: Benchmark Management System (CRUD & Execution)**

**Status**: Draft
**Priority**: High
**Target Version**: v0.8.x
**Style Guide**: NetBox-inspired (Data-centric, Clean Tables, Filters)

## **1. Context & Goal**

目前的 Benchmark 執行邏輯較為分散且參數難以動態調整。為了讓 `diagnostic-tools` 成為通用的 HPC 測試平台，我們需要建立一套完整的 **Benchmark Management System**。

**核心目標**：

1. **Recipe Management**: 讓管理者定義測試範本 (e.g., "HPCG - Quick", "HPCG - Full Stress", "Stream").
2. **Execution Flexibility**: 在觸發測試時，允許覆寫參數 (Arguments Override)。
3. **Result Correlation**: 確保每次執行的參數、Log 與結果都有完整的 CRUD 紀錄。

## **2. Database Models & Schema**

### **2.1 Model: `BenchmarkRecipe` (New)**

定義「如何執行」一個測試。

* **Columns**:
  * `name`: string (e.g., "HPCG Standard")
  * `slug`: string (unique)
  * `description`: text
  * `command`: string (The actual binary/script to run, e.g., `hpcg`)
  * `default_arguments`: jsonb (Key-value pairs of default flags, e.g., `{"--nx": 104}`)
  * `timeout_seconds`: integer (Default: 3600)
  * `status`: enum (active, deprecated)

### **2.2 Model: `BenchmarkRun` (Update)**

記錄一次實際的執行。

* **New Columns**:
  * `benchmark_recipe_id`: reference (Optional, nullable for legacy runs)
  * `arguments`: jsonb (Actual arguments used for this run, snapshot of recipe + overrides)
  * `initiator_id`: reference to User (Who started it?)

## **3. Functional Requirements**

### **3.1 Recipe Management (The "Definition" Layer)**

* **List View**: 顯示所有可用的測試配方。
* **Create/Edit**: 管理者可新增測試類型，支援 JSON 格式的預設參數。
* **Delete**: 軟刪除或檢查關聯性。

### **3.2 Triggering Benchmarks (The "Create" Action)**

* **Entry Point**: `Node` 詳細頁面 或 `BenchmarkRecipe` 頁面。
* **Configuration Modal**:
  * 選擇目標 Node(s).
  * 選擇 Recipe (若從 Node 頁面進入).
  * **Parameter Override**: 顯示 Recipe 的預設參數，並允許使用者針對此次執行進行修改。

### **3.3 Results Management**

* **List View**: 統一的執行歷史紀錄。
* **Detail View**: 顯示參數快照 (`arguments`) 與執行結果。

## **4. UI Requirements (NetBox Theme)**

### **4.1 Benchmark Recipes List**

* **Table Columns**: Name, Command, Default Args (Truncated), Timeout, Status, Actions.
* **Actions**: "Add Recipe", "Import" (YAML/JSON).

### **4.2 Run Detail View**

* **Overview Card**: Start Time, End Time, Duration, Initiator.
* **Configuration Card**: 顯示實際執行的指令與參數 (`arguments` json).

## **5. Technical Implementation Strategy**

### **5.1 Rails Controllers**

* `BenchmarkRecipesController`: Standard CRUD.
* `BenchmarkRunsController`:
  * `create`: 需處理參數合併邏輯 (`Recipe Defaults` merged with `User Overrides`).

### **5.2 Services**

* `Benchmark::ArgumentBuilderService`: 負責將 JSON 參數轉換為 CLI 字串。
* `Benchmark::TriggerRunService`: 需更新以支援 Recipe 與動態參數。

## **6. Implementation Roadmap (Phased)**

為了確保開發品質與可測試性，實作將分為三個階段。

### **Phase 1: Foundation (CRUD)**

* **Goal**: 建立資料結構與管理介面，暫不涉及實際執行。
* **Tasks**:
    1. 建立 `BenchmarkRecipe` model 與 migration。
    2. 更新 `BenchmarkRun` model (add `arguments`, `recipe_id`)。
    3. 實作 `BenchmarkRecipesController` (CRUD)。
    4. 實作 Recipes 的 Index/Show/Edit 視圖 (NetBox style)。

### **Phase 2: Execution Logic**

* **Goal**: 連接實際的 Agent 執行邏輯。
* **Tasks**:
    1. 實作 `ArgumentBuilderService`。
    2. 更新 `TriggerRunService` 以接收 Recipe 參數。
    3. 在 UI 中製作 "Run Benchmark" Modal (含參數覆寫表單)。

### **Phase 3: Visualization & Polish**

* **Goal**: 優化結果呈現。
* **Tasks**:
    1. 在 Run Details 頁面顯示 "Configuration Card"。
    2. 優化 JSON 參數的輸入介面 (Code Editor)。
