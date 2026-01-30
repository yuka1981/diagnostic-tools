require "rails_helper"

RSpec.describe Mlc::UploadService do
  let(:tempfile) { Tempfile.new([ "mlc", ".tgz" ]) }
  let(:uploaded_file) do
    ActionDispatch::Http::UploadedFile.new(
      tempfile: tempfile,
      filename: "mlc_v3.11.tgz",
      type: "application/gzip"
    )
  end

  before do
    tempfile.write("fake tarball content")
    tempfile.rewind
  end

  after do
    tempfile.close
    tempfile.unlink
  end

  describe "#call" do
    subject(:service) { described_class.new(uploaded_file) }

    it "stores the uploaded file" do
      result = service.call
      expect(result.success?).to be true
      expect(result.stored_path).to be_present
      expect(File.exist?(result.stored_path)).to be true
    end

    it "computes checksum" do
      result = service.call
      expect(result.computed_checksum).to match(/\A[a-f0-9]{64}\z/)
    end

    it "uses sanitized filename" do
      result = service.call
      expect(result.stored_path).to include("mlc_v3.11.tgz")
    end
  end

  describe "#verify_checksum" do
    subject(:service) { described_class.new(uploaded_file) }

    before { service.call }

    it "returns true for matching checksum" do
      computed = service.result.computed_checksum
      expect(service.verify_checksum("sha256", computed)).to be true
    end

    it "returns false for mismatched checksum" do
      expect(service.verify_checksum("sha256", "wrong")).to be false
    end

    it "handles sha1 algorithm" do
      sha1_checksum = Digest::SHA1.file(service.result.stored_path).hexdigest
      expect(service.verify_checksum("sha1", sha1_checksum)).to be true
    end

    it "handles md5 algorithm" do
      md5_checksum = Digest::MD5.file(service.result.stored_path).hexdigest
      expect(service.verify_checksum("md5", md5_checksum)).to be true
    end

    it "returns false for unsupported algorithm" do
      expect(service.verify_checksum("unsupported", "checksum")).to be false
    end
  end
end
