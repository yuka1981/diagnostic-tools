# frozen_string_literal: true

require "rails_helper"

RSpec.describe QctSyncJob, type: :job do
  describe "#perform" do
    let(:mock_result) do
      QctScraperService::Result.new(
        added_count: 5,
        updated_count: 10,
        errors: [],
        new_products: [ "https://example.com/product1" ]
      )
    end

    before do
      allow_any_instance_of(QctScraperService).to receive(:sync_all).and_return(mock_result)
    end

    it "calls QctScraperService" do
      expect_any_instance_of(QctScraperService).to receive(:sync_all)
      described_class.perform_now
    end

    it "creates a SyncLog record" do
      expect { described_class.perform_now }.to change(SyncLog, :count).by(1)
    end

    it "records sync results in SyncLog" do
      described_class.perform_now
      log = SyncLog.last
      expect(log.source).to eq("qct")
      expect(log.products_added).to eq(5)
      expect(log.products_updated).to eq(10)
      expect(log.completed_at).to be_present
    end

    context "when sync has errors" do
      let(:mock_result) do
        QctScraperService::Result.new(
          added_count: 3,
          updated_count: 5,
          errors: [ { url: "https://example.com", error: "Connection timeout" } ],
          new_products: []
        )
      end

      it "records errors in SyncLog" do
        described_class.perform_now
        log = SyncLog.last
        expect(log.sync_errors).not_to be_empty
      end
    end
  end

  describe "queue" do
    it "is queued to default queue" do
      expect(described_class.new.queue_name).to eq("default")
    end
  end
end
