# frozen_string_literal: true

module Racks
  class UpdateLayoutService
    Result = Struct.new(:success?, :errors, keyword_init: true)

    def initialize(rack, positions)
      @rack = rack
      @positions = positions || []
    end

    def call
      validation = ValidateLayoutService.new(@rack, @positions).call
      return Result.new(success?: false, errors: validation.errors) unless validation.success?

      ActiveRecord::Base.transaction do
        @positions.each do |pos|
          node = Node.find(pos["node_id"])

          if pos["rack_position"].nil?
            # Unrack
            node.update!(rack_id: nil, rack_position: nil)
          else
            # Assign/move
            node.update!(
              rack_id: @rack.id,
              rack_position: pos["rack_position"],
              rack_height: pos["rack_height"] || node.rack_height || 1
            )
          end
        end
      end

      Result.new(success?: true, errors: [])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, errors: [ e.message ])
    end
  end
end
