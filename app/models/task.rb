# frozen_string_literal: true

# Virtual model that wraps BenchmarkRun or ProfilingRun
# Provides unified interface for the Tasks page
class Task
  attr_reader :source

  delegate :id, :uuid, :status, :started_at, :finished_at,
           :duration, :metrics, :error_message, :node, :created_at,
           :pending?, :running?, :success?, :failed?, :cancelled?, :completed?,
           to: :source

  def self.wrap(run)
    new(run)
  end

  def initialize(source)
    @source = source
  end

  def type
    source.is_a?(BenchmarkRun) ? :benchmark : :profiling
  end

  def benchmark?
    type == :benchmark
  end

  def profiling?
    type == :profiling
  end

  def recipe_name
    if benchmark?
      source.benchmark_recipe.name
    else
      source.profiling_recipe&.name || source.subcommand
    end
  end

  def recipe
    benchmark? ? source.benchmark_recipe : source.profiling_recipe
  end

  def artifacts
    benchmark? ? source.artifact_indices : source.profiling_artifacts
  end

  # Wraps artifacts with unified interface for views
  def wrapped_artifacts
    artifacts.map { |a| ArtifactWrapper.new(a, self) }
  end

  # Wrapper providing unified interface for BenchmarkRun artifacts and ProfilingRun artifacts
  class ArtifactWrapper
    include Rails.application.routes.url_helpers

    attr_reader :artifact, :task

    delegate :id, :downloadable?, to: :artifact

    def initialize(artifact, task)
      @artifact = artifact
      @task = task
    end

    def name
      artifact.respond_to?(:filename) ? artifact.filename : File.basename(artifact.path)
    end

    def download_path
      if task.benchmark?
        download_artifact_benchmark_run_path(task.source, artifact_id: artifact.id)
      else
        download_artifact_node_profiling_run_path(task.node, task.source, artifact_id: artifact.id)
      end
    end
  end

  def dom_id
    "task_#{type}_#{id}"
  end

  def to_param
    "#{type}_#{id}"
  end

  # Parse param back to type and id
  def self.parse_param(param)
    match = param.to_s.match(/\A(benchmark|profiling)_(\d+)\z/)
    return nil unless match

    [ match[1].to_sym, match[2].to_i ]
  end

  def ==(other)
    other.is_a?(Task) && type == other.type && id == other.id
  end
end
