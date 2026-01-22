# frozen_string_literal: true

module Nodes
  class BulkCreateService
    Result = Struct.new(:success, :nodes, :conflicts, :error, keyword_init: true) do
      def success?
        success
      end
    end

    # Pattern regex: matches text like "compute-[001-003]" or "node-[1-5]-gpu"
    PATTERN_REGEX = /\A([^\[\]]*)\[(\d+)-(\d+)\]([^\[\]]*)\z/

    # @param pattern [String] hostname pattern with range, e.g., "compute-[001-003]"
    # @param base_params [Hash] parameters to apply to all created nodes
    # @param overrides [Hash] per-hostname overrides, keyed by hostname
    def initialize(pattern, base_params, overrides = {})
      @pattern = pattern.to_s
      @base_params = base_params || {}
      @overrides = overrides || {}
    end

    def call
      parsed = parse_pattern
      return parsed if parsed.is_a?(Result)

      prefix, range_start, range_end, suffix, padding = parsed

      hostnames = generate_hostnames(prefix, range_start, range_end, suffix, padding)

      conflicts = find_conflicts(hostnames)
      return failure_result(conflicts: conflicts) if conflicts.any?

      create_nodes(hostnames)
    end

    private

    def parse_pattern
      return error_result("Invalid pattern: pattern cannot be empty") if @pattern.blank?

      match = PATTERN_REGEX.match(@pattern)
      return error_result("Invalid pattern: must contain a [N-M] range") unless match

      prefix = match[1]
      start_str = match[2]
      end_str = match[3]
      suffix = match[4]

      range_start = start_str.to_i
      range_end = end_str.to_i

      return error_result("Invalid range: start (#{range_start}) must be <= end (#{range_end})") if range_start > range_end

      # Determine padding width (e.g., "001" has padding 3, "1" has padding 0)
      padding = start_str.length

      [ prefix, range_start, range_end, suffix, padding ]
    end

    def generate_hostnames(prefix, range_start, range_end, suffix, padding)
      (range_start..range_end).map do |n|
        formatted_number = padding > 1 ? n.to_s.rjust(padding, "0") : n.to_s
        "#{prefix}#{formatted_number}#{suffix}"
      end
    end

    def find_conflicts(hostnames)
      Node.where(hostname: hostnames).pluck(:hostname)
    end

    def create_nodes(hostnames)
      created_nodes = []

      Node.transaction do
        hostnames.each do |hostname|
          node_params = @base_params.merge(hostname: hostname)

          # Apply per-node overrides if present
          if @overrides.key?(hostname)
            node_params = node_params.merge(@overrides[hostname])
          end

          node = Node.new(node_params)
          unless node.save
            raise ActiveRecord::Rollback, node.errors.full_messages.join(", ")
          end
          created_nodes << node
        end
      end

      if created_nodes.size == hostnames.size
        success_result(created_nodes)
      else
        # Transaction was rolled back
        error_result("Failed to create nodes: validation errors occurred")
      end
    end

    def success_result(nodes)
      Result.new(
        success: true,
        nodes: nodes,
        conflicts: [],
        error: nil
      )
    end

    def failure_result(conflicts:)
      Result.new(
        success: false,
        nodes: [],
        conflicts: conflicts,
        error: nil
      )
    end

    def error_result(message)
      Result.new(
        success: false,
        nodes: [],
        conflicts: [],
        error: message
      )
    end
  end
end
