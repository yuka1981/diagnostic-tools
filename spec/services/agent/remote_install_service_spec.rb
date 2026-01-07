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
      bastion_host: "bastion.example.com",
      bastion_user: bastion_user,
      sudo_password: sudo_password,
      local_binary_path: local_path
    )
  end

  let(:ssh_session) { instance_double(Net::SSH::Connection::Session) }
  let(:scp_handler) { instance_double(Net::SCP) }
  let(:channel) { instance_double(Net::SSH::Connection::Channel) }

  before do
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

      it "performs the full installation flow via bastion" do
        progress_messages = []

        progress_callback = ->(msg) { progress_messages << msg }



        allow(SshConfig).to receive(:jump_host).and_return("bastion.example.com")

        expect(Net::SSH).to receive(:start).with("bastion.example.com", bastion_user, any_args).and_yield(ssh_session)



        expect(scp_handler).to receive(:upload!).with(local_path, "/tmp/agent_bin")



        # Verify some key commands

        expect(channel).to receive(:exec).with(/sudo -S scp.*root@compute-001:\/usr\/local\/bin\/hpc-agent/).at_least(:once)

        expect(channel).to receive(:exec).with(/sudo -S ssh.*systemctl\\ daemon-reload\\ \\&\\&\\ systemctl\\ enable\\ --now\\ hpc-agent/).at_least(:once)



        expect(service.call).to be true
      end



      it "performs a direct installation when bastion_host is missing" do
        allow(SshConfig).to receive(:jump_host).and_return(nil)



        direct_service = described_class.new(

          target_host: target_host,

          arch: "x86_64",

          bastion_host: nil,

          bastion_user: bastion_user,

          sudo_password: sudo_password,

          local_binary_path: local_path

        )



        # Should connect to target instead of bastion

        expect(Net::SSH).to receive(:start).with(target_host, bastion_user, any_args).and_yield(ssh_session)

        expect(scp_handler).to receive(:upload!).with(local_path, "/tmp/agent_bin_install")



        # Should run commands directly without jump host SSH prefix

        expect(channel).to receive(:exec).with(/sudo -S mv \/tmp\/agent_bin_install \/usr\/local\/bin\/hpc-agent/).at_least(:once)

        expect(channel).to receive(:exec).with(/sudo -S bash -c systemctl\\ daemon-reload\\ \\&\\&\\ systemctl\\ enable\\ --now\\ hpc-agent/).at_least(:once)



        expect(direct_service.call).to be true
      end



        it "generates a service file with the correct server URL" do
          allow(SshConfig).to receive(:jump_host).and_return(nil)



          custom_url = "https://custom-hpc.qct.ai"



          service_with_custom_url = described_class.new(



            target_host: target_host,



            arch: "x86_64",



            bastion_host: nil,



            bastion_user: bastion_user,



            sudo_password: sudo_password,



            local_binary_path: local_path,



            server_url: custom_url



          )







          allow(Net::SSH).to receive(:start).and_yield(ssh_session)



          expect(ssh_session).to receive(:exec!).with(/ExecStart=.*inventory push --server "#{custom_url}"/)



          service_with_custom_url.call
        end

  it "defaults bastion_user to root if not provided" do
    allow(SshConfig).to receive(:jump_host).and_return(nil)
    service_no_user = described_class.new(
      target_host: target_host,
      arch: "x86_64",
      bastion_host: nil,
      bastion_user: nil,
      sudo_password: sudo_password,
      local_binary_path: local_path
    )

    expect(Net::SSH).to receive(:start).with(target_host, "root", any_args).and_yield(ssh_session)
    service_no_user.call
  end

  it "raises error if a command fails" do
    allow(SshConfig).to receive(:jump_host).and_return("bastion.example.com")
    allow(Net::SSH).to receive(:start).and_yield(ssh_session)
    allow(channel).to receive(:on_request).with("exit-status").and_yield(nil, double(read_long: 1))

    expect { service.call }.to raise_error(Agent::RemoteInstallService::InstallError, /Command failed with exit code 1/)
  end
end
