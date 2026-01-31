module Salt
  class InventoryMapper
    def initialize(grains:, dmi: nil, numa: nil, network_v2: nil, cpu_topology: nil, lscpu: nil, meminfo: nil,
                   disk_usage: nil, disk_blkid: nil)
      @grains = grains.is_a?(Hash) ? grains : {}
      @dmi = dmi.is_a?(Hash) ? dmi : nil
      @numa = numa.is_a?(Hash) ? numa : nil
      @network_v2 = network_v2.is_a?(Hash) ? network_v2 : nil
      @cpu_topology = cpu_topology.is_a?(Hash) ? cpu_topology : nil
      @lscpu = lscpu.is_a?(String) ? lscpu : nil
      @meminfo = meminfo.is_a?(Hash) ? meminfo : nil
      @disk_usage = disk_usage.is_a?(Hash) ? disk_usage : nil
      @disk_blkid = disk_blkid.is_a?(Hash) ? disk_blkid : nil
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
      topology = build_cpu_topology

      {
        model_name: @grains["cpu_model"],
        cpus: @grains["num_cpus"],
        sockets: topology[:sockets],
        cores_per_socket: topology[:cores_per_socket],
        threads_per_core: topology[:threads_per_core],
        flags: topology[:flags],
        numa_nodes: @numa&.dig("node_count") || topology[:numa_nodes],
        numa_info: numa_info,
        virtualization: topology[:virtualization],
        l1d_cache: topology[:l1d_cache],
        l1i_cache: topology[:l1i_cache],
        l2_cache: topology[:l2_cache],
        l3_cache: topology[:l3_cache]
      }.compact
    end

    def map_memory_info
      total_mb = @grains["mem_total"]
      available_kb = @meminfo&.dig("MemAvailable")
      {
        total: total_mb ? total_mb * 1024 * 1024 : nil,
        available: available_kb ? available_kb * 1024 : nil
      }.compact
    end

    def map_disk_info
      if @disk_usage.present?
        map_disk_usage_info
      else
        map_disk_grains_fallback
      end
    end

    def map_disk_usage_info
      fstype_map = build_fstype_map

      @disk_usage.filter_map do |mountpoint, usage|
        next unless usage.is_a?(Hash)
        next unless usage["1K-blocks"].present?

        filesystem = usage["filesystem"]
        total_kb = usage["1K-blocks"].to_i
        used_kb = usage["used"].to_i

        {
          device: filesystem,
          mountpoint: mountpoint,
          total: total_kb * 1024,
          used: used_kb * 1024,
          fstype: fstype_map[filesystem]
        }
      end
    end

    def map_disk_grains_fallback
      disk_names = @grains["disks"] || []
      ssds = @grains["SSDs"] || []

      disk_names.map do |name|
        {
          device: name,
          type: ssds.include?(name) ? "SSD" : "HDD"
        }
      end
    end

    def build_fstype_map
      return {} unless @disk_blkid.is_a?(Hash)

      @disk_blkid.each_with_object({}) do |(device, info), map|
        next unless info.is_a?(Hash)

        map[device] = info["TYPE"] if info["TYPE"].present?
      end
    end

    def build_cpu_topology
      @cpu_topology_cache ||= begin
        if @cpu_topology
          map_cpu_topology_module
        elsif @lscpu
          parse_lscpu
        else
          {}
        end
      end
    end

    def map_cpu_topology_module
      {
        sockets: @cpu_topology["sockets"],
        cores_per_socket: @cpu_topology["cores_per_socket"],
        threads_per_core: @cpu_topology["threads_per_core"],
        flags: @cpu_topology["flags"]
      }.compact
    end

    def parse_lscpu
      fields = {}
      @lscpu.each_line do |line|
        key, _, value = line.partition(":")
        fields[key.strip] = value.strip if value
      end

      sockets = fields["Socket(s)"]&.to_i
      cores_per_socket = fields["Core(s) per socket"]&.to_i
      threads_per_core = fields["Thread(s) per core"]&.to_i
      numa_nodes = fields["NUMA node(s)"]&.to_i
      flags_str = fields["Flags"]
      virtualization = fields["Virtualization"]

      result = {}
      result[:sockets] = sockets if sockets&.positive?
      result[:cores_per_socket] = cores_per_socket if cores_per_socket&.positive?
      result[:threads_per_core] = threads_per_core if threads_per_core&.positive?
      result[:numa_nodes] = numa_nodes if numa_nodes&.positive?
      result[:flags] = flags_str.split if flags_str.present?
      result[:virtualization] = virtualization if virtualization.present?

      result[:l1d_cache] = find_cache_field(fields, "L1d")
      result[:l1i_cache] = find_cache_field(fields, "L1i")
      result[:l2_cache] = find_cache_field(fields, "L2")
      result[:l3_cache] = find_cache_field(fields, "L3")
      result.compact!

      numa_map = parse_lscpu_numa_mappings(fields)
      result[:lscpu_numa_map] = numa_map if numa_map.present?

      result
    end

    def find_cache_field(fields, prefix)
      fields["#{prefix} cache"] || fields[prefix]
    end

    def parse_lscpu_numa_mappings(fields)
      mappings = {}
      fields.each do |key, value|
        next unless key.match?(/\ANUMA node\d+ CPU\(s\)\z/)

        node_id = key[/\d+/]
        mappings[node_id] = value
      end
      mappings.presence
    end

    def build_numa_info
      nodes = @numa&.dig("nodes")
      if nodes.is_a?(Hash)
        return nodes.transform_values do |node_data|
          # Handle cpulist string from custom Salt module (e.g., "0-3,8-11")
          cpulist = node_data["cpulist"]
          if cpulist.is_a?(String) && !cpulist.empty?
            next cpulist
          end

          # Handle cpus array format (e.g., [0, 1, 2, 3])
          cpus = node_data["cpus"]
          next "" unless cpus.is_a?(Array) && cpus.any?

          format_cpu_ranges(cpus.sort)
        end
      end

      # Fall back to lscpu NUMA mappings when custom module unavailable
      topology = build_cpu_topology
      topology[:lscpu_numa_map]
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
      if @dmi && !@dmi.key?("error")
        result = @dmi.deep_symbolize_keys
        if result[:memory].is_a?(Array)
          result[:memory] = result[:memory].map { |dev| normalize_memory_device(dev) }
        end
        return result
      end

      build_dmi_from_grains
    end

    def normalize_memory_device(device)
      device.transform_keys do |key|
        key == :configured_memory_speed ? :configured_speed : key
      end
    end

    def build_dmi_from_grains
      system_info = {
        manufacturer: @grains["manufacturer"],
        product_name: @grains["productname"],
        serial_number: @grains["serialnumber"],
        uuid: @grains["uuid"]
      }.compact

      bios_info = {
        version: @grains["biosversion"],
        release_date: @grains["biosreleasedate"]
      }.compact

      result = {}
      result[:system] = system_info if system_info.any?
      result[:bios] = bios_info if bios_info.any?
      result
    end
  end
end
