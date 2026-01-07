# **AGENT.md — HPC Agent Development Specification (TDD)**

Version: 0.1.0  
Based on: PRD v0.5.2  
Language: Go 1.22+  
Pattern: Hexagonal Architecture (Ports & Adapters)

## **1\. 核心開發原則 (Core Principles)**

1. **Strict TDD**: Write Test \-\> Fail (Red) \-\> Write Code \-\> Pass (Green) \-\> Refactor.  
2. **Interface First**: 所有與作業系統 (FS, Syscall)、網路、外部指令互動的邏輯，必須先定義 interface。  
3. **Mocking**: 使用 mockgen 或手寫 Mock 來隔離外部依賴，確保測試在非 Linux/HPC 環境下（如 macOS 開發機）也能執行。  
4. **Static Binary**: 最終產出必須是 CGO\_ENABLED=0 的靜態執行檔。

## **2\. 系統架構設計 (Architecture)**

```go
// core/ports/collector.go  
type SystemCollector interface {  
    GetHostInfo() (\*model.HostInfo, error)  
    GetCPUInfo() (\*model.CPUInfo, error)  
    GetMemInfo() (\*model.MemInfo, error)  
    GetDiskInfo() (\[\]model.DiskInfo, error)  
    GetNetInfo() (\[\]model.NetInfo, error)  
}

// core/ports/uploader.go  
type InventoryUploader interface {  
    Push(ctx context.Context, data \*model.NodeState) error  
    PushArtifact(ctx context.Context, runID string, file Path) error  
}

// core/ports/executor.go  
// 用於隔離 exec.Command，方便測試 HPCG 編譯與執行  
type CommandRunner interface {  
    Run(ctx context.Context, dir string, cmd string, args ...string) (output string, err error)  
}
```

## **3\. 功能模組規格 (Modules Specs)**

### **3.1 基礎設施 (Infrastructure)**

* **Config**: 讀取 config.yaml 或環境變數 (API Endpoint, Token)。  
* **Logger**: 結構化日誌 (slog or zap)。

### **3.2 系統資訊收集 (Inventory) - hpc-agent collect**

**TDD 流程**:

1. **Test**: 建立 MockCollector，預期 GetCPUInfo 返回假資料。  
2. **Test**: 測試 CollectUseCase 組合各個 Info 並 Marshal 成符合 Schema 的 JSON。  
3. **Impl**: 實作 LinuxCollector。  
   * *CPU*: 解析 /proc/cpuinfo 或 lscpu 輸出。  
   * *Mem*: 解析 /proc/meminfo。  
   * *Net*: 解析 /sys/class/net 或 ip addr。

**驗收標準**:

* 執行 `hpc-agent collect` 輸出之 JSON 需符合 JSON Schema 驗證。  
* 執行時間 < 1s。

### **3.3 主動回報 (Push) - hpc-agent inventory push**

**TDD 流程**:

1. **Test**: 建立 MockHTTPClient。  
2. **Test**: 呼叫 Push 方法，驗證 Request Body 是否包含 Token 與正確的 JSON。  
3. **Test**: 模擬 API 500 錯誤，驗證是否重試 (Retry with Exponential Backoff) 或優雅失敗。

### **3.4 HPCG Benchmark - hpc-agent benchmark hpcg**

這是最複雜的模組，需拆解為子任務測試。

#### **A. 環境準備 (Environment Setup)**

* **Interface**: ModuleLoader  
* **Test**: 模擬執行 module load \<profile\>，驗證環境變數變更。

#### **B. 原生編譯 (Native Compilation)**

* **Test**: 模擬 make 指令執行。若目標執行檔 xhpcg 已存在且 Hash 相同，則跳過 (Build Cache 雖為 Non-goal，但基本檢查要有)。

#### **C. 設定檔生成 (Config Generation)**

* **Logic**: 根據 hpcg.dat 格式生成檔案。  
* **Test**: 輸入參數 nx=104, ny=104...，驗證生成的 hpcg.dat 內容是否正確。

#### **D. 執行與解析 (Run & Parse)**

* **Input**: 模擬的 HPCG stdout/log 檔案內容。  
* **Test (Regex)**:  
  * Case 1: 成功。擷取 GFLOPS, Time, Status=PASS。  
  * Case 2: 失敗 (Residual error)。擷取 Status=FAIL。  
  * Case 3: 崩潰 (Crash)。

#### **E. 產物上傳 (Artifact Upload)**

* **Logic**: 原子寫入 (.tmp \-\> rename)。  
* **Test**: 驗證檔案操作序列。

## **4\. CLI 介面 (Cobra)**

* main.go: Entrypoint。  
* cmd/collect.go: 綁定 CollectUseCase。  
* cmd/push.go: 綁定 PushUseCase。  
* cmd/hpcg.go: 綁定 HPCGUseCase。

## **5\. 測試策略 (Test Strategy)**

* **Unit Tests**: 覆蓋率目標 \> 80%。針對所有 Parser 與 Logic。  
* **Integration Tests**: 在 CI 環境中使用 Docker 模擬 Linux 環境，測試 /proc 讀取（部分）。  
* **Golden Files**: 對於 JSON 輸出與 Log 解析，使用 Golden File 測試法確保格式不變。
