# MLC Benchmark Entry Page Design

## Overview

Dedicated standalone page for triggering Intel MLC benchmarks with profile card selection UI.

## Page Structure

**Route:** `GET /mlc_benchmarks/new` → `MlcBenchmarksController#new`

**Sidebar:** Top-level item "MLC Benchmark" with memory/chip icon, placed after "Nodes".

**Layout:**
```
┌─────────────────────────────────────────────────────────┐
│  MLC Benchmark                                          │
│  Run Intel Memory Latency Checker on a cluster node     │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Target Node                                            │
│  ┌─────────────────────────────────────────────────┐   │
│  │ Select a node...                            ▼   │   │
│  └─────────────────────────────────────────────────┘   │
│                                                         │
│  Select Profile                                         │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐       │
│  │ Quick   │ │Standard │ │  Full   │ │  NUMA   │ ...   │
│  │ ~4 min  │ │ ~6 min  │ │ ~15 min │ │ ~5 min  │       │
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘       │
│                                                         │
│  [Advanced Options ▼]  (collapsed by default)           │
│                                                         │
│                              [ Cancel ]  [ Run MLC ]    │
└─────────────────────────────────────────────────────────┘
```

## Profile Cards

Each card displays:
- Name (bold heading)
- Runtime estimate (badge)
- Description (one line)
- Tests included (small text list)

```
┌────────────────────────────────────┐
│  Quick                    ~4 min   │
│  Fast health check                 │
│                                    │
│  Tests: idle_latency,              │
│         peak_bandwidth             │
└────────────────────────────────────┘
```

**5 profiles in responsive grid:**

| Profile | Runtime | Description | Tests |
|---------|---------|-------------|-------|
| quick (default) | ~4 min | Fast health check, pre-job validation | idle_latency, peak_bandwidth |
| standard | ~6 min | Regular memory characterization | latency_matrix, bandwidth_matrix, peak_bandwidth |
| full | ~15 min | Complete baseline, troubleshooting | All 6 tests |
| numa | ~5 min | NUMA topology focus | latency_matrix, bandwidth_matrix, c2c_latency |
| latency | ~8 min | Latency-sensitive workload tuning | idle_latency, loaded_latency, c2c_latency |

**Selection behavior:**
- Click card to select (teal border highlight)
- Single selection only
- Quick pre-selected on page load

## Advanced Options

Collapsed by default. When expanded:

```
┌─────────────────────────────────────────────────────────┐
│  Advanced Options                                   ▲   │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  MLC Binary Path (optional)                             │
│  ┌─────────────────────────────────────────────────┐   │
│  │ /opt/intel/mlc/mlc                              │   │
│  └─────────────────────────────────────────────────┘   │
│  Leave empty to use PATH or module-loaded binary        │
│                                                         │
│  Lmod Modules (optional)                                │
│  ┌─────────────────────────────────────────────────┐   │
│  │ intel-mlc/3.12, gcc/11.2                        │   │
│  └─────────────────────────────────────────────────┘   │
│  Comma-separated module names to load before running    │
│                                                         │
│  Custom Log Path (optional)                             │
│  ┌─────────────────────────────────────────────────┐   │
│  │ /shared/logs/mlc                                │   │
│  └─────────────────────────────────────────────────┘   │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

All fields optional - uses recipe defaults if empty.

## Controller Flow

```ruby
# app/controllers/mlc_benchmarks_controller.rb
class MlcBenchmarksController < ApplicationController
  def new
    @nodes = Node.order(:hostname)
    @profiles = Mlc::PROFILES
    @form = Mlc::RunForm.new
  end

  def create
    @form = Mlc::RunForm.new(form_params)

    if @form.valid?
      # Build argument overrides from profile + advanced options
      # Create BenchmarkRun with MLC recipe
      # Queue Benchmark::TriggerJob
      redirect_to node_path(@form.node), notice: "MLC benchmark triggered"
    else
      render :new, status: :unprocessable_entity
    end
  end
end
```

**Form object validates:**
- `node_id` - required
- `profile` - required, must be one of 5 profiles
- `binary_path` - optional string
- `modules` - optional string (comma-separated)
- `log_path` - optional string

**Reuses existing infrastructure:**
- `BenchmarkRecipe.find_by(slug: "mlc")`
- `Benchmark::TriggerJob`
- `BenchmarkRun`

## File Structure

```
app/
├── controllers/
│   └── mlc_benchmarks_controller.rb
├── views/
│   └── mlc_benchmarks/
│       └── new.html.erb
├── forms/
│   └── mlc/
│       └── run_form.rb
├── components/
│   └── mlc/
│       ├── profile_card_component.rb
│       ├── profile_card_component.html.erb
│       ├── profile_selector_component.rb
│       ├── profile_selector_component.html.erb
│       ├── advanced_options_component.rb
│       └── advanced_options_component.html.erb
├── javascript/
│   └── controllers/
│       └── mlc_profile_controller.js
└── lib/
    └── mlc.rb                          # PROFILES constant

config/
└── routes.rb                           # resources :mlc_benchmarks, only: [:new, :create]

app/views/shared/
└── _sidebar.html.erb                   # Add MLC Benchmark entry
```

## Implementation Notes

- No new models needed
- Profile metadata defined in `Mlc::PROFILES` constant
- Stimulus controller handles card selection state
- Form submission creates BenchmarkRun and queues TriggerJob
- Redirects to node page after successful trigger
