# Feature Request: Agent 唯一識別機制 (Hybrid UUID Strategy)

## 1. 背景與目標 (Context)

目前 Agent 在向 Rails Server 發送 Report 時，缺乏一個唯一識別碼 (Unique Identifier)，導致 Server 無法區分數據來自哪一台機器。

**目標：** 實作一套「混合式身份識別機制」。

1. **穩定性：** 優先使用持久化檔案中的 UUID。
2. **綁定硬體：** 若檔案遺失，則根據硬體特徵 (Hardware Fingerprint) 重算 UUID，確保同一台機器重裝 Agent 後 ID 仍保持不變。
3. **自動註冊：** Rails Server 收到帶有新 UUID 的請求時，自動註冊該 Node。

## 2. 技術範疇 (Technical Scope)

* **Agent:** Go (Golang)
* **Web Server:** Ruby on Rails
* **Protocol:** HTTP/JSON
* **Strategy:** Hybrid (File Persistence + Hardware Fingerprint)

---

## 3. 系統邏輯流程 (Core Logic)

### Agent 端 (Go) 啟動流程

1. **檢查識別檔：** 檢查本地路徑 (例如 `./config/node_id` 或 `/var/lib/agent/node_id`) 是否存在。
2. **路徑 A - 檔案存在：**

* 直接讀取檔案內容作為 `NodeUUID`。

1. **路徑 B - 檔案不存在 (首次啟動或檔案遺失)：**

* 執行 **Hardware Fingerprinting**：
* 讀取 Machine ID (Linux: `/etc/machine-id` 或 `/var/lib/dbus/machine-id`)。
* 若無法讀取，則讀取第一張網卡的 MAC Address。
* 將取得的特徵值進行 Hash (SHA-256) 轉換為 UUID 格式字串。

* 將產生的 `NodeUUID` 寫入識別檔 (Persistence)。

1. **發送回報：**

* 在 HTTP Request Header 加入 `X-Node-ID: <NodeUUID>`。

### Server 端 (Rails) 接收流程

1. 接收 Request。
2. 讀取 Header 中的 `X-Node-ID`。
3. 使用 `uuid` 查找 Node；若不存在則建立 (Find or Create)。

---

## 4. 實作需求細節 (Implementation Details)

### A. Agent 端實作 (Go)

請在 Agent 專案中建立一個 `identity` package 或 util function。

**功能需求：**

1. **`GetOrGenerateNodeID()` 函數：**

* 實作上述的 Hybrid 邏輯。
* 需處理權限錯誤 (若無法寫入檔案，至少要回傳 ID 並 Log warning)。

1. **指紋獲取邏輯 (Fingerprinting)：**

* 優先嘗試讀取平台特定的 Machine ID。
* Fallback: 使用 `net` package 獲取主要 Network Interface 的 MAC address。
* Hash 處理: `hex.EncodeToString(sha256.Sum256([]byte(hardware_info)))`。

1. **HTTP Client 修改：**

* 在發送 Report 的 Middleware 或 Function 中，統一注入 Header `X-Node-ID`。

**Go Pseudo-code 參考:**

```go
func GetFingerprint() string {
    // 1. Try /etc/machine-id
    // 2. Else try MAC Address
    // 3. Return SHA256 Hash of the result
}

```

### B. Server 端實作 (Ruby on Rails)

**資料庫變更 (Migration)：**

* Table: `nodes`
* Column: `uuid` (String, Not Null)
* Index: `add_index :nodes, :uuid, unique: true` (確保唯一性效能)

**Model (`Node`):**

* 增加 Validations: `validates :uuid, presence: true, uniqueness: true`

**Controller (`ReportsController`):**

* 修改 `create` action (或相關接收 endpoint)。
* 實作 `find_or_create_by` 邏輯。

```ruby
# 邏輯參考
def create
  uuid = request.headers['X-Node-ID']
  return render status: 400, json: { error: 'Missing Node ID' } if uuid.blank?

  @node = Node.find_or_create_by(uuid: uuid) do |n|
    # 設定預設值，例如用 IP 當作暫時名稱
    n.name ||= "Node-#{uuid[0..7]}" 
    n.ip_address = request.remote_ip
  end
  
  # ... 繼續處理 Report 儲存 ...
end

```

---

## 5. 驗收標準 (Acceptance Criteria)

1. **首次執行：** 清除 Agent 本地檔案後啟動，Agent 應產生一個新的 ID 並寫入檔案。
2. **重啟測試：** 重啟 Agent，讀取的 ID 必須與上次相同 (驗證持久化)。
3. **檔案刪除測試：** 刪除 `node_id` 檔案但**不變更硬體**，重新啟動 Agent，產生的 ID 必須與刪除前**完全一致** (驗證硬體指紋生效)。
4. **Rails 整合：**

* Agent 發送 Request 後，Rails 資料庫的 `nodes` 表格應出現該 UUID。
* 同一個 Agent 發送第二次 Request，Rails 不應重複建立 Node。

---

## 6. 注意事項 (Notes)

* **隱私/安全：** 對硬體資訊進行 SHA-256 Hash 是必要的，避免直接明文傳輸 MAC Address。
* **Docker 容器：** 若 Agent 跑在 Docker 中，`/etc/machine-id` 每次重建可能會變。若需支援 Docker，建議將 `node_id` 檔案路徑掛載為 Volume，或是接受 Docker Container ID 作為指紋來源。
