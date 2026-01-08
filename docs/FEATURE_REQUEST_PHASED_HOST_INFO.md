# **FEATURE REQUEST: Phased Implementation of Host Info Collection**

**Status**: Draft  
**Priority**: High  
**Target Version**: v0.6.x (Phase 2), v0.7.x (Phase 2)  
**Related**: `AGENT.md`

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

* **Bank Locator** (e.g., "P0_Node0_Channel0_Dimm0") - **Primary Key for UI Mapping**
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

## **3. User Interface Requirements**

Web UI (`nodes/show.html.erb`) 需新增區塊來呈現這些資訊。

### **3.1 Overview Card (System & BIOS)**

在頁面頂端或 "Overview" Tab 中顯示：

* **Header**: Product Name (e.g., QuantaGrid D54X-1U)
* **Details Grid**:
  * Manufacturer / Serial Number / UUID
  * BIOS Version / Release Date / ROM Size

### **3.2 Memory Topology Table**

* **Display**: 以表格列出所有 DIMM Slots。
* **Columns**: Slot (Locator), Status, Size, Type, Speed (Configured/Spec), Manufacturer, Part Num.
* **Visual Indicators**:
  * **Installed**: 綠色狀態燈。
  * **Empty**: 灰色背景或文字淡化 (Dimmed)，顯示 "Empty"。

## **4. Technical Implementation (Agent)**

### **4.1 Model Update (`agent/core/model/inventory.go`)**

```go
type HostDMIInfo struct {
    System SystemInfo   `json:"system"`
    BIOS   BIOSInfo     `json:"bios"`
    Memory []DIMMInfo   `json:"memory"`
}

type SystemInfo struct {
    Manufacturer string `json:"manufacturer"`
    ProductName  string `json:"product_name"`
    Version      string `json:"version"`
    SerialNumber string `json:"serial_number"`
    UUID         string `json:"uuid"`
    SKU          string `json:"sku_number"`
    Family       string `json:"family"`
}

type BIOSInfo struct {
    Vendor      string `json:"vendor"`
    Version     string `json:"version"`
    ReleaseDate string `json:"release_date"`
    Address     string `json:"address"`
    RuntimeSize string `json:"runtime_size"`
    ROMSize     string `json:"rom_size"`
}

type DIMMInfo struct {
    // ... (Same as previous request) ...
    Locator         string `json:"locator"`
    BankLocator     string `json:"bank_locator"`
    Size            string `json:"size"`
    Type            string `json:"type"`
    Speed           string `json:"speed"`
    ConfiguredSpeed string `json:"configured_speed"`
    Manufacturer    string `json:"manufacturer"`
    // ... other fields
}

```

### **4.2 Execution Strategy**

1. Check `HPC_DMIDECODE_METHOD` (`direct` vs `sudo`).
2. Exec `dmidecode -t 0,1,17` (一次抓取所有需要的 Type，減少 Process 開銷).
3. **Parser Logic**:

* Handle Section Headers (`System Information`, `BIOS Information`, `Memory Device`).
* Store into respective structs.

## **5. Operations Guide**

* **Phase 1 Setup**:

```bash
sudo chmod u+s $(which dmidecode)

```

* **Phase 2 Migration**:

```bash
sudo chmod u-s $(which dmidecode)
echo "hpc-user ALL=(root) NOPASSWD: /usr/sbin/dmidecode" | sudo tee /etc/sudoers.d/hpc-agent

```
