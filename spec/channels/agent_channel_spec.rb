# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe AgentChannel, type: :channel do
  include ActiveSupport::Testing::TimeHelpers

  let(:node) { create(:node, hostname: "test-node", uuid: SecureRandom.uuid) }

  before do
    # Stub the connection to have a current_node
    stub_connection current_node: node
  end

  describe "#subscribed" do
    it "successfully subscribes with a valid node" do
      subscribe

      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_from("agent_#{node.uuid}")
    end

    it "updates last_seen_at on subscription" do
      freeze_time do
        expect { subscribe }.to change { node.reload.last_seen_at }.to(Time.current)
      end
    end

    it "rejects subscription without a node" do
      stub_connection current_node: nil

      subscribe

      expect(subscription).to be_rejected
    end
  end

  describe "#receive - heartbeat action" do
    before { subscribe }

    it "updates last_seen_at when receiving heartbeat" do
      # Set last_seen_at to old value
      node.update!(last_seen_at: 10.minutes.ago)

      freeze_time do
        subscription.receive({ "action" => "heartbeat", "timestamp" => Time.current.iso8601 })

        expect(node.reload.last_seen_at).to eq(Time.current)
      end
    end

    it "keeps node online when heartbeats are received regularly" do
      node.update!(last_seen_at: 6.minutes.ago)
      expect(node.reload.online?).to be false

      freeze_time do
        subscription.receive({ "action" => "heartbeat" })

        expect(node.reload.online?).to be true
      end
    end

    it "handles heartbeat with timestamp" do
      timestamp = Time.current.utc.iso8601

      expect {
        subscription.receive({ "action" => "heartbeat", "timestamp" => timestamp })
      }.not_to raise_error

      expect(node.reload.last_seen_at).to be_present
    end

    it "handles heartbeat without timestamp" do
      expect {
        subscription.receive({ "action" => "heartbeat" })
      }.not_to raise_error

      expect(node.reload.last_seen_at).to be_present
    end
  end

  describe "#receive - report_result action" do
    before { subscribe }

    it "processes successful inventory report" do
      payload = {
        "action" => "report_result",
        "status" => "success",
        "payload" => {
          "cpu" => { "model_name" => "Intel Xeon", "cores" => 16 },
          "memory" => { "total" => 137438953472 }
        },
        "correlation_id" => "test-123"
      }

      service_result = OpenStruct.new(success?: true)
      allow_any_instance_of(Inventory::ProcessStateService).to receive(:call).and_return(service_result)

      expect { subscription.receive(payload) }.not_to raise_error
    end

    it "logs error on failed inventory report" do
      payload = {
        "action" => "report_result",
        "status" => "error",
        "error" => "Collection failed",
        "correlation_id" => "test-123"
      }

      expect(Rails.logger).to receive(:error).with(/reported an error/)

      subscription.receive(payload)
    end
  end

  describe "#beat (periodic heartbeat)" do
    before { subscribe }

    it "updates last_seen_at when beat is called" do
      node.update!(last_seen_at: 2.minutes.ago)

      freeze_time do
        # Simulate the periodic beat
        subscription.beat

        expect(node.reload.last_seen_at).to eq(Time.current)
      end
    end

    it "keeps node online through periodic beats" do
      node.update!(last_seen_at: 4.minutes.ago)
      expect(node.reload.online?).to be true # Still within 5 minute threshold

      travel 2.minutes do
        # Without beat, node would be 6 minutes stale (offline)
        subscription.beat
        expect(node.reload.online?).to be true
      end
    end
  end

  describe "node status integration" do
    before { subscribe }

    context "when node receives regular heartbeats" do
      it "remains online" do
        # Simulate 10 minutes of heartbeats every 30 seconds
        20.times do |i|
          travel (30 * i).seconds do
            subscription.receive({ "action" => "heartbeat" })
          end
        end

        # After 10 minutes of regular heartbeats, node should still be online
        travel 10.minutes do
          subscription.receive({ "action" => "heartbeat" })
          expect(node.reload.online?).to be true
        end
      end
    end

    context "when heartbeats stop" do
      it "goes offline after ONLINE_THRESHOLD" do
        freeze_time do
          subscription.receive({ "action" => "heartbeat" })
          expect(node.reload.online?).to be true
        end

        # Travel past ONLINE_THRESHOLD without heartbeat
        travel (Node::ONLINE_THRESHOLD + 1.minute) do
          expect(node.reload.online?).to be false
        end
      end
    end
  end
end
