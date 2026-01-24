# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProfilingArtifact, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:profiling_run) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:filename) }
  end

  describe "#downloadable?" do
    it "returns true when file exists" do
      artifact = build(:profiling_artifact, file_path: __FILE__)
      expect(artifact.downloadable?).to be true
    end

    it "returns false when file does not exist" do
      artifact = build(:profiling_artifact, file_path: "/nonexistent/file.html")
      expect(artifact.downloadable?).to be false
    end
  end
end
