# Tasks Page Design

**Date:** 2026-01-23
**Status:** Approved

## Overview

A unified page to view and manage all benchmark and profiling runs in a single filterable table with accordion-style row expansion.

## Page Location

- **Navigation:** Top-level "Tasks" item in main sidebar (after Nodes, before Benchmarks)
- **URL:** `/tasks`

## Page Layout

```
┌─────────────────────────────────────────────────────────────────┐
│  Tasks                                        [⟳ Off ▼]        │
│                                                                 │
│  ┌─ Filters ──────────────────────────────────────────────────┐│
│  │ Type: [All ▼]  Status: [All ▼]  Node: [All ▼]             ││
│  │ Recipe: [All ▼]  Date: [All time ▼]  [Search...]          ││
│  └────────────────────────────────────────────────────────────┘│
│                                                                 │
│  ┌─ Table ────────────────────────────────────────────────────┐│
│  │ (Sortable columns, accordion rows)                         ││
│  └────────────────────────────────────────────────────────────┘│
│                                                                 │
│  ┌─ Pagination ───────────────────────────────────────────────┐│
│  │ Showing 1-25 of 142 tasks    [◀] 1 2 3 4 5 ... 6 [▶]      ││
│  └────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

## Table Columns

| Column | Description | Sortable |
|--------|-------------|----------|
| Type | Badge: "Benchmark" (blue) or "Profiling" (purple) | Yes |
| Node | Node hostname, links to node page | Yes |
| Recipe | Recipe name (HPCG v3.1, perfspect report, etc.) | Yes |
| Status | Badge with icon: Pending (gray), Running (blue spinner), Success (green), Failed (red), Cancelled (gray) | Yes |
| Started | Relative time (2m ago) with tooltip for absolute time | Yes (default, desc) |
| Duration | Elapsed time or final duration (45m 23s) | Yes |
| Actions | Icon buttons: Cancel (if running), Delete | No |

## Row Interaction

- Click anywhere on row (except action buttons) to expand/collapse
- Chevron indicator (▶/▼) shows expand state
- Hover highlights the row
- Running tasks have subtle pulse animation on status badge

## Expanded Row Details

```
│ ▼ │ Benchmark │ node-01 │ HPCG v3.1        │ ✓ Success │ 1h ago │ 45m 23s │ [🗑] │
├────────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────┐  ┌─────────────────────────┐  ┌────────────────┐ │
│  │ DETAILS                 │  │ METRICS                 │  │ ACTIONS        │ │
│  │ Started: Jan 23, 10:15  │  │ GFLOPS: 234.5          │  │ [↻ Re-run    ] │ │
│  │ Finished: Jan 23, 10:59 │  │ Memory BW: 120 GB/s    │  │ [→ View Node ] │ │
│  │ UUID: abc-123-def       │  │ Efficiency: 94.2%      │  │ [🗑 Delete   ] │ │
│  │ Recipe: HPCG v3.1       │  │                        │  │ [⊘ Cancel    ] │ │
│  └─────────────────────────┘  └────────────────────────┘  └────────────────┘ │
│                                                                               │
│  ┌─ ARTIFACTS ────────────────────────────────────────────────────────────┐  │
│  │ 📄 output.log (12 KB)        [⬇ Download]                             │  │
│  │ 📄 results.json (2 KB)       [⬇ Download]                             │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                                                               │
│  ┌─ ERROR (only shown if failed) ─────────────────────────────────────────┐  │
│  │ Connection timeout after 30s: unable to reach node-01                  │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────────────┘
```

**Conditional display:**
- "Cancel" button only shows for pending/running tasks
- "Error" section only shows for failed tasks
- Metrics section shows whatever JSONB data exists (keys vary by recipe)

## Filters

| Filter | Options |
|--------|---------|
| Type | All, Benchmark, Profiling |
| Status | All, Pending, Running, Success, Failed, Cancelled |
| Node | All + list of node hostnames |
| Recipe | All + combined list (grouped: "Benchmark: X", "Profiling: Y") |
| Date | All time, Last hour, Last 24h, Last 7 days, Last 30 days, Custom range |
| Search | Free text - matches node hostname, recipe name, or UUID |

**Behavior:**
- Filters apply immediately on change (no submit button)
- URL updates with query params for shareable links (e.g., `/tasks?type=benchmark&status=failed`)
- "Clear all" resets to defaults
- Filters persist across pagination

## Actions

| Action | Description | Availability |
|--------|-------------|--------------|
| Cancel | Stop a running/pending task | Pending, Running |
| Re-run | Trigger same task again (same node + recipe) | All |
| Download artifacts | Download artifact files | Tasks with artifacts |
| View on node | Navigate to node detail page | All |
| Delete | Remove task record | All |

## Auto-Refresh

- Dropdown in header: Off (default), 10s, 30s, 1m, 5m
- Shows countdown indicator when active
- Stops polling when browser tab is hidden

## Pagination

- Classic page numbers
- 25 items per page
- Shows "Showing X-Y of Z tasks"

## Data Architecture

### Task Wrapper Class

```ruby
# app/models/task.rb
class Task
  attr_reader :source  # underlying BenchmarkRun or ProfilingRun

  delegate :id, :uuid, :status, :started_at, :finished_at,
           :duration, :metrics, :error_message, :node, to: :source

  def type
    source.is_a?(BenchmarkRun) ? :benchmark : :profiling
  end

  def recipe_name
    source.is_a?(BenchmarkRun) ? source.benchmark_recipe.name : source.profiling_recipe.name
  end

  def artifacts
    source.is_a?(BenchmarkRun) ? source.artifact_indices : source.profiling_artifacts
  end
