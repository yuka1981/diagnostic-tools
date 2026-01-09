# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent::RemoteUninstallService do
  let(:target_host) { "compute-001" }
  let(:ssh_user) { "admin" }
  let(:sudo_password) { "secret" }
  let(:node) { create(:node, hostname: target_host, ssh_user: ssh_user) }
  let(:service) do
    described_class.new(
      target_host: target_host,
      bastion_host: "bastion.example.com",
      bastion_user: "bastion-user",
      sudo_password: sudo_password,
      node: node
    )
  end

  let(:ssh_session) { instance_double(Net::SSH::Connection::Session) }
  let(:channel) { instance_double(Net::SSH::Connection::Channel) }

  before do
    allow(ssh_session).to receive(:exec!)
    allow(ssh_session).to receive(:open_channel).and_yield(channel)
    allow(channel).to receive(:exec).and_yield(channel, true)
    allow(channel).to receive(:send_data)
    allow(channel).to receive(:on_data)
    allow(channel).to receive(:on_extended_data)
    allow(channel).to receive(:on_request).with("exit-status").and_yield(nil, double(read_long: 0))
    allow(ssh_session).to receive(:loop)
  end

  it "performs the full uninstallation flow via bastion" do
    allow(SshConfig).to receive(:jump_host).and_return("bastion.example.com")
    expect(Net::SSH).to receive(:start).with("bastion.example.com", "bastion-user", any_args).and_yield(ssh_session)

    # Verify some key cleanup commands - sudo should be on bastion, inner command quoted
    expect(channel).to receive(:exec).with(/sudo -S ssh.*root@compute-001.*'timeout 10s systemctl stop hpc-agent/).at_least(:once)
    expect(channel).to receive(:exec).with(/sudo -S ssh.*root@compute-001.*'rm -f/).at_least(:once)

    expect(service.call).to be true
  end

  it "performs a direct uninstallation when bastion_host is missing" do
    allow(SshConfig).to receive(:jump_host).and_return(nil)

    direct_service = described_class.new(
      target_host: target_host,
      bastion_host: nil,
      sudo_password: sudo_password,
      node: node,
      bastion_user: "root"
    )

    # Should connect to target instead of bastion using root
    expect(Net::SSH).to receive(:start).with(target_host, "root", any_args).and_yield(ssh_session)

    # Should run commands directly with sudo on target (no single quotes for direct sudo)
    expect(channel).to receive(:exec).with(/sudo -S.*systemctl stop hpc-agent/).at_least(:once)
    expect(channel).to receive(:exec).with(/sudo -S.*rm -f/).at_least(:once)

    expect(direct_service.call).to be true
  end

  it "raises error if a command fails" do
    allow(SshConfig).to receive(:jump_host).and_return("bastion.example.com")
    allow(Net::SSH).to receive(:start).and_yield(ssh_session)
    allow(channel).to receive(:on_request).with("exit-status").and_yield(nil, double(read_long: 1))

    expect { service.call }.to raise_error(Agent::RemoteUninstallService::UninstallError, /Command failed with exit code 1/)
  end
end
