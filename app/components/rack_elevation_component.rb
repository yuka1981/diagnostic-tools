# frozen_string_literal: true

# RackElevationComponent renders a visual rack elevation diagram
# showing nodes positioned in U slots (NetBox-style merged cells)
class RackElevationComponent < ViewComponent::Base
  # Height in pixels per U slot
  U_HEIGHT_PX = 22

  def initialize(rack:, face: :front)
    @rack = rack
    @face = face.to_sym
  end

  # Returns elevation cells grouped by node for merged cell rendering
  # Each cell represents either:
  # - An empty U slot
  # - A multi-U node spanning its full height (single merged cell)
  def elevation_cells
    cells = []
    elevation = @rack.elevation_data(face: @face)
    processed_nodes = Set.new

    elevation.each do |unit_data|
      node = unit_data[:node]
      u_position = unit_data[:u]

      if node.nil?
        # Empty slot
        cells << { type: :empty, u: u_position, height: 1 }
      elsif !processed_nodes.include?(node.id)
        # First U of this node - create merged cell
        processed_nodes.add(node.id)
        cells << {
          type: :node,
          u: u_position,
          node: node,
          height: node.rack_height,
          top_u: node.rack_position + node.rack_height - 1
        }
      end
      # Skip subsequent U positions of already-processed nodes
    end

    cells
  end

  def rack_height
    @rack.u_height
  end

  def current_face
    @face
  end

  def opposite_face
    @face == :front ? :rear : :front
  end

  def face_label
    @face.to_s.capitalize
  end

  def node_status_classes(node)
    if node.online?
      "bg-emerald-500 hover:bg-emerald-600 text-white"
    else
      "bg-slate-400 hover:bg-slate-500 text-white"
    end
  end

  def cell_height_style(height)
    "height: #{height * U_HEIGHT_PX}px;"
  end

  def total_height_style
    "height: #{@rack.u_height * U_HEIGHT_PX}px;"
  end
end
