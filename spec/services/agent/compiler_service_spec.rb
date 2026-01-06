# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent::CompilerService do
  describe "#call" do
    let(:arch) { "x86_64" }
    let(:service) { described_class.new(arch) }

    it "executes go build command and returns path" do
      expect(Open3).to receive(:capture3)
        .with(/GOOS=linux GOARCH=amd64 go build -o .*tmp\/agent_amd64_.* \.\/agent/)
        .and_return([ "", "", double(success?: true) ])

      path = service.call
      expect(path).to include("tmp/agent_amd64_")
    end

    it "raises error if compilation fails" do
      allow(Open3).to receive(:capture3).and_return([ "", "error message", double(success?: false) ])

      expect { service.call }.to raise_error(Agent::CompilerService::CompilationError, /Failed to compile/)
    end

    context "with arm64" do
      let(:arch) { "arm64" }

      it "uses arm64 GOARCH" do
        expect(Open3).to receive(:capture3)
          .with(/GOARCH=arm64/)
          .and_return([ "", "", double(success?: true) ])

        service.call
      end
    end
  end
end
