# frozen_string_literal: true

require "rails_helper"

RSpec.describe Benchmark::CommandBuilders::Base do
  let(:agent_bin) { "/usr/local/bin/hpc-agent" }
  let(:run_id) { Faker::Alphanumeric.alphanumeric(number: 10) }
  let(:node_uuid) { Faker::Internet.uuid }
  let(:arguments) { { "size" => "1024", "iterations" => "100" } }
  let(:server_url) { "https://example.com" }
  let(:token) { Faker::Alphanumeric.alphanumeric(number: 32) }
  let(:log_path) { "/var/log/benchmark.log" }

  let(:builder) do
    described_class.new(
      agent_bin: agent_bin,
      run_id: run_id,
      node_uuid: node_uuid,
      arguments: arguments,
      server_url: server_url,
      token: token,
      log_path: log_path
    )
  end

  describe "#initialize" do
    it "sets agent_bin" do
      expect(builder.agent_bin).to eq(agent_bin)
    end

    it "sets run_id" do
      expect(builder.run_id).to eq(run_id)
    end

    it "sets node_uuid" do
      expect(builder.node_uuid).to eq(node_uuid)
    end

    it "sets arguments" do
      expect(builder.arguments).to eq(arguments)
    end

    it "sets server_url" do
      expect(builder.server_url).to eq(server_url)
    end

    it "sets token" do
      expect(builder.token).to eq(token)
    end

    it "sets log_path" do
      expect(builder.log_path).to eq(log_path)
    end

    context "when arguments is nil" do
      let(:builder_with_nil_args) do
        described_class.new(
          agent_bin: agent_bin,
          run_id: run_id,
          node_uuid: node_uuid,
          arguments: nil,
          server_url: server_url,
          token: token,
          log_path: log_path
        )
      end

      it "defaults arguments to empty hash" do
        expect(builder_with_nil_args.arguments).to eq({})
      end
    end
  end

  describe "#build" do
    it "raises NotImplementedError" do
      expect { builder.build }.to raise_error(NotImplementedError)
    end
  end

  describe "#subcommand" do
    it "raises NotImplementedError" do
      expect { builder.send(:subcommand) }.to raise_error(NotImplementedError)
    end
  end
end
