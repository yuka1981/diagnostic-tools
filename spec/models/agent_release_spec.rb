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
      it "requires binary on create" do
        release = build(:agent_release, :without_binary)
        expect(release).not_to be_valid
        expect(release.errors[:binary]).to include("must be attached")
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
    it "calculates checksum on save" do
      release = create(:agent_release, version: "v1.0.0")
      expect(release.checksum).to be_present
      # Can be SHA256 hex (64 chars) or blob's base64 checksum
      expect(release.checksum).to match(/\A([a-f0-9]{64}|[\w+\/=]+)\z/)
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
