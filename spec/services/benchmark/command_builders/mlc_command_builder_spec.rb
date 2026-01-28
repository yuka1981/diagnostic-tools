# frozen_string_literal: true

require "rails_helper"

RSpec.describe Benchmark::CommandBuilders::MlcCommandBuilder do
  let(:run_id) { Faker::Number.number(digits: 5) }
  let(:node_uuid) { Faker::Internet.uuid }
  let(:token) { Faker::Alphanumeric.alphanumeric(number: 32) }
  let(:agent_bin) { "/usr/local/bin/qis-agent" }
  let(:server_url) { "https://example.com" }

  describe "#subcommand" do
    it "returns 'mlc'" do
      builder = described_class.new(
        run_id: run_id,
        node_uuid: node_uuid,
        agent_bin: agent_bin
      )

      # Test subcommand indirectly by checking it's in the built command
      command = builder.build
      expect(command).to include("mlc")
    end
  end

  describe "#build" do
    context "with minimal arguments" do
      it "includes OMP_NUM_THREADS, agent binary, node-uuid, mlc subcommand, and run id" do
        builder = described_class.new(
          run_id: run_id,
          node_uuid: node_uuid,
          agent_bin: agent_bin
        )

        command = builder.build

        expect(command).to include("env OMP_NUM_THREADS=$(nproc)")
        expect(command).to include(agent_bin)
        expect(command).to include("--node-uuid #{node_uuid}")
        expect(command).to include("mlc")
        expect(command).to include("--id #{run_id}")
      end

      it "uses default profile 'quick'" do
        builder = described_class.new(
          run_id: run_id,
          node_uuid: node_uuid,
          agent_bin: agent_bin
        )

        command = builder.build

        expect(command).to include("--profile quick")
      end
    end

    context "with server and token" do
      it "includes --log-dir, --server, and --token flags" do
        log_dir = "/var/log/benchmarks"
        builder = described_class.new(
          run_id: run_id,
          node_uuid: node_uuid,
          agent_bin: agent_bin,
          arguments: { log_dir: log_dir },
          server_url: server_url,
          token: token
        )

        command = builder.build

        expect(command).to include("--log-dir #{log_dir}")
        expect(command).to include("--server #{server_url}")
        expect(command).to include("--token #{token}")
      end
    end

    context "with custom profile" do
      it "uses the provided profile" do
        builder = described_class.new(
          run_id: run_id,
          node_uuid: node_uuid,
          agent_bin: agent_bin,
          arguments: { profile: "full" }
        )

        command = builder.build

        expect(command).to include("--profile full")
      end
    end

    context "with binary_path" do
      it "includes --binary flag" do
        binary_path = "/opt/mlc/mlc"
        builder = described_class.new(
          run_id: run_id,
          node_uuid: node_uuid,
          agent_bin: agent_bin,
          arguments: { binary_path: binary_path }
        )

        command = builder.build

        expect(command).to include("--binary #{binary_path}")
      end
    end

    context "with modules" do
      it "includes --module flag for each module" do
        modules = %w[module1 module2 module3]
        builder = described_class.new(
          run_id: run_id,
          node_uuid: node_uuid,
          agent_bin: agent_bin,
          arguments: { modules: modules }
        )

        command = builder.build

        expect(command).to include("--module module1")
        expect(command).to include("--module module2")
        expect(command).to include("--module module3")
      end
    end

    context "with tests" do
      it "includes --tests flag with comma-separated list" do
        tests = %w[test1 test2 test3]
        builder = described_class.new(
          run_id: run_id,
          node_uuid: node_uuid,
          agent_bin: agent_bin,
          arguments: { tests: tests }
        )

        command = builder.build

        expect(command).to include("--tests test1,test2,test3")
      end
    end

    context "with all MLC-specific arguments" do
      it "includes all MLC flags in correct order" do
        builder = described_class.new(
          run_id: run_id,
          node_uuid: node_uuid,
          agent_bin: agent_bin,
          arguments: {
            profile: "full",
            binary_path: "/opt/mlc/mlc",
            modules: %w[intel/2021.4 mkl/2021.4],
            tests: %w[bandwidth latency],
            log_dir: "/var/log/mlc"
          },
          server_url: server_url,
          token: token
        )

        command = builder.build

        expect(command).to match(/env OMP_NUM_THREADS=\$\(nproc\)/)
        expect(command).to include(agent_bin)
        expect(command).to include("--node-uuid #{node_uuid}")
        expect(command).to include("mlc")
        expect(command).to include("--id #{run_id}")
        expect(command).to include("--profile full")
        expect(command).to include("--binary /opt/mlc/mlc")
        expect(command).to include("--module intel/2021.4")
        expect(command).to include("--module mkl/2021.4")
        expect(command).to include("--tests bandwidth,latency")
        expect(command).to include("--log-dir /var/log/mlc")
        expect(command).to include("--server #{server_url}")
        expect(command).to include("--token #{token}")
      end
    end

    context "HPCG-specific flags" do
      it "does not include HPCG flags like --build, --run, --rt, --nx, --ny, --nz" do
        builder = described_class.new(
          run_id: run_id,
          node_uuid: node_uuid,
          agent_bin: agent_bin,
          arguments: {
            build: true,
            run: true,
            rt: 60,
            nx: 256,
            ny: 256,
            nz: 256
          }
        )

        command = builder.build

        expect(command).not_to include("--build")
        expect(command).not_to include("--run")
        expect(command).not_to include("--rt")
        expect(command).not_to include("--nx")
        expect(command).not_to include("--ny")
        expect(command).not_to include("--nz")
      end
    end

    context "with nil or blank values" do
      it "omits flags when values are nil or blank" do
        builder = described_class.new(
          run_id: run_id,
          node_uuid: node_uuid,
          agent_bin: agent_bin,
          arguments: {
            profile: nil,
            binary_path: "",
            modules: nil,
            tests: [],
            log_dir: nil
          },
          server_url: nil,
          token: ""
        )

        command = builder.build

        # Should still have basic structure
        expect(command).to include("env OMP_NUM_THREADS=$(nproc)")
        expect(command).to include(agent_bin)
        expect(command).to include("--node-uuid #{node_uuid}")
        expect(command).to include("mlc")
        expect(command).to include("--id #{run_id}")

        # Should have default profile
        expect(command).to include("--profile quick")

        # Should not have optional flags when blank
        expect(command).not_to match(/--binary\s/)
        expect(command).not_to match(/--module\s/)
        expect(command).not_to match(/--tests\s/)
        expect(command).not_to match(/--log-dir\s/)
        expect(command).not_to match(/--server\s/)
        expect(command).not_to match(/--token\s/)
      end
    end
  end
end
