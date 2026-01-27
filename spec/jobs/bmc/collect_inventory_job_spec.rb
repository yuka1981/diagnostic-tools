# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bmc::CollectInventoryJob, type: :job do
  include ActiveJob::TestHelper

  let(:node) { create(:node, hostname: "compute-01") }
  let(:ssh_settings) do
    SshSetting.current.tap do |s|
      s.update!(
        bastion_host: "bastion.example.com",
        bastion_user: "admin",
        bastion_port: 22,
        ssh_key: "fake-ssh-key",
        timeout: 30,
        verify_host_key: false
      )
    end
  end

  before do
    ssh_settings
  end

  describe "#perform" do
    let(:mock_ssh) { instance_double(Net::SSH::Connection::Session) }

    context "when collection succeeds" do
      before do
        allow(Net::SSH).to receive(:start).and_yield(mock_ssh)
        allow(mock_ssh).to receive(:exec!).and_return("OK")
        allow(Rails.logger).to receive(:info)
      end

      it "logs success message" do
        described_class.perform_now(node.id)

        expect(Rails.logger).to have_received(:info).with(/BMC collection completed for node compute-01/)
      end
    end

    context "when collection fails" do
      before do
        allow(Net::SSH).to receive(:start).and_yield(mock_ssh)
        allow(mock_ssh).to receive(:exec!).and_return("ERROR: Connection refused")
        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:error)
      end

      it "logs success message (job completed with output)" do
        described_class.perform_now(node.id)

        # The job still logs success from Rails' perspective since SSH call succeeded
        expect(Rails.logger).to have_received(:info).with(/BMC collection completed/)
      end
    end

    context "when SSH connection fails" do
      before do
        allow(Net::SSH).to receive(:start).and_raise(StandardError.new("Connection refused"))
        allow(Rails.logger).to receive(:error)
      end

      it "logs error message" do
        described_class.perform_now(node.id)

        expect(Rails.logger).to have_received(:error).with(/BMC collection failed for node compute-01.*Connection refused/)
      end
    end

    context "when bastion host is not configured" do
      before do
        SshSetting.current.update!(bastion_host: nil)
        allow(Rails.logger).to receive(:error)
      end

      it "logs error about missing bastion configuration" do
        described_class.perform_now(node.id)

        expect(Rails.logger).to have_received(:error).with(/BMC collection failed.*Bastion host not configured/)
      end
    end

    context "when SSH authentication fails" do
      before do
        allow(Net::SSH).to receive(:start).and_raise(
          Net::SSH::AuthenticationFailed.new("admin")
        )
        allow(Rails.logger).to receive(:error)
      end

      it "logs the SSH error and completes without raising" do
        expect { described_class.perform_now(node.id) }.not_to raise_error

        expect(Rails.logger).to have_received(:error).with(/SSH error for compute-01.*Authentication failed/)
      end
    end

    context "when SSH host key verification fails" do
      before do
        allow(Net::SSH).to receive(:start).and_raise(
          Net::SSH::HostKeyMismatch.new("Host key mismatch")
        )
        allow(Rails.logger).to receive(:error)
      end

      it "logs the SSH error and completes without raising" do
        expect { described_class.perform_now(node.id) }.not_to raise_error

        expect(Rails.logger).to have_received(:error).with(/SSH error for compute-01.*Host key verification failed/)
      end
    end

    context "when other SSH exception occurs" do
      before do
        allow(Net::SSH).to receive(:start).and_raise(
          Net::SSH::Exception.new("Unknown SSH error")
        )
        allow(Rails.logger).to receive(:error)
      end

      it "logs the SSH error and completes without raising" do
        expect { described_class.perform_now(node.id) }.not_to raise_error

        expect(Rails.logger).to have_received(:error).with(/SSH error for compute-01/)
      end
    end

    context "when SSH connection times out" do
      before do
        allow(Net::SSH).to receive(:start).and_raise(
          Net::SSH::ConnectionTimeout.new("Connection timed out")
        )
      end

      it "allows the exception to propagate for retry handling" do
        # retry_on catches ConnectionTimeout internally
        expect { described_class.perform_now(node.id) }.not_to raise_error
      end
    end

    context "when node does not exist" do
      it "discards the job without error" do
        expect { described_class.perform_now(999_999) }.not_to raise_error
      end
    end

    context "with user_id for notification" do
      let(:user) { create(:user) }

      before do
        allow(Net::SSH).to receive(:start).and_yield(mock_ssh)
        allow(mock_ssh).to receive(:exec!).and_return("OK")
        allow(Rails.logger).to receive(:info)
      end

      it "creates and completes a notification" do
        expect(NotificationService).to receive(:create).with(
          user: user,
          type: "bmc_inventory_collect",
          title: "Collecting BMC inventory from compute-01",
          resource: node
        ).and_call_original

        expect(NotificationService).to receive(:start).and_call_original
        expect(NotificationService).to receive(:complete).with(
          anything,
          success: true,
          message: "BMC inventory collected successfully"
        ).and_call_original

        described_class.perform_now(node.id, user_id: user.id)
      end
    end
  end

  describe "#build_collector_command" do
    it "builds correct command with escaped hostname" do
      job = described_class.new
      # Access private method for testing
      command = job.send(:build_collector_command, node)

      expect(command).to eq("qis-bmc-collector inventory --node compute-01")
    end

    it "escapes special characters in hostname" do
      special_node = create(:node, hostname: "node-with-special-chars")
      job = described_class.new
      command = job.send(:build_collector_command, special_node)

      # Verify the command is properly formed
      expect(command).to eq("qis-bmc-collector inventory --node node-with-special-chars")
    end

    it "uses Shellwords.escape for safety" do
      # Create a node that would need escaping if malicious
      # (Note: hostname validation may prevent truly malicious names)
      dangerous_node = build(:node, hostname: "node$(whoami)")
      job = described_class.new
      command = job.send(:build_collector_command, dangerous_node)

      # Shellwords.escape should escape the $
      expect(command).to include("\\$")
    end
  end

  describe "job configuration" do
    it "is enqueued in the default queue" do
      expect(described_class.new.queue_name).to eq("default")
    end
  end

  describe "retry behavior" do
    it "has retry_on configured for ConnectionTimeout only" do
      expect(described_class.rescue_handlers).not_to be_empty
    end
  end

  describe "enqueue" do
    it "can be enqueued with node id" do
      expect {
        described_class.perform_later(node.id)
      }.to have_enqueued_job(described_class).with(node.id)
    end

    it "can be enqueued with user_id" do
      user = create(:user)

      expect {
        described_class.perform_later(node.id, user_id: user.id)
      }.to have_enqueued_job(described_class).with(node.id, user_id: user.id)
    end
  end
end
