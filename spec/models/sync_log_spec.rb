require "rails_helper"

RSpec.describe SyncLog, type: :model do
  describe "validations" do
    subject { build(:sync_log) }

    it { is_expected.to validate_presence_of(:source) }
  end

  describe "factory" do
    it "creates a valid sync log" do
      log = build(:sync_log)
      expect(log).to be_valid
    end
  end

  describe "scopes" do
    describe ".for_source" do
      let!(:qct_log) { create(:sync_log, source: "qct") }
      let!(:other_log) { create(:sync_log, source: "other") }

      it "filters by source" do
        expect(SyncLog.for_source("qct")).to include(qct_log)
        expect(SyncLog.for_source("qct")).not_to include(other_log)
      end
    end

    describe ".latest" do
      let!(:older) { create(:sync_log, completed_at: 2.days.ago) }
      let!(:newer) { create(:sync_log, completed_at: 1.day.ago) }

      it "orders by completed_at descending" do
        expect(SyncLog.latest.first).to eq(newer)
      end
    end
  end
end
