# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mlc::InstallJob, type: :job do
  let(:installation) { create(:mlc_installation) }
  let(:node) { create(:node, :online) }
  let!(:installation_node) { create(:mlc_installation_node, mlc_installation: installation, node: node) }

  describe "#perform" do
    it "sets started_at timestamp and raises NotImplementedError" do
      expect {
        described_class.perform_now(installation.id, "http://localhost:3000")
      }.to raise_error(NotImplementedError)

      installation.reload
      expect(installation.started_at).to be_present
    end
  end
end
