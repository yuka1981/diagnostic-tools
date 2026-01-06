# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Node Management", type: :system, js: true do
  let(:user) { create(:user, :approver) }

  let!(:initial_node) { create(:node, hostname: "initial-node") }

  before do
    sign_in user
  end

  it "allows an approver to add a new node with SSH settings" do
    visit nodes_path
    click_link "Add Node"

    within "#node_modal" do
      fill_in "Hostname", with: "compute-001"
      fill_in "IP Address", with: "192.168.1.100"
      select "Compute", from: "Role"
      select "x86_64", from: "Architecture"

      expect(page).to have_content("SSH Settings")
      fill_in "SSH Port", with: "22"
      fill_in "SSH User", with: "deploy"
      fill_in "User password", with: "secret-password"
      fill_in "SSH Key (optional)", with: "ssh-rsa AAAAB3Nza..."

      click_button "Save Node"
    end

    # Wait for the database record to be created
    expect {
      Timeout.timeout(5) do
        loop do
          break if Node.exists?(hostname: "compute-001")
          sleep 0.1
        end
      end
    }.not_to raise_error

    expect(page).to have_content("compute-001")
    expect(page).to have_content("192.168.1.100")

    node = Node.find_by(hostname: "compute-001")
    expect(node).to be_present
    expect(node.ssh_port).to eq(22)
    expect(node.ssh_user).to eq("deploy")
    # Virtual attributes are not persisted, so we can't check them on the model after reload
  end
end
