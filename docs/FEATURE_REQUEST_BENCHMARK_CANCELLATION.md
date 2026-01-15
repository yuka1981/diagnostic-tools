# **FEATURE REQUEST: Benchmark Cancellation Mechanism**

**Status**: Draft
**Priority**: High
**Target Version**: v0.8.x
**Dependencies**: `FEATURE_REQUEST_BENCHMARK_CRUD.md`

## **1. Context & Goal**

目前的 Benchmark 執行是「射後不理」或同步等待。若測試卡住或誤觸發長時測試，使用者無法從 Web UI 中斷。
**目標**：提供 Web UI 按鈕，允許使用者中斷 **Running (執行中)** 或 **Pending (排隊中)** 的測試。

## **2. Architecture Design**

### **2.1 Strategy by Status**
* **Pending (Queued)**: 任務尚未發送至 Agent。Rails 端直接將資料庫狀態標記為 `cancelled` 並從 Job Queue (Redis/Sidekiq) 中移除（若可行），無需建立 SSH 連線。
* **Running (Active)**: 任務正在 Agent 上執行。Rails 需透過 SSH 發送 `cancel` 指令，由 Agent 負責清理子進程 (PID)。

### **2.2 Workflow (Running State)**
1.  **Start**: Agent 啟動測試子進程，將 PID 寫入 `/var/run/diagnostic-agent/<UUID>.pid`。
2.  **Cancel**: 使用者點擊 "Cancel"。
3.  **Rails**: 呼叫 Agent `cancel --uuid <RUN_UUID>`。
4.  **Agent**: 讀取 PID 檔，發送 `SIGTERM` (5秒後 `SIGKILL`)，並清理 PID 檔。
5.  **Result**: Rails 更新 DB 狀態為 `cancelled`。

## **3. Database Changes**

* **`BenchmarkRun`**:
    * Update `status` enum: Add `cancelled` (value: 4).

## **4. Technical Implementation**

### **4.1 Agent (Go)**
* **PID Management**: 實作 `pid_manager.go` 負責 `/tmp/diagnostic-agent/` 下的 PID 檔讀寫。
* **CLI Command**: `cancel --uuid <UUID>`
    * 邏輯：檢查 PID 檔存在 -> 讀取 PID -> Kill Process -> 刪除 PID 檔。
    * 回傳：JSON `{ "status": "ok", "message": "Process 1234 killed" }` 或 `{ "status": "not_found" }`。

### **4.2 Rails (Backend)**
* **Service**: `Benchmark::CancelRunService`
    * **Logic**:
        ```ruby
        if run.pending?
          run.update!(status: :cancelled, result: { error: "Cancelled while pending" })
          # Optional: Try to delete job from Sidekiq/SolidQueue if possible
        elsif run.running?
          # Execute SSH cancellation
          SshExecutionService.new(run.node).execute("#{agent_path} cancel --uuid #{run.uuid}")
          run.update!(status: :cancelled, result: { error: "Cancelled by user" })
        end
        ```
* **Controller**: `BenchmarkRunsController#cancel`.

### **4.3 UI Requirements (NetBox Style)**
* **Run Details Modal**:
    * 在 "Pending" 或 "Running" 的 Badge 旁顯示紅色 "Cancel" 按鈕。
    * 使用 `data-turbo-confirm` 防止誤觸。