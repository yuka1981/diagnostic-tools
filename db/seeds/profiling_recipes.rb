# frozen_string_literal: true

puts "Seeding profiling recipes..."

recipes = [
  {
    name: "Quick System Report",
    slug: "quick-system-report",
    description: "Collect system hardware and BIOS configuration snapshot using Intel PerfSPECT",
    tool: "perfspect",
    subcommand: "report",
    module_name: "perfspect/3.13.0",
    default_options: {},
    timeout_seconds: 300
  },
  {
    name: "Performance Telemetry (60s)",
    slug: "performance-telemetry-60s",
    description: "Collect 60 seconds of live CPU performance metrics",
    tool: "perfspect",
    subcommand: "telemetry",
    module_name: "perfspect/3.13.0",
    default_options: { "duration" => 60 },
    timeout_seconds: 120
  },
  {
    name: "Performance Telemetry (5min)",
    slug: "performance-telemetry-5min",
    description: "Collect 5 minutes of live CPU performance metrics",
    tool: "perfspect",
    subcommand: "telemetry",
    module_name: "perfspect/3.13.0",
    default_options: { "duration" => 300 },
    timeout_seconds: 420
  },
  {
    name: "CPU Flame Graph",
    slug: "cpu-flame-graph",
    description: "Generate CPU flame graph visualization for 30 seconds",
    tool: "perfspect",
    subcommand: "flame",
    module_name: "perfspect/3.13.0",
    default_options: { "duration" => 30 },
    timeout_seconds: 120
  }
]

recipes.each do |attrs|
  ProfilingRecipe.find_or_create_by!(slug: attrs[:slug]) do |recipe|
    recipe.assign_attributes(attrs)
  end
end

puts "Created #{recipes.size} profiling recipes"
