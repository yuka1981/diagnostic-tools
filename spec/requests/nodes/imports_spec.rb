# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Nodes::Imports", type: :request do
  let(:user) { create(:user) }

  before do
    sign_in user
  end

  describe "GET /nodes/import/new" do
    it "returns the modal form" do
      get new_import_nodes_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Import Nodes")
    end

    it "renders within turbo frame" do
      get new_import_nodes_path

      expect(response.body).to include("turbo-frame")
      expect(response.body).to include('id="import_modal"')
    end
  end

  describe "POST /nodes/import" do
    context "with valid CSV file" do
      let(:csv_content) { "hostname,ip,role,arch\nnode-001,192.168.1.1,compute,x86_64\nnode-002,192.168.1.2,login,x86_64" }
      let(:tempfile) do
        file = Tempfile.new([ "nodes", ".csv" ])
        file.write(csv_content)
        file.rewind
        file
      end
      let(:uploaded_file) { Rack::Test::UploadedFile.new(tempfile.path, "text/csv") }

      after do
        tempfile.close
        tempfile.unlink
      end

      it "creates new nodes" do
        expect {
          post import_nodes_path, params: { file: uploaded_file }
        }.to change(Node, :count).by(2)
      end

      it "redirects to nodes index with success message" do
        post import_nodes_path, params: { file: uploaded_file }

        expect(response).to redirect_to(nodes_path)
        follow_redirect!
        expect(response.body).to include("Import complete: 2 created")
      end

      it "returns turbo stream response when requested" do
        post import_nodes_path, params: { file: uploaded_file }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      end
    end

    context "with missing file" do
      it "returns error" do
        post import_nodes_path

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "with invalid CSV" do
      let(:csv_content) { "invalid,headers\ndata,here" }
      let(:tempfile) do
        file = Tempfile.new([ "nodes", ".csv" ])
        file.write(csv_content)
        file.rewind
        file
      end
      let(:uploaded_file) { Rack::Test::UploadedFile.new(tempfile.path, "text/csv") }

      after do
        tempfile.close
        tempfile.unlink
      end

      it "returns error with details" do
        post import_nodes_path, params: { file: uploaded_file }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Missing required header: hostname")
      end
    end

    context "with partial success" do
      let(:csv_content) { "hostname,ip,role\nvalid-node,,compute\ninvalid-node,not-an-ip,compute" }
      let(:tempfile) do
        file = Tempfile.new([ "nodes", ".csv" ])
        file.write(csv_content)
        file.rewind
        file
      end
      let(:uploaded_file) { Rack::Test::UploadedFile.new(tempfile.path, "text/csv") }

      after do
        tempfile.close
        tempfile.unlink
      end

      it "creates valid nodes and reports errors" do
        expect {
          post import_nodes_path, params: { file: uploaded_file }
        }.to change(Node, :count).by(1)
      end
    end
  end

  describe "authentication" do
    before do
      sign_out user
    end

    it "requires authentication for new" do
      get new_import_nodes_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "requires authentication for create" do
      post import_nodes_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
