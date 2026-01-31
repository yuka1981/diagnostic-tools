# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bmc::SensorCollectionJob, type: :job do
  before do
    Rails.cache.clear
  end

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

    it "skips execution when another instance is already running" do
      Rails.cache.write(described_class::LOCK_KEY, true, expires_in: 10.minutes)

      expect(Bmc::SaltTriggerService).not_to receive(:new)

      expect {
        described_class.perform_now
      }.not_to have_enqueued_job(described_class)
    end

    it "releases the lock after execution completes" do
      allow_any_instance_of(Bmc::SaltTriggerService)
        .to receive(:collect_sensors)
        .and_return({ "success" => true })

      described_class.perform_now

      expect(Rails.cache.read(described_class::LOCK_KEY)).to be_nil
    end

    it "releases the lock even when collection raises an error" do
      allow_any_instance_of(Bmc::SaltTriggerService)
        .to receive(:collect_sensors)
        .and_raise(StandardError, "connection failed")

      expect {
        described_class.perform_now
      }.to raise_error(StandardError, "connection failed")

      expect(Rails.cache.read(described_class::LOCK_KEY)).to be_nil
    end

    it "does not re-enqueue when interval is zero" do
      allow_any_instance_of(Bmc::SaltTriggerService)
        .to receive(:collect_sensors)
        .and_return({ "success" => true })

      global = instance_double(BmcCredential, collection_interval: 0)
      allow(BmcCredential).to receive(:global_default).and_return(global)

      expect {
        described_class.perform_now
      }.not_to have_enqueued_job(described_class)
    end

    context "when multiple jobs are started simultaneously" do
      it "only one executes and the others skip" do
        trigger = instance_double(Bmc::SaltTriggerService)
        allow(Bmc::SaltTriggerService).to receive(:new).and_return(trigger)
        allow(trigger).to receive(:collect_sensors)
          .and_return({ "success" => true })

        # First job acquires the lock
        described_class.perform_now

        # Simulate a second job starting while the first has already completed
        # and released the lock - this one should also run fine
        expect(trigger).to have_received(:collect_sensors).once

        # Now simulate the lock being held (as if the first job is mid-execution)
        Rails.cache.write(described_class::LOCK_KEY, true, expires_in: 10.minutes)

        # Second job should skip
        described_class.perform_now
        expect(trigger).to have_received(:collect_sensors).once
      end
    end
  end
end
