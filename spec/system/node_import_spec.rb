# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Node Import", type: :system, js: true do
  let(:user) { create(:user, :approver) }
  let!(:node) { create(:node) }

  before do
    sign_in user
  end

  it "allows importing nodes via CSV with drag and drop" do
    visit nodes_path
    click_link "Import CSV"

    within "turbo-frame#import_modal" do
      expect(page).to have_content(/Import Nodes from CSV/i)
      expect(page).to have_content(/Click to upload or drag and drop/i)

      # Test that the Stimulus controller is connected by checking for the zone target
      expect(page).to have_css("[data-file-drop-target='zone']")

      # Note: Testing actual drag and drop in Capybara is tricky,
      # but we can at least verify the file input is there.
      expect(page).to have_field("file", type: "file", visible: false)
    end
  end
end
