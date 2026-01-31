# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bmc::SensorCollectionJob, type: :job do
  describe "#perform" do
    it "triggers sensor collection via Salt" do
      trigger = instance_double(Bmc::SaltTriggerService)
      allow(Bmc::SaltTriggerService).to receive(:new).and_return(trigger)
      expect(trigger).to receive(:collect_sensors)
        .and_return({ "success" => true })

      described_class.perform_now
    end

    it "re-enqueues itself after completion" do
      allow_any_instance_of(Bmc::SaltTriggerService)
        .to receive(:collect_sensors)
        .and_return({ "success" => true })

      expect {
        described_class.perform_now
      }.to have_enqueued_job(described_class)
    end
  end
end
