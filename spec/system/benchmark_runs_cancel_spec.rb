# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Benchmark Runs Cancel Functionality", type: :system do
  let(:user) { create(:user) }
  let(:node) { create(:node, hostname: "compute-001") }
  let(:recipe) { create(:benchmark_recipe, name: "HPL", version: "2.3.0") }

  before do
    sign_in user
  end

  describe "cancel button on index page" do
    context "with pending benchmark run" do
      let!(:pending_run) { create(:benchmark_run, :pending, node: node, benchmark_recipe: recipe) }

      it "displays cancel icon button for pending runs", :js do
        visit benchmark_runs_path

        within("#benchmark_run_#{pending_run.id}") do
          expect(page).to have_css("[title='Cancel']")
          expect(page).to have_css("svg") # Icon instead of text
        end
      end

      it "cancels run when clicking cancel icon and confirming", :js do
        visit benchmark_runs_path

        within("#benchmark_run_#{pending_run.id}") do
          accept_confirm("Are you sure you want to cancel this benchmark run?") do
            find("[title='Cancel']").click
          end
        end

        # Wait for the status to update
        expect(page).to have_content("Cancelled", wait: 5)
        expect(pending_run.reload.status).to eq("cancelled")
      end

      it "does not cancel run when dismissing confirmation", :js do
        visit benchmark_runs_path

        within("#benchmark_run_#{pending_run.id}") do
          dismiss_confirm("Are you sure you want to cancel this benchmark run?") do
            find("[title='Cancel']").click
          end
        end

        # Status should remain pending
        expect(pending_run.reload.status).to eq("pending")
      end
    end

    context "with running benchmark run" do
      let!(:running_run) { create(:benchmark_run, :running, node: node, benchmark_recipe: recipe) }

      before do
        # Mock SSH for running benchmark cancellation
        mock_channel = instance_double(Net::SSH::Connection::Channel)
        mock_session = instance_double(Net::SSH::Connection::Session, loop: true)

        allow(mock_session).to receive(:open_channel).and_yield(mock_channel)
        allow(mock_channel).to receive(:exec).and_yield(mock_channel, true)
        allow(mock_channel).to receive(:on_data) do |&block|
          block.call(mock_channel, '{"status":"ok","message":"Process killed","pid":123}')
        end
        allow(mock_channel).to receive(:on_extended_data)
        allow(mock_channel).to receive(:on_request).with("exit-status").and_yield(mock_channel, double(read_long: 0))
        allow(mock_channel).to receive(:on_request).with("exit-signal").and_yield(mock_channel, double(read_long: nil))

        allow(Net::SSH).to receive(:start).and_yield(mock_session)
      end

      it "displays cancel icon button for running runs", :js do
        visit benchmark_runs_path

        within("#benchmark_run_#{running_run.id}") do
          expect(page).to have_css("[title='Cancel']")
        end
      end

      it "cancels running run via SSH when confirmed", :js do
        visit benchmark_runs_path

        within("#benchmark_run_#{running_run.id}") do
          accept_confirm do
            find("[title='Cancel']").click
          end
        end

        expect(page).to have_content("Cancelled", wait: 5)
        expect(running_run.reload.status).to eq("cancelled")
      end
    end

    context "with completed benchmark run" do
      let!(:success_run) { create(:benchmark_run, :success, node: node, benchmark_recipe: recipe) }
      let!(:failed_run) { create(:benchmark_run, :failed, node: node, benchmark_recipe: recipe) }

      it "does not display cancel button for successful runs", :js do
        visit benchmark_runs_path

        within("#benchmark_run_#{success_run.id}") do
          expect(page).not_to have_css("[title='Cancel']")
        end
      end

      it "does not display cancel button for failed runs", :js do
        visit benchmark_runs_path

        within("#benchmark_run_#{failed_run.id}") do
          expect(page).not_to have_css("[title='Cancel']")
        end
      end
    end
  end

  describe "cancel button on show page" do
    context "with pending benchmark run" do
      let!(:pending_run) { create(:benchmark_run, :pending, node: node, benchmark_recipe: recipe) }

      it "displays Cancel Run button on show page", :js do
        visit benchmark_run_path(pending_run)

        expect(page).to have_button("Cancel Run")
      end

      it "cancels run and redirects when clicking Cancel Run button", :js do
        visit benchmark_run_path(pending_run)

        accept_confirm("Are you sure you want to cancel this benchmark run?") do
          click_button "Cancel Run"
        end

        # Wait for the page to change - either redirect or status update
        # The cancel button should disappear after successful cancel
        expect(page).not_to have_button("Cancel Run", wait: 5)

        # Verify the run was actually cancelled
        expect(pending_run.reload.status).to eq("cancelled")
      end
    end

    context "with completed benchmark run" do
      let!(:success_run) { create(:benchmark_run, :success, node: node, benchmark_recipe: recipe) }

      it "does not display Cancel Run button for completed runs", :js do
        visit benchmark_run_path(success_run)

        expect(page).not_to have_button("Cancel Run")
      end
    end
  end

  describe "cancel button in slide-over modal" do
    context "with pending benchmark run" do
      let!(:pending_run) { create(:benchmark_run, :pending, node: node, benchmark_recipe: recipe) }

      it "displays Cancel button in slide-over modal", :js do
        visit benchmark_runs_path

        # Open slide-over
        within("#benchmark_run_#{pending_run.id}") do
          find("[title='View Details']").click
        end

        expect(page).to have_css("[data-slide-over-target='panel']", visible: true, wait: 5)

        within("[data-slide-over-target='panel']") do
          expect(page).to have_button("Cancel", wait: 5)
        end
      end

      it "cancels run from slide-over modal and updates both modal and row", :js do
        visit benchmark_runs_path

        # Open slide-over
        within("#benchmark_run_#{pending_run.id}") do
          find("[title='View Details']").click
        end

        expect(page).to have_css("[data-slide-over-target='panel']", visible: true, wait: 5)

        within("[data-slide-over-target='panel']") do
          accept_confirm do
            click_button "Cancel"
          end
        end

        # Modal should update to show cancelled status
        within("[data-slide-over-target='panel']") do
          expect(page).to have_content("Cancelled", wait: 5)
          expect(page).not_to have_button("Cancel")
        end

        # Row in the table should also be updated
        within("#benchmark_run_#{pending_run.id}") do
          expect(page).to have_content("Cancelled")
        end
      end
    end
  end

  describe "cancel button on nodes overview page" do
    context "with pending benchmark run" do
      let!(:pending_run) { create(:benchmark_run, :pending, node: node, benchmark_recipe: recipe) }

      it "displays cancel icon in Recent Benchmark Runs table", :js do
        visit node_path(node)

        within("#node_recent_runs_tbody") do
          expect(page).to have_css("[title='Cancel']")
        end
      end

      it "cancels run from nodes overview page", :js do
        visit node_path(node)

        within("#node_recent_runs_tbody") do
          accept_confirm do
            find("[title='Cancel']").click
          end
        end

        expect(page).to have_content("Cancelled", wait: 5)
        expect(pending_run.reload.status).to eq("cancelled")
      end
    end
  end

  describe "ID column display" do
    let!(:benchmark_run) { create(:benchmark_run, node: node, benchmark_recipe: recipe) }

    it "displays ID column in benchmark runs index table", :js do
      visit benchmark_runs_path

      # Check header
      expect(page).to have_css("th", text: "ID")

      # Check run ID is displayed
      within("#benchmark_run_#{benchmark_run.id}") do
        expect(page).to have_content(benchmark_run.id.to_s)
      end
    end

    it "displays ID column in nodes overview Recent Benchmark Runs table", :js do
      visit node_path(node)

      # Check header (uppercase in UI)
      within("#node_recent_runs_tbody") do
        expect(page).to have_content(benchmark_run.id.to_s)
      end

      # Check header exists in the table
      expect(page).to have_css("th", text: /ID/i)
    end
  end
end
