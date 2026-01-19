# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent::RemoteInstallService do
  let(:target_host) { "compute-001" }
  let(:ssh_user) { "admin" }
  let(:sudo_password) { "secret" }
  let(:local_path) { "/tmp/local_agent" }
  let(:node) { create(:node, hostname: target_host, ssh_user: ssh_user) }
  let(:service) do
    described_class.new(
      target_host: target_host,
      arch: "x86_64",
      bastion_host: "bastion.example.com",
      bastion_user: "bastion-user",
      sudo_password: sudo_password,
      local_binary_path: local_path,
      node: node
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
    allow(SshConfig).to receive(:jump_host).and_return("bastion.example.com")
    expect(Net::SSH).to receive(:start).with("bastion.example.com", "bastion-user", any_args).and_yield(ssh_session)

    # Verify some key commands - target user is always root
    expect(scp_handler).to receive(:upload!).with(local_path, "/tmp/agent_bin")
    expect(channel).to receive(:exec).with(/sudo -S scp.*root@compute-001/).at_least(:once)
    # Match bash -c with escaped space (Shellwords.escape)
    expect(channel).to receive(:exec).with(/sudo -S ssh.*root@compute-001.*bash\\ -c.*/).at_least(:once)

    expect(service.call).to be_success
  end

  it "performs a direct installation when bastion_host is missing" do
    allow(SshConfig).to receive(:jump_host).and_return(nil)

    direct_service = described_class.new(
      target_host: target_host,
      arch: "x86_64",
      bastion_host: nil,
      sudo_password: sudo_password,
      local_binary_path: local_path,
      node: node,
      bastion_user: "root"
    )

    # Should connect to target instead of bastion
    expect(Net::SSH).to receive(:start).with(node.ip, "root", any_args).and_yield(ssh_session)
    expect(scp_handler).to receive(:upload!).with(local_path, "/tmp/agent_bin_install")

    # Should run commands directly with sudo on target
    expect(channel).to receive(:exec).with(/sudo -S mv \/tmp\/agent_bin_install/).at_least(:once)
    expect(channel).to receive(:exec).with(/sudo -S bash -c.*chown root:root/).at_least(:once)
    expect(channel).to receive(:exec).with(/sudo -S bash -c.*systemctl/).at_least(:once)

    expect(direct_service.call).to be_success
  end

  it "generates a service file with the correct server URL" do
    allow(SshConfig).to receive(:jump_host).and_return(nil)
    custom_url = "https://custom-hpc.qct.ai"

    service_with_custom_url = described_class.new(
      target_host: target_host,
      arch: "x86_64",
      bastion_host: nil,
      sudo_password: sudo_password,
      local_binary_path: local_path,
      server_url: custom_url,
      node: node,
      bastion_user: "root"
    )

    allow(Net::SSH).to receive(:start).and_yield(ssh_session)
    expect(ssh_session).to receive(:exec!).with(/ExecStart=.*inventory push --server "#{custom_url}"/)

    service_with_custom_url.call
  end

  it "defaults to root if node ssh_user is missing" do
    allow(SshConfig).to receive(:jump_host).and_return(nil)
    node.update!(ssh_user: nil)
    service_no_user = described_class.new(
      target_host: target_host,
      arch: "x86_64",
      bastion_host: nil,
      sudo_password: sudo_password,
      local_binary_path: local_path,
      node: node,
      bastion_user: "root"
    )

    expect(Net::SSH).to receive(:start).with(node.ip, "root", any_args).and_yield(ssh_session)
    service_no_user.call
  end

  it "falls back to hostname if node IP is missing" do
    allow(SshConfig).to receive(:jump_host).and_return(nil)
    node.update!(ip: nil)

    fallback_service = described_class.new(
      target_host: target_host,
      arch: "x86_64",
      bastion_host: nil,
      sudo_password: sudo_password,
      local_binary_path: local_path,
      node: node,
      bastion_user: "root"
    )

    expect(Net::SSH).to receive(:start).with(target_host, "root", any_args).and_yield(ssh_session)
    fallback_service.call
  end

  it "uses node IP for connection if available during direct installation" do
    allow(SshConfig).to receive(:jump_host).and_return(nil)
    node.update!(ip: "192.168.1.100")

    direct_service = described_class.new(
      target_host: target_host,
      arch: "x86_64",
      bastion_host: nil,
      sudo_password: sudo_password,
      local_binary_path: local_path,
      node: node,
      bastion_user: "root"
    )

    # Should connect to IP (192.168.1.100) instead of hostname (compute-001)
    expect(Net::SSH).to receive(:start).with("192.168.1.100", "root", any_args).and_yield(ssh_session)

    expect(direct_service.call).to be_success
  end

  it "tries hostname if IP connection fails with timeout" do
    allow(SshConfig).to receive(:jump_host).and_return(nil)
    node.update!(ip: "192.168.1.100")

    direct_service = described_class.new(
      target_host: target_host,
      arch: "x86_64",
      bastion_host: nil,
      sudo_password: sudo_password,
      local_binary_path: local_path,
      node: node,
      bastion_user: "root"
    )

    # First attempt with IP fails
    expect(Net::SSH).to receive(:start).with("192.168.1.100", "root", any_args).and_raise(Net::SSH::ConnectionTimeout)

    # Second attempt with hostname succeeds
    expect(Net::SSH).to receive(:start).with(target_host, "root", any_args).and_yield(ssh_session)

    expect(direct_service.call).to be_success
  end

  it "raises error if a command fails" do
    allow(SshConfig).to receive(:jump_host).and_return("bastion.example.com")
    allow(Net::SSH).to receive(:start).and_yield(ssh_session)
    allow(channel).to receive(:on_request).with("exit-status").and_yield(nil, double(read_long: 1))

    expect { service.call }.to raise_error(Agent::RemoteInstallService::InstallError, /Command failed with exit code 1/)
  end

  describe "localhost local execution" do
    let(:localhost_node) { build_stubbed(:node, ip: "127.0.0.1", hostname: "localhost-node") }

    describe "#localhost?" do
      it "returns true for 127.0.0.1" do
        service = described_class.new(
          target_host: "127.0.0.1",
          arch: "x86_64",
          sudo_password: sudo_password,
          local_binary_path: local_path,
          node: localhost_node
        )
        expect(service.send(:localhost?)).to be true
      end

      it "returns true for localhost" do
        service = described_class.new(
          target_host: "localhost",
          arch: "x86_64",
          sudo_password: sudo_password,
          local_binary_path: local_path,
          node: localhost_node
        )
        expect(service.send(:localhost?)).to be true
      end

      it "returns true for ::1 IPv6" do
        service = described_class.new(
          target_host: "::1",
          arch: "x86_64",
          sudo_password: sudo_password,
          local_binary_path: local_path,
          node: localhost_node
        )
        expect(service.send(:localhost?)).to be true
      end

      it "returns false for regular hostname" do
        service = described_class.new(
          target_host: "compute-001",
          arch: "x86_64",
          sudo_password: sudo_password,
          local_binary_path: local_path,
          node: node
        )
        expect(service.send(:localhost?)).to be false
      end
    end

    describe "local installation" do
      let(:localhost_service) do
        described_class.new(
          target_host: "127.0.0.1",
          arch: "x86_64",
          sudo_password: sudo_password,
          local_binary_path: local_path,
          node: localhost_node,
          server_url: "http://localhost:3000",
          agent_token: "test-token"
        )
      end

      before do
        allow(File).to receive(:exist?).and_return(true)
        allow(FileUtils).to receive(:mkdir_p)
        allow(FileUtils).to receive(:cp)
        allow(FileUtils).to receive(:chmod)
        allow(File).to receive(:write)
        allow(File).to receive(:read).with("/etc/hpc-agent/node_id").and_return("test-uuid-1234")
      end

      context "when all commands succeed" do
        before do
          allow(Open3).to receive(:capture3) do |cmd|
            status = instance_double(Process::Status, success?: true, exitstatus: 0)
            [ "", "", status ]
          end
        end

        it "uses local execution instead of SSH" do
          expect(Net::SSH).not_to receive(:start)
          expect(FileUtils).to receive(:cp).with(local_path, "/tmp/agent_bin_install")

          localhost_service.call
        end

        it "returns successful result" do
          result = localhost_service.call
          expect(result).to be_success
        end

        it "returns the agent UUID" do
          result = localhost_service.call
          expect(result.agent_uuid).to eq("test-uuid-1234")
        end

        it "reports progress for local execution" do
          messages = []
          service_with_progress = described_class.new(
            target_host: "127.0.0.1",
            arch: "x86_64",
            sudo_password: sudo_password,
            local_binary_path: local_path,
            node: localhost_node,
            on_progress: ->(msg) { messages << msg }
          )

          allow(Open3).to receive(:capture3) do |cmd|
            status = instance_double(Process::Status, success?: true, exitstatus: 0)
            [ "", "", status ]
          end
          allow(File).to receive(:read).with("/etc/hpc-agent/node_id").and_return("uuid")

          service_with_progress.call

          expect(messages).to include(/local installation/i)
        end
      end

      context "when a command fails" do
        it "raises InstallError with command details" do
          allow(Open3).to receive(:capture3) do |cmd|
            status = instance_double(Process::Status, success?: false, exitstatus: 1)
            [ "", "Permission denied", status ]
          end

          expect { localhost_service.call }.to raise_error(
            Agent::RemoteInstallService::InstallError,
            /Permission denied/
          )
        end

        it "includes exit code in error message" do
          allow(Open3).to receive(:capture3) do |cmd|
            status = instance_double(Process::Status, success?: false, exitstatus: 127)
            [ "", "command not found", status ]
          end

          expect { localhost_service.call }.to raise_error(
            Agent::RemoteInstallService::InstallError,
            /exit 127/
          )
        end

        it "uses stdout when stderr is empty" do
          allow(Open3).to receive(:capture3) do |cmd|
            status = instance_double(Process::Status, success?: false, exitstatus: 1)
            [ "Error from stdout", "", status ]
          end

          expect { localhost_service.call }.to raise_error(
            Agent::RemoteInstallService::InstallError,
            /Error from stdout/
          )
        end
      end
    end

    describe "#build_local_command" do
      context "with password provided" do
        let(:localhost_service) do
          described_class.new(
            target_host: "127.0.0.1",
            arch: "x86_64",
            sudo_password: "mysudopass",
            local_binary_path: local_path,
            node: localhost_node
          )
        end

        it "builds command with sudo when use_sudo is true" do
          cmd = localhost_service.send(:build_local_command, "mv /tmp/file /dest", use_sudo: true)
          expect(cmd).to include("sudo")
          expect(cmd).to match(/mv.*\/tmp\/file.*\/dest/)
        end

        it "pipes password to sudo -S" do
          cmd = localhost_service.send(:build_local_command, "systemctl start hpc-agent", use_sudo: true)
          expect(cmd).to include("echo")
          expect(cmd).to include("sudo -S")
        end

        it "includes timeout to prevent hanging" do
          cmd = localhost_service.send(:build_local_command, "systemctl start hpc-agent", use_sudo: true)
          expect(cmd).to include("timeout")
        end

        it "returns plain command when use_sudo is false" do
          cmd = localhost_service.send(:build_local_command, "cat /etc/hpc-agent/node_id", use_sudo: false)
          expect(cmd).to eq("cat /etc/hpc-agent/node_id")
          expect(cmd).not_to include("sudo")
        end
      end

      context "without password (blank)" do
        let(:no_password_service) do
          described_class.new(
            target_host: "127.0.0.1",
            arch: "x86_64",
            sudo_password: "",
            local_binary_path: local_path,
            node: localhost_node
          )
        end

        it "still uses sudo -S to prevent TTY hang" do
          cmd = no_password_service.send(:build_local_command, "mv /tmp/file /dest", use_sudo: true)
          expect(cmd).to include("sudo -S")
        end

        it "includes timeout to prevent hanging" do
          cmd = no_password_service.send(:build_local_command, "mv /tmp/file /dest", use_sudo: true)
          expect(cmd).to include("timeout")
        end

        it "does not include echo for empty password" do
          cmd = no_password_service.send(:build_local_command, "mv /tmp/file /dest", use_sudo: true)
          expect(cmd).not_to match(/echo.*\|/)
        end
      end

      context "without password (nil)" do
        let(:nil_password_service) do
          described_class.new(
            target_host: "127.0.0.1",
            arch: "x86_64",
            sudo_password: nil,
            local_binary_path: local_path,
            node: localhost_node
          )
        end

        it "still uses sudo -S to prevent TTY hang" do
          cmd = nil_password_service.send(:build_local_command, "mv /tmp/file /dest", use_sudo: true)
          expect(cmd).to include("sudo -S")
        end

        it "includes timeout to prevent hanging" do
          cmd = nil_password_service.send(:build_local_command, "mv /tmp/file /dest", use_sudo: true)
          expect(cmd).to include("timeout")
        end
      end
    end
  end

  describe "server URL normalization" do
    it "strips path from server URL" do
      service = described_class.new(
        target_host: target_host,
        arch: "x86_64",
        sudo_password: sudo_password,
        local_binary_path: local_path,
        node: node,
        server_url: "http://localhost:3000/nodes"
      )

      expect(service.instance_variable_get(:@server_url)).to eq("http://localhost:3000")
    end

    it "preserves non-default ports" do
      service = described_class.new(
        target_host: target_host,
        arch: "x86_64",
        sudo_password: sudo_password,
        local_binary_path: local_path,
        node: node,
        server_url: "http://example.com:8080/some/path"
      )

      expect(service.instance_variable_get(:@server_url)).to eq("http://example.com:8080")
    end

    it "omits default HTTP port 80" do
      service = described_class.new(
        target_host: target_host,
        arch: "x86_64",
        sudo_password: sudo_password,
        local_binary_path: local_path,
        node: node,
        server_url: "http://example.com:80/path"
      )

      expect(service.instance_variable_get(:@server_url)).to eq("http://example.com")
    end

    it "omits default HTTPS port 443" do
      service = described_class.new(
        target_host: target_host,
        arch: "x86_64",
        sudo_password: sudo_password,
        local_binary_path: local_path,
        node: node,
        server_url: "https://example.com:443/path"
      )

      expect(service.instance_variable_get(:@server_url)).to eq("https://example.com")
    end

    it "handles URL without path" do
      service = described_class.new(
        target_host: target_host,
        arch: "x86_64",
        sudo_password: sudo_password,
        local_binary_path: local_path,
        node: node,
        server_url: "http://localhost:3000"
      )

      expect(service.instance_variable_get(:@server_url)).to eq("http://localhost:3000")
    end

    it "handles malformed URL gracefully" do
      service = described_class.new(
        target_host: target_host,
        arch: "x86_64",
        sudo_password: sudo_password,
        local_binary_path: local_path,
        node: node,
        server_url: "not-a-valid-url"
      )

      # Should return the original value when URL parsing fails
      expect(service.instance_variable_get(:@server_url)).to eq("not-a-valid-url")
    end
  end

  describe "improved error handling" do
    describe "error message content" do
      it "includes stdout when stderr is empty" do
        allow(SshConfig).to receive(:jump_host).and_return(nil)

        direct_service = described_class.new(
          target_host: target_host,
          arch: "x86_64",
          bastion_host: nil,
          sudo_password: sudo_password,
          local_binary_path: local_path,
          node: node,
          bastion_user: "root"
        )

        # Mock SSH with stdout output but empty stderr
        stdout_data = "Error: binary not found"
        allow(Net::SSH).to receive(:start).and_yield(ssh_session)

        allow(channel).to receive(:on_data) do |&block|
          block.call(channel, stdout_data)
        end
        allow(channel).to receive(:on_extended_data) do |&block|
          # Empty stderr
        end
        allow(channel).to receive(:on_request).with("exit-status").and_yield(nil, double(read_long: 1))

        expect { direct_service.call }.to raise_error(
          Agent::RemoteInstallService::InstallError,
          /binary not found/
        )
      end

      it "includes the phase/step in error message" do
        allow(SshConfig).to receive(:jump_host).and_return(nil)

        direct_service = described_class.new(
          target_host: target_host,
          arch: "x86_64",
          bastion_host: nil,
          sudo_password: sudo_password,
          local_binary_path: local_path,
          node: node,
          bastion_user: "root"
        )

        allow(Net::SSH).to receive(:start).and_yield(ssh_session)
        allow(channel).to receive(:on_request).with("exit-status").and_yield(nil, double(read_long: 1))

        expect { direct_service.call }.to raise_error(Agent::RemoteInstallService::InstallError) do |error|
          # Error should contain context about what failed
          expect(error.message).to match(/Installation failed|Command failed/)
        end
      end
    end

    describe "SSH connection errors" do
      it "provides clear error for authentication failure" do
        allow(SshConfig).to receive(:jump_host).and_return(nil)

        direct_service = described_class.new(
          target_host: target_host,
          arch: "x86_64",
          bastion_host: nil,
          sudo_password: sudo_password,
          local_binary_path: local_path,
          node: node,
          bastion_user: "root"
        )

        allow(Net::SSH).to receive(:start).and_raise(Net::SSH::AuthenticationFailed.new("admin"))

        expect { direct_service.call }.to raise_error(
          Agent::RemoteInstallService::InstallError,
          /Authentication failed/i
        )
      end

      it "provides clear error for connection refused" do
        allow(SshConfig).to receive(:jump_host).and_return(nil)

        direct_service = described_class.new(
          target_host: target_host,
          arch: "x86_64",
          bastion_host: nil,
          sudo_password: sudo_password,
          local_binary_path: local_path,
          node: node,
          bastion_user: "root"
        )

        allow(Net::SSH).to receive(:start).and_raise(Errno::ECONNREFUSED)

        expect { direct_service.call }.to raise_error(
          Agent::RemoteInstallService::InstallError,
          /Connection refused/i
        )
      end

      it "provides clear error for host unreachable" do
        allow(SshConfig).to receive(:jump_host).and_return(nil)

        direct_service = described_class.new(
          target_host: target_host,
          arch: "x86_64",
          bastion_host: nil,
          sudo_password: sudo_password,
          local_binary_path: local_path,
          node: node,
          bastion_user: "root"
        )

        allow(Net::SSH).to receive(:start).and_raise(Errno::EHOSTUNREACH)

        expect { direct_service.call }.to raise_error(
          Agent::RemoteInstallService::InstallError,
          /Host unreachable/i
        )
      end

      it "provides clear error for connection timeout" do
        allow(SshConfig).to receive(:jump_host).and_return(nil)

        direct_service = described_class.new(
          target_host: target_host,
          arch: "x86_64",
          bastion_host: nil,
          sudo_password: sudo_password,
          local_binary_path: local_path,
          node: node,
          bastion_user: "root"
        )

        allow(Net::SSH).to receive(:start).and_raise(Net::SSH::ConnectionTimeout)

        expect { direct_service.call }.to raise_error(
          Agent::RemoteInstallService::InstallError,
          /timed out/i
        )
      end
    end
  end
end
