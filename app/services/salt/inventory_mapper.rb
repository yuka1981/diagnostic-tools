module Salt
  class InventoryMapper
    def initialize(grains:, dmi: nil, numa: nil, network_v2: nil)
      @grains = grains.is_a?(Hash) ? grains : {}
      @dmi = dmi.is_a?(Hash) ? dmi : nil
      @numa = numa.is_a?(Hash) ? numa : nil
      @network_v2 = network_v2.is_a?(Hash) ? network_v2 : nil
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
        kernel: "#{@grains['kernel']} #{@grains['kernelrelease']}",
        os: @grains["os"],
        os_release: @grains["osrelease"],
        platform: @grains["os"],
        platform_version: @grains["osrelease"]
      }
    end

    def map_cpu_info
      numa_info = build_numa_info

      {
        model_name: @grains["cpu_model"],
        cpus: @grains["num_cpus"],
        numa_nodes: @numa&.dig("node_count"),
        numa_info: numa_info
      }.compact
    end

    def map_memory_info
      total_mb = @grains["mem_total"]
      {
        total: total_mb ? total_mb * 1024 * 1024 : nil
      }.compact
    end

    def map_disk_info
      disk_names = @grains["disks"] || []
      ssds = @grains["SSDs"] || []

      disk_names.map do |name|
        {
          device: name,
          type: ssds.include?(name) ? "SSD" : "HDD"
        }
      end
    end

    def build_numa_info
      nodes = @numa&.dig("nodes")
      return nil unless nodes.is_a?(Hash)

      nodes.transform_values do |node_data|
        cpus = node_data["cpus"]
        next "" unless cpus.is_a?(Array) && cpus.any?

        format_cpu_ranges(cpus.sort)
      end
    end

    def format_cpu_ranges(cpus)
      ranges = []
      range_start = cpus.first
      prev = cpus.first

      cpus.drop(1).each do |cpu|
        if cpu == prev + 1
          prev = cpu
        else
          ranges << (range_start == prev ? range_start.to_s : "#{range_start}-#{prev}")
          range_start = cpu
          prev = cpu
        end
      end
      ranges << (range_start == prev ? range_start.to_s : "#{range_start}-#{prev}")
      ranges.join(",")
    end

    def map_network_info
      interfaces = @grains.dig("ip4_interfaces") || {}
      interfaces.reject { |iface, _| iface == "lo" }.map do |iface, ips|
        { interface: iface, ip: ips.first }
      end
    end

    def map_network_v2_info
      return {} unless @network_v2

      @network_v2.deep_symbolize_keys
    end

    def map_dmi_info
      return {} unless @dmi

      @dmi.deep_symbolize_keys
    end
  end
end
