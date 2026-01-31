# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Nodes::Discrepancies", type: :request do
  let(:user) { create(:user, :approver) }
  let(:node) { create(:node) }
  let!(:discrepancy) { create(:inventory_discrepancy, node: node) }

  before { sign_in user }

  describe "PATCH /nodes/:node_id/discrepancies/:id/resolve" do
    it "resolves the discrepancy" do
      patch resolve_node_discrepancy_path(node, discrepancy), params: {
        resolution_note: "Verified correct in person"
      }
      expect(discrepancy.reload).to be_resolved
      expect(discrepancy.resolution_note).to eq("Verified correct in person")
    end
  end
end
