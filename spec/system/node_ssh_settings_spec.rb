# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Node SSH Settings", type: :system, js: true do
  let(:admin) { create(:user, :approver) }
  let!(:existing_node) { create(:node, hostname: "existing-node") }

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
    visit nodes_path
    click_link "Add Node"

    within "turbo-frame#node_modal" do
      fill_in "Hostname", with: "override-node"

      # Navigate to step 3 (Connection)
      click_button "Next"
      click_button "Next"

      # Enable SSH user override and wait for field to be visible
      check "Override SSH User"
      # Wait for the field to become visible after checkbox toggle
      expect(page).to have_field("node[ssh_user]", visible: true)
      fill_in "node[ssh_user]", with: "custom-user"

      click_button "Save Node"
    end

    # Wait for node to appear in list (turbo_stream appends to table)
    expect(page).to have_content("override-node", wait: 5)

    # Ensure modal is closed
    expect(page).not_to have_selector("turbo-frame#node_modal .card-netbox")

    node = Node.find_by(hostname: "override-node")
    expect(node).to be_present
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
      # Modal title uses CSS uppercase transform, so match case-insensitively
      expect(page).to have_content(/Install Agent: global-node/i)
      expect(page).to have_button("Begin Installation")
    end
  end
end
