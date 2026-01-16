# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Settings::AgentReleases", type: :request do
  let(:approver) { create(:user, :approver) }
  let(:regular_user) { create(:user) }

  describe "GET /settings/agent_releases" do
    context "when not authenticated" do
      it "redirects to login" do
        get settings_agent_releases_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "when authenticated as approver" do
      before { sign_in approver }

      it "returns http success" do
        get settings_agent_releases_path
        expect(response).to have_http_status(:success)
      end

      it "displays the releases list" do
        release = create(:agent_release, version: "v1.0.0")
        get settings_agent_releases_path
        expect(response.body).to include("v1.0.0")
      end
    end

    context "when authenticated as regular user" do
      before { sign_in regular_user }

      it "redirects with unauthorized message" do
        get settings_agent_releases_path
        expect(response).to redirect_to(root_path)
        follow_redirect!
        expect(response.body).to include("not authorized")
      end
    end
  end

  describe "GET /settings/agent_releases/:id" do
    let!(:release) { create(:agent_release, version: "v1.0.0") }

    before { sign_in approver }

    it "returns http success" do
      get settings_agent_release_path(release)
      expect(response).to have_http_status(:success)
    end

    it "displays release details" do
      get settings_agent_release_path(release)
      expect(response.body).to include("v1.0.0")
      expect(response.body).to include("SHA256 Checksum")
    end
  end

  describe "GET /settings/agent_releases/new" do
    before { sign_in approver }

    it "returns http success" do
      get new_settings_agent_release_path
      expect(response).to have_http_status(:success)
    end

    it "displays creation method options" do
      get new_settings_agent_release_path
      expect(response.body).to include("Creation Method")
      expect(response.body).to include("Upload Binary")
      expect(response.body).to include("Build from Source")
    end

    context "when Go is available" do
      before do
        allow(Agent::CompilerService).to receive(:go_available?).and_return(true)
        allow(Agent::CompilerService).to receive(:go_version).and_return("go version go1.21.0 linux/amd64")
      end

      it "shows Go version" do
        get new_settings_agent_release_path
        expect(response.body).to include("go version go1.21.0")
      end

      it "enables build option" do
        get new_settings_agent_release_path
        expect(response.body).not_to include("Go toolchain not available")
      end
    end

    context "when Go is not available" do
      before do
        allow(Agent::CompilerService).to receive(:go_available?).and_return(false)
      end

      it "shows Go not available message" do
        get new_settings_agent_release_path
        expect(response.body).to include("Go toolchain not available")
      end
    end
  end

  describe "POST /settings/agent_releases" do
    before { sign_in approver }

    let(:binary_file) do
      fixture_file_upload(
        StringIO.new("#!/bin/bash\necho test"),
        "application/octet-stream",
        true,
        original_filename: "hpc-agent"
      )
    end

    context "with valid parameters" do
      it "creates a new release" do
        # Create a temp file for the upload
        file = Tempfile.new([ "hpc-agent", "" ])
        file.binmode
        file.write("#!/bin/bash\necho 'agent binary'")
        file.rewind

        expect {
          post settings_agent_releases_path, params: {
            agent_release: {
              version: "v2.0.0",
              release_notes: "New release",
              binary: Rack::Test::UploadedFile.new(file.path, "application/octet-stream", true, original_filename: "hpc-agent")
            }
          }
        }.to change(AgentRelease, :count).by(1)

        file.close
        file.unlink
      end

      it "redirects to the show page" do
        file = Tempfile.new([ "hpc-agent", "" ])
        file.binmode
        file.write("#!/bin/bash\necho 'agent binary'")
        file.rewind

        post settings_agent_releases_path, params: {
          agent_release: {
            version: "v2.0.0",
            release_notes: "New release",
            binary: Rack::Test::UploadedFile.new(file.path, "application/octet-stream", true, original_filename: "hpc-agent")
          }
        }

        expect(response).to redirect_to(settings_agent_release_path(AgentRelease.last))

        file.close
        file.unlink
      end
    end

    context "with invalid parameters" do
      it "does not create a release without version" do
        expect {
          post settings_agent_releases_path, params: {
            agent_release: { version: "", release_notes: "Test" }
          }
        }.not_to change(AgentRelease, :count)
      end

      it "renders the new form with errors" do
        post settings_agent_releases_path, params: {
          agent_release: { version: "", release_notes: "Test" }
        }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "with build mode" do
      before do
        allow(Agent::CompilerService).to receive(:go_available?).and_return(true)
        allow(Agent::CompilerService).to receive(:go_version).and_return("go version go1.21.0")
      end

      context "when compilation succeeds" do
        let(:mock_release) { create(:agent_release, version: "v3.0.0") }

        before do
          allow(Agent::CompilerService).to receive(:build_release).and_return(mock_release)
        end

        it "creates a release from source" do
          post settings_agent_releases_path, params: {
            creation_mode: "build",
            agent_release: {
              version: "v3.0.0",
              release_notes: "Built from source"
            }
          }

          expect(response).to redirect_to(settings_agent_release_path(mock_release))
          follow_redirect!
          expect(response.body).to include("successfully built from source")
        end

        it "calls CompilerService with correct parameters" do
          expect(Agent::CompilerService).to receive(:build_release).with(
            version_tag: "v3.0.0",
            release_notes: "Built from source",
            arch: "x86_64",
            custom_ldflags: nil
          ).and_return(mock_release)

          post settings_agent_releases_path, params: {
            creation_mode: "build",
            agent_release: {
              version: "v3.0.0",
              release_notes: "Built from source"
            }
          }
        end

        it "passes custom architecture and ldflags when provided" do
          expect(Agent::CompilerService).to receive(:build_release).with(
            version_tag: "v3.0.0",
            release_notes: "Built from source",
            arch: "arm64",
            custom_ldflags: "-s -w"
          ).and_return(mock_release)

          post settings_agent_releases_path, params: {
            creation_mode: "build",
            target_arch: "arm64",
            custom_ldflags: "-s -w",
            agent_release: {
              version: "v3.0.0",
              release_notes: "Built from source"
            }
          }
        end
      end

      context "when compilation fails" do
        before do
          allow(Agent::CompilerService).to receive(:build_release)
            .and_raise(Agent::CompilerService::CompilationError.new("Build failed: missing dependency"))
        end

        it "renders the form with error" do
          post settings_agent_releases_path, params: {
            creation_mode: "build",
            agent_release: {
              version: "v3.0.0",
              release_notes: "Test"
            }
          }

          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.body).to include("Compilation failed")
          expect(response.body).to include("missing dependency")
        end

        it "preserves form values" do
          post settings_agent_releases_path, params: {
            creation_mode: "build",
            agent_release: {
              version: "v3.0.0",
              release_notes: "Test notes"
            }
          }

          expect(response.body).to include("v3.0.0")
        end
      end
    end
  end

  describe "PATCH /settings/agent_releases/:id" do
    let!(:release) { create(:agent_release, version: "v1.0.0") }

    before { sign_in approver }

    it "updates the release" do
      patch settings_agent_release_path(release), params: {
        agent_release: { release_notes: "Updated notes" }
      }
      expect(release.reload.release_notes).to eq("Updated notes")
    end

    it "redirects to the show page" do
      patch settings_agent_release_path(release), params: {
        agent_release: { release_notes: "Updated notes" }
      }
      expect(response).to redirect_to(settings_agent_release_path(release))
    end
  end

  describe "DELETE /settings/agent_releases/:id" do
    let!(:release) { create(:agent_release, version: "v1.0.0") }

    before { sign_in approver }

    it "deletes the release" do
      expect {
        delete settings_agent_release_path(release)
      }.to change(AgentRelease, :count).by(-1)
    end

    it "redirects to the index page" do
      delete settings_agent_release_path(release)
      expect(response).to redirect_to(settings_agent_releases_path)
    end
  end

  describe "status transition actions" do
    let!(:release) { create(:agent_release, version: "v1.0.0") }

    before { sign_in approver }

    describe "PATCH /settings/agent_releases/:id/deprecate" do
      it "changes status to deprecated" do
        patch deprecate_settings_agent_release_path(release)
        expect(release.reload).to be_deprecated
      end
    end

    describe "PATCH /settings/agent_releases/:id/activate" do
      let!(:release) { create(:agent_release, :deprecated, version: "v1.0.0") }

      it "changes status to active" do
        patch activate_settings_agent_release_path(release)
        expect(release.reload).to be_active
      end
    end

    describe "PATCH /settings/agent_releases/:id/recall" do
      let!(:release) { create(:agent_release, :deprecated, version: "v1.0.0") }

      it "changes status to recalled" do
        patch recall_settings_agent_release_path(release)
        expect(release.reload).to be_recalled
      end
    end
  end
end
