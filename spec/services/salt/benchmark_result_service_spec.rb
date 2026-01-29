require "rails_helper"

RSpec.describe Salt::BenchmarkResultService do
  let(:node) { create(:node, hostname: "node-01") }
  let(:recipe) { create(:benchmark_recipe, benchmark_type: :hpcg) }
  let(:run) { create(:benchmark_run, :running, node: node, benchmark_recipe: recipe) }
  let(:salt_client) { instance_double(SaltApiClient) }

  let(:job_return_data) do
    {
      "node-01" => {
        "retcode" => 0,
        "return" => {
          "status" => "PASS",
          "metrics" => { "gflops" => 45.67, "time" => 1823.45 },
          "start_time" => "2026-01-29T12:00:00Z",
          "end_time" => "2026-01-29T12:30:00Z",
          "log_content" => "Benchmark completed successfully",
          "artifacts" => ["/tmp/hpcg/HPCG-Benchmark.txt"]
        }
      }
    }
  end

  let(:service) do
    described_class.new(
      benchmark_run: run,
      job_return: job_return_data,
      salt_client: salt_client
    )
  end

  describe "#call" do
    before do
      allow(salt_client).to receive(:run)
        .with("node-01", "cp.push", path: "/tmp/hpcg/HPCG-Benchmark.txt")
        .and_return(true)
    end

    it "updates the benchmark run with results" do
      service.call
      run.reload
      expect(run.status).to eq("success")
      expect(run.metrics["gflops"]).to eq(45.67)
      expect(run.finished_at).to be_present
      expect(run.log_path).to be_present
    end

    it "maps FAIL status correctly" do
      job_return_data["node-01"]["return"]["status"] = "FAIL"
      job_return_data["node-01"]["return"]["error_message"] = "Residual check failed"

      service.call
      run.reload
      expect(run.status).to eq("failed")
      expect(run.error_message).to eq("Residual check failed")
    end

    it "handles missing return data gracefully" do
      bad_data = { "node-01" => { "retcode" => 1, "return" => "Error: state not found" } }
      service = described_class.new(benchmark_run: run, job_return: bad_data, salt_client: salt_client)

      service.call
      run.reload
      expect(run.status).to eq("failed")
    end
  end
end
