require "rails_helper"

RSpec.describe Salt::EventListenerService do
  let(:salt_client) { instance_double(SaltApiClient) }
  let(:service) { described_class.new(salt_client: salt_client) }

  describe "#dispatch_event" do
    let(:node) { create(:node, hostname: "node-01") }

    it "routes benchmark job returns to BenchmarkResultService" do
      run = create(:benchmark_run, :running, node: node)
      event_tag = "salt/job/ret/20260129120000123456"
      event_data = {
        "fun" => "state.apply",
        "fun_args" => [ { "mods" => "benchmark.hpcg", "pillar" => { "run_id" => run.uuid } } ],
        "return" => {
          "status" => "PASS",
          "metrics" => { "gflops" => 45.67 }
        },
        "id" => "node-01",
        "retcode" => 0
      }

      result_service = instance_double(Salt::BenchmarkResultService, call: true)
      expect(Salt::BenchmarkResultService).to receive(:new)
        .with(hash_including(benchmark_run: run))
        .and_return(result_service)
      service.dispatch_event(event_tag, event_data)
    end

    it "routes presence change events to node status updates" do
      event_tag = "salt/presence/change"
      event_data = {
        "new" => [],
        "lost" => [ "node-01" ]
      }

      service.dispatch_event(event_tag, event_data)
      # Node presence is handled - no error raised
    end

    it "ignores unrecognized event tags" do
      service.dispatch_event("salt/auth/something", { "id" => "node-01" })
      # No error, no action
    end
  end

  describe "#update_presence" do
    it "marks lost nodes as disconnected" do
      node = create(:node, hostname: "node-01", salt_status: :connected)

      service.update_presence(new_minions: [], lost_minions: [ "node-01" ])
      expect(node.reload.salt_status).to eq("disconnected")
    end

    it "marks new nodes as connected" do
      node = create(:node, hostname: "node-02", salt_status: :disconnected)

      service.update_presence(new_minions: [ "node-02" ], lost_minions: [])
      expect(node.reload.salt_status).to eq("connected")
    end

    it "does not flip unknown nodes to disconnected" do
      node = create(:node, hostname: "node-03", salt_status: :unknown)

      service.update_presence(new_minions: [], lost_minions: [ "node-03" ])
      expect(node.reload.salt_status).to eq("unknown")
    end
  end
end
