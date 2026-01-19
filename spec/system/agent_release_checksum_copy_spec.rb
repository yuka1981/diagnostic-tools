# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Agent Release Checksum Copy", type: :system do
  let(:user) { create(:user, :approver) }
  let(:agent_release) { create(:agent_release, :without_binary, version: "v1.0.0") }

  before do
    sign_in user
  end

  describe "checksum copy to clipboard" do
    context "with multi-arch binaries" do
      let!(:agent_binary) do
        create(:agent_binary, agent_release: agent_release, arch: "x86_64")
      end

      it "displays copy button next to checksum", :js do
        visit settings_agent_release_path(agent_release)

        expect(page).to have_content(/binaries/i)
        expect(page).to have_css("[data-controller='clipboard']")
        expect(page).to have_css("[data-clipboard-target='source']", visible: :all)
        expect(page).to have_css("[data-action='click->clipboard#copy']")
      end

      it "copies checksum to clipboard when clicking copy button", :js do
        visit settings_agent_release_path(agent_release)

        # Find the copy button and click it
        copy_button = find("[data-action='click->clipboard#copy']", match: :first)
        copy_button.click

        # The button should show success feedback (icon changes or tooltip)
        expect(page).to have_css("[data-clipboard-target='success']", visible: true, wait: 2)
      end

      it "shows full checksum in hidden element for copying", :js do
        visit settings_agent_release_path(agent_release)

        # The full checksum should be in a hidden element - use JS to get text content
        checksum_text = page.evaluate_script(
          "document.querySelector('[data-clipboard-target=\"source\"]').textContent.trim()"
        )
        expect(checksum_text).to eq(agent_binary.checksum)
      end

      it "reverts to copy icon after success feedback", :js do
        visit settings_agent_release_path(agent_release)

        copy_button = find("[data-action='click->clipboard#copy']", match: :first)
        copy_button.click

        # Should show success first
        expect(page).to have_css("[data-clipboard-target='success']", visible: true, wait: 2)

        # Then revert to normal state after timeout
        expect(page).to have_css("[data-clipboard-target='icon']", visible: true, wait: 3)
        expect(page).to have_css("[data-clipboard-target='success']", visible: :hidden, wait: 3)
      end
    end

    context "with legacy single binary" do
      let(:legacy_release) { create(:agent_release, version: "v2.0.0") }

      before do
        # Ensure no multi-arch binaries exist
        legacy_release.agent_binaries.destroy_all
      end

      it "displays copy button next to legacy checksum", :js do
        visit settings_agent_release_path(legacy_release)

        expect(page).to have_content("SHA256 Checksum")
        expect(page).to have_css("[data-controller='clipboard']")
      end
    end

    context "when checksum is not present" do
      let!(:agent_binary) do
        binary = create(:agent_binary, agent_release: agent_release, arch: "x86_64")
        binary.update_column(:checksum, nil)
        binary
      end

      it "does not display copy button when checksum is missing", :js do
        visit settings_agent_release_path(agent_release)

        # Should show dash instead of checksum with copy button
        expect(page).to have_content("—")
        # No clipboard controller when checksum is nil
        expect(page).not_to have_css("[data-controller='clipboard']")
      end
    end
  end

  describe "clicking on truncated checksum" do
    let!(:agent_binary) do
      create(:agent_binary, agent_release: agent_release, arch: "x86_64")
    end

    it "allows clicking on checksum text to copy", :js do
      visit settings_agent_release_path(agent_release)

      # The checksum text itself should be clickable
      checksum_element = find("[data-action='click->clipboard#copy']", match: :first)
      expect(checksum_element).to be_visible

      checksum_element.click

      # Should show success feedback
      expect(page).to have_css("[data-clipboard-target='success']", visible: true, wait: 2)
    end
  end
end
