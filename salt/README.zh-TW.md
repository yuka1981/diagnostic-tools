> 本文件為 [README.md](README.md) 的繁體中文翻譯版本。

# Salt 模組部署 — 操作指南

本目錄包含 SaltStack 自訂模組、state 檔案，以及用於管理 HPC 叢集節點的
reactor 設定。Salt 用於從運算節點收集硬體資產清冊，並遠端執行效能測試
（HPCG 與 MLC）。

Salt master 透過 Ansible 自動部署與設定。master 啟動後，會透過 GitFS 從
Git 拉取本目錄的內容，因此合併到追蹤分支的任何變更都會自動生效。

---

## 目錄

1. [前置條件](#前置條件)
2. [目錄結構](#目錄結構)
3. [安裝指南](#安裝指南)
4. [測試](#測試)
5. [自訂模組參考](#自訂模組參考)
6. [效能測試編排](#效能測試編排)
7. [Reactor 事件](#reactor-事件)
8. [疑難排解](#疑難排解)
9. [安全性注意事項](#安全性注意事項)

---

## 前置條件

開始之前，請確認具備以下條件：

- **Ansible 2.14+** 已安裝於控制機器（筆電或跳板主機）。
- 控制機器具備 **SSH 存取權限**，可連線至所有目標伺服器（master 與
  minion），且使用的帳號擁有 sudo 權限。
- **目標伺服器**執行 Rocky Linux 9 / RHEL 9 / AlmaLinux 9，或
  Ubuntu 20.04+ / Debian 11+。Ansible role 會自動偵測作業系統類型，
  並使用 `dnf`（RHEL）或 `apt`（Debian）安裝套件。
- Salt master（主控端）與所有 minion（受控端）節點之間的 **網路連線**
  需開通 **4505** 與 **4506** 連接埠（Salt 的 ZeroMQ 傳輸通道）。
- Salt master 上的 **8000 連接埠** 需開放，供 Salt REST API 使用
  （由 Rails 應用程式呼叫）。
- 一組 **GitHub 個人存取權杖**（或機器帳號權杖），需具備儲存庫的讀取
  權限，以便 master 透過 GitFS 拉取 state 檔案。
- 如需在本機執行單元測試，需安裝 **Python 3.8+** 與 **pytest**。

---

## 目錄結構

```
salt/
├── _modules/                    # 自訂 Salt 執行模組
│   ├── benchmark.py             # 效能測試執行（HPCG、MLC）
│   └── inventory.py             # 系統資產清冊收集
├── _tests/                      # 自訂模組的單元測試
│   ├── __init__.py
│   ├── test_benchmark.py        # benchmark 模組測試
│   └── test_inventory.py        # inventory 模組測試
├── benchmark/                   # 效能測試編排用 Salt state 檔案
│   ├── hpcg/
│   │   ├── init.sls             # HPCG 主編排器（包含 prepare、execute、collect）
│   │   ├── prepare.sls          # 建立工作目錄並驗證 hpcg 執行檔
│   │   ├── execute.sls          # 透過 module.run 執行 benchmark.run_hpcg
│   │   └── collect.sls          # 透過 cp.push_dir 將產出檔推送回 master
│   └── mlc/
│       ├── init.sls             # MLC 主編排器（包含 prepare、execute、collect）
│       ├── prepare.sls          # 建立工作目錄並驗證 mlc 執行檔
│       ├── execute.sls          # 透過 module.run 執行 benchmark.run_mlc
│       └── collect.sls          # 透過 cp.push_dir 將產出檔推送回 master
├── master.d/
│   └── api.conf                 # Salt API 設定的參考副本（實際設定由 Ansible 部署）
└── reactor/
    ├── job_return.sls           # 效能測試任務完成時透過 POST 通知 Rails
    └── presence_change.sls      # minion 上線或離線時透過 POST 通知 Rails
```

部署 Salt 的 Ansible 檔案位於儲存庫根目錄的 `ansible/` 下：

```
ansible/
├── ansible.cfg                          # Ansible 設定（roles 路徑、inventory、vault）
├── playbooks/
│   └── salt.yml                         # 主 playbook（兩個 play：master + minion）
├── inventory/
│   ├── hosts.yml                        # 主機清單檔（INI 格式）
│   └── group_vars/
│       ├── salt_minions.yml             # Minion 群組變數
│       └── salt_master/
│           ├── main.yml                 # 非機密 master 變數
│           ├── vault.yml                # 加密的機密資料（不納入 Git）
│           └── vault.yml.example        # 加密機密資料的範本
└── roles/
    ├── salt_master/                     # 安裝與設定 Salt master
    │   ├── defaults/main.yml
    │   ├── handlers/main.yml
    │   ├── tasks/
    │   │   ├── main.yml
    │   │   ├── install.yml              # APT 套件庫 + 套件安裝
    │   │   ├── configure.yml            # 部署 api.conf
    │   │   ├── gitfs.yml                # 設定 GitFS 後端
    │   │   ├── auth.yml                 # PAM 認證與函式層級 ACL
    │   │   ├── reactor.yml              # 部署 reactor SLS 檔案
    │   │   └── service.yml              # 啟用並啟動服務
    │   └── templates/
    │       ├── api.conf.j2
    │       ├── auth.conf.j2
    │       ├── gitfs.conf.j2
    │       ├── reactor.conf.j2
    │       ├── job_return.sls.j2
    │       └── presence_change.sls.j2
    └── salt_minion/                     # 安裝與設定 Salt minion
        ├── defaults/main.yml
        ├── handlers/main.yml
        ├── tasks/
        │   ├── main.yml
        │   ├── install.yml              # APT 套件庫 + 套件安裝
        │   ├── configure.yml            # 將 minion 指向 master
        │   └── service.yml              # 啟用並啟動 salt-minion
        └── templates/
            └── minion.conf.j2
```

---

## 安裝指南

### 步驟 1：設定 Ansible Inventory

建立一個 inventory 檔案，定義兩個主機群組：`salt_master`（一台主機）
與 `salt_minions`（一或多台運算節點）。

在 `ansible/inventory/hosts.yml` 建立檔案：

```ini
[salt_master]
salt-master-01  ansible_host=10.0.0.1

[salt_minions]
compute-01      ansible_host=10.0.1.1
compute-02      ansible_host=10.0.1.2
compute-03      ansible_host=10.0.1.3

[all:vars]
ansible_user=deploy
ansible_ssh_private_key_file=~/.ssh/id_ed25519
```

請將主機名稱、IP 位址及 SSH 設定替換為你實際的值。

---

### 步驟 2：設定變數

編輯 `ansible/inventory/group_vars/salt_master/main.yml` 以符合你的環境。
預設值如下：

```yaml
salt_version: "3006"

# GitFS -- master 從此儲存庫拉取 salt/ state 檔案
salt_gitfs_user: "machine-account"
salt_gitfs_branch: "develop"
salt_gitfs_repo: "https://github.com/yuka1981/diagnostic-tools.git"
salt_gitfs_update_interval: 60

# Salt REST API
salt_api_port: 8000
salt_api_user: "rails_salt_user"
salt_api_ssl_cert: "/etc/salt/pki/api/cert.crt"
salt_api_ssl_key: "/etc/salt/pki/api/key.key"

# 網路
salt_master_address: "10.0.0.1"
rails_webhook_url: "https://your-rails-app.com/api/v1/salt/events"

# 引用 vault 加密的機密資料（請勿在此填入真實值）
salt_gitfs_token: "{{ vault_salt_gitfs_token }}"
salt_api_password: "{{ vault_salt_api_password }}"
```

需要更新的關鍵變數：

| 變數 | 設定說明 |
|---|---|
| `salt_master_address` | minion 用於連線至 master 的 IP 或主機名稱 |
| `salt_gitfs_repo` | 本儲存庫的 Git URL |
| `salt_gitfs_branch` | master 應追蹤的分支（例如 `develop` 或 `main`） |
| `rails_webhook_url` | Rails webhook 端點的完整 URL |
| `salt_api_ssl_cert` / `salt_api_ssl_key` | master 上 SSL 憑證與金鑰的路徑 |

minion role 使用 `ansible/roles/salt_minion/defaults/main.yml` 中的預設值：

```yaml
salt_version: "3006"
salt_master_address: "salt"
```

如果你的 master 主機名稱無法解析為 `salt`，請在
`group_vars/salt_minions.yml` 或 inventory 中覆寫 `salt_master_address`。

---

### 步驟 3：建立 Ansible Vault

機密資料（GitFS 的 GitHub 權杖與 Salt API 密碼）必須儲存在加密的 vault
檔案中。已提供範本檔案。

```bash
# 複製範例檔案
cp ansible/inventory/group_vars/salt_master/vault.yml.example \
   ansible/inventory/group_vars/salt_master/vault.yml

# 編輯檔案並替換預留值，然後加密
ansible-vault encrypt ansible/inventory/group_vars/salt_master/vault.yml
```

加密前，請編輯 `vault.yml` 並替換預留值：

```yaml
vault_salt_gitfs_token: "ghp_your_actual_github_token_here"
vault_salt_api_password: "a_strong_random_password"
```

> **注意：** 切勿將未加密的 `vault.yml` 提交至版本控制。僅 `.example`
> 檔案應納入版本控制。

---

### 步驟 4：部署 Salt Master

使用 `--limit` 旗標執行 playbook，先僅部署 master：

```bash
cd ansible

ansible-playbook playbooks/salt.yml \
  --limit salt_master \
  --ask-vault-pass
```

> **注意：** `ansible.cfg` 檔案已設定預設 inventory 與 vault 密碼檔，
> 因此若 `ansible.cfg` 已設定好，則不需要 `-i` 參數。
> 如不想每次輸入 vault 密碼，可在 `ansible.cfg` 中設定
> `vault_password_file = ~/.vault_pass`。

此步驟會：

1. 新增 SaltStack 套件庫（來自 `packages.broadcom.com`）並安裝
   `salt-master` 與 `salt-api`。在 RHEL 上，也會安裝 EPEL 並透過
   `salt-pip` 將 `pygit2` 安裝至 Salt 內建的 Python。
2. 建立 PAM 使用者（`rails_salt_user`）以供 API 認證使用。
3. 在 `/etc/salt/master.d/` 下部署設定檔：
   - `api.conf` -- REST API 設定（8000 連接埠、SSL、Tornado）
   - `gitfs.conf` -- 指向本儲存庫的 GitFS 後端
   - `auth.conf` -- PAM 外部認證與函式層級權限
   - `reactor.conf` -- Reactor 事件對應 SLS 的映射
4. 將 reactor SLS 檔案部署至 `/srv/salt/reactor/`。
5. 啟用並啟動 `salt-master` 與 `salt-api` 服務。

確認 master 正在執行：

```bash
ssh salt-master-01 'sudo systemctl status salt-master salt-api'
```

---

### 步驟 5：部署 Salt Minion

```bash
cd ansible

ansible-playbook playbooks/salt.yml \
  --limit salt_minions \
  --ask-vault-pass
```

此步驟會：

1. 新增 SaltStack 套件庫並安裝 `salt-minion`。
2. 部署 `/etc/salt/minion.d/master.conf`，將 minion 指向 master 位址。
3. 啟用並啟動 `salt-minion` 服務。

> **注意：** 你也可以省略 `--limit` 在同一次執行中同時部署 master 與
> minion。playbook 會先執行 master play，再執行 minion play。

---

### 步驟 6：接受 Minion 金鑰

minion 啟動時會將其公鑰傳送給 master。你必須接受這些金鑰，master 才能
與 minion 通訊。

在 Salt master 上執行：

```bash
# 列出所有待接受的金鑰
sudo salt-key --list unaccepted

# 接受特定 minion
sudo salt-key --accept compute-01

# 或一次接受所有待接受的金鑰
sudo salt-key --accept-all
```

驗證已接受的 minion 是否可達：

```bash
sudo salt '*' test.ping
```

預期輸出：

```
compute-01:
    True
compute-02:
    True
compute-03:
    True
```

> **注意：** 如果 `test.ping` 沒有回應或逾時，請檢查 master 與 minion
> 之間是否已開放 4505 與 4506 連接埠。詳見[疑難排解](#疑難排解)。

---

### 步驟 7：同步自訂模組

自訂執行模組（`inventory` 與 `benchmark`）位於本儲存庫的
`salt/_modules/` 下。master 透過 GitFS 拉取這些模組，但每個 minion 需要
先下載才能使用。

```bash
# 同步模組至所有 minion
sudo salt '*' saltutil.sync_modules
```

預期輸出：

```
compute-01:
    - modules.inventory
    - modules.benchmark
compute-02:
    - modules.inventory
    - modules.benchmark
```

> **注意：** master 重啟時會自動同步模組（透過 Ansible handler），但在
> 首次部署或更新模組程式碼後，你應該手動執行同步。

---

### 步驟 8：驗證安裝

執行以下命令確認一切正常運作：

```bash
# 確認所有 minion 有回應
sudo salt '*' test.ping

# 確認自訂 inventory 模組可用
sudo salt 'compute-01' sys.doc inventory

# 從單一節點收集 DMI 資訊
sudo salt 'compute-01' inventory.collect_dmi

# 從所有節點收集 CPU 拓撲
sudo salt '*' inventory.collect_cpu

# 查看 grains（Salt 內建的系統資訊）
sudo salt 'compute-01' grains.items
```

如果 `inventory.collect_dmi` 回傳 `dmidecode not found` 的錯誤，請確認
minion 上已安裝 `dmidecode`（`sudo apt install dmidecode`）。

---

## 測試

### 在本機執行單元測試

單元測試位於 `salt/_tests/`，使用 pytest 搭配 unittest.mock 模擬系統呼叫。
執行測試不需要安裝 Salt。

```bash
# 從儲存庫根目錄執行
python -m pytest salt/_tests/ -v
```

預期輸出：

```
salt/_tests/test_inventory.py::TestCollectDmi::test_collect_dmi_returns_structured_data PASSED
salt/_tests/test_inventory.py::TestCollectDmi::test_collect_dmi_handles_missing_dmidecode PASSED
salt/_tests/test_inventory.py::TestCollectNuma::test_collect_numa_returns_topology PASSED
salt/_tests/test_inventory.py::TestCollectNuma::test_collect_numa_handles_no_numa PASSED
salt/_tests/test_inventory.py::TestCollectNetworkV2::test_collect_network_v2_returns_devices PASSED
salt/_tests/test_inventory.py::TestCollectNetworkV2::test_collect_network_v2_handles_lshw_failure PASSED
salt/_tests/test_inventory.py::TestParseDmiMemory::test_parse_dmi_memory_returns_list_of_devices PASSED
salt/_tests/test_inventory.py::TestParseDmiMemory::test_parse_dmi_memory_handles_empty_output PASSED
salt/_tests/test_inventory.py::TestParseDmiMemory::test_parse_dmi_memory_handles_no_devices PASSED
salt/_tests/test_inventory.py::TestCollectMeminfo::test_collect_meminfo_parses_proc_meminfo PASSED
salt/_tests/test_inventory.py::TestCollectMeminfo::test_parse_proc_meminfo_handles_empty PASSED
salt/_tests/test_inventory.py::TestCollectMeminfo::test_parse_proc_meminfo_handles_plain_integers PASSED
salt/_tests/test_benchmark.py::TestRunHpcg::test_run_hpcg_returns_results PASSED
salt/_tests/test_benchmark.py::TestRunHpcg::test_run_hpcg_handles_failure PASSED
salt/_tests/test_benchmark.py::TestCancel::test_cancel_sends_sigterm PASSED
salt/_tests/test_benchmark.py::TestCancel::test_cancel_returns_error_when_no_process PASSED
```

### 在正式 Minion 上測試資產清冊收集

Salt master 與 minion 部署完成後，測試各個 inventory 函式：

```bash
# DMI 資料（BIOS、系統、主機板、記憶體 DIMM）
sudo salt 'compute-01' inventory.collect_dmi

# 從 /proc/meminfo 取得記憶體統計資訊
sudo salt 'compute-01' inventory.collect_meminfo

# NUMA 拓撲（節點數量、CPU 列表、各節點記憶體）
sudo salt 'compute-01' inventory.collect_numa

# CPU 拓撲（插槽、核心、執行緒、型號名稱、旗標）
sudo salt 'compute-01' inventory.collect_cpu

# 透過 lshw 取得網路裝置資訊（名稱、驅動程式、速度、MAC、廠商）
sudo salt 'compute-01' inventory.collect_network_v2
```

### 測試效能測試執行

> **注意：** 效能測試執行檔（`hpcg` 與 `mlc`）必須已安裝在 minion 上，
> 且位於系統 `$PATH` 中（或透過 `binary_path` 參數為 MLC 指定完整路徑）。

```bash
# 在單一節點上執行 HPCG 效能測試
sudo salt 'compute-01' benchmark.run_hpcg \
  work_dir=/tmp/hpcg \
  run_id=test-run-001

# 以 quick 設定檔執行 MLC 效能測試
sudo salt 'compute-01' benchmark.run_mlc \
  work_dir=/tmp/mlc \
  run_id=test-run-002 \
  binary_path=/opt/mlc/mlc \
  profile=quick
```

---

## 自訂模組參考

### inventory 模組

| 函式 | 說明 | 關鍵系統相依性 |
|---|---|---|
| `inventory.collect_dmi()` | 透過 `dmidecode -t 0,1,2,17` 收集 BIOS、系統、主機板及記憶體 DIMM 的詳細資訊。回傳包含 `bios`、`system`、`baseboard` 與 `memory`（DIMM 列表）鍵的字典。 | `dmidecode` |
| `inventory.collect_meminfo()` | 解析 `/proc/meminfo`，回傳以 kB 為單位的記憶體值字典（例如 `MemTotal`、`MemFree`、`SwapTotal`）。 | 無（讀取 `/proc/meminfo`） |
| `inventory.collect_numa()` | 從 `/sys/devices/system/node/` 讀取 NUMA 拓撲。回傳 `node_count` 以及將節點編號對應到 `cpulist` 與 `memory_kb` 的 `nodes` 字典。 | 無（讀取 `/sys`） |
| `inventory.collect_cpu()` | 解析 `/proc/cpuinfo` 以提取 CPU 拓撲。回傳 `model_name`、`sockets`、`cores`、`cores_per_socket`、`threads`、`threads_per_core` 及 `flags`。 | 無（讀取 `/proc/cpuinfo`） |
| `inventory.collect_network_v2()` | 使用 `lshw -class network -json` 收集網路介面卡資訊。回傳 `devices` 列表，每個介面包含 `name`、`product`、`vendor`、`mac`、`driver`、`speed`、`link` 及 `pci_slot`。 | `lshw` |

### benchmark 模組

| 函式 | 說明 | 參數 |
|---|---|---|
| `benchmark.run_hpcg(work_dir, run_id, timeout=3600)` | 在指定工作目錄中執行 `hpcg` 執行檔。回傳狀態（`PASS`/`FAIL`）、解析後的指標（例如 `gflops`）、時間戳記、日誌內容，以及產出檔案路徑列表。 | `work_dir`（字串）、`run_id`（字串）、`timeout`（整數，秒） |
| `benchmark.run_mlc(work_dir, run_id, binary_path='mlc', profile='quick', timeout=3600)` | 執行 MLC。在 `quick` 設定檔下，測量閒置延遲與尖峰注入頻寬。回傳與 `run_hpcg` 相同的結構，但包含 MLC 特有的指標（例如 `idle_latency_ns`）。 | `work_dir`（字串）、`run_id`（字串）、`binary_path`（字串）、`profile`（字串）、`timeout`（整數，秒） |
| `benchmark.cancel()` | 透過 `pgrep` 找到正在執行的 `hpcg` 或 `mlc` 程序並傳送 SIGTERM。回傳 `{success: True, pid: ...}` 或錯誤字典。 | 無 |

---

## 效能測試編排

效能測試可透過直接呼叫執行模組，或套用 Salt state 來編排完整工作流程
（準備、執行、收集）。

### 透過 Salt State 執行（建議方式）

`salt/benchmark/` 下的 state 檔案提供三階段工作流程：

1. **準備** -- 建立工作目錄並驗證效能測試執行檔已安裝。
2. **執行** -- 透過自訂執行模組執行效能測試。
3. **收集** -- 使用 `cp.push_dir` 將 minion 上的產出檔推送回 master。

#### HPCG

```bash
sudo salt 'compute-01' state.apply benchmark.hpcg \
  pillar='{"run_id": "hpcg-20260131-001", "work_dir": "/tmp/hpcg"}'
```

#### MLC

```bash
sudo salt 'compute-01' state.apply benchmark.mlc \
  pillar='{"run_id": "mlc-20260131-001", "work_dir": "/tmp/mlc", "binary_path": "/opt/mlc/mlc", "profile": "quick"}'
```

### 在多個節點上執行

使用 glob 或列表目標在多個節點上執行效能測試：

```bash
# 所有運算節點
sudo salt 'compute-*' state.apply benchmark.hpcg \
  pillar='{"run_id": "hpcg-batch-001", "work_dir": "/tmp/hpcg"}'

# 特定節點
sudo salt -L 'compute-01,compute-02' state.apply benchmark.mlc \
  pillar='{"run_id": "mlc-batch-001", "work_dir": "/tmp/mlc", "binary_path": "mlc"}'
```

### 產出檔案的存放位置

收集階段完成後，產出檔會被推送至 master，儲存在：

```
/var/cache/salt/master/minions/<minion-id>/files/<work_dir>/
```

例如，`compute-01` 搭配 `work_dir=/tmp/hpcg` 的情況：

```
/var/cache/salt/master/minions/compute-01/files/tmp/hpcg/
```

---

## Reactor 事件

Salt master 監控其事件匯流排上的兩種事件模式，並透過 HTTP POST 轉發給
Rails 應用程式。

### 上線狀態變更

- **事件標籤：** `salt/presence/change`
- **觸發條件：** minion 連線至 master 或從 master 斷線。
- **Reactor 檔案：** `/srv/salt/reactor/presence_change.sls`
- **傳送至 Rails 的內容：**

```json
{
  "tag": "salt/presence/change",
  "new": ["compute-03"],
  "lost": []
}
```

這讓 Rails 應用程式能夠追蹤哪些節點目前在線上。

### 效能測試任務回報

- **事件標籤：** `salt/job/ret/*`
- **觸發條件：** 任何任務在 minion 上完成。reactor 會過濾函式名稱包含
  `benchmark` 或套用的 state 包含 `benchmark` 的任務。
- **Reactor 檔案：** `/srv/salt/reactor/job_return.sls`
- **傳送至 Rails 的內容：**

```json
{
  "tag": "salt/job/ret/20260131120000000000",
  "fun": "benchmark.run_hpcg",
  "id": "compute-01",
  "jid": "20260131120000000000",
  "retcode": 0,
  "return": { "status": "PASS", "metrics": { "gflops": 45.67 }, "..." : "..." }
}
```

兩個 reactor 均透過從 master 設定中讀取的 Bearer token（`rails_api_token`）
向 Rails 進行認證。

---

## 疑難排解

本節記錄在實際部署中遇到的問題，並提供逐步解決方案。

### 部署檢查清單

首次部署時，問題通常按以下順序出現。
請依此清單逐步驗證，確認通過後再進行下一步。

```
1. Ansible playbook 執行無錯誤
   - [ ] Salt 套件安裝完成（DNS 失敗時請檢查套件庫 URL）
   - [ ] group_vars 正確載入（檢查目錄結構）
   - [ ] PAM 使用者已建立

2. salt-master 服務啟動
   - [ ] 設定檔擁有者為 salt:salt（非 root:root）
   - [ ] SSL 憑證存在於 /etc/salt/pki/api/
   - [ ] 連接埠 4505、4506、8000 正在監聽

3. salt-minion 連線
   - [ ] 防火牆允許連接埠 4505 與 4506
   - [ ] Minion 設定指向正確的 master 位址
   - [ ] Minion 金鑰已在 master 上接受（salt-key -A）

4. 自訂模組運作正常
   - [ ] GitFS 提供檔案（salt-run fileserver.file_list）
   - [ ] pygit2 安裝於 Salt 的 Python 中（非系統 Python）
   - [ ] 模組已同步至 minion（salt '*' saltutil.sync_modules）

5. Salt API 有回應
   - [ ] PAM 認證正常（RHEL 上的 shadow 群組權限）
   - [ ] API 登入回傳 token
   - [ ] API 指令回傳結果（master 已完全初始化）
```

每完成一個主要步驟後，請使用 `sudo salt '*' test.ping` 驗證連線。

### Salt 套件庫 URL："Could not resolve host: repo.saltproject.io"

**症狀：** Ansible 安裝任務在嘗試從 `repo.saltproject.io` 下載套件時，
出現 DNS 或連線錯誤而失敗。

**原因：** Salt Project 於 2024 年 10 月關閉了 `repo.saltproject.io`，
並遷移至 Broadcom 的基礎架構。舊的 URL 已無法解析。

**修正方式：** 本儲存庫中的 Ansible role 已使用新的 URL。如果你遇到此
錯誤，可能是使用了舊版的 role。正確的套件庫來源如下：

| 作業系統系列 | 套件庫 URL |
|---|---|
| RHEL / Rocky | `https://packages.broadcom.com/artifactory/saltproject-rpm/` |
| Debian / Ubuntu | `https://packages.broadcom.com/artifactory/saltproject-deb/` |
| GPG 金鑰 | `https://packages.broadcom.com/artifactory/api/security/keypair/SaltProjectKey/public` |

在 RHEL 上，最簡單的方式是下載官方 repo 檔案：

```bash
curl -fsSL https://github.com/saltstack/salt-install-guide/releases/latest/download/salt.repo \
  | sudo tee /etc/yum.repos.d/salt.repo
```

---

### group_vars 未載入："'salt_api_password' is undefined"

**症狀：** playbook 執行失敗，出現 `'salt_api_password' is undefined` 或
類似的錯誤訊息，但這些變數明明已定義在 `group_vars/` 中。
執行 `ansible -m debug -a "var=salt_api_password" salt_master` 可正常
取得值，但 `ansible-playbook` 卻無法。

**原因：** Ansible 解析 `group_vars/` 時，是相對於 **inventory 目錄**或
**playbook 目錄**，而非專案根目錄。如果 `group_vars/` 位於
`ansible/group_vars/`，但 inventory 位於 `ansible/inventory/hosts.yml`，
playbook 就會找不到變數。

**修正方式：** 將 `group_vars/` 放在 `inventory/` 目錄內：

```
ansible/inventory/
├── hosts.yml
└── group_vars/
    ├── salt_minions.yml
    └── salt_master/
        ├── main.yml            # 非機密變數
        ├── vault.yml           # 加密的機密資料
        └── vault.yml.example
```

此外，不要在同一層同時存在 `group_vars/salt_master.yml`（檔案）與
`group_vars/salt_master/`（目錄）。Ansible 可能只會載入其中一個。
請將檔案移入目錄並重新命名為 `main.yml`。

---

### group_vars 檔案與目錄衝突

**症狀：** 來自 `group_vars/salt_master.yml` 的部分變數可正常載入，但
`group_vars/salt_master/vault.yml` 中的 vault 變數無法載入（或相反）。

**原因：** 同時存在檔案 `group_vars/salt_master.yml` 與目錄
`group_vars/salt_master/` 會造成衝突。Ansible 可能只會處理其中一個。

**修正方式：** 只使用目錄形式：

```bash
# 將檔案移入目錄
mv group_vars/salt_master.yml group_vars/salt_master/main.yml
```

---

### 設定檔權限被拒：salt-master 無法啟動

**症狀：** `systemctl status salt-master` 顯示 `failed`，錯誤訊息為
`PermissionError: [Errno 13] Permission denied: '/etc/salt/master.d/api.conf'`。

**原因：** 在 RHEL/Rocky 上，`salt-master` 服務以 `salt` 使用者（非 root）
執行。如果 `/etc/salt/master.d/` 中的設定檔擁有者為 `root:root` 且權限為
`0640`，`salt` 使用者將無法讀取。

**修正方式：** 部署到 `/etc/salt/master.d/` 的所有設定檔必須由 `salt:salt`
擁有：

```bash
# 在 master 上快速修正
sudo chown salt:salt /etc/salt/master.d/*.conf
sudo systemctl restart salt-master
```

本儲存庫的 Ansible role 已在所有 template 任務中設定 `owner: salt` 與
`group: salt`。如果你遇到此錯誤，請確認 role 檔案使用以下設定：

```yaml
- name: Deploy configuration
  ansible.builtin.template:
    src: some_config.j2
    dest: /etc/salt/master.d/some_config.conf
    owner: salt
    group: salt
    mode: '0640'
```

---

### 缺少 SSL 憑證：salt-api 未監聽 8000 連接埠

**症狀：** `ss -tlnp | grep 8000` 無任何輸出。`salt-api` 服務可能正在
執行，但 REST 端點無法連線。

**原因：** `api.conf` 中引用的 SSL 憑證/金鑰檔案不存在：

```yaml
rest_tornado:
  ssl_crt: /etc/salt/pki/api/cert.crt
  ssl_key: /etc/salt/pki/api/key.key
```

**修正方式：** 產生自簽憑證（適合測試用途）：

```bash
sudo mkdir -p /etc/salt/pki/api
sudo openssl req -x509 -nodes -days 3650 \
  -newkey rsa:2048 \
  -keyout /etc/salt/pki/api/key.key \
  -out /etc/salt/pki/api/cert.crt \
  -subj "/CN=$(hostname)/O=SaltStack"
sudo chown salt:salt /etc/salt/pki/api/cert.crt /etc/salt/pki/api/key.key
sudo chmod 640 /etc/salt/pki/api/cert.crt /etc/salt/pki/api/key.key
sudo systemctl restart salt-api
```

Ansible role 會自動產生自簽憑證。正式環境中，請替換為你組織 CA 簽發的
憑證。

---

### 找不到 pygit2："gitfs is configured but could not be loaded"

**症狀：** master 日誌顯示：

```
[ERROR   ] gitfs is configured but could not be loaded, are pygit2 and libgit2 installed?
[CRITICAL] No suitable gitfs provider module is installed.
```

GitFS 未回傳任何檔案，且 `salt-run fileserver.file_list` 為空。

**原因：** Salt 3006+（onedir 套件）將自己的 Python 打包在
`/opt/saltstack/salt/bin/python3`。系統的 `python3-pygit2` 套件對 Salt
不可見，因為 Salt 不使用系統 Python。

**修正方式：** 將 pygit2 安裝至 Salt 內建的 Python：

```bash
# RHEL：先安裝 patchelf（pygit2 wheel 所需）
sudo dnf install -y patchelf

# 將 pygit2 安裝至 Salt 的 Python
sudo /opt/saltstack/salt/bin/pip3 install pygit2

# 重啟以載入新模組
sudo systemctl restart salt-master

# 驗證
sudo salt-run fileserver.update
sudo salt-run fileserver.file_list
```

> **注意：** 透過 `dnf` 或 `apt` 安裝的系統 `python3-pygit2` 套件不會
> 被 Salt 3006+ 使用。你必須透過 Salt 的 pip 安裝。

---

### PAM 認證失敗："Could not authenticate using provided credentials"

**症狀：** Salt API 登入回傳 401。master 日誌顯示：

```
unix_chkpwd: password check failed for user (rails_salt_user)
pam_unix(login:auth): authentication failure ... user=rails_salt_user
[ERROR   ] Pam auth failed for rails_salt_user
```

**原因：** 在 RHEL/Rocky 上，`salt-master` 以 `salt` 使用者（非 root）
執行。PAM 使用 `unix_chkpwd` 驗證 `/etc/shadow` 中的密碼，但
`/etc/shadow` 預設權限為 `0000` -- `salt` 使用者無法讀取。

此外，如果 PAM 使用者的 shell 設為 `/usr/sbin/nologin`，PAM 可能會
直接拒絕認證。

**修正方式（兩部分）：**

1. 透過 shadow 群組授予 `salt` 使用者 `/etc/shadow` 的讀取權限：

```bash
sudo groupadd -f shadow
sudo usermod -aG shadow salt
sudo chgrp shadow /etc/shadow
sudo chmod g+r /etc/shadow
sudo systemctl restart salt-master
```

2. 確保 PAM 使用者有有效的 shell：

```bash
sudo usermod -s /bin/bash rails_salt_user
```

本儲存庫的 Ansible role 會自動處理以上兩項設定。

---

### Salt API 指令逾時："The master is not responding"

**症狀：** API 登入正常（回傳 token），但任何指令執行
（`test.ping`、`get_minions` 等）回傳：

```
Salt request timed out. The master is not responding.
```

**原因：** 可能的情況：

- `salt-master` 程序尚未完全初始化（啟動後需要 60-90 秒，所有 worker
  才會就緒）。
- `MWorkerQueue` 程序卡在 CPU 忙碌迴圈中（Salt 3006 的已知 ZMQ 問題）。
  使用以下指令檢查：`ps aux | grep MWorkerQueue`
- salt-api 在 master 完成初始化之前就已啟動。

**修正方式：**

1. 停止 salt-api，重啟 salt-master，等待後再啟動 salt-api：

```bash
sudo systemctl stop salt-api
sudo systemctl restart salt-master
sleep 60    # 等待 master 完全初始化
sudo systemctl start salt-api
```

2. 在啟動 API 之前確認 master 狀態正常：

```bash
# 啟動 salt-api 之前，所有連接埠都應在監聽狀態
sudo ss -tlnp | grep -E '4505|4506'

# CLI ping 應正常運作
sudo salt '*' test.ping --timeout=15
```

3. 如果 `MWorkerQueue` CPU 使用率過高（50% 以上），停止並全新啟動：

```bash
sudo systemctl stop salt-api
sudo systemctl stop salt-master
sudo rm -f /var/run/salt/master/*.ipc
sudo systemctl start salt-master
sleep 60
sudo systemctl start salt-api
```

> **注意：** 本部署使用的 `rest_tornado` 後端建議用於 Salt 3006，
> 因為它可以避免某些 CherryPy 相關的忙碌迴圈問題。

---

### 防火牆阻擋 minion 連線

**症狀：** Minion 金鑰未出現在 master 上（`salt-key -L` 未顯示待接受的
金鑰）。minion 日誌顯示逾時錯誤。

**原因：** master 上的防火牆阻擋了 4505 與 4506 連接埠。

**修正方式（RHEL/Rocky 上使用 firewalld）：**

```bash
# 在 Salt master 上執行
sudo firewall-cmd --permanent --add-port=4505/tcp
sudo firewall-cmd --permanent --add-port=4506/tcp
sudo firewall-cmd --permanent --add-port=8000/tcp
sudo firewall-cmd --reload

# 驗證
sudo firewall-cmd --list-ports
```

**所需連接埠：**

| 連接埠 | 方向 | 協定 | 用途 |
|---|---|---|---|
| 4505 | Minion 至 Master | TCP | Salt 發布通道（ZeroMQ） |
| 4506 | Minion 至 Master | TCP | Salt 回傳通道（ZeroMQ） |
| 8000 | Rails 至 Master | TCP | Salt REST API（HTTPS） |

> **注意：** 如果你的環境使用 `firewalld`，可考慮在 Ansible role 中加入
> 防火牆任務。目前的 role 不管理防火牆規則。

---

### Minion 金鑰未出現

**症狀：** 啟動 minion 後，`salt-key --list unaccepted` 未顯示待接受的
金鑰。

**可能原因：**

- Minion 無法透過 4505 連接埠連線至 master。請檢查防火牆規則（見上方
  說明）。
- Minion 設定中的 `salt_master_address` 無法解析。驗證方式：
  `ssh compute-01 'getent hosts <master-address>'`
- Minion 服務未在執行：
  `ssh compute-01 'sudo systemctl status salt-minion'`

```bash
# 在 minion 上檢查日誌中的連線錯誤
sudo journalctl -u salt-minion --no-pager -n 50
```

---

### 找不到自訂模組

**症狀：** 執行 `salt 'compute-01' inventory.collect_dmi` 回傳
`'inventory.collect_dmi' is not available`。

**修正方式：** 同步模組：

```bash
sudo salt '*' saltutil.sync_modules
```

如果同步回傳空列表，表示 master 可能尚未從 Git 拉取模組。強制更新
GitFS：

```bash
sudo salt-run fileserver.update
sudo salt '*' saltutil.sync_modules
```

---

### 找不到效能測試執行檔

**症狀：** `benchmark.run_hpcg` 或 state apply 回傳找不到執行檔的錯誤。

**修正方式：** 在 minion 上安裝效能測試執行檔，並確認其位於系統 `$PATH`
中，或使用 `binary_path` 參數為 MLC 提供完整路徑：

```bash
sudo salt 'compute-01' benchmark.run_mlc \
  work_dir=/tmp/mlc \
  run_id=test \
  binary_path=/usr/local/bin/mlc
```

---

### Reactor 未觸發

**症狀：** Rails 未收到 webhook 事件。

**檢查方式：**

```bash
# 即時監看 Salt 事件匯流排
sudo salt-run state.event pretty=True

# 在 master 日誌中查找 reactor 錯誤
sudo grep -i reactor /var/log/salt/master | tail -20
```

請確認 master group vars 中的 `rails_webhook_url` 設定正確，且 Rails
應用程式可從 master 連線存取。

---

## 安全性注意事項

### Ansible Vault

所有機密資料（GitHub 權杖、Salt API 密碼）儲存在 Ansible Vault 加密檔案
`ansible/inventory/group_vars/salt_master/vault.yml` 中。未加密的範例檔案
（`vault.yml.example`）列出預期的變數名稱，但僅包含預留值。

- 執行 playbook 時務必使用 `--ask-vault-pass`（或 `--vault-password-file`）。
- 切勿將解密後的機密資料提交至 Git。

### PAM 認證

Salt API 使用 PAM 外部認證。Ansible role 建立系統使用者（預設為
`rails_salt_user`），並使用 `no_log: true` 以防止密碼雜湊出現在 Ansible
輸出中。

該使用者的 shell 設為 `/bin/bash`，以便在 RHEL 系統上進行 PAM 認證。
此使用者沒有家目錄且為系統帳號，並非用於互動式 SSH 存取。

### 函式層級權限

PAM 使用者僅被授權存取特定的 Salt 函式白名單：

- `grains.items`
- `inventory.*`
- `benchmark.run_hpcg`、`benchmark.run_mlc`、`benchmark.cancel`
- `test.ping`
- `state.apply`
- `cmd.run`
- `cp.push`、`cp.push_dir`
- `saltutil.sync_modules`
- Runner：`manage.status`

這表示 API 使用者無法執行此清單以外的任意 Salt 函式。

### SSL/TLS

Salt REST API 設定為透過 Tornado 使用 HTTPS，並在設定中指定憑證與金鑰。
正式環境部署時，請務必使用有效的憑證。

### 限制 API 用戶端類型

API 設定限制允許的 netapi 用戶端類型為：

- `local` -- 在 minion 上執行函式
- `local_async` -- 非同步執行函式
- `runner` -- 在 master 上執行 runner 函式

這可防止使用其他用戶端類型，例如 `wheel`（可修改金鑰或設定）。
