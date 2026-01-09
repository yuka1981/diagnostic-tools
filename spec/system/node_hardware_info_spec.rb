require 'rails_helper'

RSpec.describe 'Node Hardware Info', type: :system, js: true do
  let(:user) { create(:user, :approver) }
  let!(:node) { create(:node, hostname: 'hardware-node') }
  let!(:node_state) { create(:node_state, :complete, node: node) }

  before do
    login_as(user)
  end

  it 'displays detailed hardware information including DMI data' do
    visit node_path(node)

    # Switch to Hardware tab
    find('a', text: /HARDWARE/i).click

    # Wait for content to be visible
    expect(page).to have_selector('.card-netbox', text: /SYSTEM/i, visible: true)

    # Check System Info
    within('.card-netbox', text: /SYSTEM/i, match: :first) do
      expect(page).to have_content('Manufacturer Inc.')
      expect(page).to have_content('SuperServer 123')
      expect(page).to have_content('SN123456789')
    end

    # Check Memory Topology (Hidden by default)
    within('div.card-netbox', text: /MEMORY TOPOLOGY/i) do
      expect(page).not_to have_selector('div[data-disclosure-target="content"]', visible: true)
      
      # Test Toggle - Show
      find('button[role="switch"]').click
      expect(page).to have_selector('div[data-disclosure-target="content"]', visible: true)
      expect(page).to have_content('32G')
      expect(page).to have_content('A1')
    end

    # Check Memory Detailed Table (Hidden by default)
    within('div.card-netbox', text: /MEMORY DEVICES/i) do
      expect(page).not_to have_selector('table', visible: true)

      # Test Toggle - Show
      find('button[role="switch"]').click
      expect(page).to have_selector('table', visible: true)
      
      expect(page).to have_content('DIMM_A1')
      expect(page).to have_content('32 GB')
      expect(page).to have_content('Samsung')
      expect(page).to have_css('span', text: /ACTIVE/i)
      
      expect(page).to have_content('DIMM_A2')
      expect(page).to have_css('span', text: /EMPTY/i)

      # Test Toggle - Hide again
      find('button[role="switch"]').click
      expect(page).not_to have_selector('table', visible: true)
    end
  end
end
