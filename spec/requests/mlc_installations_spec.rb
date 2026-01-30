require "rails_helper"

RSpec.describe "MlcInstallations", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /mlc_installations/new" do
    it "renders the new installation form" do
      get new_mlc_installation_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Intel MLC Installation")
    end

    it "lists available nodes" do
      node = create(:node, hostname: "compute-001", salt_status: :connected)
      get new_mlc_installation_path

      expect(response.body).to include("compute-001")
    end
  end

  describe "POST /mlc_installations" do
    let(:node) { create(:node, :online) }

    before do
      # Create test fixture directory
      FileUtils.mkdir_p(Rails.root.join("spec/fixtures/files"))
      File.write(Rails.root.join("spec/fixtures/files/mlc_test.tgz"), "fake tarball content")
    end

    let(:tarball) do
      fixture_file_upload(
        Rails.root.join("spec/fixtures/files/mlc_test.tgz"),
        "application/gzip"
      )
    end

    it "creates installation and redirects to show" do
      # Mock the job to not actually run
      allow(Mlc::InstallJob).to receive(:perform_later)

      post mlc_installations_path, params: {
        mlc_installation: {
          source_type: "upload",
          binary_path: "Linux/mlc",
          node_ids: [ node.id ],
          failure_mode: "stop_on_first"
        },
        tarball: tarball
      }

      expect(response).to have_http_status(:redirect)
      expect(MlcInstallation.count).to eq(1)
    end

    it "enqueues install job" do
      expect(Mlc::InstallJob).to receive(:perform_later).with(
        kind_of(Integer),
        kind_of(String),
        kind_of(String),
        user_id: user.id
      )

      post mlc_installations_path, params: {
        mlc_installation: {
          source_type: "upload",
          binary_path: "Linux/mlc",
          node_ids: [ node.id ],
          failure_mode: "stop_on_first"
        },
        tarball: tarball
      }
    end
  end

  describe "GET /mlc_installations/:id" do
    let(:installation) { create(:mlc_installation, :running, created_by: user) }
    let(:node) { create(:node, :online, hostname: "compute-001") }
    let!(:installation_node) { create(:mlc_installation_node, :running, mlc_installation: installation, node: node) }

    it "renders the installation status" do
      get mlc_installation_path(installation)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(installation.uuid)
    end

    it "shows node status" do
      get mlc_installation_path(installation)

      expect(response.body).to include("compute-001")
    end
  end

  describe "DELETE /mlc_installations/:id" do
    let(:installation) { create(:mlc_installation, :running, created_by: user) }
    let!(:installation_node) { create(:mlc_installation_node, :running, mlc_installation: installation) }

    it "cancels the installation" do
      delete mlc_installation_path(installation)

      installation.reload
      expect(installation.status).to eq("cancelled")
    end

    it "marks running nodes as cancelled" do
      delete mlc_installation_path(installation)

      installation_node.reload
      expect(installation_node.status).to eq("cancelled")
    end

    it "redirects back to installation" do
      delete mlc_installation_path(installation)

      expect(response).to redirect_to(mlc_installation_path(installation))
    end
  end
end
