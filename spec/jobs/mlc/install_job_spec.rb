require "rails_helper"

RSpec.describe Mlc::InstallJob, type: :job do
  let(:installation) { create(:mlc_installation) }
  let(:node) { create(:node, :online, :direct) }
  let!(:installation_node) { create(:mlc_installation_node, mlc_installation: installation, node: node) }

  describe "#perform" do
    it "sets started_at timestamp" do
      allow_any_instance_of(Mlc::TriggerInstallService).to receive(:call)
        .and_return(SshExecutionService::Result.new(success: true, output: "INSTALL_STARTED PID=123"))

      described_class.perform_now(installation.id, "http://localhost:3000", "token")

      installation.reload
      expect(installation.started_at).to be_present
    end

    it "processes pending nodes" do
      trigger_service = instance_double(Mlc::TriggerInstallService)
      allow(Mlc::TriggerInstallService).to receive(:new).and_return(trigger_service)
      allow(trigger_service).to receive(:call)
        .and_return(SshExecutionService::Result.new(success: true, output: "INSTALL_STARTED PID=123"))

      described_class.perform_now(installation.id, "http://localhost:3000", "token")

      expect(trigger_service).to have_received(:call).once
    end

    context "when trigger fails with stop_on_first mode" do
      before do
        installation.update!(failure_mode: :stop_on_first)
        # Create a second node
        create(:mlc_installation_node, mlc_installation: installation, node: create(:node, :online, :direct))
      end

      it "marks installation as failed" do
        allow_any_instance_of(Mlc::TriggerInstallService).to receive(:call)
          .and_return(SshExecutionService::Result.new(success: false, error: "Connection refused"))

        described_class.perform_now(installation.id, "http://localhost:3000", "token")

        installation.reload
        expect(installation.status).to eq("failed")
      end

      it "skips remaining nodes" do
        allow_any_instance_of(Mlc::TriggerInstallService).to receive(:call)
          .and_return(SshExecutionService::Result.new(success: false, error: "Connection refused"))

        described_class.perform_now(installation.id, "http://localhost:3000", "token")

        skipped_count = installation.mlc_installation_nodes.skipped.count
        expect(skipped_count).to eq(1)
      end
    end

    context "when all nodes succeed" do
      it "marks installation as completed" do
        allow_any_instance_of(Mlc::TriggerInstallService).to receive(:call)
          .and_return(SshExecutionService::Result.new(success: true, output: "INSTALL_STARTED PID=123"))

        described_class.perform_now(installation.id, "http://localhost:3000", "token")

        installation.reload
        expect(installation.status).to eq("completed")
      end
    end
  end
end
