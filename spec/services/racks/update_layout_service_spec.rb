# frozen_string_literal: true

require "rails_helper"

RSpec.describe Racks::UpdateLayoutService do
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

      it "updates node positions" do
        described_class.new(server_rack, positions).call
        expect(node1.reload.rack_position).to eq(1)
        expect(node1.rack_height).to eq(2)
        expect(node1.rack_id).to eq(server_rack.id)
      end
    end

    context "with invalid positions" do
      let(:node) { create(:node) }
      let(:positions) do
        [ { "node_id" => node.id, "rack_position" => 20, "rack_height" => 1 } ]
      end

      it "returns failure" do
        result = described_class.new(server_rack, positions).call
        expect(result).not_to be_success
      end

      it "does not update nodes" do
        original_position = node.rack_position
        described_class.new(server_rack, positions).call
        expect(node.reload.rack_position).to eq(original_position)
      end
    end

    context "unracking a node" do
      let(:node) { create(:node, server_rack: server_rack, rack_position: 1, rack_height: 1) }
      let(:positions) do
        [ { "node_id" => node.id, "rack_position" => nil } ]
      end

      it "removes rack assignment" do
        described_class.new(server_rack, positions).call
        expect(node.reload.rack_id).to be_nil
        expect(node.rack_position).to be_nil
      end
    end
  end
end
