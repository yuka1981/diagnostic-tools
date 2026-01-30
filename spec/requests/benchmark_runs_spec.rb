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

      it "includes turbo frame wrapper in response" do
        get benchmark_run_path(benchmark_run), headers: { "Turbo-Frame" => "slide_over_content" }
        expect(response.body).to include('id="slide_over_content"')
      end

      it "includes run details in turbo frame response" do
        get benchmark_run_path(benchmark_run), headers: { "Turbo-Frame" => "slide_over_content" }
        expect(response.body).to include(node.hostname)
        expect(response.body).to include(recipe.name)
      end
    end

    context "with regular request (fallback turbo frame)" do
      it "includes hidden slide_over_content frame in full page response" do
        get benchmark_run_path(benchmark_run)
        expect(response).to have_http_status(:success)
        # The page should include the hidden slide_over_content partial as a fallback
        expect(response.body).to include('id="slide_over_content"')
      end

      it "includes both full page content and slide-over frame content" do
        get benchmark_run_path(benchmark_run)
        # Full page content
        expect(response.body).to include("Run Details")
        expect(response.body).to include("Configuration")
        # Hidden slide-over frame content (wrapped in hidden div)
        expect(response.body).to include('class="hidden"')
        expect(response.body).to include("tab-summary")
      end
    end
  end

  describe "POST /benchmark_runs/:id/cancel" do
    context "when benchmark run is pending" do
      let(:pending_run) { create(:benchmark_run, node: node, benchmark_recipe: recipe, status: :pending) }

      it "cancels the run without SSH" do
        expect(Net::SSH).not_to receive(:start)
        post cancel_benchmark_run_path(pending_run)
        expect(pending_run.reload.status).to eq("cancelled")
      end

      it "redirects to benchmark runs index" do
        post cancel_benchmark_run_path(pending_run)
        expect(response).to redirect_to(benchmark_runs_path)
      end

      it "sets success flash message" do
        post cancel_benchmark_run_path(pending_run)
        expect(flash[:notice]).to eq("Benchmark run cancelled successfully.")
      end

      it "sets error_message on the run" do
        post cancel_benchmark_run_path(pending_run)
        expect(pending_run.reload.error_message).to include("Cancelled by user")
      end
    end

    context "when benchmark run is running" do
      let(:running_run) { create(:benchmark_run, :running, node: node, benchmark_recipe: recipe) }

      it "cancels the run" do
        post cancel_benchmark_run_path(running_run)
        expect(running_run.reload.status).to eq("cancelled")
      end

      it "redirects to benchmark runs index" do
        post cancel_benchmark_run_path(running_run)
        expect(response).to redirect_to(benchmark_runs_path)
      end

      it "sets success flash message" do
        post cancel_benchmark_run_path(running_run)
        expect(flash[:notice]).to eq("Benchmark run cancelled successfully.")
      end
    end

    context "when benchmark run is already completed" do
      let(:completed_run) { create(:benchmark_run, :success, node: node, benchmark_recipe: recipe) }

      it "does not cancel the run" do
        post cancel_benchmark_run_path(completed_run)
        expect(completed_run.reload.status).to eq("success")
      end

      it "redirects to the run page" do
        post cancel_benchmark_run_path(completed_run)
        expect(response).to redirect_to(benchmark_run_path(completed_run))
      end

      it "sets alert flash message" do
        post cancel_benchmark_run_path(completed_run)
        expect(flash[:alert]).to eq("Cannot cancel a completed benchmark run.")
      end
    end

    context "when benchmark run is already cancelled" do
      let(:cancelled_run) { create(:benchmark_run, :cancelled, node: node, benchmark_recipe: recipe) }

      it "does not change the run" do
        post cancel_benchmark_run_path(cancelled_run)
        expect(cancelled_run.reload.status).to eq("cancelled")
      end

      it "sets alert flash message" do
        post cancel_benchmark_run_path(cancelled_run)
        expect(flash[:alert]).to eq("Cannot cancel a completed benchmark run.")
      end
    end

    context "with turbo stream request" do
      let(:pending_run) { create(:benchmark_run, node: node, benchmark_recipe: recipe, status: :pending) }

      it "returns turbo stream response" do
        post cancel_benchmark_run_path(pending_run), headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      end

      it "replaces the run row" do
        post cancel_benchmark_run_path(pending_run), headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(response.body).to include("turbo-stream")
        expect(response.body).to include("benchmark_run_#{pending_run.id}")
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

    before { Rails.configuration.x.artifacts_base_path = Dir.tmpdir }
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

    context "with stored_path (server-managed storage)" do
      let(:storage_dir) { Rails.root.join("tmp", "test_storage_artifacts", benchmark_run.uuid) }
      let(:stored_file) do
        FileUtils.mkdir_p(storage_dir)
        file_path = File.join(storage_dir, "uploaded_result.txt")
        File.write(file_path, "Uploaded artifact content")
        file_path
      end

      before do
        allow(Rails.configuration.x).to receive(:artifacts_storage_path).and_return(Rails.root.join("tmp", "test_storage_artifacts").to_s)
      end

      after do
        FileUtils.rm_rf(Rails.root.join("tmp", "test_storage_artifacts"))
      end

      it "downloads from stored_path when available" do
        artifact = create(:artifact_index, benchmark_run: benchmark_run, path: "/nonexistent/original.txt", stored_path: stored_file, file_type: "txt")
        get download_artifact_benchmark_run_path(benchmark_run, artifact_id: artifact.id)
        expect(response).to have_http_status(:success)
        expect(response.body).to eq("Uploaded artifact content")
      end

      it "prefers stored_path over original path" do
        # Create a temp file for the original path
        original_file = Tempfile.new([ "original", ".txt" ])
        original_file.write("Original content - should not be served")
        original_file.rewind

        artifact = create(:artifact_index, benchmark_run: benchmark_run, path: original_file.path, stored_path: stored_file, file_type: "txt")

        get download_artifact_benchmark_run_path(benchmark_run, artifact_id: artifact.id)
        expect(response).to have_http_status(:success)
        expect(response.body).to eq("Uploaded artifact content")

        original_file.close!
      end

      it "falls back to original path if stored_path does not exist" do
        original_file = Tempfile.new([ "fallback", ".txt" ])
        original_file.write("Fallback content")
        original_file.rewind
        Rails.configuration.x.artifacts_base_path = Dir.tmpdir

        artifact = create(:artifact_index, benchmark_run: benchmark_run, path: original_file.path, stored_path: "/nonexistent/stored.txt", file_type: "txt")

        get download_artifact_benchmark_run_path(benchmark_run, artifact_id: artifact.id)
        expect(response).to have_http_status(:success)
        expect(response.body).to eq("Fallback content")

        original_file.close!
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

      it "sets correct content type for dat files (hpcg.dat config)" do
        dat_file = Tempfile.new([ "hpcg", ".dat" ])
        dat_file.write("HPCG benchmark input file\n104 104 104\n60\n")
        dat_file.rewind
        dat_artifact = create(:artifact_index, benchmark_run: benchmark_run, path: dat_file.path, file_type: "dat")

        get download_artifact_benchmark_run_path(benchmark_run, artifact_id: dat_artifact.id)
        expect(response.content_type).to include("text/plain")

        dat_file.close!
      end
    end
  end
end
