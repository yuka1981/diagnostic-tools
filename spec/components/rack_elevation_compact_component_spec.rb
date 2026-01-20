# frozen_string_literal: true

require "rails_helper"

RSpec.describe RackElevationCompactComponent, type: :component do
  let(:rack) { create(:equipment_rack, u_height: 42) }

  describe "#elevation_cells" do
    context "with empty rack" do
      it "returns all empty cells" do
        component = described_class.new(rack: rack)
        cells = component.elevation_cells

        expect(cells.length).to eq(42)
        expect(cells.all? { |c| c[:type] == :empty }).to be true
      end
    end

    context "with single-U nodes" do
      let!(:node1) { create(:node, rack: rack, rack_position: 1, rack_height: 1, rack_face: :front) }
      let!(:node2) { create(:node, rack: rack, rack_position: 10, rack_height: 1, rack_face: :front) }

      it "returns correct cells for front face" do
        component = described_class.new(rack: rack)
        cells = component.elevation_cells

        node_cells = cells.select { |c| c[:type] == :node }
        expect(node_cells.length).to eq(2)
        expect(node_cells.map { |c| c[:node].hostname }).to contain_exactly(node1.hostname, node2.hostname)
      end
    end

    context "with multi-U node" do
      let!(:node) { create(:node, rack: rack, rack_position: 5, rack_height: 4, rack_face: :front) }

      it "returns single merged cell for multi-U node" do
        component = described_class.new(rack: rack)
        cells = component.elevation_cells

        node_cells = cells.select { |c| c[:type] == :node }
        expect(node_cells.length).to eq(1)

        cell = node_cells.first
        expect(cell[:height]).to eq(4)
        expect(cell[:node]).to eq(node)
      end

      it "has correct number of empty cells" do
        component = described_class.new(rack: rack)
        cells = component.elevation_cells

        empty_cells = cells.select { |c| c[:type] == :empty }
        # 42 total - 4 occupied = 38 empty
        expect(empty_cells.length).to eq(38)
      end
    end
  end

  describe "#labeled_u_positions" do
    it "returns positions every 10 U for 42U rack" do
      component = described_class.new(rack: rack)
      expect(component.labeled_u_positions).to eq([ 10, 20, 30, 40 ])
    end

    it "returns positions every 10 U for smaller rack" do
      small_rack = create(:equipment_rack, :small) # 12U
      component = described_class.new(rack: small_rack)
      expect(component.labeled_u_positions).to eq([ 10 ])
    end

    it "returns empty array for very small rack" do
      tiny_rack = create(:equipment_rack, u_height: 8)
      component = described_class.new(rack: tiny_rack)
      expect(component.labeled_u_positions).to eq([])
    end
  end

  describe "#cell_height_style" do
    let(:component) { described_class.new(rack: rack) }

    it "calculates correct height for single U (12px)" do
      expect(component.cell_height_style(1)).to eq("height: 12px;")
    end

    it "calculates correct height for multi-U" do
      expect(component.cell_height_style(4)).to eq("height: 48px;")
    end
  end

  describe "#total_height_style" do
    it "calculates correct total height for 42U rack (504px)" do
      component = described_class.new(rack: rack)
      expect(component.total_height_style).to eq("height: 504px;")
    end

    it "calculates correct total height for smaller rack" do
      small_rack = create(:equipment_rack, :small) # 12U
      component = described_class.new(rack: small_rack)
      expect(component.total_height_style).to eq("height: 144px;")
    end
  end

  describe "#rack_width" do
    it "returns 150px" do
      component = described_class.new(rack: rack)
      expect(component.rack_width).to eq("150px")
    end
  end

  describe "#node_status_classes" do
    let(:component) { described_class.new(rack: rack) }

    context "with online node" do
      let(:node) { create(:node, last_heartbeat_at: 1.minute.ago) }

      it "returns emerald-600 background" do
        classes = component.node_status_classes(node)
        expect(classes).to include("bg-emerald-600")
        expect(classes).to include("text-white")
      end
    end

    context "with offline node" do
      let(:node) { create(:node, last_heartbeat_at: 10.minutes.ago) }

      it "returns slate-600 background" do
        classes = component.node_status_classes(node)
        expect(classes).to include("bg-slate-600")
        expect(classes).to include("text-white")
      end
    end

    context "with never-seen node" do
      let(:node) { create(:node, last_heartbeat_at: nil) }

      it "returns slate-600 background" do
        classes = component.node_status_classes(node)
        expect(classes).to include("bg-slate-600")
      end
    end
  end

  describe "rendering" do
    let!(:node) { create(:node, rack: rack, rack_position: 1, rack_height: 2, rack_face: :front, last_heartbeat_at: 1.minute.ago) }

    it "renders the component" do
      render_inline(described_class.new(rack: rack))

      expect(page).to have_css("div.bg-white")
    end

    it "renders rack name" do
      render_inline(described_class.new(rack: rack))

      expect(page).to have_text(rack.name)
    end

    it "renders link to rack page" do
      render_inline(described_class.new(rack: rack))

      expect(page).to have_link(href: "/racks/#{rack.id}")
    end

    it "renders node hostname" do
      render_inline(described_class.new(rack: rack))

      expect(page).to have_text(node.hostname)
    end

    it "renders with compact width style" do
      render_inline(described_class.new(rack: rack))

      expect(page).to have_css("[style*='width: 150px']")
    end

    it "renders empty slots with bg-slate-100 background" do
      render_inline(described_class.new(rack: rack))

      expect(page).to have_css(".bg-slate-100")
    end

    it "renders node hostname with text-shadow style" do
      render_inline(described_class.new(rack: rack))

      expect(page).to have_css("span.truncate[style*='text-shadow']")
    end
  end
end
