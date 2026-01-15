### **Epic: Agent Native Hardware Collection Transformation**

**Context**: The current Agent relies heavily on external commands like `dmidecode`, making deployment dependent on host tools and parsing fragile. The goal is to transform the Agent into a self-contained executable using Native Go Libraries for hardware collection.

---

### **Q1: How do we resolve the deployment difficulties caused by relying on external shell commands (like `dmidecode`) for hardware info?**

**User Story 1: Static Hardware Topology Discovery**

> **As a** System Administrator,
> **I want** the Agent to directly read CPU, Memory, and Baseboard information via internal Go libraries (`ghw`),
> **So that** I do not need to pre-install `dmidecode` or `lshw` on the target host to get an accurate hardware inventory.

**Acceptance Criteria:**

1. **Given** a standard Linux environment (with `/sys` access permissions).
2. **When** the Agent starts and executes Inventory Collection.
3. **Then** the system must successfully parse and return the following fields via the `ghw` library without calling shell commands:

* **CPU**: Model, Socket Count, Core Count, Thread Count.
* **Memory**: Total Physical Memory, DIMM Modules details (Banks/Slots).
* **Baseboard**: Vendor, Product Name.

1. **Note**: Must verify readability when `/sys` is mounted inside a Docker container.

---

### **Q2: Besides static specs, how can we obtain real-time system resource usage more stability, without parsing text output from `top` or `free`?**

**User Story 2: Dynamic System Metrics Collection**

> **As a** SRE (Site Reliability Engineer),
> **I want** the Agent to use `gopsutil` to collect CPU load, memory, and disk usage,
> **So that** I can obtain strongly-typed numerical data and avoid regex failures caused by OS version differences.

**Acceptance Criteria:**

1. **Given** the Agent is running.
2. **When** the dynamic monitoring cycle is triggered.
3. **Then** the system must return the following precise values via `gopsutil`:

* **Load Average**: 1m, 5m, 15m.
* **Memory**: Used, Free, Cached Bytes.
* **Disk Usage**: Total/Used/Free space and Inode usage for major partitions (`/`, `/var`).
* **Network**: Interface Flags and Traffic Counters (Bytes Sent/Recv).

---

### **Q3: For storage devices and accelerators (GPU/PCI), how do we ensure we capture detailed physical info (like NVMe serials or GPU models)?**

**User Story 3: Advanced PCI & Block Device Scanning**

> **As a** Hardware Ops,
> **I want** the Agent to identify physical Disk Serial Numbers and GPU/NIC Vendor information,
> **So that** I can accurately map hardware assets and prepare for subsequent CUDA or InfiniBand detection.

**Acceptance Criteria:**

1. **Given** a server equipped with NVMe SSDs and NVIDIA GPUs.
2. **When** the hardware scan is executed.
3. **Then** the system should identify the following via `ghw`:

* **Block Devices**: Disk Name, Model, Serial Number, Bus Type (NVMe/SATA).
* **PCI Devices**: Filter devices with Class `03` (Display) or `0302` (3D) to record Vendor/Product Name and PCI Address.
* **Networking Hardware**: Identify the Vendor (e.g., Mellanox/Intel) and Product Name of physical network cards.

---

### **Q4: How does the Agent ensure functional continuity in restricted environments (e.g., old Kernels or insufficient permissions) where `/sys` is unreadable?**

**User Story 4: Hybrid Collection & Fallback Strategy**

> **As a** Platform Architect,
> **I want** the Agent to prioritize the Native Collector but automatically switch back to the Legacy Shell Collector upon failure,
> **So that** the Agent can still provide basic hardware information even in systems that do not support `ghw` or have restricted permissions.

**Acceptance Criteria:**

1. **Given** an environment where `NativeCollector` cannot read `/sys/class/dmi` (simulating insufficient permissions).
2. **When** the `Collect()` method is called.
3. **Then** the system must catch the error and automatically downgrade to call the existing `dmidecode` or `lspci` modules.
4. **Then** a Warning message should be recorded in the Log, indicating the switch to Fallback mode.
5. **Verification**: Verify that the format of key fields (such as UUID, Serial Number) returned by Native mode and Shell mode is consistent to ensure a unified data model.
