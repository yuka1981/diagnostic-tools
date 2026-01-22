# frozen_string_literal: true

require "rails_helper"

RSpec.describe Profiling::TriggerService do
  let(:node) { create(:node) }
  let(:run) { create(:profiling_run, node: node, subcommand: "report") }
  let(:service) { described_class.new(run, server_url: "http://localhost:3000", api_token: "secret") }

  describe "#call" do
    context "when Ansible execution succeeds" do
      before do
        allow_any_instance_of(Ansible::ExecutorService).to receive(:call)
          .and_return(Ansible::ExecutorService::Result.new(success: true, output: "Playbook completed"))
      end

      it "returns success" do
        result = service.call
        expect(result.success?).to be true
      end

      it "logs output" do
        result = service.call
        expect(result.output).to include("Playbook completed")
      end
    end

    context "when Ansible execution fails" do
      before do
        allow_any_instance_of(Ansible::ExecutorService).to receive(:call)
          .and_return(Ansible::ExecutorService::Result.new(success: false, error: "Module not found"))
      end

      it "returns failure" do
        result = service.call
        expect(result.success?).to be false
      end

      it "includes error message" do
        result = service.call
        expect(result.error).to include("Module not found")
      end
    end
  end

  describe "#playbook_for_subcommand" do
    it "maps report to report.yml" do
      expect(service.send(:playbook_for_subcommand, "report")).to eq("perfspect/report.yml")
    end

    it "maps telemetry to telemetry.yml" do
      expect(service.send(:playbook_for_subcommand, "telemetry")).to eq("perfspect/telemetry.yml")
    end

    it "maps flame to flame.yml" do
      expect(service.send(:playbook_for_subcommand, "flame")).to eq("perfspect/flame.yml")
    end

    it "raises error for unknown subcommand" do
      expect { service.send(:playbook_for_subcommand, "unknown") }
        .to raise_error(ArgumentError, /Unknown subcommand/)
    end
  end

  describe "#build_extra_vars" do
    it "includes target host from node" do
      extra_vars = service.send(:build_extra_vars)
      expect(extra_vars[:target_host]).to eq(node.hostname)
    end

    it "includes run uuid" do
      extra_vars = service.send(:build_extra_vars)
      expect(extra_vars[:run_uuid]).to eq(run.uuid)
    end

    it "includes api_server" do
      extra_vars = service.send(:build_extra_vars)
      expect(extra_vars[:api_server]).to eq("http://localhost:3000")
    end

    it "includes api_token" do
      extra_vars = service.send(:build_extra_vars)
      expect(extra_vars[:api_token]).to eq("secret")
    end

    it "includes options from run" do
      run_with_options = create(:profiling_run, node: node, subcommand: "telemetry", options: { "duration" => 60 })
      service_with_options = described_class.new(run_with_options, server_url: "http://localhost:3000", api_token: "secret")
      extra_vars = service_with_options.send(:build_extra_vars)
      expect(extra_vars[:options]).to eq({ "duration" => 60 })
    end

    it "includes perfspect_module from recipe" do
      recipe = create(:profiling_recipe, module_name: "perfspect/3.14.0")
      run_with_recipe = create(:profiling_run, node: node, profiling_recipe: recipe)
      service_with_recipe = described_class.new(run_with_recipe, server_url: "http://localhost:3000", api_token: "secret")
      extra_vars = service_with_recipe.send(:build_extra_vars)
      expect(extra_vars[:perfspect_module]).to eq("perfspect/3.14.0")
    end
  end
end
