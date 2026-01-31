# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bmc::SaltTriggerService do
  let(:salt_client) { instance_double(SaltApiClient) }

  before do
    allow(SaltApiClient).to receive(:new).and_return(salt_client)
  end

  describe "#collect_sensors" do
    it "calls Salt runner for sensor collection" do
      expect(salt_client).to receive(:run_runner)
        .with("qis_bmc.collect_sensors", kwarg: {})
        .and_return({ "success" => true })

      result = described_class.new.collect_sensors
      expect(result["success"]).to be true
    end

    it "passes node filter when specified" do
      expect(salt_client).to receive(:run_runner)
        .with("qis_bmc.collect_sensors", kwarg: { node: "compute-001" })
        .and_return({ "success" => true })

      described_class.new.collect_sensors(node: "compute-001")
    end
  end

  describe "#collect_inventory" do
    it "calls Salt runner for inventory collection" do
      expect(salt_client).to receive(:run_runner)
        .with("qis_bmc.collect_inventory", kwarg: {})
        .and_return({ "success" => true })

      described_class.new.collect_inventory
    end
  end

  describe "#check_connectivity" do
    it "calls Salt runner for connectivity check" do
      expect(salt_client).to receive(:run_runner)
        .with("qis_bmc.check_connectivity", kwarg: {})
        .and_return({ "success" => true, "statuses" => [] })

      described_class.new.check_connectivity
    end
  end
end
