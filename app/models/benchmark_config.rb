# frozen_string_literal: true

class BenchmarkConfig
  DEFAULT_WORK_DIR = "hpcg_source"

  # Get the effective benchmark work directory for a node
  def self.work_dir_for(_node = nil)
    DEFAULT_WORK_DIR
  end

  # Get the default work directory constant
  def self.default_work_dir
    DEFAULT_WORK_DIR
  end
end
