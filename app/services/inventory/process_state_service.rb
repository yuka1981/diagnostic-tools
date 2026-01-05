# frozen_string_literal: true

module Inventory
  class ProcessStateService
    # Error codes for proper error classification
    ERROR_CODES = {
      not_found: :not_found,
      bad_request: :bad_request,
      internal_error: :internal_error
    }.freeze

    Result = Struct.new(:success, :state_created, :node_state, :error, :error_code, keyword_init: true) do
      def success?
        success
      end

      def not_found?
        error_code == :not_found
      end
    end

    def initialize(node_id: nil, hostname: nil, raw_json:)
      raise ArgumentError, "Either node_id or hostname must be provided" if node_id.blank? && hostname.blank?

      @node_id = node_id
      @hostname = hostname
      @raw_json = raw_json&.with_indifferent_access
    end

    def call
      return error_result("Raw JSON is empty", :bad_request) if @raw_json.nil?

      node = find_node
      return error_result("Node not found", :not_found) unless node

      process_state(node)
    end

    private

    def find_node
      if @node_id.present?
        Node.find_by(id: @node_id)
      elsif @hostname.present?
        Node.find_by(hostname: @hostname)
      end
    end

    def process_state(node)
      current_state = node.current_state
      new_state_data = build_state_data

      if state_changed?(current_state, new_state_data)
        create_new_state(node, new_state_data)
      else
        touch_node(node, current_state)
      end
    end

    def build_state_data
      {
        host_info: @raw_json[:host] || {},
        cpu_info: @raw_json[:cpu] || {},
        mem_info: @raw_json[:memory] || {},
        disk_info: @raw_json[:disks] || [],
        net_info: @raw_json[:network] || []
      }
    end

    def state_changed?(current_state, new_data)
      return true if current_state.nil?

      # Build a temporary NodeState object to calculate hash consistently
      # This leverages the model's content_hash logic (DRY principle)
      temp_state = NodeState.new(new_data)
      current_state.content_hash != temp_state.content_hash
    end

    def create_new_state(node, state_data)
      node_state = node.node_states.create!(
        **state_data,
        captured_at: Time.current
      )

      node.touch_last_seen

      Result.new(
        success: true,
        state_created: true,
        node_state: node_state
      )
    rescue ActiveRecord::RecordInvalid => e
      error_result("Failed to create NodeState: #{e.message}", :internal_error)
    end

    def touch_node(node, current_state)
      node.touch_last_seen

      Result.new(
        success: true,
        state_created: false,
        node_state: current_state
      )
    end

    def error_result(message, code = :bad_request)
      Result.new(
        success: false,
        state_created: false,
        node_state: nil,
        error: message,
        error_code: code
      )
    end
  end
end
