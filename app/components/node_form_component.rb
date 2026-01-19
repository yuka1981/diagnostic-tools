# frozen_string_literal: true

class NodeFormComponent < ViewComponent::Base
  def initialize(node:, api_keys: [], racks: [])
    @node = node
    @api_keys = api_keys
    @racks = racks
  end

  private

  # Returns rack options formatted as "Room Name - Rack Name" or "Unassigned - Rack Name"
  def rack_options
    @racks.map do |rack|
      room_name = rack.room&.name || "Unassigned"
      [ "#{room_name} - #{rack.name}", rack.id ]
    end
  end
end
