# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Node Management", type: :system, js: true do
  include ActionView::RecordIdentifier
  let(:user) { create(:user, :approver) }

  let!(:initial_node) { create(:node, hostname: "initial-node") }

  before do
    sign_in user
  end

  it "allows an approver to add a new node with SSH settings" do
    visit nodes_path
    click_link "Add Node"

    within "turbo-frame#node_modal" do
      # Step 1: Basic Information
      fill_in "Hostname", with: "compute-001"
      fill_in "IP Address", with: "192.168.1.100"
      select "Compute", from: "Role"
      select "x86_64", from: "Architecture"
      click_button "Next"

      # Step 2: Server & Location (skip through)
      click_button "Next"

      # Step 3: Connection - SSH Connection (override-based form)
      expect(page).to have_content(/SSH Connection/i)

      # Enable SSH User override and fill in
      check "Override SSH User"
      fill_in "node[ssh_user]", with: "deploy"

      # Enable SSH Port override and fill in
      check "Override SSH Port"
      fill_in "node[ssh_port]", with: "22"

      click_button "Save Node"
    end

    expect(page).to have_content("compute-001")
    expect(page).to have_content("192.168.1.100")

    node = Node.find_by(hostname: "compute-001")
    expect(node).to be_present
    expect(node.ssh_port).to eq(22)
    expect(node.ssh_user).to eq("deploy")
    expect(node.ssh_user_override).to be true
    expect(node.ssh_port_override).to be true

    # Ensure modal is closed
    expect(page).not_to have_selector("turbo-frame#node_modal .card-netbox")
  end

end
