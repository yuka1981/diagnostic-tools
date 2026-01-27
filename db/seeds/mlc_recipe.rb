# frozen_string_literal: true

puts "Seeding MLC benchmark recipe..."

BenchmarkRecipe.find_or_create_by!(slug: "mlc") do |recipe|
  recipe.name = "Intel MLC"
  recipe.version = "3.12"
  recipe.command = "qis-agent mlc"
  recipe.description = "Intel Memory Latency Checker - comprehensive memory subsystem characterization"
  recipe.timeout_seconds = 1800
  recipe.default_profile = {
    "profile" => "quick",
    "binary_path" => "",
    "modules" => [],
    "threshold_mode" => "auto_baseline",
    "baseline_tolerance" => {
      "warning_percent" => 10,
      "fail_percent" => 20
    },
    "manual_thresholds" => {
      "idle_latency_ns" => { "max" => 100 },
      "peak_bandwidth.all_reads" => { "min" => 150_000 }
    }
  }
end

puts "MLC benchmark recipe created."
