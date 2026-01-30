require "rails_helper"

RSpec.describe Mlc::BinaryDetectionService do
  let(:extract_dir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(extract_dir) }

  describe "#call" do
    context "with valid tarball structure" do
      let(:mlc_binary_path) { File.join(extract_dir, "mlc_v3.11", "Linux", "mlc") }

      before do
        # Create mock extracted structure
        linux_dir = File.join(extract_dir, "mlc_v3.11", "Linux")
        FileUtils.mkdir_p(linux_dir)
        File.write(mlc_binary_path, "ELF binary content")
      end

      it "detects binary candidates" do
        service = described_class.new(extract_dir)
        # Stub file type detection to return ELF for our test file
        allow(service).to receive(:detect_file_type).with(mlc_binary_path).and_return("ELF 64-bit LSB executable")
        result = service.call

        expect(result.success?).to be true
        expect(result.candidates).not_to be_empty
        expect(result.candidates.first[:relative_path]).to include("Linux/mlc")
      end
    end

    context "with no binaries found" do
      it "returns error" do
        service = described_class.new(extract_dir)
        result = service.call

        expect(result.success?).to be false
        expect(result.error).to include("No MLC binary")
      end
    end
  end

  describe "#detect_version" do
    let(:binary_path) { File.join(extract_dir, "mlc") }

    before do
      # Create a mock binary that outputs version
      File.write(binary_path, "#!/bin/bash\necho 'Intel(R) Memory Latency Checker - v3.11'")
      FileUtils.chmod(0o755, binary_path)
    end

    it "extracts version from binary output" do
      service = described_class.new(extract_dir)
      version = service.detect_version(binary_path)
      expect(version).to eq("3.11")
    end
  end
end
