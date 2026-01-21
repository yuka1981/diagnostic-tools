# frozen_string_literal: true

require "rails_helper"

RSpec.describe Racks::ValidateLayoutService do
  let(:site) { create(:site) }
  let(:room) { create(:room, site: site) }
  let(:server_rack) { create(:server_rack, room: room, u_height: 10) }

  describe "#call" do
    context "with valid positions" do
      let(:node1) { create(:node) }
      let(:node2) { create(:node) }
      let(:positions) do
        [
          { "node_id" => node1.id, "rack_position" => 1, "rack_height" => 2 },
          { "node_id" => node2.id, "rack_position" => 5, "rack_height" => 1 }
        ]
      end

      it "returns success" do
        result = described_class.new(server_rack, positions).call
        expect(result).to be_success
      end
    end

    context "with overlapping positions" do
      let(:node1) { create(:node) }
      let(:node2) { create(:node) }
      let(:positions) do
        [
          { "node_id" => node1.id, "rack_position" => 1, "rack_height" => 3 },
          { "node_id" => node2.id, "rack_position" => 2, "rack_height" => 1 }
        ]
      end

      it "returns failure" do
        result = described_class.new(server_rack, positions).call
        expect(result).not_to be_success
      end

      it "includes overlap error" do
        result = described_class.new(server_rack, positions).call
        expect(result.errors).to include(/overlaps/)
      end
    end

    context "with position out of bounds" do
      let(:node) { create(:node) }
      let(:positions) do
        [ { "node_id" => node.id, "rack_position" => 11, "rack_height" => 1 } ]
      end

      it "returns failure" do
        result = described_class.new(server_rack, positions).call
        expect(result).not_to be_success
      end
    end

    context "with node extending beyond rack height" do
      let(:node) { create(:node) }
      let(:positions) do
        [ { "node_id" => node.id, "rack_position" => 9, "rack_height" => 3 } ]
      end

      it "returns failure" do
        result = described_class.new(server_rack, positions).call
        expect(result).not_to be_success
      end
    end

    context "with null position (unracking)" do
      let(:node) { create(:node, server_rack: server_rack, rack_position: 1, rack_height: 1) }
      let(:positions) do
        [ { "node_id" => node.id, "rack_position" => nil } ]
      end

      it "returns success" do
        result = described_class.new(server_rack, positions).call
        expect(result).to be_success
      end
    end

    context "with non-existent node" do
      let(:positions) do
        [ { "node_id" => 99999, "rack_position" => 1, "rack_height" => 1 } ]
      end

      it "returns failure" do
        result = described_class.new(server_rack, positions).call
        expect(result).not_to be_success
      end
    end
  end
end
