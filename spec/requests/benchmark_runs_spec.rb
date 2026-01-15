# frozen_string_literal: true

require "rails_helper"

RSpec.describe "BenchmarkRuns", type: :request do
  let(:user) { create(:user) }
  let(:node) { create(:node) }
  let(:recipe) { create(:benchmark_recipe, :hpcg) }
  let!(:benchmark_run) { create(:benchmark_run, node: node, benchmark_recipe: recipe) }

  before { sign_in user }

  describe "GET /benchmark_runs" do
    it "returns http success" do
      get benchmark_runs_path
      expect(response).to have_http_status(:success)
    end

    it "displays the benchmark runs list" do
      get benchmark_runs_path
      expect(response.body).to include(recipe.name)
      expect(response.body).to include(node.hostname)
    end

    context "with filters" do
      let!(:success_run) { create(:benchmark_run, node: node, benchmark_recipe: recipe, status: :success) }
      let!(:failed_run) { create(:benchmark_run, node: node, benchmark_recipe: recipe, status: :failed) }

      it "filters by status" do
        get benchmark_runs_path(status: "success")
        expect(response).to have_http_status(:success)
      end

      it "filters by node" do
        get benchmark_runs_path(node_id: node.id)
        expect(response).to have_http_status(:success)
      end

      it "filters by recipe" do
        get benchmark_runs_path(recipe_id: recipe.id)
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /benchmark_runs/:id" do
    it "returns http success" do
      get benchmark_run_path(benchmark_run)
      expect(response).to have_http_status(:success)
    end

    it "displays the benchmark run details" do
      get benchmark_run_path(benchmark_run)
      expect(response.body).to include(recipe.display_name)
      expect(response.body).to include(node.hostname)
    end

    context "with configuration card" do
      let(:benchmark_run) do
        create(:benchmark_run,
               node: node,
               benchmark_recipe: recipe,
               arguments: { "nx" => 128, "ny" => 128, "nz" => 104 })
      end

      it "displays the configuration section" do
        get benchmark_run_path(benchmark_run)
        expect(response.body).to include("Configuration")
        expect(response.body).to include(recipe.command)
      end

      it "displays effective arguments" do
        get benchmark_run_path(benchmark_run)
        expect(response.body).to include("Effective Arguments")
        expect(response.body).to include("--nx")
      end
    end

    context "with results card" do
      context "when run is pending" do
        let(:benchmark_run) { create(:benchmark_run, node: node, benchmark_recipe: recipe, status: :pending) }

        it "displays waiting message" do
          get benchmark_run_path(benchmark_run)
          expect(response.body).to include("Waiting for results")
        end
      end

      context "when run is successful with metrics" do
        let(:benchmark_run) do
          create(:benchmark_run,
                 node: node,
                 benchmark_recipe: recipe,
                 status: :success,
                 metrics: { "gflops" => 45.67, "result" => "PASS" })
        end

        it "displays metrics" do
          get benchmark_run_path(benchmark_run)
          expect(response.body).to include("Results")
          expect(response.body).to include("PASS")
        end
      end

      context "when run failed" do
        let(:benchmark_run) do
          create(:benchmark_run,
                 node: node,
                 benchmark_recipe: recipe,
                 status: :failed,
                 error_message: "Build failed")
        end

        it "displays error message" do
          get benchmark_run_path(benchmark_run)
          expect(response.body).to include("Error Message")
          expect(response.body).to include("Build failed")
        end
      end
    end

    context "with artifacts" do
      let(:temp_artifact_file) do
        file = Tempfile.new([ "artifact", ".txt" ])
        file.write("Artifact content")
        file.rewind
        file
      end
      let!(:artifact) { create(:artifact_index, benchmark_run: benchmark_run, path: temp_artifact_file.path, file_type: "txt") }

      after { temp_artifact_file.close! }

      it "displays artifacts section" do
        get benchmark_run_path(benchmark_run)
        expect(response.body).to include("Artifacts")
        expect(response.body).to include(File.basename(artifact.path))
      end

      it "includes download links when file exists" do
        get benchmark_run_path(benchmark_run)
        expect(response.body).to include("Download")
        expect(response.body).to include(download_artifact_benchmark_run_path(benchmark_run, artifact_id: artifact.id))
      end
    end

    context "with unavailable artifacts" do
      let!(:artifact) { create(:artifact_index, benchmark_run: benchmark_run, path: "/nonexistent/file.txt", file_type: "txt") }

      it "shows unavailable status when file does not exist" do
        get benchmark_run_path(benchmark_run)
        expect(response.body).to include("Unavailable")
        expect(response.body).to include("File not found on server")
        expect(response.body).not_to include(download_artifact_benchmark_run_path(benchmark_run, artifact_id: artifact.id))
      end
    end

    context "with turbo frame request for slide over" do
      it "renders slide over content partial" do
        get benchmark_run_path(benchmark_run), headers: { "Turbo-Frame" => "slide_over_content" }
        expect(response).to have_http_status(:success)
        expect(response.body).to include("tab-summary")
      end
    end
  end

  describe "GET /benchmark_runs/:id/artifacts/:artifact_id/download" do
    let!(:artifact) { create(:artifact_index, benchmark_run: benchmark_run, path: temp_file.path, file_type: "txt") }
    let(:temp_file) do
      file = Tempfile.new([ "test_artifact", ".txt" ])
      file.write("Test artifact content")
      file.rewind
      file
    end

    after { temp_file.close! }

    context "when file exists" do
      it "downloads the file" do
        get download_artifact_benchmark_run_path(benchmark_run, artifact_id: artifact.id)
        expect(response).to have_http_status(:success)
        expect(response.headers["Content-Disposition"]).to include("attachment")
      end

      it "sets correct content type for txt files" do
        get download_artifact_benchmark_run_path(benchmark_run, artifact_id: artifact.id)
        expect(response.content_type).to include("text/plain")
      end

      it "includes the filename in disposition" do
        get download_artifact_benchmark_run_path(benchmark_run, artifact_id: artifact.id)
        expect(response.headers["Content-Disposition"]).to include(File.basename(temp_file.path))
      end
    end

    context "when file does not exist" do
      let!(:artifact) { create(:artifact_index, benchmark_run: benchmark_run, path: "/nonexistent/file.txt", file_type: "txt") }

      it "redirects with error message" do
        get download_artifact_benchmark_run_path(benchmark_run, artifact_id: artifact.id)
        expect(response).to redirect_to(benchmark_run_path(benchmark_run))
        expect(flash[:alert]).to eq("Artifact file not found on server.")
      end
    end

    context "when artifact does not exist" do
      it "returns not found status" do
        get download_artifact_benchmark_run_path(benchmark_run, artifact_id: 999999)
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when artifact belongs to different benchmark run" do
      let(:other_run) { create(:benchmark_run, node: node, benchmark_recipe: recipe) }
      let!(:other_artifact) { create(:artifact_index, benchmark_run: other_run, path: temp_file.path) }

      it "returns not found status" do
        get download_artifact_benchmark_run_path(benchmark_run, artifact_id: other_artifact.id)
        expect(response).to have_http_status(:not_found)
      end
    end

    context "with different file types" do
      let(:json_file) do
        file = Tempfile.new([ "results", ".json" ])
        file.write('{"result": "pass"}')
        file.rewind
        file
      end

      after { json_file.close! }

      it "sets correct content type for json files" do
        json_artifact = create(:artifact_index, benchmark_run: benchmark_run, path: json_file.path, file_type: "json")
        get download_artifact_benchmark_run_path(benchmark_run, artifact_id: json_artifact.id)
        expect(response.content_type).to include("application/json")
      end

      it "sets correct content type for log files" do
        log_file = Tempfile.new([ "benchmark", ".log" ])
        log_file.write("Log content")
        log_file.rewind
        log_artifact = create(:artifact_index, benchmark_run: benchmark_run, path: log_file.path, file_type: "log")

        get download_artifact_benchmark_run_path(benchmark_run, artifact_id: log_artifact.id)
        expect(response.content_type).to include("text/plain")

        log_file.close!
      end

      it "sets octet-stream for unknown file types" do
        unknown_file = Tempfile.new([ "data", ".xyz" ])
        unknown_file.write("Binary data")
        unknown_file.rewind
        unknown_artifact = create(:artifact_index, benchmark_run: benchmark_run, path: unknown_file.path, file_type: "xyz")

        get download_artifact_benchmark_run_path(benchmark_run, artifact_id: unknown_artifact.id)
        expect(response.content_type).to include("application/octet-stream")

        unknown_file.close!
      end
    end
  end
end
