# **FEATURE REQUEST: Agent Daemon Mode, Heartbeat & SELinux Support**

**Status**: ✅ Implemented
**Priority**: Critical
**Target Version**: v0.9.x
**Dependencies**: `Go Agent`, `Rails API`, `Deployment Scripts`

## **1. Context & Problem**

1.  **Systemd Failure**: 目前 Agent 僅支援 `inventory push` (執行即結束) 模式。若在 Systemd 設定 `Restart=always`，會造成 Rapid Restart Loop 導致服務被標記為 Failed。
2.  **SELinux Denial**: 在 RHEL/Rocky Linux 9 (Enforcing 模式) 下，Agent Binary 若無正確標籤 (Context) 或存取受限資源，會被 Kernel 攔截導致啟動失敗。
3.  **Lack of Visibility**: Rails 端無法即時得知節點是否「在線」，只能依賴上次 Inventory 更新時間。

## **2. Functional Requirements**

### **2.1 Agent Daemon Mode** ✅

* **Command**: `hpc-agent start`
* **Behavior**:
    * ✅ 啟動後進入 **Blocking Loop**，不會結束程序。
    * ✅ 定期執行任務 (Heartbeat, Scheduled Inventory)。
    * ✅ 優雅處理 `SIGTERM` / `SIGINT` 信號以進行資源釋放。

### **2.2 Heartbeat Mechanism** ✅

* **Agent**: ✅ 每 `N` 秒 (預設 60s) 發送一次輕量級 HTTP POST 到 Rails。
* **Rails**: ✅ 接收 Heartbeat，更新 `Node` 的 `last_heartbeat_at` 時間戳與狀態 (Online/Offline)。

### **2.3 SELinux Compatibility (Installation Phase)** ✅

* ✅ 安裝腳本需檢測 SELinux 狀態 (`getenforce`)。
* ✅ 若為 `Enforcing`，需自動執行：
    * ✅ **File Context**: 確保 binary 具有 `bin_t` 標籤。
    * ⏳ **Policy Exception**: 若 Agent 需讀取 DMI/SMBIOS，需透過 `audit2allow` 產生並安裝 `.pp` 策略模組 (Deferred - only if needed in practice)

## **3. Technical Specifications**

### **3.1 Agent Implementation (Go)** ✅

* **New Command**: `agent/cmd/start.go`
    * ✅ Flags: `--heartbeat-interval` (default: 60s), `--inventory-interval` (default: 0, disabled)
* **Heartbeat Service**: `agent/core/heartbeat/service.go`
    * ✅ Loop: `time.NewTicker`
    * ✅ Payload:
      ```json
      {
        "uuid": "node-uuid-123",
        "version": "v0.9.0",
        "timestamp": "2026-01-17T12:00:00Z",
        "status": "idle"
      }
      ```

### **3.2 Rails Implementation** ✅

* **API**: ✅ `POST /api/v1/nodes/:uuid/heartbeat`
* **Controller**: `app/controllers/api/v1/heartbeats_controller.rb`
* **Model Update**:
    * ✅ `Node#last_heartbeat_at`: Datetime
    * ✅ `Node#agent_status`: String (idle/busy)
    * ✅ `Node#online?`: Returns true if `last_heartbeat_at > 2.minutes.ago`

### **3.3 Installation Script (`install.sh`)** ✅

```bash
# SELinux handling (from agent/scripts/install.sh)
if command -v getenforce >/dev/null 2>&1; then
    selinux_status=$(getenforce 2>/dev/null || echo "Disabled")
    if [[ "$selinux_status" == "Enforcing" ]]; then
        # Try semanage (persistent), fall back to chcon (temporary)
        if command -v semanage >/dev/null 2>&1; then
            semanage fcontext -a -t bin_t "$agent_path" 2>/dev/null || \
                semanage fcontext -m -t bin_t "$agent_path" 2>/dev/null || true
            restorecon -v "$agent_path"
        else
            chcon -t bin_t "$agent_path"
        fi
    fi
fi
```

## **4. Updated Systemd Service File** ✅

```ini
[Unit]
Description=HPC Diagnostic Agent
Documentation=https://github.com/yuka1981/diagnostic-tools
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/hpc-agent start --node-uuid "${NODE_UUID}" --server "${SERVER_URL}" --token "${AGENT_TOKEN}" --heartbeat-interval ${HEARTBEAT_INTERVAL:-60s} --inventory-interval ${INVENTORY_INTERVAL:-1h}
Restart=always
RestartSec=10s
User=root

# Hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/etc/hpc-agent

[Install]
WantedBy=multi-user.target
```

## **5. Implementation Summary**

| Component | File | Status |
|-----------|------|--------|
| Daemon start command | `agent/cmd/start.go` | ✅ |
| Heartbeat service | `agent/core/heartbeat/service.go` | ✅ |
| Heartbeat API | `app/controllers/api/v1/heartbeats_controller.rb` | ✅ |
| Node online status | `app/models/node.rb` | ✅ |
| Install script | `agent/scripts/install.sh` | ✅ |
| Uninstall script | `agent/scripts/uninstall.sh` | ✅ |
| Service template | `agent/init/hpc-agent.service` | ✅ |
| Migration: last_heartbeat_at | `db/migrate/*_add_last_heartbeat_at_to_nodes.rb` | ✅ |
| Migration: agent_status | `db/migrate/*_add_agent_status_to_nodes.rb` | ✅ |

## **6. Usage**

### Agent CLI
```bash
hpc-agent start \
  --node-uuid <uuid> \
  --server https://hpc.example.com \
  --token <token> \
  --heartbeat-interval 60s \
  --inventory-interval 1h
```

### Installation
```bash
sudo ./install.sh \
  --node-uuid <uuid> \
  --server https://hpc.example.com \
  --token <token> \
  --binary ./hpc-agent \
  --heartbeat-interval 60s \
  --inventory-interval 1h
```

## **7. Design Decisions**

1. **Online Threshold**: Changed from spec's 5 minutes to 2 minutes for more responsive status updates.
2. **Inventory Interval**: Default disabled (0) in CLI, default 1h in install script. Can be set to 0 to disable scheduled inventory pushes.
3. **Status Field**: Agent reports `idle`/`busy` status. Set to `busy` during inventory collection.
4. **SELinux**: Prefers `semanage` (persistent) over `chcon` (temporary) when available.
