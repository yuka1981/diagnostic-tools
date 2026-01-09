# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Node SSH Settings", type: :system do
  let(:admin) { create(:user, :approver) }

  before do
    sign_in admin
    SshSetting.current.update!(bastion_host: "global.bastion", bastion_user: "global-user", bastion_port: 22)
  end

  it "allows selecting connection method when creating a node" do
    visit new_node_path

    fill_in "Hostname", with: "custom-node"
    select "Custom bastion", from: "Connection Method"

    # Custom fields should be visible (handled by stimulus controller, but capybara sees them)
    # We need to fill them in
    fill_in "Jump Host", with: "custom.bastion"
    fill_in "Jump User", with: "custom-user"
    fill_in "Jump Port", with: "2222"

    click_button "Save Node"

    expect(page).to have_content("Node was successfully created")

    node = Node.last
    expect(node.ssh_connect_method).to eq("custom_bastion")
    expect(node.jump_host).to eq("custom.bastion")
    expect(node.jump_user).to eq("custom-user")
    expect(node.jump_port).to eq(2222)
  end

  it "preloads correct bastion settings in install modal" do
    # 1. Global Bastion Node
    global_node = create(:node, hostname: "global-node", ssh_connect_method: :global_bastion)
    visit new_node_install_path(hostname: global_node.hostname)

    # We check that the form renders correctly under the new NetBox theme
    within('turbo-frame#install_modal') do
      expect(page).to have_content("Install Agent: global-node")
      expect(page).to have_button("Begin Installation")
    end
  end
end