end
```

### Query Approach

Fetch both types, wrap in Task objects, sort/paginate in Ruby. Acceptable for typical task volumes (hundreds to low thousands).

## Routes

```ruby
resources :tasks, only: [:index] do
  member do
    post :cancel
    post :rerun
    delete :destroy
  end
end
```

**URL patterns:**
- `GET /tasks` - List all tasks
- `GET /tasks?type=benchmark&status=running` - Filtered list
- `POST /tasks/:id/cancel?type=benchmark` - Cancel a task
- `POST /tasks/:id/rerun?type=profiling` - Re-run a task
- `DELETE /tasks/:id?type=benchmark` - Delete a task

## Controller

```ruby
# app/controllers/tasks_controller.rb
class TasksController < ApplicationController
  def index
    @tasks = Tasks::FilterQuery.new(filter_params).call
    @tasks = @tasks.page(params[:page]).per(25)
  end

  def cancel
    task = find_task
    Benchmark::CancelRunService.call(task) if params[:type] == "benchmark"
    # ... profiling cancel
  end

  def rerun
    # Create new run with same recipe + node
  end

  def destroy
    find_task.destroy
  end
end
```

## View Structure

```
app/views/tasks/
├── index.html.erb          # Main page layout
├── _filter_bar.html.erb    # Filter controls
├── _task_row.html.erb      # Collapsed row partial
├── _task_details.html.erb  # Expanded details partial
└── _pagination.html.erb    # Page controls
```

## Stimulus Controllers

### accordion_controller.js
- Toggles visibility of details section
- Updates chevron indicator
- Allows only one expanded row at a time (optional)

### auto_refresh_controller.js
- Dropdown to select interval (Off/10s/30s/1m/5m)
- Shows countdown indicator when active
- Turbo-reloads the table frame on interval
- Stops polling when tab is hidden (Page Visibility API)

## Turbo Frames

```erb
<turbo-frame id="tasks-table">
  <!-- Table content, reloaded on filter change or auto-refresh -->
</turbo-frame>

<turbo-frame id="task-details-<%= task.uuid %>">
  <!-- Expanded row details -->
</turbo-frame>
```

## Interaction Flow

1. Filter change → Updates URL → Turbo replaces `tasks-table` frame
2. Row click → Stimulus toggles local visibility (no server round-trip)
3. Auto-refresh tick → Turbo reloads `tasks-table` frame
