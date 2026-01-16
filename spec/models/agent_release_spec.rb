# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentRelease, type: :model do
  describe "associations" do
    it "has one attached binary" do
      release = build(:agent_release)
      expect(release.binary).to be_attached
    end
  end

  describe "validations" do
    subject { build(:agent_release) }

    it { is_expected.to validate_presence_of(:version) }
    it { is_expected.to validate_uniqueness_of(:version) }
    it { is_expected.to validate_length_of(:version).is_at_most(50) }
    it { is_expected.to validate_length_of(:release_notes).is_at_most(10_000) }

    describe "version format" do
      it "accepts valid semantic versions" do
        valid_versions = %w[v1.0.0 1.0.0 v0.5.2 2.1 v1.0.0-beta v1.0.0-rc.1]
        valid_versions.each do |version|
          release = build(:agent_release, version: version)
          expect(release).to be_valid, "Expected #{version} to be valid"
        end
      end

      it "rejects invalid version formats" do
        invalid_versions = [ "latest", "v1", "1.0.0.0.0", "version-1" ]
        invalid_versions.each do |version|
          release = build(:agent_release, version: version)
          expect(release).not_to be_valid, "Expected #{version} to be invalid"
        end
      end
    end

    describe "binary attachment" do
      it "does not require direct binary attachment (binaries are via AgentBinary model)" do
        # Binaries are now attached via AgentBinary model, not directly to AgentRelease
        release = build(:agent_release, :without_binary)
        expect(release).to be_valid
      end
    end
  end

  describe "enums" do
    it "defines status enum" do
      expect(described_class.statuses).to eq(
        "active" => 0,
        "deprecated" => 1,
        "recalled" => 2
      )
    end

    it "defaults to active status" do
      release = described_class.new
      expect(release.status).to eq("active")
    end
  end

  describe "scopes" do
    let!(:active_release) { create(:agent_release, version: "v1.0.0") }
    let!(:deprecated_release) { create(:agent_release, :deprecated, version: "v0.9.0") }
    let!(:recent_release) { create(:agent_release, version: "v1.1.0") }

    describe ".latest_first" do
      it "orders by created_at descending" do
        expect(described_class.latest_first.first).to eq(recent_release)
      end
    end

    describe ".by_status" do
      it "filters by status" do
        expect(described_class.by_status(:active)).to include(active_release, recent_release)
        expect(described_class.by_status(:active)).not_to include(deprecated_release)
      end
    end
  end

  describe ".latest" do
    it "returns the most recent active release" do
      create(:agent_release, version: "v1.0.0")
      latest = create(:agent_release, version: "v1.1.0")
      create(:agent_release, :deprecated, version: "v1.2.0")

      expect(described_class.latest).to eq(latest)
    end

    it "returns nil when no active releases exist" do
      create(:agent_release, :deprecated, version: "v1.0.0")
      expect(described_class.latest).to be_nil
    end
  end

  describe "checksum calculation" do
    it "calculates SHA256 hex checksum on save" do
      release = create(:agent_release, version: "v1.0.0")
      expect(release.checksum).to be_present
      # Must be SHA256 hex (64 lowercase hex characters)
      expect(release.checksum).to match(/\A[a-f0-9]{64}\z/)
    end

    it "updates checksum when binary changes" do
      release = create(:agent_release, version: "v1.0.0")
      original_checksum = release.checksum

      # Use a different file with different content
      new_file = Tempfile.new([ "new-agent", "" ])
      new_file.binmode
      new_file.write("completely different binary content #{Time.now.to_i}")
      new_file.rewind

      # Use the setter method to trigger @binary_updated flag
      release.binary = {
        io: new_file,
        filename: "hpc-agent-new",
        content_type: "application/octet-stream"
      }
      release.save!

      expect(release.checksum).to be_present
      expect(release.checksum).not_to eq(original_checksum)
      # Must still be SHA256 hex
      expect(release.checksum).to match(/\A[a-f0-9]{64}\z/)
    end

    describe "#valid_sha256_checksum?" do
      it "returns true for valid SHA256 hex checksums" do
        release = build(:agent_release)
        release.checksum = "a" * 64
        expect(release.valid_sha256_checksum?).to be true

        release.checksum = "0123456789abcdef" * 4
        expect(release.valid_sha256_checksum?).to be true
      end

      it "returns false for Base64 checksums (MD5)" do
        release = build(:agent_release)
        release.checksum = "Et4ZSvH556lTOVWBafoWzA=="
        expect(release.valid_sha256_checksum?).to be false
      end

      it "returns false for blank checksums" do
        release = build(:agent_release)
        release.checksum = nil
        expect(release.valid_sha256_checksum?).to be false

        release.checksum = ""
        expect(release.valid_sha256_checksum?).to be false
      end
    end

    describe "#recalculate_checksum!" do
      it "recalculates and saves checksum from binary" do
        release = create(:agent_release, version: "v1.0.0")
        # Manually set an invalid checksum
        release.update_column(:checksum, "invalid_base64_checksum==")

        expect(release.recalculate_checksum!).to be true
        release.reload
        expect(release.valid_sha256_checksum?).to be true
      end
    end

    describe ".recalculate_invalid_checksums!" do
      it "recalculates only invalid checksums" do
        # Create releases with valid and invalid checksums
        valid_release = create(:agent_release, version: "v1.0.0")
        invalid_release = create(:agent_release, version: "v2.0.0")
        invalid_release.update_column(:checksum, "InvalidBase64==")

        results = described_class.recalculate_invalid_checksums!

        expect(results[:success]).to eq(1)
        expect(results[:skipped]).to eq(1)
        expect(results[:failed]).to eq(0)

        invalid_release.reload
        expect(invalid_release.valid_sha256_checksum?).to be true
      end
    end
  end

  describe "instance methods" do
    let(:release) { create(:agent_release, version: "v1.0.0") }

    describe "#display_name" do
      it "returns formatted display name" do
        expect(release.display_name).to eq("Agent v1.0.0")
      end
    end

    describe "#binary_filename" do
      it "returns the filename when binary is attached" do
        expect(release.binary_filename).to eq("hpc-agent")
      end

      it "returns nil when binary is not attached" do
        release = build(:agent_release, :without_binary)
        expect(release.binary_filename).to be_nil
      end
    end

    describe "#binary_size" do
      it "returns the byte size of the binary" do
        expect(release.binary_size).to be > 0
      end

      it "returns 0 when binary is not attached" do
        release = build(:agent_release, :without_binary)
        expect(release.binary_size).to eq(0)
      end
    end

    describe "#formatted_size" do
      it "returns formatted size with units" do
        expect(release.formatted_size).to match(/\d+\.\d+ (B|KB|MB|GB)/)
      end

      it "returns dash when no binary attached" do
        release = build(:agent_release, :without_binary)
        expect(release.formatted_size).to eq("—")
      end
    end
  end
end
