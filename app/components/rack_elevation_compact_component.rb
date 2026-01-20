# frozen_string_literal: true

# RackElevationCompactComponent renders a compact rack elevation diagram
# for use in room overview pages (smaller than the full RackElevationComponent)
class RackElevationCompactComponent < ViewComponent::Base
  # Compact height: 12px per U (vs 22px in full-size)
  U_HEIGHT_PX = 12

  def initialize(rack:)
    @rack = rack
  end

  # Returns elevation cells grouped by node for merged cell rendering
  # Each cell represents either:
  # - An empty U slot
  # - A multi-U node spanning its full height (single merged cell)
  def elevation_cells
    cells = []
    elevation = @rack.elevation_data(face: :front)
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

  def rack_name
    @rack.name
  end

  def rack_id
    @rack.id
  end

  # Returns U positions that should have labels (every 10 U)
  def labeled_u_positions
    (10..@rack.u_height).step(10).to_a
  end

  def node_status_classes(node)
    if node.online?
      "bg-emerald-600 text-white"
    else
      "bg-slate-600 text-white"
    end
  end

  def cell_height_style(height)
    "height: #{height * U_HEIGHT_PX}px;"
  end

  def total_height_style
    "height: #{@rack.u_height * U_HEIGHT_PX}px;"
  end

  # Compact width is 150px (vs 260px full-size)
  def rack_width
    "150px"
  end

  # Returns data attributes hash for node preview hover card
  def node_preview_data(node)
    {
      controller: "node-preview",
      node_preview_hostname_value: node.hostname,
      node_preview_position_value: "U#{node.rack_position}-U#{node.rack_position + node.rack_height - 1}",
      node_preview_height_value: "#{node.rack_height}U",
      node_preview_cpu_value: node.cpu_summary,
      node_preview_ram_value: node.ram_summary,
      node_preview_url_value: Rails.application.routes.url_helpers.node_path(node),
      action: "mouseenter->node-preview#mouseEnter mouseleave->node-preview#mouseLeave click->node-preview#click"
    }
  end
end
