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
      fill_in "Hostname", with: "compute-001"
      fill_in "IP Address", with: "192.168.1.100"
      select "Compute", from: "Role"
      select "x86_64", from: "Architecture"

      expect(page).to have_content(/SSH Configuration/i)
      fill_in "SSH Port", with: "22"
      fill_in "SSH User", with: "deploy"
      fill_in "Sudo Password", with: "secret-password"
      fill_in "SSH Key (optional)", with: "ssh-rsa AAAAB3Nza..."

      click_button "Save Node"
    end

    expect(page).to have_content("compute-001")
    expect(page).to have_content("192.168.1.100")

    node = Node.find_by(hostname: "compute-001")
    expect(node).to be_present
    expect(node.ssh_port).to eq(22)
    expect(node.ssh_user).to eq("deploy")

    # Ensure modal is closed
    expect(page).not_to have_selector("turbo-frame#node_modal .card-netbox")
  end

  it "allows an approver to remove an agent" do
    node = create(:node, hostname: "uninstall-target", source: :agent_push, ip: "10.0.0.5")
    visit nodes_path

    # Use a more specific selector to avoid intercepting other elements
    within "tr##{dom_id(node)}" do
      find("a[title='Uninstall Agent']").click
    end

    # Mock the background job service to succeed immediately
    uninstaller = instance_double(Agent::RemoteUninstallService, call: true)
    allow(Agent::RemoteUninstallService).to receive(:new).and_return(uninstaller)

    within "turbo-frame#uninstall_modal" do
      expect(page).to have_content(/Uninstall Agent: uninstall-target/i)

      fill_in "Remote Sudo Password", with: "secret"
      fill_in "SSH Password / Key Passphrase", with: "password"

      click_button "Begin Uninstallation"

      # Wait for the processing state
      expect(page).to have_content(/Uninstalling Agent.../i)
    end

    # We need to ensure the job runs and broadcasts
    # Since we are in a system test with JS, the job will actually run if we use perform_enqueued_jobs
    # or we can just manually trigger the broadcast that the job would do,
    # but we need to wait for the subscription to be active.

    # Wait a bit for ActionCable subscription
    sleep 1

    Turbo::StreamsChannel.broadcast_replace_to(
      "agent_uninstall_uninstall-target",
      target: "agent_uninstall_status_uninstall-target",
      partial: "nodes/uninstalls/status",
      locals: {
        status: "success",
        message: "Agent uninstalled successfully",
        target_host: "uninstall-target",
        steps: Agent::RemoteUninstallService::STEPS
      }
    )

    # Verify the successful state arrived via Turbo Stream
    expect(page).to have_content(/Uninstallation Successful/i, wait: 10)
    click_link "Done"

    expect(page).to have_current_path(nodes_path)
  end

  it "disables the Install button if the agent is already installed" do
    create(:node, hostname: "already-installed", source: :agent_push)
    visit nodes_path

    within "tr", text: "already-installed" do
      expect(page).to have_css("span[title='hpc-agent is already installed']")
      expect(page).not_to have_link(title: "Install Agent")
    end
  end

  it "disables the Uninstall button if the agent is not installed" do
    create(:node, hostname: "not-installed", source: :manual)
    visit nodes_path

    within "tr", text: "not-installed" do
      expect(page).to have_css("span[title='hpc-agent is not installed']")
      expect(page).not_to have_link(title: "Uninstall Agent")
    end
  end
end
