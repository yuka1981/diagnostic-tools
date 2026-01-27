# frozen_string_literal: true

module Mlc
  PROFILES = {
    quick: {
      name: "Quick",
      runtime: "~4 min",
      description: "Fast health check, pre-job validation",
      tests: %w[idle_latency peak_bandwidth]
    },
    standard: {
      name: "Standard",
      runtime: "~6 min",
      description: "Regular memory characterization",
      tests: %w[latency_matrix bandwidth_matrix peak_bandwidth]
    },
    full: {
      name: "Full",
      runtime: "~15 min",
      description: "Complete baseline, troubleshooting",
      tests: %w[idle_latency loaded_latency latency_matrix bandwidth_matrix peak_bandwidth c2c_latency]
    },
    numa: {
      name: "NUMA",
      runtime: "~5 min",
      description: "NUMA topology focus",
      tests: %w[latency_matrix bandwidth_matrix c2c_latency]
    },
    latency: {
      name: "Latency",
      runtime: "~8 min",
      description: "Latency-sensitive workload tuning",
      tests: %w[idle_latency loaded_latency c2c_latency]
    }
  }.freeze
end
