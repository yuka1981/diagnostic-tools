# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentEvent do
  describe "associations" do
    it { is_expected.to belong_to(:node) }
    it { is_expected.to belong_to(:user).optional }
    it { is_expected.to belong_to(:agent_release).optional }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:operation) }
    it { is_expected.to validate_presence_of(:status) }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:operation).with_values(install: "install", upgrade: "upgrade", uninstall: "uninstall").backed_by_column_of_type(:string) }
    it { is_expected.to define_enum_for(:status).with_values(pending: "pending", running: "running", success: "success", failed: "failed", rolled_back: "rolled_back").backed_by_column_of_type(:string) }
  end

  describe "factory" do
    it "creates a valid agent_event" do
      event = build(:agent_event)
      expect(event).to be_valid
    end
  end

  describe "#duration" do
    it "returns nil when not completed" do
      event = build(:agent_event, started_at: 1.minute.ago, completed_at: nil)
      expect(event.duration).to be_nil
    end

    it "returns duration in seconds when completed" do
      event = build(:agent_event, started_at: 1.minute.ago, completed_at: Time.current)
      expect(event.duration).to be_within(1).of(60)
    end
  end

  describe "#mark_running!" do
    it "sets status to running and started_at" do
      event = create(:agent_event)
      event.mark_running!
      expect(event.status).to eq("running")
      expect(event.started_at).to be_present
    end
  end

  describe "#mark_success!" do
    it "sets status to success and completed_at" do
      event = create(:agent_event, :running)
      event.mark_success!
      expect(event.status).to eq("success")
      expect(event.completed_at).to be_present
    end
  end

  describe "#mark_failed!" do
    it "sets status to failed with error details" do
      event = create(:agent_event, :running)
      event.mark_failed!(message: "SSH timeout", details: { stderr: "Connection refused" })
      expect(event.status).to eq("failed")
      expect(event.error_message).to eq("SSH timeout")
      expect(event.error_details["stderr"]).to eq("Connection refused")
      expect(event.completed_at).to be_present
    end
  end

  describe "#mark_rolled_back!" do
    it "sets status to rolled_back" do
      event = create(:agent_event, :running)
      event.mark_rolled_back!(message: "Update failed, restored previous version")
      expect(event.status).to eq("rolled_back")
      expect(event.error_message).to eq("Update failed, restored previous version")
    end
  end
end
