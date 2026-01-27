# frozen_string_literal: true

require "rails_helper"

RSpec.describe Benchmark::CommandBuilders::HpcgCommandBuilder do
  let(:run_id) { Faker::Number.number(digits: 5) }
  let(:node_uuid) { Faker::Internet.uuid }
  let(:agent_bin) { "/usr/local/bin/hpc-agent" }
  let(:server_url) { Faker::Internet.url }
  let(:token) { Faker::Alphanumeric.alphanumeric(number: 32) }

  describe "#subcommand" do
    it "returns 'hpcg'" do
      builder = described_class.new(
        run_id: run_id,
        node_uuid: node_uuid,
        agent_bin: agent_bin
      )

      expect(builder.subcommand).to eq("hpcg")
    end
  end

  describe "#build" do
    context "with minimal arguments (defaults)" do
      it "generates command with OMP_NUM_THREADS, agent binary, node-uuid, hpcg subcommand, and id" do
        builder = described_class.new(
          run_id: run_id,
          node_uuid: node_uuid,
          agent_bin: agent_bin
        )

        command = builder.build

        expect(command).to include("env OMP_NUM_THREADS=$(nproc)")
        expect(command).to include(agent_bin)
        expect(command).to include("--node-uuid #{node_uuid}")
        expect(command).to include("hpcg")
        expect(command).to include("--id #{run_id}")
      end

      it "includes default build command" do
        builder = described_class.new(
          run_id: run_id,
          node_uuid: node_uuid,
          agent_bin: agent_bin
        )

        command = builder.build

        expect(command).to include('--build "make arch=Linux_OpenMP"')
      end

      it "includes default run command" do
        builder = described_class.new(
          run_id: run_id,
          node_uuid: node_uuid,
          agent_bin: agent_bin
        )

        command = builder.build

        expect(command).to include('--run "./bin/xhpcg"')
      end

      it "includes default runtime (60 seconds)" do
        builder = described_class.new(
          run_id: run_id,
          node_uuid: node_uuid,
          agent_bin: agent_bin
        )

        command = builder.build

        expect(command).to include("--rt 60")
      end
    end

    context "with optional server and token" do
      it "includes --log-path when provided" do
        builder = described_class.new(
          run_id: run_id,
          node_uuid: node_uuid,
          agent_bin: agent_bin,
          arguments: { "log_path" => "/var/log/hpcg" }
        )

        command = builder.build

        expect(command).to include("--log-path /var/log/hpcg")
      end

      it "includes --server when provided" do
        builder = described_class.new(
          run_id: run_id,
          node_uuid: node_uuid,
          agent_bin: agent_bin,
          server_url: server_url
        )

        command = builder.build

        expect(command).to include("--server #{server_url}")
      end

      it "includes --token when provided" do
        builder = described_class.new(
          run_id: run_id,
          node_uuid: node_uuid,
          agent_bin: agent_bin,
          token: token
        )

        command = builder.build

        expect(command).to include("--token #{token}")
      end
    end

    context "with custom arguments" do
      it "overrides build command when provided" do
        custom_build = "make arch=Linux_MPI"
        builder = described_class.new(
          run_id: run_id,
          node_uuid: node_uuid,
          agent_bin: agent_bin,
          arguments: { "build" => custom_build }
        )

        command = builder.build

        expect(command).to include("--build \"#{custom_build}\"")
        expect(command).not_to include("Linux_OpenMP")
      end

      it "overrides run command when provided" do
        custom_run = "./bin/custom_benchmark"
        builder = described_class.new(
          run_id: run_id,
          node_uuid: node_uuid,
          agent_bin: agent_bin,
          arguments: { "run" => custom_run }
        )

        command = builder.build

        expect(command).to include("--run \"#{custom_run}\"")
        expect(command).not_to include("./bin/xhpcg")
      end

      it "overrides runtime when 'rt' is provided" do
        builder = described_class.new(
          run_id: run_id,
          node_uuid: node_uuid,
          agent_bin: agent_bin,
          arguments: { "rt" => 120 }
        )

        command = builder.build

        expect(command).to include("--rt 120")
        expect(command).not_to include("--rt 60")
      end

      it "uses 'timeout' key as fallback for 'rt'" do
        builder = described_class.new(
          run_id: run_id,
          node_uuid: node_uuid,
          agent_bin: agent_bin,
          arguments: { "timeout" => 180 }
        )

        command = builder.build

        expect(command).to include("--rt 180")
      end

      it "includes --nx when provided" do
        builder = described_class.new(
          run_id: run_id,
          node_uuid: node_uuid,
          agent_bin: agent_bin,
          arguments: { "nx" => 256 }
        )

        command = builder.build

        expect(command).to include("--nx 256")
      end

      it "includes --ny when provided" do
        builder = described_class.new(
          run_id: run_id,
          node_uuid: node_uuid,
          agent_bin: agent_bin,
          arguments: { "ny" => 256 }
        )

        command = builder.build

        expect(command).to include("--ny 256")
      end

      it "includes --nz when provided" do
        builder = described_class.new(
          run_id: run_id,
          node_uuid: node_uuid,
          agent_bin: agent_bin,
          arguments: { "nz" => 256 }
        )

        command = builder.build

        expect(command).to include("--nz 256")
      end

      it "includes all dimension flags when provided" do
        builder = described_class.new(
          run_id: run_id,
          node_uuid: node_uuid,
          agent_bin: agent_bin,
          arguments: { "nx" => 128, "ny" => 256, "nz" => 512 }
        )

        command = builder.build

        expect(command).to include("--nx 128")
        expect(command).to include("--ny 256")
        expect(command).to include("--nz 512")
      end
    end

    context "when values are nil or blank" do
      it "omits --nx when nil" do
        builder = described_class.new(
          run_id: run_id,
          node_uuid: node_uuid,
          agent_bin: agent_bin,
          arguments: { "nx" => nil }
        )

        command = builder.build

        expect(command).not_to include("--nx")
      end

      it "omits --log-path when blank" do
        builder = described_class.new(
          run_id: run_id,
          node_uuid: node_uuid,
          agent_bin: agent_bin,
          arguments: { "log_path" => "" }
        )

        command = builder.build

        expect(command).not_to include("--log-path")
      end

      it "omits --server when nil" do
        builder = described_class.new(
          run_id: run_id,
          node_uuid: node_uuid,
          agent_bin: agent_bin,
          server_url: nil
        )

        command = builder.build

        expect(command).not_to include("--server")
      end

      it "omits --token when blank" do
        builder = described_class.new(
          run_id: run_id,
          node_uuid: node_uuid,
          agent_bin: agent_bin,
          token: ""
        )

        command = builder.build

        expect(command).not_to include("--token")
      end
    end

    context "full command with all options" do
      it "generates complete command string" do
        builder = described_class.new(
          run_id: run_id,
          node_uuid: node_uuid,
          agent_bin: agent_bin,
          server_url: server_url,
          token: token,
          arguments: {
            "build" => "make arch=Linux_MPI",
            "run" => "./bin/xhpcg-mpi",
            "rt" => 300,
            "nx" => 128,
            "ny" => 256,
            "nz" => 512,
            "log_path" => "/var/log/hpcg"
          }
        )

        command = builder.build

        expect(command).to include("env OMP_NUM_THREADS=$(nproc)")
        expect(command).to include(agent_bin)
        expect(command).to include("--node-uuid #{node_uuid}")
        expect(command).to include("hpcg")
        expect(command).to include("--id #{run_id}")
        expect(command).to include('--build "make arch=Linux_MPI"')
        expect(command).to include('--run "./bin/xhpcg-mpi"')
        expect(command).to include("--rt 300")
        expect(command).to include("--nx 128")
        expect(command).to include("--ny 256")
        expect(command).to include("--nz 512")
        expect(command).to include("--log-path /var/log/hpcg")
        expect(command).to include("--server #{server_url}")
        expect(command).to include("--token #{token}")
      end
    end
  end
end
