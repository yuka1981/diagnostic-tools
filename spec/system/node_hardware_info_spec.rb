require 'rails_helper'

RSpec.describe 'Node Hardware Info', type: :system do
  let(:user) { create(:user, :approver) }
  let!(:node) { create(:node, hostname: 'hardware-node') }
  let!(:node_state) { create(:node_state, :complete, node: node) }

  before do
    login_as(user)
  end

  it 'displays detailed hardware information including DMI data' do
    visit node_path(node)

    # Switch to Hardware tab
    click_link 'Hardware'

    # Check System Info
    within('.card-netbox', text: 'System', match: :first) do
      expect(page).to have_content('Manufacturer Inc.')
      expect(page).to have_content('SuperServer 123')
      expect(page).to have_content('SN123456789')
    end

    # Check BIOS Info
    within('div.card-netbox', text: 'BIOS') do
      expect(page).to have_content('AMI')
      expect(page).to have_content('V1.2.3')
    end

    # Check Memory Topology
    expect(page).to have_content('Memory Topology')
    expect(page).to have_content('P0_Node0_Channel0')
    expect(page).to have_content('32 GB')
    expect(page).to have_content('DIMM_A1')
    expect(page).to have_content('Empty')
    expect(page).to have_content('DIMM_A2')

    # Check Memory Detailed Table
    within('div.card-netbox', text: 'Memory Devices') do
      expect(page).to have_content('DIMM_A1')
      expect(page).to have_content('32 GB')
      expect(page).to have_content('Samsung')
      expect(page).to have_css('span', text: 'Active')

      expect(page).to have_content('DIMM_A2')
      expect(page).to have_css('span', text: 'Empty')
    end
  end
end
