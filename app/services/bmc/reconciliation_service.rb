# frozen_string_literal: true

module Bmc
  class ReconciliationService
    Result = Struct.new(:success, :discrepancies, :error, keyword_init: true) do
      def success? = success
    end

    COMPARISON_RULES = {
      "processors.*.serial" => :critical,
      "processors.*.cores" => :critical,
      "processors.*.model" => :warning,
      "memory.*.serial" => :critical,
      "memory.*.size_gb" => :warning,
      "memory.*.slot" => :info,
      "storage.*.serial" => :critical,
      "storage.*.capacity" => :warning,
      "bios.version" => :warning,
      "bios.vendor" => :info
    }.freeze

    def self.call(node)
      new(node).call
    end

    def initialize(node)
      @node = node
    end

    def call
      inband = @node.node_states.order(captured_at: :desc).first
      bmc = @node.latest_bmc_inventory

      return Result.new(success: true, discrepancies: []) unless inband && bmc

      discrepancies = compare(inband, bmc)
      saved_discrepancies = save_discrepancies(discrepancies)
      resolve_fixed_discrepancies(discrepancies)

      Result.new(success: true, discrepancies: saved_discrepancies)
    rescue StandardError => e
      Result.new(success: false, error: e.message)
    end

    private

    def compare(inband, bmc)
      discrepancies = []

      COMPARISON_RULES.each do |path, severity|
        inband_values = extract_values(inband, path)
        bmc_values = extract_values_from_bmc(bmc, path)

        # Compare values - focus on matching by position/index for arrays
        differences = find_differences(path, inband_values, bmc_values, severity)
        discrepancies.concat(differences)
      end

      discrepancies
    end

    def extract_values(inband, path)
      parts = path.split(".")
      data = case parts.first
      when "processors" then inband.cpu_info || {}
      when "memory" then (inband.dmi_info || {})["memory"] || []
      when "storage" then inband.disk_info || []
      when "bios" then (inband.dmi_info || {})["bios"] || {}
      else {}
      end

      navigate_inband_path(data, parts)
    end

    def extract_values_from_bmc(bmc, path)
      parts = path.split(".")
      data = case parts.first
      when "processors" then bmc.processors || []
      when "memory" then bmc.memory || []
      when "storage" then bmc.storage || []
      when "bios" then bmc.bios || {}
      else {}
      end

      navigate_path(data, parts)
    end

    def navigate_inband_path(data, parts)
      # Navigate through path for inband data
      # Inband data has different structure:
      # - cpu_info is a hash with direct values like { "cores" => 20, "model" => "Intel" }
      # - dmi_info["memory"] is an array with serial_number key (not serial)
      # - dmi_info["bios"] is a hash with direct values
      current = data
      remaining_parts = parts[1..]

      # Handle wildcard for arrays
      if remaining_parts.first == "*"
        if current.is_a?(Array)
          field = remaining_parts[1]
          # Map field names from BMC convention to inband convention
          inband_field = map_inband_field(parts.first, field)
          return current.map { |item| item[inband_field] || item[inband_field.to_sym] }.compact
        elsif current.is_a?(Hash)
          # For cpu_info which is a single hash, extract the field directly
          field = remaining_parts[1]
          inband_field = map_inband_field(parts.first, field)
          value = current[inband_field] || current[inband_field.to_sym]
          return Array(value).compact
        end
        return []
      end

      # Non-wildcard path (like "bios.version")
      remaining_parts.each do |part|
        break unless current.is_a?(Hash)

        current = current[part] || current[part.to_sym]
      end
      Array(current).compact
    end

    def map_inband_field(category, field)
      # Map BMC field names to inband field names where they differ
      case [ category, field ]
      when [ "memory", "serial" ]
        "serial_number"
      else
        field
      end
    end

    def navigate_path(data, parts)
      # Navigate through path like "processors.*.serial" for BMC data (arrays)
      current = data
      parts[1..].each do |part|
        if part == "*"
          # Wildcard - collect from all array elements
          return [] unless current.is_a?(Array)
          # Continue with next part on each element
        elsif current.is_a?(Array)
          current = current.map { |item| item[part] || item[part.to_sym] }.compact
        elsif current.is_a?(Hash)
          current = current[part] || current[part.to_sym]
        end
      end
      Array(current)
    end

    def find_differences(path, inband_values, bmc_values, severity)
      differences = []

      # Simple comparison - check if values match
      inband_set = Set.new(inband_values.map(&:to_s).reject(&:blank?))
      bmc_set = Set.new(bmc_values.map(&:to_s).reject(&:blank?))

      # Values in BMC but not in inband
      (bmc_set - inband_set).each do |value|
        differences << {
          field_path: path,
          inband_value: nil,
          bmc_value: value,
          severity: severity
        }
      end

      # Values in inband but not in BMC
      (inband_set - bmc_set).each do |value|
        differences << {
          field_path: path,
          inband_value: value,
          bmc_value: nil,
          severity: severity
        }
      end

      differences
    end

    def save_discrepancies(discrepancies)
      discrepancies.map do |d|
        existing = @node.inventory_discrepancies.unresolved.find_by(
          field_path: d[:field_path],
          inband_value: d[:inband_value],
          bmc_value: d[:bmc_value]
        )

        next existing if existing

        @node.inventory_discrepancies.create!(
          field_path: d[:field_path],
          inband_value: d[:inband_value],
          bmc_value: d[:bmc_value],
          severity: d[:severity]
        )
      end.compact
    end

    def resolve_fixed_discrepancies(current_discrepancies)
      # Find discrepancies that no longer exist and resolve them
      current_keys = current_discrepancies.map do |d|
        [ d[:field_path], d[:inband_value], d[:bmc_value] ]
      end

      @node.inventory_discrepancies.unresolved.find_each do |disc|
        key = [ disc.field_path, disc.inband_value, disc.bmc_value ]
        unless current_keys.include?(key)
          disc.update!(resolved_at: Time.current, resolution_note: "Auto-resolved: values now match")
        end
      end
    end
  end
end
