# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Rooms', type: :system do
  let(:user) { create(:user, :approver) }
  let!(:room) { create(:room, name: 'Data Center A') }
  let!(:rack1) { create(:equipment_rack, name: 'R01', room: room, row: 'Row A') }
  let!(:rack2) { create(:equipment_rack, name: 'R02', room: room, row: 'Row A') }

  before do
    login_as(user)
  end

  describe 'Room show page' do
    describe 'Rack Elevation Overview legend' do
      it 'displays legend at the top of the Rack Elevation Overview section' do
        visit room_path(room)

        within('.card-netbox', text: 'Rack Elevation Overview') do
          # The legend should appear before the row groups
          # Check that the legend div with border-b (top separator) exists
          expect(page).to have_css('.mb-4.pb-4.border-b')

          # Verify legend contains the three status indicators
          legend = find('.mb-4.pb-4.border-b')
          expect(legend).to have_content('Online')
          expect(legend).to have_content('Offline')
          expect(legend).to have_content('Empty')
        end
      end

      it 'displays legend with updated colors' do
        visit room_path(room)

        within('.card-netbox', text: 'Rack Elevation Overview') do
          legend = find('.mb-4.pb-4.border-b')

          # Check updated color classes
          expect(legend).to have_css('.bg-emerald-600')  # Online - updated from emerald-500
          expect(legend).to have_css('.bg-slate-600')    # Offline - updated from slate-400
          expect(legend).to have_css('.bg-slate-100')    # Empty - updated from slate-50
        end
      end

      it 'does not have legend at the bottom with old styling' do
        visit room_path(room)

        within('.card-netbox', text: 'Rack Elevation Overview') do
          # Should NOT have the old bottom legend styling
          expect(page).not_to have_css('.mt-4.pt-4.border-t.border-slate-200.flex.items-center')
        end
      end
    end
  end
end
