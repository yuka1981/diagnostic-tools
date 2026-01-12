# FEATURE REQUEST: Intel PerfSpect Integration

**Status**: Draft
**Priority**: High
**Target Version**: v0.9.x
**Dependencies**: `agent` (Go), `perfspect` (External Binary)
**Related**: `FEATURE_REQUEST_PHASED_HOST_INFO.md`

## 1. Context & Goal

To obtain deeper system information than DMI (such as Uncore counters, detailed NUMA topology, and PCIe lane bandwidth utilization), we will integrate **Intel PerfSpect**.
The Diagnostic Agent will first try to generate a report with PerfSpect; if it fails, it will fall back to the standard `dmidecode`.

## 2. Integration Strategy (The "Untracked" Approach)

To keep the project lightweight and comply with licensing, we **do not include PerfSpect source code in Git**.

* **Build & Distribution**:
    * The web server prepares the correct PerfSpect binary based on the target server architecture.
    * The web server then pushes the matching binary to the target server.
* **Install Location**:
    * Install `perfspect` into the same folder as the `hpc-agent` binary on the target server.

## 3. Version Binding & Parser Logic

Because PerfSpect's JSON output schema can change between versions, the Agent parser must be tightly version-bound.

* **Target Version**: `Release v3.x.x` (specify a concrete version, e.g. `v3.12.1`)
* **Verification Logic**:
    1.  When the Agent starts or runs a collection, execute `./perfspect version`.
    2.  If the version mismatches, treat it as "PerfSpect Unavailable," trigger the fallback mechanism, and log a warning.
* **Parser Implementation**:
    * Implement version-specific structs in `agent/core/parser/perfspect/v3_x_x/`.
    * **Strict Decoding**: Use Go `json.Unmarshal` against concrete structs; error if any field is missing.

## 4. Execution Flow & Fallback Mechanism

The Agent should implement a `HybridInventoryCollector`.

### **Step 1: Attempt PerfSpect**
* **Command**: `sudo ./perfspect report --format json --output /tmp/report.json`
* **Timeout**: Set a 120-second execution timeout (to avoid hanging).
* **Success Criteria**: Exit code 0 and the JSON file exists and is non-empty.

### **Step 2: Parse & Transform**
* If Step 1 succeeds, read the JSON.
* Convert PerfSpect JSON into the Agent's internal `HostInventory` model.
    * *Mapping Example*: PerfSpect `system.cpu` -> Inventory `CPUInfo`.

### **Step 3: Fallback to DMI**
* **Trigger Conditions**:
    * PerfSpect binary is missing.
    * PerfSpect times out or Exit Code != 0.
    * PerfSpect version mismatch.
    * JSON parse failure.
* **Action**: Run `dmidecode -t 0,1,17` (existing Phase 1/2 logic).
* **UI Status**: Mark the data source in the Web UI as "Legacy DMI" (yellow) or "PerfSpect" (green).

## 5. UI Requirements (Node Show Page)

Add an "Advanced Telemetry" section to the `nodes/show` page (only show it when the source is PerfSpect).

* **Hardware Topology**: Show a more accurate Socket/Core/Thread mapping diagram.
* **PCIe Bandwidth**: Show negotiated width/speed for each Root Port.
* **PMU/Uncore Events**: If PerfSpect collected counters, show a summary table.
* **Source Indicator**: Show "Data Source: Intel PerfSpect v1.4" at the top of the page (with version).

## 6. Action Items for Agent Team

1.  Build per-architecture PerfSpect binaries on the web server.
2.  Push the matching binary to each target server.
3.  Install `perfspect` into the same folder as the `hpc-agent` binary.
4.  Implement `PerfspectCollector` struct in Go.
5.  Implement `FallbackCollector` wrapper.
