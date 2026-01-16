# frozen_string_literal: true

require "rails_helper"

RSpec.describe NodeLogChannel, type: :channel do
  let(:node) { create(:node) }
  let(:approver_user) { create(:user, :approver) }
  let(:regular_user) { create(:user) }

  before do
    stub_connection current_user: current_user
  end

  describe "#subscribed" do
    context "with approver user" do
      let(:current_user) { approver_user }

      it "subscribes to the node logs stream" do
        subscribe(node_id: node.id)
        expect(subscription).to be_confirmed
        expect(subscription).to have_stream_from("node_logs_#{node.id}")
      end
    end

    context "with regular user" do
      let(:current_user) { regular_user }

      it "rejects the subscription" do
        subscribe(node_id: node.id)
        expect(subscription).to be_rejected
      end
    end

    context "without user" do
      let(:current_user) { nil }

      it "rejects the subscription" do
        subscribe(node_id: node.id)
        expect(subscription).to be_rejected
      end
    end

    context "with invalid node_id" do
      let(:current_user) { approver_user }

      it "rejects the subscription" do
        subscribe(node_id: -1)
        expect(subscription).to be_rejected
      end
    end
  end
end
