# frozen_string_literal: true

require "rails_helper"

RSpec.describe RackElevationComponent, type: :component do
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
        component = described_class.new(rack: rack, face: :front)
        cells = component.elevation_cells

        node_cells = cells.select { |c| c[:type] == :node }
        expect(node_cells.length).to eq(2)
        expect(node_cells.map { |c| c[:node].hostname }).to contain_exactly(node1.hostname, node2.hostname)
      end
    end

    context "with multi-U node" do
      let!(:node) { create(:node, rack: rack, rack_position: 5, rack_height: 4, rack_face: :front) }

      it "returns single merged cell for multi-U node" do
        component = described_class.new(rack: rack, face: :front)
        cells = component.elevation_cells

        node_cells = cells.select { |c| c[:type] == :node }
        expect(node_cells.length).to eq(1)

        cell = node_cells.first
        expect(cell[:height]).to eq(4)
        expect(cell[:node]).to eq(node)
      end

      it "has correct number of empty cells" do
        component = described_class.new(rack: rack, face: :front)
        cells = component.elevation_cells

        empty_cells = cells.select { |c| c[:type] == :empty }
        # 42 total - 4 occupied = 38 empty
        expect(empty_cells.length).to eq(38)
      end
    end

    context "with front and rear nodes" do
      let!(:front_node) { create(:node, rack: rack, rack_position: 1, rack_height: 2, rack_face: :front) }
      let!(:rear_node) { create(:node, rack: rack, rack_position: 1, rack_height: 2, rack_face: :rear) }

      it "shows only front nodes for front face" do
        component = described_class.new(rack: rack, face: :front)
        cells = component.elevation_cells

        node_cells = cells.select { |c| c[:type] == :node }
        expect(node_cells.length).to eq(1)
        expect(node_cells.first[:node]).to eq(front_node)
      end

      it "shows only rear nodes for rear face" do
        component = described_class.new(rack: rack, face: :rear)
        cells = component.elevation_cells

        node_cells = cells.select { |c| c[:type] == :node }
        expect(node_cells.length).to eq(1)
        expect(node_cells.first[:node]).to eq(rear_node)
      end
    end
  end

  describe "#node_status_classes" do
    let(:component) { described_class.new(rack: rack) }

    context "with online node" do
      let(:node) { create(:node, last_heartbeat_at: 1.minute.ago) }

      it "returns emerald-600 background with hover state" do
        classes = component.node_status_classes(node)
        expect(classes).to include("bg-emerald-600")
        expect(classes).to include("hover:bg-emerald-700")
        expect(classes).to include("text-white")
      end
    end

    context "with offline node" do
      let(:node) { create(:node, last_heartbeat_at: 10.minutes.ago) }

      it "returns slate-600 background with hover state" do
        classes = component.node_status_classes(node)
        expect(classes).to include("bg-slate-600")
        expect(classes).to include("hover:bg-slate-700")
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

  describe "#current_face and #opposite_face" do
    it "returns correct values for front face" do
      component = described_class.new(rack: rack, face: :front)
      expect(component.current_face).to eq(:front)
      expect(component.opposite_face).to eq(:rear)
    end

    it "returns correct values for rear face" do
      component = described_class.new(rack: rack, face: :rear)
      expect(component.current_face).to eq(:rear)
      expect(component.opposite_face).to eq(:front)
    end

    it "handles string face parameter" do
      component = described_class.new(rack: rack, face: "front")
      expect(component.current_face).to eq(:front)
    end
  end

  describe "#cell_height_style" do
    let(:component) { described_class.new(rack: rack) }

    it "calculates correct height for single U" do
      expect(component.cell_height_style(1)).to eq("height: 22px;")
    end

    it "calculates correct height for multi-U" do
      expect(component.cell_height_style(4)).to eq("height: 88px;")
    end
  end

  describe "#total_height_style" do
    it "calculates correct total height for 42U rack" do
      component = described_class.new(rack: rack)
      expect(component.total_height_style).to eq("height: 924px;")
    end

    it "calculates correct total height for smaller rack" do
      small_rack = create(:equipment_rack, :small) # 12U
      component = described_class.new(rack: small_rack)
      expect(component.total_height_style).to eq("height: 264px;")
    end
  end

  describe "rendering" do
    let!(:node) { create(:node, rack: rack, rack_position: 1, rack_height: 2, rack_face: :front, last_heartbeat_at: 1.minute.ago) }

    it "renders the component" do
      render_inline(described_class.new(rack: rack))

      expect(page).to have_css("[data-controller='rack-elevation']")
      expect(page).to have_text("Rack Elevation")
    end

    it "renders front/rear toggle" do
      render_inline(described_class.new(rack: rack, face: :front))

      expect(page).to have_text("Front")
      expect(page).to have_text("Rear")
    end

    it "renders node hostname" do
      render_inline(described_class.new(rack: rack, face: :front))

      expect(page).to have_text(node.hostname)
    end

    it "renders legend" do
      render_inline(described_class.new(rack: rack))

      expect(page).to have_text("Online")
      expect(page).to have_text("Offline")
      expect(page).to have_text("Empty")
    end

    it "renders turbo frame" do
      render_inline(described_class.new(rack: rack))

      expect(page).to have_css("turbo-frame#rack_elevation_#{rack.id}")
    end

    it "includes link to node page" do
      render_inline(described_class.new(rack: rack, face: :front))

      expect(page).to have_link(href: "/nodes/#{node.id}")
    end

    it "renders empty slots with bg-slate-100 background" do
      render_inline(described_class.new(rack: rack, face: :front))

      expect(page).to have_css(".bg-slate-100")
    end

    it "renders node hostname with text-shadow style" do
      render_inline(described_class.new(rack: rack, face: :front))

      expect(page).to have_css("span.truncate[style*='text-shadow']")
    end
  end
end
