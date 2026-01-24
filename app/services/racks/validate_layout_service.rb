# frozen_string_literal: true

module Racks
  class ValidateLayoutService
    include RangeOverlap

    Result = Struct.new(:success?, :errors, keyword_init: true)

    def initialize(rack, positions)
      @rack = rack
      @positions = positions || []
      @errors = []
    end

    def call
      validate_positions
      Result.new(success?: @errors.empty?, errors: @errors)
    end

    private

    def validate_positions
      planned_placements = []

      @positions.each do |pos|
        node_id = pos["node_id"]
        rack_position = pos["rack_position"]
        rack_height = pos["rack_height"] || 1

        # Skip unracking operations
        next if rack_position.nil?

        # Validate node exists
        node = Node.find_by(id: node_id)
        unless node
          @errors << "Node #{node_id} not found"
          next
        end

        # Validate position bounds
        if rack_position < 1
          @errors << "#{node.hostname}: position must be at least 1"
          next
        end

        if rack_position > @rack.u_height
          @errors << "#{node.hostname}: position #{rack_position} exceeds rack height #{@rack.u_height}"
          next
        end

        node_top = rack_position + rack_height - 1
        if node_top > @rack.u_height
          @errors << "#{node.hostname}: extends beyond rack height (position #{rack_position} + height #{rack_height} = #{node_top + 1})"
          next
        end

        # Check for overlaps with other planned placements
        planned_placements.each do |other|
          if ranges_overlap?(rack_position, node_top, other[:position], other[:top])
            @errors << "#{node.hostname} overlaps with #{other[:hostname]}"
          end
        end

        planned_placements << {
          node_id: node_id,
          hostname: node.hostname,
          position: rack_position,
          top: node_top
        }
      end
    end
  end
end
