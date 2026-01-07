# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent::UninstallJob, type: :job do
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
      bastion_host: "10.0.0.1",
      bastion_user: "admin",
      credentials_cache_key: cache_key
    }
  end

  let(:uninstaller) { instance_double(Agent::RemoteUninstallService, call: true) }

  before do
    allow(Agent::RemoteUninstallService).to receive(:new).and_return(uninstaller)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    Rails.cache.write("install_creds_#{cache_key}", credentials)
  end

  it "uninstalls the agent" do
    described_class.perform_now(**params)

    expect(Agent::RemoteUninstallService).to have_received(:new).with(hash_including(
                                                                     bastion_host: "10.0.0.1",
                                                                     bastion_password: "password",
                                                                     sudo_password: "sudo_password"
                                                                   ))
    expect(uninstaller).to have_received(:call)

    # Verify broadcasts
    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
      "agent_uninstall_compute-001",
      hash_including(locals: hash_including(status: "success"))
    )
    expect(Rails.cache.read("install_creds_#{cache_key}")).to be_nil
  end

  it "broadcasts error if uninstallation fails" do
    allow(uninstaller).to receive(:call).and_raise(Agent::RemoteUninstallService::UninstallError, "Failed")

    described_class.perform_now(**params)

    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
      "agent_uninstall_compute-001",
      hash_including(locals: hash_including(status: "error", message: "Failed"))
    )
  end
end
