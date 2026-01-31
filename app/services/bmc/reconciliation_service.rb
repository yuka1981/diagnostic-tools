# frozen_string_literal: true

module Bmc
  class ReconciliationService
    SEVERITY_MAP = {
      "serial" => :critical,
      "cores_physical" => :critical,
      "cores" => :critical,
      "model" => :warning,
      "version" => :warning,
      "speed_mhz" => :warning,
      "size_gb" => :warning
    }.freeze

    def initialize(node)
      @node = node
    end

    def call
      latest_bmc = @node.bmc_inventories.order(captured_at: :desc).first
      latest_state = @node.node_states.order(created_at: :desc).first

      return { compared: false, reason: "missing data" } unless latest_bmc && latest_state

      current_discrepancies = compare(latest_state, latest_bmc)

      # Auto-resolve discrepancies that no longer exist
      @node.inventory_discrepancies.unresolved.each do |disc|
        unless current_discrepancies.any? { |d| d[:field_path] == disc.field_path }
          disc.resolve!(note: "Auto-resolved: values now match")
        end
      end

      # Create new discrepancies
      current_discrepancies.each do |disc|
        next if @node.inventory_discrepancies.unresolved.exists?(field_path: disc[:field_path])

        @node.inventory_discrepancies.create!(disc)
      end

      { compared: true, discrepancies: current_discrepancies.size }
    end

    private

    def compare(state, bmc)
      discrepancies = []

      # Compare processor core count
      # In-band cpu_info reports per-socket cores; multiply by sockets for total
      state_cores_per_socket = state.cpu_info&.dig("cores")
      state_sockets = state.cpu_info&.dig("sockets") || 1
      state_total_cores = state_cores_per_socket.to_i * state_sockets.to_i if state_cores_per_socket
      bmc_total_cores = bmc.processors&.sum { |p| p["cores_physical"].to_i }

      if state_total_cores && bmc_total_cores && state_total_cores != bmc_total_cores
        discrepancies << {
          field_path: "processors.0.cores_physical",
          inband_value: state_total_cores.to_s,
          bmc_value: bmc_total_cores.to_s,
          severity: severity_for("cores_physical")
        }
      end

      # Compare processor model
      state_model = state.cpu_info&.dig("model")
      bmc_model = bmc.processors&.first&.dig("model")

      if state_model && bmc_model && state_model != bmc_model
        discrepancies << {
          field_path: "processors.0.model",
          inband_value: state_model,
          bmc_value: bmc_model,
          severity: severity_for("model")
        }
      end

      discrepancies
    end

    def severity_for(field_name)
      SEVERITY_MAP.fetch(field_name, :info)
    end
  end
end
