# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Node SSH Settings", type: :system, js: true do
  let(:admin) { create(:user, :approver) }

  before do
    sign_in admin
    SshSetting.current.update!(
      bastion_host: "global.bastion",
      bastion_user: "global-user",
      bastion_port: 22,
      ssh_user: "global-ssh-user",
      ssh_port: 22
    )
  end

  it "allows configuring SSH overrides when creating a node", js: true do
    visit new_node_path

    fill_in "Hostname", with: "override-node"

    # Navigate to step 3 (Connection)
    click_button "Next"
    click_button "Next"

    # Enable SSH user override
    check "Override SSH User"
    fill_in "SSH User", with: "custom-user"

    click_button "Save Node"

    expect(page).to have_content("Node was successfully created")

    node = Node.last
    expect(node.ssh_user_override).to be true
    expect(node.ssh_user).to eq("custom-user")
    expect(node.effective_ssh_user).to eq("custom-user")
  end

  it "uses global defaults when overrides are not enabled" do
    node = create(:node, hostname: "default-node", ssh_user_override: false)

    expect(node.effective_ssh_user).to eq("global-ssh-user")
    expect(node.effective_ssh_port).to eq(22)
  end

  it "preloads correct bastion settings in install modal" do
    global_node = create(:node, hostname: "global-node", ssh_connect_method: :global_bastion)
    visit new_node_install_path(hostname: global_node.hostname)

    within("turbo-frame#install_modal") do
      expect(page).to have_content("Install Agent: global-node")
      expect(page).to have_button("Begin Installation")
    end
  end
end
