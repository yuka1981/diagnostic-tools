# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent::CompilerService do
  describe "#call" do
    let(:arch) { "x86_64" }
    let(:service) { described_class.new(arch) }

    it "executes go build command and returns path" do
      expect(Open3).to receive(:capture3)
        .with(hash_including("GOARCH" => "amd64"), "go", "build", "-o", anything, ".", hash_including(chdir: /agent\z/))
        .and_return(["", "", double(success?: true)])

      expect(FileUtils).to receive(:mv).with(anything, anything)

      path = service.call
      expect(path).to include("tmp/agent_amd64_")
    end

    it "raises error if compilation fails" do
      allow(Open3).to receive(:capture3).and_return(["", "error message", double(success?: false)])

      expect { service.call }.to raise_error(Agent::CompilerService::CompilationError, /Failed to compile/)
    end

    context "with arm64" do
      let(:arch) { "arm64" }

      it "uses arm64 GOARCH" do
        expect(Open3).to receive(:capture3)
          .with(hash_including("GOARCH" => "arm64"), "go", "build", "-o", anything, ".", hash_including(chdir: /agent\z/))
          .and_return(["", "", double(success?: true)])

        expect(FileUtils).to receive(:mv).with(anything, anything)

        service.call
      end
    end
  end
end