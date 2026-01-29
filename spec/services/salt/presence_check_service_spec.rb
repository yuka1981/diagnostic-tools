require "rails_helper"

RSpec.describe Salt::PresenceCheckService do
  let(:salt_client) { instance_double(SaltApiClient) }
  let(:service) { described_class.new(salt_client: salt_client) }

  describe "#call" do
    let!(:node_01) { create(:node, hostname: "node-01", last_heartbeat_at: 1.minute.ago) }
    let!(:node_02) { create(:node, hostname: "node-02", last_heartbeat_at: 1.minute.ago) }
    let!(:node_03) { create(:node, hostname: "node-03", last_heartbeat_at: 1.minute.ago) }

    before do
      allow(salt_client).to receive(:run_runner)
        .with("manage.status")
        .and_return({
          "up" => ["node-01", "node-02"],
          "down" => ["node-03"]
        })
    end

    it "marks up nodes with current heartbeat" do
      service.call
      node_01.reload
      expect(node_01.online?).to be true
    end

    it "clears heartbeat for down nodes" do
      service.call
      node_03.reload
      expect(node_03.online?).to be false
    end

    it "returns counts of up and down nodes" do
      result = service.call
      expect(result[:up]).to eq(2)
      expect(result[:down]).to eq(1)
    end

    it "handles SaltApiClient errors" do
      allow(salt_client).to receive(:run_runner)
        .and_raise(SaltApiClient::TimeoutError, "timeout")

      result = service.call
      expect(result[:error]).to include("timeout")
    end
  end
end
