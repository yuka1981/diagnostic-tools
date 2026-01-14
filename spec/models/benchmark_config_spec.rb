# frozen_string_literal: true

require "rails_helper"

RSpec.describe BenchmarkConfig do
  describe ".work_dir_for" do
    let(:node) { create(:node) }

    context "when node has benchmark_work_dir set" do
      before { node.update!(benchmark_work_dir: "/custom/path") }

      it "returns the node's work directory" do
        expect(described_class.work_dir_for(node)).to eq("/custom/path")
      end
    end

    context "when node has no benchmark_work_dir but global is set" do
      before do
        SshSetting.current.update!(benchmark_work_dir: "/global/path")
      end

      it "returns the global work directory" do
        expect(described_class.work_dir_for(node)).to eq("/global/path")
      end
    end

    context "when neither node nor global work_dir is set" do
      before do
        SshSetting.current.update!(benchmark_work_dir: nil)
      end

      it "returns the default work directory" do
        expect(described_class.work_dir_for(node)).to eq(BenchmarkConfig::DEFAULT_WORK_DIR)
      end
    end

    context "when node is nil" do
      before do
        SshSetting.current.update!(benchmark_work_dir: nil)
      end

      it "returns the default work directory" do
        expect(described_class.work_dir_for(nil)).to eq(BenchmarkConfig::DEFAULT_WORK_DIR)
      end
    end
  end

  describe ".global_work_dir" do
    it "returns nil when not configured" do
      SshSetting.current.update!(benchmark_work_dir: nil)
      expect(described_class.global_work_dir).to be_nil
    end

    it "returns the configured value" do
      SshSetting.current.update!(benchmark_work_dir: "/global/benchmark")
      expect(described_class.global_work_dir).to eq("/global/benchmark")
    end
  end

  describe ".default_work_dir" do
    it "returns the default constant" do
      expect(described_class.default_work_dir).to eq("hpcg_source")
    end
  end
end
