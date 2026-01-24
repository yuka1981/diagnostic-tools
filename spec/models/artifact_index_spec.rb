# frozen_string_literal: true

require "rails_helper"

RSpec.describe ArtifactIndex, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:path) }
    it { is_expected.to validate_presence_of(:file_type) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:benchmark_run) }
  end

  describe "#effective_path" do
    let(:artifact) { build(:artifact_index, path: "/shared/artifacts/test.log", stored_path: nil) }

    context "when stored_path is present" do
      it "returns the stored_path" do
        artifact.stored_path = "/storage/artifacts/uuid123/test.log"
        expect(artifact.effective_path).to eq("/storage/artifacts/uuid123/test.log")
      end
    end

    context "when stored_path is blank" do
      it "returns the original path" do
        artifact.stored_path = nil
        expect(artifact.effective_path).to eq("/shared/artifacts/test.log")
      end
    end
  end

  describe "#downloadable?" do
    let(:artifact) { build(:artifact_index, path: "/shared/artifacts/test.log", stored_path: nil) }

    context "when stored_path file exists" do
      it "returns true" do
        artifact.stored_path = "/tmp/test_artifact_downloadable.log"
        File.write(artifact.stored_path, "test content")

        expect(artifact.downloadable?).to be true

        File.delete(artifact.stored_path)
      end
    end

    context "when original path file exists but stored_path is blank" do
      it "returns true" do
        artifact.path = "/tmp/test_artifact_original.log"
        File.write(artifact.path, "test content")

        expect(artifact.downloadable?).to be true

        File.delete(artifact.path)
      end
    end

    context "when neither file exists" do
      it "returns false" do
        artifact.path = "/nonexistent/path.log"
        artifact.stored_path = nil

        expect(artifact.downloadable?).to be false
      end
    end

    context "when stored_path is set but file does not exist, but original path exists" do
      it "returns true (falls back to original)" do
        artifact.stored_path = "/nonexistent/stored.log"
        artifact.path = "/tmp/test_artifact_fallback.log"
        File.write(artifact.path, "test content")

        expect(artifact.downloadable?).to be true

        File.delete(artifact.path)
      end
    end
  end

  describe "#filename" do
    let(:artifact) { build(:artifact_index, path: "/shared/artifacts/benchmark_1/output.log", stored_path: nil) }

    it "returns the basename of the effective path" do
      expect(artifact.filename).to eq("output.log")
    end

    context "when stored_path is present" do
      it "returns the basename of stored_path" do
        artifact.stored_path = "/storage/artifacts/uuid123/results.json"
        expect(artifact.filename).to eq("results.json")
      end
    end
  end

  describe "#safe_download_path" do
    let(:benchmark_run) { create(:benchmark_run) }

    context "with stored_path" do
      let(:artifact) { create(:artifact_index, benchmark_run: benchmark_run, stored_path: stored_path, path: "/legacy/path") }

      context "when file exists in storage" do
        let(:stored_path) { Rails.root.join("storage", "artifacts", "test.txt").to_s }

        before do
          FileUtils.mkdir_p(File.dirname(stored_path))
          File.write(stored_path, "test content")
        end

        after { FileUtils.rm_f(stored_path) }

        it "returns the stored_path" do
          expect(artifact.safe_download_path).to eq(stored_path)
        end
      end

      context "when stored file does not exist" do
        let(:stored_path) { "/storage/artifacts/nonexistent.txt" }

        it "returns nil" do
          expect(artifact.safe_download_path).to be_nil
        end
      end
    end

    context "with path traversal attempt" do
      let(:artifact) { create(:artifact_index, benchmark_run: benchmark_run, stored_path: "/storage/artifacts/../../../etc/passwd") }

      it "returns nil" do
        expect(artifact.safe_download_path).to be_nil
      end
    end
  end
end
