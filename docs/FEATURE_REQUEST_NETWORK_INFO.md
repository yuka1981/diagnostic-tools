# **FEATURE REQUEST: Network Interface & InfiniBand Discovery**

**Status**: Draft
**Priority**: High
**Target Version**: v0.7.x
**Related**: `FEATURE_REQUEST_PHASED_HOST_INFO.md`
**Style Guide**: NetBox-inspired (Interface Tables, Status Badges, LAG/Bonding visualization)

## **1. Context & Strategy**

HPC 節點的網路拓樸極為複雜，包含管理網段 (Ethernet) 與高速計算網段 (InfiniBand/RoCE)。由於 `dmidecode` 無法提供即時狀態與 InfiniBand 專屬參數 (LID, GUID)，本功能將採用 **「分層收集策略 (Layered Collection Strategy)」**。

| Layer | Scope | Source | Purpose |
| --- | --- | --- | --- |
| **L1** | **Hardware (PCIe)** | `lspci` | 識別實體卡型號 (e.g., ConnectX-6), NUMA Node 綁定 |
| **L2** | **OS / Logical** | `ip`, `/sys/class/net` | 取得 IP, MAC, MTU, Link State (Up/Down) |
| **L3** | **High Performance (IB)** | `ibv_devinfo`, `/sys/class/infiniband` | 取得 HPC 關鍵數據: LID, GUID, Link Width, Speed |

## **2. Data Requirements**

Agent 需整合多個來源的資訊，並將其關聯（例如：將 `ib0` 介面關聯到實體 `PCI 0000:3b:00.0` 裝置）。

### **2.1 L1: Physical Hardware (PCIe)**

* **Source**: `lspci -vmm -D`
* **Fields**:
* **PCI Address**: (e.g., `0000:3b:00.0`) - **Primary Key for Hardware Mapping**
* **Vendor**: (e.g., "Mellanox Technologies")
* **Device**: (e.g., "MT28908 Family [ConnectX-6]")
* **NUMA Node**: (e.g., 0) - *Critical for process pinning*

### **2.2 L2: Logical Interfaces (Ethernet & IB)**

* **Source**: `ip -j link show`, `ip -j addr show`
* **Fields**:
* **Interface Name**: (e.g., `eth0`, `ib0`)
* **Type**: (e.g., `ether`, `infiniband`, `loopback`)
* **OperState**: (e.g., `UP`, `DOWN`, `LOWERLAYERDOWN`)
* **MAC Address**: (Permanent & Current)
* **MTU**: (e.g., 1500, 9000, 4096)
* **IPv4/IPv6 Addresses**: List of CIDRs.
* **Master (LAG)**: 指示該介面是否屬於某個 Bond (e.g., `bond0`)。

### **2.3 L3: InfiniBand Specifics (HPC)**

僅針對 Type 為 InfiniBand 的裝置收集。

* **Source**: `/sys/class/infiniband/<hca>/ports/<port>/` 或 `ibv_devinfo`
* **Fields**:
* **HCA Name**: (e.g., `mlx5_0`)
* **Port State**: (e.g., `Active`, `Initializing`)
* **LID (Local ID)**: (e.g., `14`) - *Subnet Routing Key*
* **GUID (Port/Node)**: (e.g., `b8:59:9f:03:00:d5:bb:cc`)
* **Link Rate**: (e.g., `HDR`, `NDR`, `100 Gbps`)
* **Link Width**: (e.g., `4X`)

## **3. User Interface Requirements (NetBox Style)**

### **3.1 Interfaces Table (Main View)**

這是主要的網路資訊呈現區塊，模仿 NetBox 的 "Interfaces" Tab。

* **Columns**:
* **Name**: (e.g., `eth0`, `ib0`) - **Bold**, 顯示為連結。
* *Visual Hint*: 若為 Bond Member，名稱縮排並顯示 "↳" 符號。

* **Status**: Badge Component.
* `Active (UP)`: `bg-green-500 text-white`.
* `Down`: `bg-red-500 text-white`.
* `Testing/PFC`: `bg-yellow-500`.

