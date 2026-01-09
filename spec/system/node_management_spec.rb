# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Node Management", type: :system, js: true do
  include ActionView::RecordIdentifier
  let(:user) { create(:user, :approver) }

  let!(:initial_node) { create(:node, hostname: "initial-node") }

  before do
    sign_in user
    # Hide sidebar to prevent interception in tests
    if RSpec.current_example.metadata[:js]
      visit root_path # Ensure we are on a page to execute script
      page.execute_script("document.querySelector('aside').style.display = 'none'")
    end
  end

  it "allows an approver to add a new node with SSH settings" do
    visit nodes_path
    click_link "Add Node"

    within "#node_modal" do
      fill_in "Hostname", with: "compute-001"
      fill_in "IP Address", with: "192.168.1.100"
      select "Compute", from: "Role"
      select "x86_64", from: "Architecture"

      expect(page).to have_content(/SSH Configuration/i)
      fill_in "SSH Port", with: "22"
      fill_in "SSH User", with: "deploy"
      fill_in "User password", with: "secret-password"
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
    expect(page).not_to have_selector("#node_modal .fixed")
  end

  it "allows an approver to remove an agent" do
    node = create(:node, hostname: "uninstall-target", source: :agent_push, ip: "10.0.0.5")
    visit nodes_path

    # Ensure any previous modals are closed
    expect(page).not_to have_selector(".fixed.inset-0")

    # Use a more specific selector to avoid intercepting other elements
    within "tr##{dom_id(node)}" do
      find("a[title='Uninstall Agent']").click
    end

    within "#uninstall_modal" do
      expect(page).to have_field("Hostname", with: "uninstall-target", readonly: true)
      # Check IP address (using have_field or generic find since it's a raw input in my previous replace)
      # In my previous replace I used <input type="text" value="<%= @node&.ip %>" readonly ...>
      # It doesn't have a name/id that have_field might easily find unless I add label.
      # Wait, I did add label: <%= f.label :ip, "IP Address" %>
      expect(page).to have_field("IP Address", with: "10.0.0.5", readonly: true)

      fill_in "Sudo Password (Required)", with: "secret"

      # Mock the background job behavior
      uninstaller = instance_double(Agent::RemoteUninstallService, call: true)
      allow(Agent::RemoteUninstallService).to receive(:new).and_return(uninstaller)

      click_button "Confirm Removal"

      # Wait for the "Uninstalling Agent..." processing state
      expect(page).to have_content("Uninstalling Agent...")
      expect(page).to have_content("Connecting to host")
    end

    # The job is async, but we can simulate the broadcast that the job would do
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
    expect(page).to have_content("Uninstallation Successful")
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

  it "navigates to node details when clicking hostname" do
    visit nodes_path

    within "tr##{dom_id(initial_node)}" do
      click_link initial_node.hostname
    end

    expect(page).to have_current_path(node_path(initial_node))
    expect(page).to have_content(initial_node.hostname)
    # expect(page).to have_content("Host Information") # Only shown if state exists, initial_node might be bare
  end
end
