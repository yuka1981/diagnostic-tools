require 'rails_helper'

RSpec.describe 'UI Overhaul', type: :system do
  let(:user) { create(:user) }
  let(:node) { create(:node, hostname: 'test-node') }

  before do
    login_as(user)
  end

  describe 'Layout' do
    it 'renders the sidebar with correct sections' do
      visit dashboard_path

      within('aside') do
        expect(page).to have_content('InfraScope') # Brand
        expect(page).to have_content(/ORGANIZATION/i) # Section header
        expect(page).to have_link('Dashboard')
        expect(page).to have_link('Nodes')
        expect(page).to have_content(/BENCHMARKS/i) # Section header
        expect(page).to have_link('Benchmark Runs')
      end
    end

    it 'renders the navbar with user profile' do
      visit dashboard_path

      within('header') do
        expect(page).to have_content(user.name || user.email)
      end

      # Breadcrumb check
      expect(page).to have_content('Dashboard')
    end
  end

  describe 'Node Details' do
    it 'renders the new object view structure with tabs' do
      visit node_path(node)

      expect(page).to have_content(node.hostname)

      # Verify Tabs exist
      within('.tabs') do
        expect(page).to have_link('Overview')
        expect(page).to have_link('Hardware')
        expect(page).to have_link('Benchmark History')
        expect(page).to have_link('Logs')
      end
    end
  end
end