* **Type**: Label (e.g., `1000BASE-T`, `InfiniBand HDR`).
* **IP Address**: 顯示 Primary IP，若有多個則顯示 "+2 more" tooltip。
* **MAC / GUID**: Monospace font.
* **Speed**: (e.g., "100 Gbps").
* **PCI**: 顯示 PCI Address (e.g., `0000:3b:00.0`)，點擊可篩選。

* **Row Actions**: "Graph" (流量圖), "Edit" (若支援設定).

### **3.2 InfiniBand Detail Card (Side Panel or Expanded Row)**

當使用者點擊 `ib0` 或 InfiniBand 類型的介面時，顯示 HPC 專屬資訊卡片。

* **Header**: **HCA Details: mlx5_0**
* **Layout**: Key-Value Grid (NetBox Attribute Table style).
* **Fields**:
* **LID**: `0x000E` (Dec: 14)
* **GUID**: `b8:59:9f...`
* **Firmware**: 顯示於 Tooltip 或額外欄位。
* **Negotiated Speed**: `HDR (200 Gbps)` vs `Supported: NDR`.
* *Warning Logic*: 若 Negotiated < Supported，顯示黃色驚嘆號。

### **3.3 LAG / Bonding Visualization**

若偵測到 Bonding (`bond0`)，UI 需明確呈現階層關係。

* **Parent Row**: `bond0` (Type: LAG), Status: UP.
* **Child Rows**: `eth0`, `eth1` (Type: 10GBASE-T).
* 背景色稍微加深 (`bg-slate-50`) 以區分從屬關係。

## **4. Technical Implementation (Agent)**

### **4.1 Dependencies**

* `iproute2` (Standard on Linux)
* `pciutils` (Standard on Linux)
* `rdma-core` (Optional: 僅當需要完整 IB 功能時) - *若未安裝，Agent 應優雅降級 (Graceful Degradation)，只回傳 L1/L2 資訊。*

### **4.2 Go Model Structure (`agent/core/model/network.go`)**

```go
type NetworkInventory struct {
    Interfaces []InterfaceInfo `json:"interfaces"`
}

type InterfaceInfo struct {
    // L2: Logical (OS)
    Name        string   `json:"name"`
    Type        string   `json:"type"`      // ether, infiniband, loopback
    OperState   string   `json:"oper_state"` // UP, DOWN
    MACAddress  string   `json:"mac_address"`
    MTU         int      `json:"mtu"`
    IPAddresses []string `json:"ip_addresses"`
    Master      string   `json:"master"`     // For bonding (e.g., "bond0")

    // L1: Physical (PCI) - Optional
    PCIAddress  string   `json:"pci_address,omitempty"`
    Vendor      string   `json:"vendor,omitempty"`
    Model       string   `json:"model,omitempty"`
    NUMANode    int      `json:"numa_node,omitempty"`

    // L3: InfiniBand - Optional
    InfiniBand  *IBInfo  `json:"infiniband,omitempty"`
}

type IBInfo struct {
    HCAName   string `json:"hca_name"`
    Port      int    `json:"port"`
    LID       string `json:"lid"`
    GUID      string `json:"guid"`
    LinkSpeed string `json:"link_speed"` // e.g., "HDR"
}

```

### **4.3 Execution Logic**

1. **PCI Discovery**: 執行 `lspci -vmm` 建立 `PCI Address -> Vendor/Model` 的 Map。
2. **Link Discovery**: 執行 `ip -j link show`。

* 解析 JSON 輸出。
* 針對每個 Interface，嘗試從 `/sys/class/net/<iface>/device` 讀取 symlink 以取得 PCI Address。
* 利用 PCI Address 從 Step 1 的 Map 中填入 Vendor/Model 資訊。

1. **IP Discovery**: 執行 `ip -j addr show` 將 IP 填入對應 Interface。
2. **IB Enrichment**: 若 Interface type 為 `infiniband`：

* 讀取 `/sys/class/infiniband/<hca>/ports/<port>/` 下的 `lid`, `rate`, `state` 檔案。
* 填入 `InfiniBand` struct。

## **5. Operations Guide**

* **Permissions**:
* `ip` and `lspci`: 通常不需要 root，但為了讀取完整的 `/sys` 或特定 extended info，建議以 sudo 提權或 `CAP_NET_ADMIN` 執行。
* **Recommendation**: 延續先前的 sudoers 設定，給予 Agent 執行 `ip` 與讀取 `/sys` 的權限。
