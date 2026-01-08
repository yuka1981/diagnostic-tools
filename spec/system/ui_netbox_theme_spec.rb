require 'rails_helper'

RSpec.describe 'UI NetBox Theme Migration', type: :system do
  let(:user) { create(:user, :approver) }
  let!(:node) { create(:node, hostname: 'netbox-node') }

  before do
    login_as(user)
  end

  describe 'Global Layout' do
    it 'has the correct theme colors and structure' do
      visit dashboard_path

      # Sidebar
      expect(page).to have_selector('aside.bg-slate-900')

      # Top Header
      expect(page).to have_selector('header.bg-white.border-slate-200')

      # Page Background
      expect(page).to have_selector('html.bg-slate-100')
    end

    it 'renders breadcrumbs' do
      visit nodes_path
      within('.breadcrumb', match: :first) do
        expect(page).to have_link('Home')
        expect(page).to have_content('Nodes')
      end
    end
  end

  describe 'Node Details (Object View)' do
    it 'matches NetBox device view layout' do
      visit node_path(node)

      # Title and Status Badge
      expect(page).to have_css('h1', text: node.hostname)

      # Action Buttons (Edit should use secondary style but be present)
      expect(page).to have_link('Edit')

      # Tabs
      expect(page).to have_css('.tabs')

      # Grid Layout (col-span-6 for panels)
      expect(page).to have_selector('.grid-cols-12')
    end
  end

  describe 'Data Tables' do
    it 'uses dense text-sm typography' do
      visit nodes_path
      expect(page).to have_selector('table.text-sm')
    end
  end

  describe 'Forms' do
    it 'uses NetBox input styles' do
      visit new_node_path
      # Use a selector that doesn't trigger pseudo-class issues in Capybara
      expect(page).to have_css('input[class*="focus:ring-teal-500"]')
    end
  end
end
