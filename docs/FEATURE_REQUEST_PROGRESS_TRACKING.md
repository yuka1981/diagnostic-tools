# FEATURE_REQUEST: Benchmark Progress Tracking & Heartbeat

**Status:** Pending Implementation
**Priority:** Critical
**Context:** 目前 Benchmark 執行時，Web UI 無法得知 Agent 的即時進度。若 Agent 執行失敗或卡住，UI 會永久停留在 `Pending` 狀態。需實作進度回報與心跳機制。

---

## 1. Backend (Ruby on Rails)

### 1.1 Database Schema Update

**Goal**: 擴充 `benchmark_runs` 以支援更細緻的狀態追蹤與心跳檢查。

> **AI Prompt**:
> "Act as a Rails Architect.
>
> 1. Update `BenchmarkRun` model enum for `status`.
>    - Current: `pending`, `success`, `failed`.
>    - New: `pending`, `preparing`, `building`, `running`, `uploading`, `success`, `failed`, `lost`.
> 2. Add a new column `last_heartbeat_at` (datetime) to `benchmark_runs`.
> 3. Add a new column `current_phase` (string) to describe current operation (e.g., 'Compiling xhpl')."

### 1.2 API Endpoint for Progress

**Goal**: 提供 API 讓 Agent 回報當前狀態。

> **AI Prompt**:
> "Act as a Rails Developer.
>
> 1. Create a new API endpoint: `PATCH /api/v1/runs/:id/progress`.
> 2. Payload params: `{ status: string, phase: string }`.
> 3. Logic: Update the `BenchmarkRun`'s status, phase, and touch `last_heartbeat_at`.
> 4. Use **Turbo Stream** to broadcast the change to the Web UI immediately (replace the row or update the status badge)."

### 1.3 Watchdog Job (Dead Job Detection)

**Goal**: 偵測並清理失去聯繫的任務。

> **AI Prompt**:
> "Create a Rails Background Job `BenchmarkWatchdogJob`.
>
> 1. Schedule it to run every 5 minutes.
> 2. Query `BenchmarkRun` records that are in 'active' states (`preparing`, `building`, `running`) BUT `last_heartbeat_at` is older than 5 minutes.
> 3. Mark these runs as `lost` and append a log note 'Agent heartbeat lost'."

---

## 2. Agent (Go)

### 2.1 Reporter Module

**Goal**: 封裝與後端 API 溝通的邏輯。

> **AI Prompt**:
> "Act as a Go Developer.
>
> 1. Create a `Reporter` struct in `internal/reporter`.
> 2. It should hold `RunID`, `APIUrl`, `APIToken`.
> 3. Implement method `ReportState(status string, phase string)` that sends a PATCH request to the Rails API.
> 4. Implement method `StartHeartbeat(ctx context.Context)`:
>    - Start a ticker (e.g., every 30 seconds).
>    - Send a PATCH request with the *current* status just to update the server's `last_heartbeat_at`.
>    - Stop when context is cancelled."

### 2.2 Integration in Benchmark Logic

**Goal**: 在 HPL/HPCG 執行流程中插入回報點。

> **AI Prompt**:
> "Refactor the `internal/benchmark` execution flow:
>
> 1. Initialize `Reporter` at the start of the command.
> 2. **Before Build**: Call `reporter.ReportState("building", "Compiling Source")`.
> 3. **Before Run**: Call `reporter.ReportState("running", "Executing Benchmark")`.
>    - *Crucial*: Start the `reporter.StartHeartbeat` goroutine here, as this step takes long.
> 4. **Before Upload**: Call `reporter.ReportState("uploading", "Syncing Artifacts")`.
> 5. **On Error**: Ensure `reporter.ReportState("failed", errorMsg)` is called before exit.
> 6. **On Success**: Stop heartbeat, then report `success`."

---

## 3. Web UI (Hotwire)

### 3.1 Visual Feedback

**Goal**: 讓使用者知道現在「正在做什麼」。

> **AI Prompt**:
> "Update the `RunRowComponent` (ViewComponent):
>
> 1. If status is `building`, show an Amber badge with 'Building...'.
> 2. If status is `running`, show a Blue badge with a spinner animation 'Running...'.
> 3. If status is `lost`, show a Gray badge 'Lost Connection'.
> 4. Ensure Turbo Stream updates render these states correctly without page refresh."

---

## 總結檢查清單 (Definition of Done)

- [ ] 當 Agent 開始編譯時，Web UI 狀態應即時變為 "Building"。
- [ ] 當 Agent 開始執行 srun 時，Web UI 狀態應即時變為 "Running"。
- [ ] 若手動砍掉 Agent Process，5 分鐘後 Web UI 應自動顯示 "Lost"。
- [ ] 資料庫中能看到完整的狀態變更歷程 (透過 Audit log 或狀態欄位確認)。
