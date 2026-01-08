# **AGENT.md — HPC Agent Development Specification (TDD)**

Version: 0.2.0  
Based on: PRD v0.6.x  
Language: Go 1.22+  
Pattern: Hexagonal Architecture (Ports & Adapters)

## **1. 核心開發原則 (Core Principles)**

1. **Strict TDD**: Write Test -> Fail (Red) -> Write Code -> Pass (Green) -> Refactor.  
2. **Interface First**: 所有與作業系統 (FS, Syscall)、網路、外部指令互動的邏輯，必須先定義 interface。  
3. **Mocking**: 使用手寫 Mock 或 Test Doubles 來隔離外部依賴，確保測試在非 Linux/HPC 環境下也能執行。  
4. **Static Binary**: 最終產出必須是 `CGO_ENABLED=0` 的靜態執行檔。

## **2. 系統架構設計 (Architecture)**

### **2.1 核心介面 (Core Ports)**

```go
// core/ports/interfaces.go

type SystemCollector interface {
    GetHostInfo(ctx context.Context) (*model.HostInfo, error)
    GetCPUInfo(ctx context.Context) (*model.CPUInfo, error)
    GetMemInfo(ctx context.Context) (*model.MemoryInfo, error)
    GetDiskInfo(ctx context.Context) ([]model.DiskInfo, error)
    GetNetInfo(ctx context.Context) ([]model.NetInfo, error)
    GetDMIInfo(ctx context.Context) (*model.HostDMIInfo, error)
}

type InventoryCollector interface {
    Collect(ctx context.Context) (*model.NodeState, error)
}

type Uploader interface {
    Upload(ctx context.Context, payload interface{}) error
    CheckAuth(ctx context.Context) error
}

type CommandRunner interface {
    Run(ctx context.Context, dir, name string, args ...string) ([]byte, error)
}
```

### **2.2 串流與命令處理 (Stream & Command Handling)**

```go
// core/stream/client.go

type CommandHandler interface {
    HandleCommand(ctx context.Context, action string, payload map[string]interface{}, responder Responder) error
}

type Responder interface {
    Send(ctx context.Context, payload interface{}) error
}
```

## **3. 功能模組規格 (Modules Specs)**

### **3.1 節點身份識別 (Node Identity)**

* **Mechanism**: 首次啟動時於 `/etc/hpc-agent/node_id` (或指定目錄) 生成並儲存 UUID。
* **Persistence**: 確保 Agent 重啟後 UUID 保持不變，用於伺服器端去重。

### **3.2 系統資訊收集 (Inventory) - hpc-agent collect**

* **DMI (Phase 1)**: 透過 `dmidecode -t 0,1,17` 取得。若執行失敗 (如無權限) 應回傳 Warning 並繼續其他收集任務。
* **CPU**: 解析 `/proc/cpuinfo` 並輔以 `/sys/devices/system/cpu` 取得頻率與快取。
* **Memory**: 解析 `/proc/meminfo` 取得 Total, Free, Available, Buffers, Cached, Swap。
* **Disk**: 讀取 `/proc/mounts` 並使用 `unix.Statfs` 取得空間資訊。

### **3.3 雙向通訊 (Streaming) - hpc-agent start**

* **Protocol**: ActionCable WebSocket。
* **Authentication**: 透過 `X-Node-ID` Header 與 `Authorization: Bearer <token>`。
* **Commands**: 支援 `collect_inventory`, `uninstall`, `ping` 等指令。

### **3.4 HPCG Benchmark**

* **Workflow**: 
    1. 環境載入 (Lmod/Environment Modules)。
    2. 源碼編譯 (Native Optimization)。
    3. 設定生成 (hpcg.dat)。
    4. 執行與日誌解析。
    5. 產物上傳 (JSON Metrics + Log files)。

## **4. CLI 介面 (Cobra)**

* `hpc-agent start`: 以常駐程式 (Daemon) 模式執行，連接 WebSocket。
* `hpc-agent collect`: 單次收集系統資訊並輸出 JSON。
* `hpc-agent inventory push`: 收集並上傳至伺服器。
* `hpc-agent check-key`: 驗證 API Token 效力。

## **5. 測試策略 (Test Strategy)**

* **Unit Tests**: 核心 Parser (CPU, Mem, DMI) 必須有完整 Unit Test。
* **Mock Runner**: 使用 `MockCommandRunner` 模擬外部指令輸出，避免真實執行。
* **JSON Verification**: 確保輸出格式符合後端 `NodeState` 定義。
