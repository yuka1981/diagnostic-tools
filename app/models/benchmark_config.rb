# frozen_string_literal: true

class BenchmarkConfig
  DEFAULT_WORK_DIR = "hpcg_source"

  # Get the effective benchmark work directory for a node
  # Priority: node.benchmark_work_dir > global setting > default
  def self.work_dir_for(node)
    node&.benchmark_work_dir.presence ||
      global_work_dir ||
      DEFAULT_WORK_DIR
  end

  # Get the global default work directory
  def self.global_work_dir
    SshSetting.current.benchmark_work_dir.presence
  end

  # Get the default work directory constant
  def self.default_work_dir
    DEFAULT_WORK_DIR
  end
end
