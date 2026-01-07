# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Node Uninstall Settings", type: :system do
  let(:admin) { create(:user, :approver) }

  before do
    sign_in admin
    SshSetting.current.update!(bastion_host: "global.bastion", bastion_user: "global-user", bastion_port: 22)
  end

  it "preloads correct bastion settings in uninstall modal based on connection method" do
    # 1. Global Bastion Node
    global_node = create(:node, :agent_push, hostname: "global-node", ssh_connect_method: :global_bastion)
    visit new_node_uninstall_path(hostname: global_node.hostname)
    expect(find_field("Bastion Host (Optional)").value).to eq("global.bastion")

    # 2. Custom Bastion Node
    custom_node = create(:node, :agent_push, hostname: "custom-node", ssh_connect_method: :custom_bastion, jump_host: "custom.bastion", jump_user: "custom-user")
    visit new_node_uninstall_path(hostname: custom_node.hostname)
    expect(find_field("Bastion Host (Optional)").value).to eq("custom.bastion")
    expect(find_field("SSH/Bastion User (Optional)").value).to eq("custom-user")

    # 3. Direct Connection Node
    direct_node = create(:node, :agent_push, hostname: "direct-node", ssh_connect_method: :direct)
    visit new_node_uninstall_path(hostname: direct_node.hostname)
    expect(find_field("Bastion Host (Optional)").value).to be_nil.or be_empty
  end
end
