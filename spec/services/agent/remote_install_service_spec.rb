# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent::RemoteInstallService do
  let(:target_host) { "compute-001" }
  let(:bastion_user) { "admin" }
  let(:sudo_password) { "secret" }
  let(:local_path) { "/tmp/local_agent" }
  let(:service) do
    described_class.new(
      target_host: target_host,
      arch: "x86_64",
      bastion_user: bastion_user,
      sudo_password: sudo_password,
      local_binary_path: local_path
    )
  end

  let(:ssh_session) { instance_double(Net::SSH::Connection::Session) }
  let(:scp_handler) { instance_double(Net::SCP) }
  let(:channel) { instance_double(Net::SSH::Connection::Channel) }

  before do
    allow(SshConfig).to receive(:jump_host).and_return("bastion.example.com")
    allow(Net::SSH).to receive(:start).with("bastion.example.com", bastion_user, any_args).and_yield(ssh_session)
    allow(ssh_session).to receive(:scp).and_return(scp_handler)
    allow(scp_handler).to receive(:upload!)
    allow(ssh_session).to receive(:exec!)
    allow(ssh_session).to receive(:open_channel).and_yield(channel)
    allow(channel).to receive(:exec).and_yield(channel, true)
    allow(channel).to receive(:send_data)
    allow(channel).to receive(:on_data)
    allow(channel).to receive(:on_extended_data)
    allow(channel).to receive(:on_request).with("exit-status").and_yield(nil, double(read_long: 0))
    allow(ssh_session).to receive(:loop)
  end

  it "performs the full installation flow" do
    expect(scp_handler).to receive(:upload!).with(local_path, "/tmp/agent_bin")

    # Verify some key commands
    expect(channel).to receive(:exec).with(/sudo -S scp.*root@compute-001:\/usr\/local\/bin\/agent/).at_least(:once)
    expect(channel).to receive(:exec).with(/sudo -S ssh.*systemctl enable --now hpc-agent/).at_least(:once)

    expect(service.call).to be true
  end

  it "raises error if a command fails" do
    allow(channel).to receive(:on_request).with("exit-status").and_yield(nil, double(read_long: 1))

    expect { service.call }.to raise_error(Agent::RemoteInstallService::InstallError, /Command failed with exit code 1/)
  end
end
