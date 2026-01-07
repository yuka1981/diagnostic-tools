# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Settings::SshSettings", type: :system do
  let(:admin) { create(:user, :approver) }

  before do
    sign_in admin
  end

  it "allows updating global SSH settings" do
    visit settings_ssh_path

    # Check initial state
    expect(page).to have_content("SSH Settings")
    expect(page).to have_content("Global Bastion Configuration")

    # Fill in the form
    fill_in "Bastion Hostname or IP", with: "bastion.example.com"
    fill_in "Bastion SSH User", with: "admin-user"
    fill_in "SSH Port", with: "2222"

    click_button "Save Settings"

    # Verify success message
    expect(page).to have_content("SSH settings updated successfully")

    # Verify persisted values
    expect(page).to have_field("Bastion Hostname or IP", with: "bastion.example.com")
    expect(page).to have_field("Bastion SSH User", with: "admin-user")
    expect(page).to have_field("SSH Port", with: "2222")

    # Verify database state
    setting = SshSetting.current
    expect(setting.bastion_host).to eq("bastion.example.com")
    expect(setting.bastion_user).to eq("admin-user")
    expect(setting.bastion_port).to eq(2222)
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
