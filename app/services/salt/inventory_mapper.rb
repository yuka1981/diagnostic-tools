module Salt
  class InventoryMapper
    def initialize(grains:, dmi: nil, numa: nil, network_v2: nil)
      @grains = grains || {}
      @dmi = dmi
      @numa = numa
      @network_v2 = network_v2
    end

    def call
      {
        host: map_host_info,
        cpu: map_cpu_info,
        memory: map_memory_info,
        disks: map_disk_info,
        network: map_network_info,
        network_v2: map_network_v2_info,
        dmi: map_dmi_info
      }
    end

    private

    def map_host_info
      primary_ip = @grains.dig("ip4_interfaces")
        &.reject { |iface, _| iface == "lo" }
        &.values&.flatten&.first

      {
        hostname: @grains["host"],
        ip: primary_ip,
        arch: @grains["cpuarch"],
        kernel: @grains["kernel"],
        kernel_release: @grains["kernelrelease"],
        os: @grains["os"],
        os_release: @grains["osrelease"]
      }
    end

    def map_cpu_info
      {
        model: @grains["cpu_model"],
        cores: @grains["num_cpus"],
        numa_nodes: @numa&.dig("node_count"),
        numa_topology: @numa&.dig("nodes")
      }.compact
    end

    def map_memory_info
      total_mb = @grains["mem_total"]
      {
        total_kb: total_mb ? total_mb * 1024 : nil
      }.compact
    end

    def map_disk_info
      disk_names = @grains["disks"] || []
      ssds = @grains["SSDs"] || []

      disk_names.map do |name|
        {
          name: name,
          type: ssds.include?(name) ? "SSD" : "HDD"
        }
      end
    end

    def map_network_info
      interfaces = @grains.dig("ip4_interfaces") || {}
      interfaces.reject { |iface, _| iface == "lo" }.map do |iface, ips|
        { interface: iface, ip: ips.first }
      end
    end

    def map_network_v2_info
      return {} unless @network_v2

      @network_v2
    end

    def map_dmi_info
      return {} unless @dmi

      @dmi
    end
  end
end
