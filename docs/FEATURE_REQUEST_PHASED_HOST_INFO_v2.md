# **FEATURE REQUEST: Phased Implementation of Host Info Collection & Visualization**

**Status**: Draft
**Priority**: High
**Target Version**: v0.6.x (Phase 1), v0.7.x (Phase 1)
**Related**: `AGENT.md`, `UI_DESIGN_GUIDELINES.md`
**Reference**: [Oracle Memory Topology Documentation](https://docs.oracle.com/cd/E27124_01/html/E27125/z40006011391452.html)
**Style Guide**: NetBox-inspired (Data-dense, Clean Tables, Card-based layout)

## **1. Context & Roadmap**

為了取得詳細的硬體資訊（System, BIOS, Memory DIMM），我們需要存取底層 DMI 表格。考量實作難度、安全性與功能深度，將採用三階段導入策略：

| Phase | Method | Ops Requirement | Pros | Cons |
| :--- | :--- | :--- | :--- | :--- |
| **Phase 1** | **dmidecode + SUID** | `chmod u+s /usr/sbin/dmidecode` | 實作最快，Agent 無需改動 sudo 邏輯 | 安全性較低 (全域使用者皆可讀 DMI) |
| **Phase 2** | **dmidecode + Sudoers** | `/etc/sudoers` NOPASSWD 設定 | 安全性標準，符合資安稽核 | 需維護 Sudoers 規則 |
| **Phase 3** | **Intel PerfSpect** | 安裝 Python & PerfSpect 依賴 | 可取得更深層 PMU/Uncore 數據 | 部署成本極高 (Dependencies) |

## **2. Data Requirements**

Agent 需透過 `dmidecode -t 0,1,17` 取得並解析以下三個區塊的資訊。

### **2.1 System Information (Type 1)**

用於識別機器型號與唯一 ID。

* **Manufacturer**: (e.g., "Quanta Cloud Technology Inc.")
* **Product Name**: (e.g., "QuantaGrid D54X-1U")
* **Version**: (e.g., "---")
* **Serial Number**: (e.g., "To be filled by O.E.M.")
* **UUID**: (e.g., "7d916442-2c24-11ee-be23-74d4dd2e9195") - **重要：用於節點去重識別**
* **SKU Number**: (e.g., "Default string")
* **Family**: (e.g., "Default String")

### **2.2 BIOS Information (Type 0)**

用於確認 Firmware 版本與升級需求。

* **Vendor**: (e.g., "American Megatrends International, LLC.")
* **Version**: (e.g., "3B05.QCT402")
* **Release Date**: (e.g., "11/17/2023")
* **Address**: (e.g., "0xF0000")
* **Runtime Size**: (e.g., "64 kB")
* **ROM Size**: (e.g., "64 MB")

### **2.3 Memory Information (Type 17)**

需解析所有 DIMM Slot 狀態，包含空插槽。

* **Bank Locator** (e.g., "P0_Node0_Channel0_Dimm0") - **CRITICAL: Primary Key for Topology Grouping**
* **Locator** (e.g., "DIMM_A1")
* **Size** (e.g., "32 GB" or "No Module Installed")
* **Type** (e.g., "DDR4")
* **Speed** (Spec Speed, e.g., "2666 MT/s")
* **Configured Memory Speed** (Actual Speed, e.g., "2400 MT/s")
* **Manufacturer** (e.g., "Samsung")
* **Part Number** (e.g., "M393A4K40CB2-CTD")
* **Serial Number**
* **Asset Tag**
* **Rank**
* **Min/Max/Configured Voltage**
* **Firmware Version**
* **Form Factor**

## **3. User Interface Requirements (NetBox Style)**

UI 設計需遵循 NetBox 風格：強調資訊密度、邊框清晰的卡片 (Cards)、以及狀態標籤 (Badges)。

### **3.1 Page Header & Layout**

* **Breadcrumb**: `Home / Nodes / [Node Name] / Hardware`
* **Header**:
  * **Title**: 節點名稱 (Large, Bold)。
  * **Subtitle**: Product Name & Serial Number (Grey text)。
  * **Right Action Buttons**: Edit, Delete, Refresh (Standard NetBox button group).

### **3.2 Info Panels (System & BIOS)**

使用兩欄式卡片佈局呈現靜態資訊。

* **Component**: `Card` with `CardHeader` and `Table` (key-value pairs).
* **Style**: Header Background `bg-slate-100`, Table Rows Zebra striping (`odd:bg-white even:bg-slate-50`).

### **3.3 Visual Memory Topology (Motherboard Map)**

此區塊需實作 Oracle 文件中描述的階層化結構，但以 NetBox 的現代化 UI 呈現。

referece: <https://docs.oracle.com/cd/E27124_01/html/E27125/figures/A0000_DIMM_config.jpg>

#### **A. Grouping Strategy (Topology Logic)**

由於不同廠商的 `Bank Locator` 命名規則不同 (e.g., `P0_Node0...` vs `CPU1_DIMM...`)，前端需實作一個 **Flexible Grouper**：

1. **Regex Extraction**: 嘗試從 `Bank Locator` 或 `Locator` 提取 "CPU", "Socket", "Node", "P#" 等關鍵字。
2. **Fallback**: 若無法解析，則將所有 DIMM 視為 "Default Group"。
3. **Hierarchy**: `Socket (Container) -> Channel (Optional Sub-group) -> Slot (Item)`

#### **B. Visual Layout (The "Map")**

* **Container**: 標題 "Memory Topology"。使用 Flex/Grid 顯示多個 **CPU Socket Blocks**。
* **Socket Block**:
  * **Header**: 顯示 "CPU 0" 或 "Socket 1"。
  * **Grid**: 內含該 Socket 下的所有 DIMM Slots (例如 8 或 12 個格子)。
* **DIMM Slot Component**:
  * **Shape**: 長方形方塊 (Vertical Rectangle)，模擬實體插槽。
  * **Status Colors**:
    * **Healthy (Installed)**: `bg-green-500` border-green-600` (Solid).
    * **Empty**: `bg-slate-100` `border-dashed border-2 border-slate-300` `text-slate-400`.
    * **Warning**: `bg-yellow-100` `border-yellow-400` (若 Config Speed < Spec Speed).
  * **Content**:
    * **Top**: Locator (e.g., "A1") - Small font.
    * **Middle**: Size (e.g., "32G") - Bold.
    * **Bottom**: Type (e.g., "DDR4") - Tiny font.
* **Interactions**:
  * **Tooltip**: Hover 顯示完整資訊 (Manufacturer, Part Number, Speed)。

### **3.4 Memory Detailed Table**

位於視覺化區塊下方，提供完整數據列表 (NetBox standard table)。

* **Columns**: Slot, Status (Badge), Size, Type, Speed (Config/Spec), Manufacturer, Part Num.

## **4. Technical Implementation (Agent)**

### **4.1 Model Update (`agent/core/model/inventory.go`)**

```go
type HostDMIInfo struct {
    System SystemInfo   `json:"system"`
    BIOS   BIOSInfo     `json:"bios"`
    Memory []DIMMInfo   `json:"memory"`
}

type DIMMInfo struct {
    Locator         string `json:"locator"`
    BankLocator     string `json:"bank_locator"` // Critical for UI grouping
    Size            string `json:"size"`
    Type            string `json:"type"`
    Speed           string `json:"speed"`
    ConfiguredSpeed string `json:"configured_speed"`
    Manufacturer    string `json:"manufacturer"`
    PartNumber      string `json:"part_number"`
    SerialNumber    string `json:"serial_number"`
}

```

### **4.2 Parser Logic Requirement**

1. **"No Module Installed" Handling**: parser 必須能識別 `dmidecode` 輸出中的 "No Module Installed" 或 "Not Specified"，並將其標記為 Empty，而非遺漏該筆資料。**這是繪製完整拓樸圖的關鍵。**
2. **Raw Data Preservation**: 盡量保留原始的 `Bank Locator` 字串，將解析邏輯交由前端處理，以保持 Agent 輕量化。

## **5. Operations Guide**

* **Phase 1 Setup**:

```bash
sudo chmod u+s $(which dmidecode)
```
