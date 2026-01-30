require "rails_helper"

RSpec.describe Salt::PresenceCheckService do
  let(:salt_client) { instance_double(SaltApiClient) }
  let(:service) { described_class.new(salt_client: salt_client) }

  describe "#call" do
    let!(:node_01) { create(:node, hostname: "node-01", salt_status: :connected) }
    let!(:node_02) { create(:node, hostname: "node-02", salt_status: :connected) }
    let!(:node_03) { create(:node, hostname: "node-03", salt_status: :connected) }

    before do
      allow(salt_client).to receive(:run_runner)
        .with("manage.status")
        .and_return({
          "up" => [ "node-01", "node-02" ],
          "down" => [ "node-03" ]
        })
    end

    it "marks up nodes as salt_connected" do
      service.call
      expect(node_01.reload.salt_status).to eq("connected")
    end

    it "updates last_seen_at for up nodes" do
      service.call
      expect(node_01.reload.last_seen_at).to be_within(2.seconds).of(Time.current)
    end

    it "marks down nodes as salt_disconnected" do
      service.call
      expect(node_03.reload.salt_status).to eq("disconnected")
    end

    it "does not flip unknown nodes to disconnected" do
      unknown_node = create(:node, hostname: "node-04", salt_status: :unknown)
      service.call
      expect(unknown_node.reload.salt_status).to eq("unknown")
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
