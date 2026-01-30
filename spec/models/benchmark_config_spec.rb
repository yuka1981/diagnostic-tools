# frozen_string_literal: true

require "rails_helper"

RSpec.describe BenchmarkConfig do
  describe ".work_dir_for" do
    it "returns the default work directory" do
      expect(described_class.work_dir_for(nil)).to eq(BenchmarkConfig::DEFAULT_WORK_DIR)
    end

    it "returns the default work directory regardless of node" do
      node = create(:node)
      expect(described_class.work_dir_for(node)).to eq(BenchmarkConfig::DEFAULT_WORK_DIR)
    end
  end

  describe ".default_work_dir" do
    it "returns the default constant" do
      expect(described_class.default_work_dir).to eq("hpcg_source")
    end
  end
end
