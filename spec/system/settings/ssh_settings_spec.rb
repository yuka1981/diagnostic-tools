# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Settings::SshDefaults", type: :system do
  let(:admin) { create(:user, :approver) }

  before do
    sign_in admin
  end

  it "allows updating global SSH settings" do
    visit settings_ssh_defaults_path

    # Check initial state
    expect(page).to have_content("SSH Defaults")
    expect(page).to have_content("Bastion / Jump Host")

    # Fill in the form
    fill_in "Host", with: "bastion.example.com"
    fill_in "node[bastion_user]", with: "admin-user", visible: false
    fill_in "node[bastion_port]", with: "2222", visible: false

    click_button "Save SSH Defaults"

    # Verify success message
    expect(page).to have_content("SSH defaults updated successfully")

    # Verify database state
    setting = SshSetting.current
    expect(setting.bastion_host).to eq("bastion.example.com")
  end

  it "allows updating global Agent settings" do
    visit settings_agent_path

    # Check initial state
    expect(page).to have_content("Agent Configuration")
    expect(page).to have_content("Reporting Settings")

    # Fill in the form
    fill_in "Server URL (Reporting Endpoint)", with: "https://hpc.example.com"

    click_button "Save Configuration"

    # Verify success message
    expect(page).to have_content("Agent configuration updated successfully")

    # Verify persisted values
    expect(page).to have_field("Server URL (Reporting Endpoint)", with: "https://hpc.example.com")

    # Verify database state
    setting = SshSetting.current
    expect(setting.server_url).to eq("https://hpc.example.com")
  end
end
