# frozen_string_literal: true

require "digest"
require "json"

module Inventory
  class ProcessStateService
    Result = Struct.new(:success, :state_created, :node_state, :error, keyword_init: true) do
      def success?
        success
      end
    end

    def initialize(node_id: nil, hostname: nil, raw_json:)
      @node_id = node_id
      @hostname = hostname
      @raw_json = raw_json&.with_indifferent_access
    end

    def call
      return error_result("Raw JSON is empty") if @raw_json.nil?

      node = find_node
      return error_result("Node not found") unless node

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
        cpu_info: @raw_json[:cpu_info] || {},
        mem_info: @raw_json[:mem_info] || {},
        disk_info: @raw_json[:disk_info] || [],
        net_info: @raw_json[:net_info] || []
      }
    end

    def state_changed?(current_state, new_data)
      return true if current_state.nil?

      # Compare content hashes directly
      new_content_hash = compute_content_hash(new_data)
      current_state.content_hash != new_content_hash
    end

    def compute_content_hash(data)
      content = {
        cpu_info: deep_sort_keys(data[:cpu_info] || {}),
        mem_info: deep_sort_keys(data[:mem_info] || {}),
        disk_info: deep_sort_keys(data[:disk_info] || []),
        net_info: deep_sort_keys(data[:net_info] || [])
      }
      Digest::SHA256.hexdigest(JSON.generate(content))
    end

    # Recursively sort hash keys to ensure consistent JSON output
    def deep_sort_keys(obj)
      case obj
      when Hash
        obj.sort.to_h.transform_values { |v| deep_sort_keys(v) }
      when Array
        obj.map { |item| deep_sort_keys(item) }
      else
        obj
      end
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
      error_result("Failed to create NodeState: #{e.message}")
    end

    def touch_node(node, current_state)
      node.touch_last_seen

      Result.new(
        success: true,
        state_created: false,
        node_state: current_state
      )
    end

    def error_result(message)
      Result.new(
        success: false,
        state_created: false,
        node_state: nil,
        error: message
      )
    end
  end
end
