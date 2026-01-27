# frozen_string_literal: true

module Mlc
  class ThresholdEvaluator
    def initialize(benchmark_run, recipe)
      @run = benchmark_run
      @recipe = recipe
      @node = benchmark_run.node
      @config = recipe.default_profile || {}
      @metrics = benchmark_run.metrics || {}
    end

    def evaluate
      case @config["threshold_mode"]
      when "manual"
        evaluate_manual
      when "auto_baseline"
        evaluate_auto_baseline
      when "cluster_relative"
        evaluate_cluster_relative
      else
        { status: "skipped", message: "No threshold mode configured", results: {} }
      end
    end

    private

    def evaluate_manual
      thresholds = @config["manual_thresholds"] || {}
      results = {}
      overall_status = "pass"

      thresholds.each do |metric_path, constraints|
        value = dig_metric(metric_path)
        next if value.nil?

        result = check_manual_constraints(value, constraints)
        results[metric_path] = result
        overall_status = worse_status(overall_status, result[:status])
      end

      { status: overall_status, results: results }
    end

    def evaluate_auto_baseline
      tolerance = @config["baseline_tolerance"] || {}
      warning_pct = tolerance["warning_percent"] || 10
      fail_pct = tolerance["fail_percent"] || 20

      baselines = MlcBaseline.for_node(@node).index_by(&:metric_type)
      results = {}
      overall_status = "pass"

      flatten_metrics(@metrics).each do |metric_type, value|
        baseline = baselines[metric_type]
        next unless baseline

        deviation_pct = ((value - baseline.value) / baseline.value * 100).abs
        status = determine_baseline_status(deviation_pct, warning_pct, fail_pct)

        results[metric_type] = {
          status: status,
          value: value,
          baseline: baseline.value,
          deviation_percent: deviation_pct.round(2)
        }
        overall_status = worse_status(overall_status, status)
      end

      { status: overall_status, results: results }
    end

    def evaluate_cluster_relative
      # TODO: Implement cluster-relative comparison
      { status: "skipped", message: "Cluster-relative mode not yet implemented", results: {} }
    end

    def determine_baseline_status(deviation_pct, warning_pct, fail_pct)
      if deviation_pct > fail_pct
        "fail"
      elsif deviation_pct > warning_pct
        "warn"
      else
        "pass"
      end
    end

    def dig_metric(path)
      parts = path.split(".")
      parts.reduce(@metrics) do |obj, key|
        return nil unless obj.is_a?(Hash)

        obj[key] || obj[key.to_sym]
      end
    end

    def flatten_metrics(hash, prefix = "")
      hash.each_with_object({}) do |(key, value), result|
        full_key = prefix.empty? ? key.to_s : "#{prefix}.#{key}"
        if value.is_a?(Hash)
          result.merge!(flatten_metrics(value, full_key))
        elsif value.is_a?(Numeric)
          result[full_key] = value
        end
      end
    end

    def check_manual_constraints(value, constraints)
      status = "pass"

      if constraints["max"] && value > constraints["max"]
        status = "fail"
      elsif constraints["min"] && value < constraints["min"]
        status = "fail"
      end

      { status: status, value: value, constraints: constraints }
    end

    def worse_status(current, new_status)
      order = { "pass" => 0, "warn" => 1, "fail" => 2 }
      order[new_status] > order[current] ? new_status : current
    end
  end
end
