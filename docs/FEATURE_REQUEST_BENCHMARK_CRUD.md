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

### **2.1 Model: `BenchmarkRecipe` (New/Enhanced)**

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
* `benchmark_recipe_id`: reference
* `arguments`: jsonb (Actual arguments used for this run, snapshot of recipe + overrides)
* `initiator_id`: reference to User (Who started it?)

## **3. Functional Requirements**

### **3.1 Recipe Management (The "Definition" Layer)**

* **List View**: 顯示所有可用的測試配方。
* **Create/Edit**:
* 管理者可新增測試類型。
* 支援定義 `default_arguments` (建議使用 JSON Editor 或 Key-Value UI)。

* **Delete**: 軟刪除 (Soft Delete) 或檢查是否有關聯的 Runs。

### **3.2 Triggering Benchmarks (The "Create" Action)**

* **Entry Point**: `Node` 詳細頁面 或 `BenchmarkRecipe` 頁面。
* **Configuration Modal**:
* 選擇目標 Node(s).
* 選擇 Recipe (若從 Node 頁面進入).
* **Parameter Override**: 顯示 Recipe 的預設參數，並允許使用者針對此次執行進行修改 (Form Object Pattern)。

### **3.3 Results Management (The "Read/Update" Layer)**

* **List View**: 統一的執行歷史紀錄 (NetBox Filter styles: Filter by Node, Status, Recipe, Date).
* **Detail View**:
* **Parameters Card**: 顯示該次執行當下的參數設定。
* **Logs Tab**: 顯示 Stdout/Stderr (透過 `TurboFrame` 非同步加載)。
* **Metrics Tab**: 若有解析出的數值 (Score, GFLOPs)，以圖表或 Key-Value 呈現。

* **Delete**: 允許刪除誤觸發或無效的測試紀錄 (連同 Logs 檔案與 Artifacts)。

## **4. UI Requirements (NetBox Theme)**

### **4.1 Benchmark Recipes List**

* **Table Columns**: Name, Command, Default Args (Truncated), Timeout, Last Run, Status.
* **Actions**: "Add Recipe", "Import" (YAML/JSON).

### **4.2 Run Configuration Form**

* 使用 **Card-based Layout**。
* **Arguments Section**:
* 列出 JSON keys 作為 Label。
* Input 欄位預填 Default Value。
* 提供 "Reset to Default" 按鈕。

### **4.3 Run Detail View**

* **Header**:
* Title: `[Node Name] - [Recipe Name]`
* Subtitle: Run ID (UUID)
* Badge: Status (Pending, Running, Completed, Failed).

* **Layout**:
* **Left Column**:
* **Overview Card**: Start Time, End Time, Duration, Initiator.
* **Configuration Card**: 顯示實際執行的指令與參數 (`arguments` json).

* **Right Column (Tabs)**:
* **Results**: Parsed Metrics (Green checkmarks, Red crosses).
* **Console Output**: 黑色背景 Terminal 風格顯示 Raw Logs.

## **5. Technical Implementation Strategy**

### **5.1 Rails Controllers**

* `BenchmarkRecipesController`: Standard CRUD.
* `BenchmarkRunsController`:
* `create`: 需處理參數合併邏輯 (`Recipe Defaults` merged with `User Overrides`).
* `destroy`: 需觸發 Service 清理關聯檔案 (Artifacts).

### **5.2 Services (`app/services/benchmark/`)**

1. **`ArgumentBuilderService`**:

* Input: Recipe, User Params.
* Output: Final JSON string for Agent (or CLI flags string).

1. **`TriggerRunService`** (Update):

* 需接收 `recipe_id` 與 `custom_arguments`.
* 將組合後的參數傳遞給 SSH Service。

### **5.3 Agent Interaction**

* Agent 需支援接收 JSON 格式的參數 payload，或透過 Flag 傳遞。
* *目前架構維持*：Rails 組裝好完整的 CLI Command string (包含 flags)，Agent 照單全收執行即可。
