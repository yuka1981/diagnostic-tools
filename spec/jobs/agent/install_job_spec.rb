# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent::InstallJob, type: :job do
  let(:cache_key) { "test_cache_key" }
  let(:credentials) do
    {
      bastion_password: "password",
      sudo_password: "sudo_password"
    }
  end
  let(:params) do
    {
      target_host: "compute-001",
      arch: "x86_64",
      bastion_user: "admin",
      credentials_cache_key: cache_key,
      server_url: "http://test.com"
    }
  end

  let(:compiler) { instance_double(Agent::CompilerService, call: "/tmp/agent") }
  let(:installer) { instance_double(Agent::RemoteInstallService, call: true) }

  before do
    allow(Agent::CompilerService).to receive(:new).and_return(compiler)
    allow(Agent::RemoteInstallService).to receive(:new).and_return(installer)
    allow(FileUtils).to receive(:rm_f)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    Rails.cache.write("install_creds_#{cache_key}", credentials)
  end

  it "compiles and installs the agent" do
    described_class.perform_now(**params)

    expect(compiler).to have_received(:call)
    expect(Agent::RemoteInstallService).to have_received(:new).with(hash_including(
                                                                     bastion_password: "password",
                                                                     sudo_password: "sudo_password"
                                                                   ))
    expect(installer).to have_received(:call)

    # Verify intermediate broadcasts
    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
      "agent_install_compute-001",
      hash_including(locals: hash_including(status: "processing", message: "Compiling Go agent for x86_64"))
    )

    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
      "agent_install_compute-001",
      hash_including(locals: hash_including(status: "success"))
    )
    expect(Rails.cache.read("install_creds_#{cache_key}")).to be_nil
  end

  it "broadcasts error if installation fails" do
    allow(installer).to receive(:call).and_raise(Agent::RemoteInstallService::InstallError, "Failed")

    described_class.perform_now(**params)

    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
      "agent_install_compute-001",
      hash_including(locals: hash_including(status: "error", message: "Failed"))
    )
  end

  it "broadcasts error if credentials expired" do
    Rails.cache.delete("install_creds_#{cache_key}")

    described_class.perform_now(**params)

    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
      "agent_install_compute-001",
      hash_including(locals: hash_including(status: "error", message: "Installation failed: Credentials expired or not found. Please try again."))
    )
  end
end
