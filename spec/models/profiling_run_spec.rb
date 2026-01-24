# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProfilingRun, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:node) }
    it { is_expected.to belong_to(:profiling_recipe).optional }
    it { is_expected.to belong_to(:user).optional }
    it { is_expected.to have_many(:profiling_artifacts).dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_presence_of(:subcommand) }

    it "generates uuid automatically" do
      run = build(:profiling_run, uuid: nil)
      run.valid?
      expect(run.uuid).to be_present
    end
  end

  describe "enums" do
    it "defines status values" do
      expect(ProfilingRun.statuses).to eq({
        "pending" => 0,
        "running" => 1,
        "success" => 2,
        "failed" => 3,
        "cancelled" => 4
      })
    end
  end

  describe "scopes" do
    let(:node) { create(:node) }

    describe ".recent" do
      it "orders by created_at descending" do
        old_run = create(:profiling_run, node: node, created_at: 1.hour.ago)
        new_run = create(:profiling_run, node: node, created_at: 1.minute.ago)
        expect(ProfilingRun.recent.first).to eq(new_run)
      end
    end

    describe ".for_node" do
      it "returns runs for specified node" do
        run = create(:profiling_run, node: node)
        other_run = create(:profiling_run)
        expect(ProfilingRun.for_node(node)).to contain_exactly(run)
      end
    end
  end

  describe "#duration" do
    it "returns nil when not completed" do
      run = build(:profiling_run, :running)
      expect(run.duration).to be_nil
    end

    it "returns duration in seconds when completed" do
      run = build(:profiling_run, started_at: 1.hour.ago, finished_at: Time.current)
      expect(run.duration).to be_within(1).of(3600)
    end
  end

  describe "#completed?" do
    it "returns true for success" do
      expect(build(:profiling_run, status: :success).completed?).to be true
    end

    it "returns true for failed" do
      expect(build(:profiling_run, status: :failed).completed?).to be true
    end

    it "returns false for running" do
      expect(build(:profiling_run, status: :running).completed?).to be false
    end
  end
end
