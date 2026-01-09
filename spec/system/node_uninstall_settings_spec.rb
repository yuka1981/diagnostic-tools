# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Node Uninstall Settings", type: :system do
  let(:admin) { create(:user, :approver) }

  before do
    sign_in admin
    SshSetting.current.update!(bastion_host: "global.bastion", bastion_user: "global-user", bastion_port: 22)
  end

  it "preloads correct bastion settings in uninstall modal" do
    # 1. Global Bastion Node
    global_node = create(:node, :agent_push, hostname: "global-node", ssh_connect_method: :global_bastion)
    visit new_node_uninstall_path(hostname: global_node.hostname)

    within('turbo-frame#uninstall_modal') do
      expect(page).to have_content("Uninstall Agent: global-node")
      expect(page).to have_button("Begin Uninstallation")
    end
  end
end
