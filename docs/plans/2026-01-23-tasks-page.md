# Tasks Page Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a unified "Tasks" page that displays both benchmark runs and profiling runs in a single filterable table with accordion-style row expansion.

**Architecture:** A virtual `Task` model wraps `BenchmarkRun` and `ProfilingRun` objects. A `Tasks::FilterQuery` fetches from both tables, merges results, and applies filters. Stimulus controllers handle accordion expansion and auto-refresh. Turbo Frames enable filter changes without full page reloads.

**Tech Stack:** Rails 7.2, Hotwire (Turbo + Stimulus), Tailwind CSS, Kaminari pagination

---

## Task 1: Add Task Model (Virtual Wrapper)

**Files:**
- Create: `app/models/task.rb`
- Test: `spec/models/task_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/models/task_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Task do
  let(:node) { create(:node) }
  let(:benchmark_recipe) { create(:benchmark_recipe, :hpcg) }
  let(:profiling_recipe) { create(:profiling_recipe) }

  describe ".wrap" do
    it "wraps a BenchmarkRun" do
      run = create(:benchmark_run, node: node, benchmark_recipe: benchmark_recipe)
      task = Task.wrap(run)

      expect(task.type).to eq(:benchmark)
      expect(task.id).to eq(run.id)
      expect(task.uuid).to eq(run.uuid)
    end

    it "wraps a ProfilingRun" do
      run = create(:profiling_run, node: node, profiling_recipe: profiling_recipe)
      task = Task.wrap(run)

      expect(task.type).to eq(:profiling)
      expect(task.id).to eq(run.id)
      expect(task.uuid).to eq(run.uuid)
    end
  end

  describe "#type" do
    it "returns :benchmark for BenchmarkRun" do
      run = create(:benchmark_run, node: node, benchmark_recipe: benchmark_recipe)
      expect(Task.wrap(run).type).to eq(:benchmark)
    end

    it "returns :profiling for ProfilingRun" do
      run = create(:profiling_run, node: node, profiling_recipe: profiling_recipe)
      expect(Task.wrap(run).type).to eq(:profiling)
    end
  end

  describe "#recipe_name" do
    it "returns benchmark recipe name" do
      run = create(:benchmark_run, node: node, benchmark_recipe: benchmark_recipe)
      expect(Task.wrap(run).recipe_name).to eq(benchmark_recipe.name)
    end

    it "returns profiling recipe name" do
      run = create(:profiling_run, node: node, profiling_recipe: profiling_recipe)
      expect(Task.wrap(run).recipe_name).to eq(profiling_recipe.name)
    end

    it "returns subcommand when profiling recipe is nil" do
      run = create(:profiling_run, node: node, profiling_recipe: nil, subcommand: "report")
      expect(Task.wrap(run).recipe_name).to eq("report")
    end
  end

  describe "#artifacts" do
    it "returns artifact_indices for benchmark" do
      run = create(:benchmark_run, node: node, benchmark_recipe: benchmark_recipe)
      artifact = create(:artifact_index, benchmark_run: run)

      expect(Task.wrap(run).artifacts).to include(artifact)
    end

    it "returns profiling_artifacts for profiling" do
      run = create(:profiling_run, node: node, profiling_recipe: profiling_recipe)
      artifact = create(:profiling_artifact, profiling_run: run)

      expect(Task.wrap(run).artifacts).to include(artifact)
    end
  end

  describe "#dom_id" do
    it "returns unique dom id for benchmark" do
      run = create(:benchmark_run, node: node, benchmark_recipe: benchmark_recipe)
      expect(Task.wrap(run).dom_id).to eq("task_benchmark_#{run.id}")
    end

    it "returns unique dom id for profiling" do
      run = create(:profiling_run, node: node, profiling_recipe: profiling_recipe)
      expect(Task.wrap(run).dom_id).to eq("task_profiling_#{run.id}")
    end
  end

  describe "delegated methods" do
    it "delegates status to source" do
      run = create(:benchmark_run, node: node, benchmark_recipe: benchmark_recipe, status: :running)
      expect(Task.wrap(run).status).to eq("running")
    end

    it "delegates node to source" do
      run = create(:benchmark_run, node: node, benchmark_recipe: benchmark_recipe)
      expect(Task.wrap(run).node).to eq(node)
    end

    it "delegates duration to source" do
      run = create(:benchmark_run, node: node, benchmark_recipe: benchmark_recipe,
                   started_at: 1.hour.ago, finished_at: 30.minutes.ago)
      expect(Task.wrap(run).duration).to be_within(1).of(1800)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/models/task_spec.rb -v`
Expected: FAIL with "uninitialized constant Task"

**Step 3: Write minimal implementation**

```ruby
# app/models/task.rb
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

    [match[1].to_sym, match[2].to_i]
  end

  def ==(other)
    other.is_a?(Task) && type == other.type && id == other.id
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rspec spec/models/task_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/models/task.rb spec/models/task_spec.rb
git commit -m "feat(tasks): add Task virtual model wrapping benchmark/profiling runs"
```

---

## Task 2: Add Tasks::FilterQuery

**Files:**
- Create: `app/queries/tasks/filter_query.rb`
- Test: `spec/queries/tasks/filter_query_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/queries/tasks/filter_query_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tasks::FilterQuery do
  let(:node1) { create(:node, hostname: "node-01") }
  let(:node2) { create(:node, hostname: "node-02") }
  let(:benchmark_recipe) { create(:benchmark_recipe, :hpcg) }
  let(:profiling_recipe) { create(:profiling_recipe) }

  let!(:benchmark_run1) { create(:benchmark_run, node: node1, benchmark_recipe: benchmark_recipe, status: :success, created_at: 1.hour.ago) }
  let!(:benchmark_run2) { create(:benchmark_run, node: node2, benchmark_recipe: benchmark_recipe, status: :failed, created_at: 2.hours.ago) }
  let!(:profiling_run1) { create(:profiling_run, node: node1, profiling_recipe: profiling_recipe, status: :running, created_at: 30.minutes.ago) }
  let!(:profiling_run2) { create(:profiling_run, node: node2, profiling_recipe: profiling_recipe, status: :pending, created_at: 3.hours.ago) }

  describe "#call" do
    it "returns all tasks sorted by created_at desc" do
      tasks = described_class.new.call
      expect(tasks.map(&:uuid)).to eq([profiling_run1, benchmark_run1, benchmark_run2, profiling_run2].map(&:uuid))
    end

    it "wraps results in Task objects" do
      tasks = described_class.new.call
      expect(tasks).to all(be_a(Task))
    end
  end

  describe "filtering by type" do
    it "filters benchmark only" do
      tasks = described_class.new(type: "benchmark").call
      expect(tasks.map(&:type)).to all(eq(:benchmark))
      expect(tasks.size).to eq(2)
    end

    it "filters profiling only" do
      tasks = described_class.new(type: "profiling").call
      expect(tasks.map(&:type)).to all(eq(:profiling))
      expect(tasks.size).to eq(2)
    end
  end

  describe "filtering by status" do
    it "filters by success status" do
      tasks = described_class.new(status: "success").call
      expect(tasks.map(&:status)).to all(eq("success"))
    end

    it "filters by running status" do
      tasks = described_class.new(status: "running").call
      expect(tasks.map(&:status)).to all(eq("running"))
    end
  end

  describe "filtering by node" do
    it "filters by node_id" do
      tasks = described_class.new(node_id: node1.id).call
      expect(tasks.map { |t| t.node.id }).to all(eq(node1.id))
      expect(tasks.size).to eq(2)
    end
  end

  describe "filtering by recipe" do
    it "filters by benchmark recipe" do
      tasks = described_class.new(recipe_id: "benchmark_#{benchmark_recipe.id}").call
      expect(tasks).to all(be_benchmark)
    end

    it "filters by profiling recipe" do
      tasks = described_class.new(recipe_id: "profiling_#{profiling_recipe.id}").call
      expect(tasks).to all(be_profiling)
    end
  end

  describe "search" do
    it "searches by node hostname" do
      tasks = described_class.new(q: "node-01").call
      expect(tasks.map { |t| t.node.hostname }).to all(eq("node-01"))
    end

    it "searches by recipe name" do
      tasks = described_class.new(q: benchmark_recipe.name).call
      expect(tasks).to all(be_benchmark)
    end

    it "searches by uuid" do
      tasks = described_class.new(q: benchmark_run1.uuid[0..8]).call
      expect(tasks.map(&:uuid)).to include(benchmark_run1.uuid)
    end
  end

  describe "date range filtering" do
    it "filters by last hour" do
      tasks = described_class.new(date_range: "last_hour").call
      expect(tasks.map(&:uuid)).to contain_exactly(profiling_run1.uuid)
    end

    it "filters by last 24 hours" do
      tasks = described_class.new(date_range: "last_24h").call
      expect(tasks.size).to eq(4)
    end
  end

  describe "combined filters" do
    it "applies multiple filters" do
      tasks = described_class.new(type: "benchmark", status: "success").call
      expect(tasks.size).to eq(1)
      expect(tasks.first.uuid).to eq(benchmark_run1.uuid)
    end
  end

  describe "#filtered?" do
    it "returns false when no filters" do
      expect(described_class.new.filtered?).to be false
    end

    it "returns true when type filter" do
      expect(described_class.new(type: "benchmark").filtered?).to be true
    end

    it "returns true when search query" do
      expect(described_class.new(q: "test").filtered?).to be true
    end
  end

  describe "#total_count" do
    it "returns count before pagination" do
      query = described_class.new
      expect(query.total_count).to eq(4)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/queries/tasks/filter_query_spec.rb -v`
Expected: FAIL with "uninitialized constant Tasks::FilterQuery"

**Step 3: Write minimal implementation**

```ruby
# app/queries/tasks/filter_query.rb
# frozen_string_literal: true

module Tasks
  # Query object for filtering and searching combined benchmark/profiling runs
  class FilterQuery
    VALID_TYPES = %w[benchmark profiling].freeze
    VALID_STATUSES = BenchmarkRun.statuses.keys.freeze
    DATE_RANGES = {
      "last_hour" => 1.hour,
      "last_24h" => 24.hours,
      "last_7d" => 7.days,
      "last_30d" => 30.days
    }.freeze

    attr_reader :params

    def initialize(params = {})
      @params = params.to_h.with_indifferent_access
      @cached_results = nil
    end

    def call
      @cached_results ||= fetch_and_merge_results
    end

    def total_count
      call.size
    end

    def filtered?
      type_filter.present? || status.present? || node_id.present? ||
        recipe_id.present? || search_query.present? || date_range.present?
    end

    # Accessors for form repopulation
    def type_filter
      params[:type].presence
    end

    def status
      params[:status].presence
    end

    def node_id
      params[:node_id].presence
    end

    def recipe_id
      params[:recipe_id].presence
    end

    def search_query
      params[:q].presence
    end

    def date_range
      params[:date_range].presence
    end

    private

    def fetch_and_merge_results
      benchmark_tasks = fetch_benchmark_runs.map { |r| Task.wrap(r) }
      profiling_tasks = fetch_profiling_runs.map { |r| Task.wrap(r) }

      (benchmark_tasks + profiling_tasks).sort_by { |t| -t.created_at.to_i }
    end

    def fetch_benchmark_runs
      return BenchmarkRun.none if type_filter == "profiling"

      scope = BenchmarkRun.includes(:node, :benchmark_recipe)
      scope = apply_common_filters(scope, :benchmark)
      scope = apply_benchmark_recipe_filter(scope)
      scope = apply_benchmark_search(scope)
      scope
    end

    def fetch_profiling_runs
      return ProfilingRun.none if type_filter == "benchmark"

      scope = ProfilingRun.includes(:node, :profiling_recipe)
      scope = apply_common_filters(scope, :profiling)
      scope = apply_profiling_recipe_filter(scope)
      scope = apply_profiling_search(scope)
      scope
    end

    def apply_common_filters(scope, type)
      scope = scope.where(status: status) if status.present? && VALID_STATUSES.include?(status)
      scope = scope.where(node_id: node_id) if node_id.present?
      scope = apply_date_range(scope) if date_range.present?
      scope
    end

    def apply_date_range(scope)
      duration = DATE_RANGES[date_range]
      return scope unless duration

      scope.where(created_at: duration.ago..)
    end

    def apply_benchmark_recipe_filter(scope)
      return scope unless recipe_id.present?

      parsed = parse_recipe_id
      return scope unless parsed && parsed[:type] == :benchmark

      scope.where(benchmark_recipe_id: parsed[:id])
    end

    def apply_profiling_recipe_filter(scope)
      return scope unless recipe_id.present?

      parsed = parse_recipe_id
      return scope unless parsed && parsed[:type] == :profiling

      scope.where(profiling_recipe_id: parsed[:id])
    end

    def parse_recipe_id
      match = recipe_id.to_s.match(/\A(benchmark|profiling)_(\d+)\z/)
      return nil unless match

      { type: match[1].to_sym, id: match[2].to_i }
    end

    def apply_benchmark_search(scope)
      return scope unless search_query.present?

      term = "%#{search_query}%"
      scope.joins(:node, :benchmark_recipe)
           .where("nodes.hostname ILIKE :term OR benchmark_recipes.name ILIKE :term OR benchmark_runs.uuid ILIKE :term", term: term)
    end

    def apply_profiling_search(scope)
      return scope unless search_query.present?

      term = "%#{search_query}%"
      scope.left_joins(:profiling_recipe)
           .joins(:node)
           .where("nodes.hostname ILIKE :term OR profiling_recipes.name ILIKE :term OR profiling_runs.uuid ILIKE :term OR profiling_runs.subcommand ILIKE :term", term: term)
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rspec spec/queries/tasks/filter_query_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/queries/tasks/filter_query.rb spec/queries/tasks/filter_query_spec.rb
git commit -m "feat(tasks): add FilterQuery for combined benchmark/profiling task filtering"
```

---

## Task 3: Add TasksController

**Files:**
- Create: `app/controllers/tasks_controller.rb`
- Test: `spec/requests/tasks_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/requests/tasks_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Tasks", type: :request do
  let(:user) { create(:user) }
  let(:node) { create(:node) }
  let(:benchmark_recipe) { create(:benchmark_recipe, :hpcg) }
  let(:profiling_recipe) { create(:profiling_recipe) }

  before { sign_in user }

  describe "GET /tasks" do
    let!(:benchmark_run) { create(:benchmark_run, node: node, benchmark_recipe: benchmark_recipe) }
    let!(:profiling_run) { create(:profiling_run, node: node, profiling_recipe: profiling_recipe) }

    it "returns http success" do
      get tasks_path
      expect(response).to have_http_status(:success)
    end

    it "displays both benchmark and profiling runs" do
      get tasks_path
      expect(response.body).to include(node.hostname)
      expect(response.body).to include(benchmark_recipe.name)
      expect(response.body).to include(profiling_recipe.name)
    end

    context "with type filter" do
      it "filters benchmark only" do
        get tasks_path(type: "benchmark")
        expect(response.body).to include(benchmark_recipe.name)
        expect(response.body).not_to include(profiling_recipe.name)
      end

      it "filters profiling only" do
        get tasks_path(type: "profiling")
        expect(response.body).to include(profiling_recipe.name)
        expect(response.body).not_to include(benchmark_recipe.name)
      end
    end

    context "with status filter" do
      let!(:success_run) { create(:benchmark_run, node: node, benchmark_recipe: benchmark_recipe, status: :success) }

      it "filters by status" do
        get tasks_path(status: "success")
        expect(response).to have_http_status(:success)
      end
    end

    context "with pagination" do
      before do
        30.times { create(:benchmark_run, node: node, benchmark_recipe: benchmark_recipe) }
      end

      it "paginates results" do
        get tasks_path
        expect(response.body).to include("Next")
      end

      it "accepts page parameter" do
        get tasks_path(page: 2)
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "POST /tasks/:id/cancel" do
    context "with benchmark run" do
      let(:pending_run) { create(:benchmark_run, node: node, benchmark_recipe: benchmark_recipe, status: :pending) }

      it "cancels the benchmark run" do
        post cancel_task_path("benchmark_#{pending_run.id}")
        expect(pending_run.reload.status).to eq("cancelled")
      end

      it "redirects to tasks path" do
        post cancel_task_path("benchmark_#{pending_run.id}")
        expect(response).to redirect_to(tasks_path)
      end
    end

    context "with profiling run" do
      let(:pending_run) { create(:profiling_run, node: node, profiling_recipe: profiling_recipe, status: :pending) }

      it "cancels the profiling run" do
        post cancel_task_path("profiling_#{pending_run.id}")
        expect(pending_run.reload.status).to eq("cancelled")
      end
    end
  end

  describe "DELETE /tasks/:id" do
    context "with benchmark run" do
      let!(:run) { create(:benchmark_run, node: node, benchmark_recipe: benchmark_recipe) }

      it "deletes the benchmark run" do
        expect {
          delete task_path("benchmark_#{run.id}")
        }.to change(BenchmarkRun, :count).by(-1)
      end
    end

    context "with profiling run" do
      let!(:run) { create(:profiling_run, node: node, profiling_recipe: profiling_recipe) }

      it "deletes the profiling run" do
        expect {
          delete task_path("profiling_#{run.id}")
        }.to change(ProfilingRun, :count).by(-1)
      end
    end
  end

  describe "POST /tasks/:id/rerun" do
    context "with benchmark run" do
      let(:run) { create(:benchmark_run, node: node, benchmark_recipe: benchmark_recipe, status: :success) }

      it "creates a new benchmark run" do
        expect {
          post rerun_task_path("benchmark_#{run.id}")
        }.to change(BenchmarkRun, :count).by(1)
      end

      it "redirects to tasks path" do
        post rerun_task_path("benchmark_#{run.id}")
        expect(response).to redirect_to(tasks_path)
      end
    end

    context "with profiling run" do
      let(:run) { create(:profiling_run, node: node, profiling_recipe: profiling_recipe, status: :success) }

      it "creates a new profiling run" do
        expect {
          post rerun_task_path("profiling_#{run.id}")
        }.to change(ProfilingRun, :count).by(1)
      end
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/requests/tasks_spec.rb -v`
Expected: FAIL with "No route matches [GET] \"/tasks\""

**Step 3: Add routes**

```ruby
# config/routes.rb
# Add after line 105 (after benchmark_recipes block), before notifications:

resources :tasks, only: [:index] do
  member do
    post :cancel
    post :rerun
  end
end
```

**Step 4: Write controller implementation**

```ruby
# app/controllers/tasks_controller.rb
# frozen_string_literal: true

class TasksController < ApplicationController
  layout "dashboard"
  helper_method :filter_params

  def index
    @filter = Tasks::FilterQuery.new(filter_params)
    all_tasks = @filter.call
    @tasks = Kaminari.paginate_array(all_tasks).page(params[:page]).per(25)

    # Load data for filter dropdowns
    @nodes = Node.order(:hostname)
    @benchmark_recipes = BenchmarkRecipe.active.order(:name)
    @profiling_recipes = ProfilingRecipe.active.order(:name)
  end

  def cancel
    run = find_run
    return redirect_with_error("Task not found") unless run

    unless run.pending? || run.running?
      return redirect_with_error("Cannot cancel a completed task")
    end

    if run.is_a?(BenchmarkRun)
      service = Benchmark::CancelRunService.new(run)
      result = service.call
      message = result.success? ? "Task cancelled successfully" : "Failed to cancel: #{result.error}"
    else
      run.update!(status: :cancelled, error_message: "Cancelled by user at #{Time.current}")
      message = "Task cancelled successfully"
    end

    respond_to do |format|
      format.html { redirect_to tasks_path, notice: message }
      format.turbo_stream { redirect_to tasks_path, notice: message }
    end
  end

  def destroy
    run = find_run
    return redirect_with_error("Task not found") unless run

    run.destroy!
    redirect_to tasks_path, notice: "Task deleted successfully"
  end

  def rerun
    run = find_run
    return redirect_with_error("Task not found") unless run

    if run.is_a?(BenchmarkRun)
      new_run = BenchmarkRun.create!(
        node: run.node,
        benchmark_recipe: run.benchmark_recipe,
        arguments: run.arguments,
        log_path: run.log_path
      )
      Benchmark::TriggerJob.perform_later(new_run.id)
    else
      new_run = ProfilingRun.create!(
        node: run.node,
        profiling_recipe: run.profiling_recipe,
        subcommand: run.subcommand,
        options: run.options,
        user: current_user
      )
      Profiling::TriggerJob.perform_later(new_run.id)
    end

    redirect_to tasks_path, notice: "Task re-triggered successfully"
  end

  private

  def filter_params
    params.permit(:type, :status, :node_id, :recipe_id, :date_range, :q)
  end

  def find_run
    parsed = Task.parse_param(params[:id])
    return nil unless parsed

    type, id = parsed
    type == :benchmark ? BenchmarkRun.find_by(id: id) : ProfilingRun.find_by(id: id)
  end

  def redirect_with_error(message)
    redirect_to tasks_path, alert: message
  end
end
```

**Step 5: Run test to verify it passes**

Run: `bin/rspec spec/requests/tasks_spec.rb -v`
Expected: PASS (some may fail due to missing views - that's OK for now)

**Step 6: Commit**

```bash
git add config/routes.rb app/controllers/tasks_controller.rb spec/requests/tasks_spec.rb
git commit -m "feat(tasks): add TasksController with index, cancel, delete, rerun actions"
```

---

## Task 4: Add Accordion Stimulus Controller

**Files:**
- Create: `app/javascript/controllers/accordion_controller.js`

**Step 1: Write the controller**

```javascript
// app/javascript/controllers/accordion_controller.js
import { Controller } from "@hotwired/stimulus"

// Handles accordion row expansion in tables
// Usage:
//   <div data-controller="accordion">
//     <tr data-accordion-target="row" data-action="click->accordion#toggle">
//     <tr data-accordion-target="details" class="hidden">
export default class extends Controller {
  static targets = ["row", "details", "chevron"]
  static values = {
    open: { type: Boolean, default: false },
    exclusive: { type: Boolean, default: true }
  }

  toggle(event) {
    // Don't toggle if clicking on buttons or links
    if (event.target.closest('button, a, [data-no-toggle]')) {
      return
    }

    const row = event.currentTarget
    const index = this.rowTargets.indexOf(row)

    if (index === -1) return

    const details = this.detailsTargets[index]
    const chevron = this.chevronTargets[index]
    const isCurrentlyOpen = !details.classList.contains('hidden')

    // Close all if exclusive mode
    if (this.exclusiveValue && !isCurrentlyOpen) {
      this.closeAll()
    }

    // Toggle current
    details.classList.toggle('hidden', isCurrentlyOpen)
    if (chevron) {
      chevron.classList.toggle('rotate-90', !isCurrentlyOpen)
    }
    row.classList.toggle('bg-slate-50', !isCurrentlyOpen)
  }

  closeAll() {
    this.detailsTargets.forEach((details, index) => {
      details.classList.add('hidden')
      const chevron = this.chevronTargets[index]
      if (chevron) {
        chevron.classList.remove('rotate-90')
      }
      this.rowTargets[index]?.classList.remove('bg-slate-50')
    })
  }
}
```

**Step 2: Register controller (verify index.js imports correctly)**

Check `app/javascript/controllers/index.js` - Stimulus auto-loads controllers from this directory.

**Step 3: Commit**

```bash
git add app/javascript/controllers/accordion_controller.js
git commit -m "feat(tasks): add accordion Stimulus controller for row expansion"
```

---

## Task 5: Add Auto-Refresh Stimulus Controller

**Files:**
- Create: `app/javascript/controllers/auto_refresh_controller.js`

**Step 1: Write the controller**

```javascript
// app/javascript/controllers/auto_refresh_controller.js
import { Controller } from "@hotwired/stimulus"

// Auto-refresh controller for Tasks page
// Usage:
//   <div data-controller="auto-refresh" data-auto-refresh-frame-value="tasks_list">
//     <select data-auto-refresh-target="select" data-action="change->auto-refresh#updateInterval">
export default class extends Controller {
  static targets = ["select", "countdown"]
  static values = {
    frame: String,
    interval: { type: Number, default: 0 }
  }

  connect() {
    this.timer = null
    this.countdownTimer = null
    this.remainingSeconds = 0
    this.startIfNeeded()

    // Pause when tab is hidden
    document.addEventListener('visibilitychange', this.handleVisibilityChange.bind(this))
  }

  disconnect() {
    this.stop()
    document.removeEventListener('visibilitychange', this.handleVisibilityChange.bind(this))
  }

  updateInterval(event) {
    this.intervalValue = parseInt(event.target.value, 10) || 0
    this.stop()
    this.startIfNeeded()
  }

  intervalValueChanged() {
    this.stop()
    this.startIfNeeded()
  }

  startIfNeeded() {
    if (this.intervalValue > 0 && !document.hidden) {
      this.remainingSeconds = this.intervalValue / 1000
      this.updateCountdown()
      this.startCountdown()
      this.timer = setTimeout(() => this.refresh(), this.intervalValue)
    }
  }

  stop() {
    if (this.timer) {
      clearTimeout(this.timer)
      this.timer = null
    }
    if (this.countdownTimer) {
      clearInterval(this.countdownTimer)
      this.countdownTimer = null
    }
    this.updateCountdown()
  }

  refresh() {
    const frame = document.getElementById(this.frameValue)
    if (frame) {
      frame.reload()
    }
    this.startIfNeeded()
  }

  startCountdown() {
    this.countdownTimer = setInterval(() => {
      this.remainingSeconds = Math.max(0, this.remainingSeconds - 1)
      this.updateCountdown()
    }, 1000)
  }

  updateCountdown() {
    if (!this.hasCountdownTarget) return

    if (this.intervalValue > 0 && this.remainingSeconds > 0) {
      this.countdownTarget.textContent = `${this.remainingSeconds}s`
      this.countdownTarget.classList.remove('hidden')
    } else {
      this.countdownTarget.classList.add('hidden')
    }
  }

  handleVisibilityChange() {
    if (document.hidden) {
      this.stop()
    } else {
      this.startIfNeeded()
    }
  }
}
```

**Step 2: Commit**

```bash
git add app/javascript/controllers/auto_refresh_controller.js
git commit -m "feat(tasks): add auto-refresh Stimulus controller with countdown"
```

---

## Task 6: Add Tasks Index View

**Files:**
- Create: `app/views/tasks/index.html.erb`
- Create: `app/views/tasks/_filter_bar.html.erb`
- Create: `app/views/tasks/_task_row.html.erb`
- Create: `app/views/tasks/_task_details.html.erb`

**Step 1: Create index view**

```erb
<%# app/views/tasks/index.html.erb %>
<% content_for(:page_title) { "Tasks" } %>

<div data-controller="accordion auto-refresh"
     data-auto-refresh-frame-value="tasks_list"
     data-accordion-exclusive-value="true">

  <div class="flex items-center justify-between mb-6">
    <h1 class="text-2xl font-bold text-slate-900">Tasks</h1>

    <%# Auto-refresh control %>
    <div class="flex items-center gap-2">
      <span data-auto-refresh-target="countdown" class="text-xs text-slate-500 hidden"></span>
      <select data-auto-refresh-target="select"
              data-action="change->auto-refresh#updateInterval"
              class="text-sm rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500">
        <option value="0">Auto-refresh: Off</option>
        <option value="10000">10s</option>
        <option value="30000">30s</option>
        <option value="60000">1m</option>
        <option value="300000">5m</option>
      </select>
    </div>
  </div>

  <%# Filter Bar %>
  <%= render "tasks/filter_bar" %>

  <%# Tasks List (Turbo Frame) %>
  <%= turbo_frame_tag "tasks_list", data: { turbo_action: "advance" } do %>
    <div class="card-netbox">
      <% if @tasks.any? %>
        <%# Filter Summary %>
        <% if @filter.filtered? %>
          <div class="border-b border-slate-200 bg-slate-50 px-6 py-3">
            <p class="text-sm text-slate-600">
              Showing <%= pluralize(@filter.total_count, "task") %>
              <% if @filter.search_query.present? %>
                matching <strong class="font-medium text-slate-900">"<%= h(@filter.search_query) %>"</strong>
              <% end %>
            </p>
          </div>
        <% end %>

        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-slate-200 text-sm">
            <thead class="bg-slate-50">
              <tr>
                <th scope="col" class="w-8 px-3 py-2 border-b"></th>
                <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500 border-b">Type</th>
                <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500 border-b">Node</th>
                <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500 border-b">Recipe</th>
                <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500 border-b">Status</th>
                <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500 border-b">Started</th>
                <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500 border-b">Duration</th>
                <th scope="col" class="relative px-3 py-2 border-b">
                  <span class="sr-only">Actions</span>
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-slate-200 bg-white">
              <% @tasks.each do |task| %>
                <%= render "tasks/task_row", task: task %>
                <%= render "tasks/task_details", task: task %>
              <% end %>
            </tbody>
          </table>
        </div>

        <%# Pagination %>
        <% if @tasks.total_pages > 1 %>
          <div class="border-t border-slate-200 bg-slate-50 px-6 py-4">
            <nav class="flex items-center justify-between" aria-label="Pagination">
              <div class="hidden sm:block">
                <p class="text-xs font-bold text-slate-500 uppercase">
                  Showing
                  <span class="text-slate-700"><%= @tasks.offset_value + 1 %></span>
                  to
                  <span class="text-slate-700"><%= [@tasks.offset_value + @tasks.limit_value, @tasks.total_count].min %></span>
                  of
                  <span class="text-slate-700"><%= @tasks.total_count %></span>
                  tasks
                </p>
              </div>
              <div class="flex flex-1 justify-between sm:justify-end gap-2">
                <% if @tasks.prev_page %>
                  <%= link_to "Previous",
                      tasks_path(filter_params.merge(page: @tasks.prev_page)),
                      data: { turbo_frame: "tasks_list" },
                      class: "btn-secondary" %>
                <% end %>
                <% if @tasks.next_page %>
                  <%= link_to "Next",
                      tasks_path(filter_params.merge(page: @tasks.next_page)),
                      data: { turbo_frame: "tasks_list" },
                      class: "btn-secondary" %>
                <% end %>
              </div>
            </nav>
          </div>
        <% end %>
      <% else %>
        <div class="flex flex-col items-center justify-center py-12 text-center">
          <div class="h-12 w-12 rounded-full bg-slate-100 flex items-center justify-center mb-4">
            <%= lucide_icon("list-checks", class: "h-6 w-6 text-slate-400") %>
          </div>
          <p class="text-sm font-medium text-slate-900">
            <% if @filter.filtered? %>
              No tasks match your filters
            <% else %>
              No tasks yet
            <% end %>
          </p>
          <% if @filter.filtered? %>
            <%= link_to "Clear all filters", tasks_path,
                data: { turbo_frame: "tasks_list" },
                class: "mt-4 btn-secondary" %>
          <% end %>
        </div>
      <% end %>
    </div>
  <% end %>
</div>
```

**Step 2: Create filter bar partial**

```erb
<%# app/views/tasks/_filter_bar.html.erb %>
<div class="card-netbox mb-6">
  <div class="card-header">
    <h3 class="card-title">Filters</h3>
  </div>
  <div class="p-4">
    <%= form_with url: tasks_path, method: :get, data: { controller: "autosubmit", turbo_frame: "tasks_list", turbo_action: "advance" }, class: "flex flex-wrap items-end gap-4" do |f| %>
      <%# Search Field %>
      <div class="flex-1 min-w-[200px]">
        <label for="q" class="block text-xs font-bold text-slate-500 uppercase mb-1">Search</label>
        <%= f.text_field :q,
            value: @filter.search_query,
            placeholder: "Search by node, recipe, UUID...",
            class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" %>
      </div>

      <%# Type Filter %>
      <div class="w-32">
        <label for="type" class="block text-xs font-bold text-slate-500 uppercase mb-1">Type</label>
        <%= f.select :type,
            options_for_select([["All Types", ""], ["Benchmark", "benchmark"], ["Profiling", "profiling"]], @filter.type_filter),
            {},
            class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm",
            data: { action: "change->autosubmit#submit" } %>
      </div>

      <%# Status Filter %>
      <div class="w-32">
        <label for="status" class="block text-xs font-bold text-slate-500 uppercase mb-1">Status</label>
        <%= f.select :status,
            options_for_select([["All Statuses", ""]] + BenchmarkRun.statuses.keys.map { |s| [s.humanize, s] }, @filter.status),
            {},
            class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm",
            data: { action: "change->autosubmit#submit" } %>
      </div>

      <%# Node Filter %>
      <div class="w-40">
        <label for="node_id" class="block text-xs font-bold text-slate-500 uppercase mb-1">Node</label>
        <%= f.select :node_id,
            options_for_select([["All Nodes", ""]] + @nodes.map { |n| [n.hostname, n.id] }, @filter.node_id),
            {},
            class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm",
            data: { action: "change->autosubmit#submit" } %>
      </div>

      <%# Recipe Filter %>
      <div class="w-48">
        <label for="recipe_id" class="block text-xs font-bold text-slate-500 uppercase mb-1">Recipe</label>
        <%= f.select :recipe_id,
            options_for_select(
              [["All Recipes", ""]] +
              @benchmark_recipes.map { |r| ["Benchmark: #{r.name}", "benchmark_#{r.id}"] } +
              @profiling_recipes.map { |r| ["Profiling: #{r.name}", "profiling_#{r.id}"] },
              @filter.recipe_id
            ),
            {},
            class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm",
            data: { action: "change->autosubmit#submit" } %>
      </div>

      <%# Date Range Filter %>
      <div class="w-36">
        <label for="date_range" class="block text-xs font-bold text-slate-500 uppercase mb-1">Date</label>
        <%= f.select :date_range,
            options_for_select([
              ["All Time", ""],
              ["Last Hour", "last_hour"],
              ["Last 24 Hours", "last_24h"],
              ["Last 7 Days", "last_7d"],
              ["Last 30 Days", "last_30d"]
            ], @filter.date_range),
            {},
            class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm",
            data: { action: "change->autosubmit#submit" } %>
      </div>

      <%# Actions %>
      <div class="flex items-center gap-2">
        <%= f.submit "Search", class: "btn-primary cursor-pointer" %>

        <% if @filter.filtered? %>
          <%= link_to "Clear", tasks_path,
              data: { turbo_frame: "tasks_list" },
              class: "btn-secondary" %>
        <% end %>
      </div>
    <% end %>
  </div>
</div>
```

**Step 3: Create task row partial**

```erb
<%# app/views/tasks/_task_row.html.erb %>
<tr id="<%= task.dom_id %>"
    class="hover:bg-slate-50 transition-colors cursor-pointer"
    data-accordion-target="row"
    data-action="click->accordion#toggle">
  <td class="px-3 py-2">
    <%= lucide_icon("chevron-right", class: "h-4 w-4 text-slate-400 transition-transform", data: { accordion_target: "chevron" }) %>
  </td>
  <td class="whitespace-nowrap px-3 py-2">
    <% if task.benchmark? %>
      <span class="inline-flex items-center rounded-sm px-2 py-0.5 text-xs font-medium bg-blue-100 text-blue-800">
        Benchmark
      </span>
    <% else %>
      <span class="inline-flex items-center rounded-sm px-2 py-0.5 text-xs font-medium bg-purple-100 text-purple-800">
        Profiling
      </span>
    <% end %>
  </td>
  <td class="whitespace-nowrap px-3 py-2 text-sm text-slate-600">
    <%= link_to task.node.hostname, node_path(task.node), class: "hover:text-teal-600", data: { no_toggle: true } %>
  </td>
  <td class="whitespace-nowrap px-3 py-2">
    <p class="text-sm font-medium text-slate-900"><%= task.recipe_name %></p>
  </td>
  <td class="whitespace-nowrap px-3 py-2">
    <span class="inline-flex items-center rounded-sm px-2 py-0.5 text-xs font-medium <%= task_status_badge_class(task.status) %>">
      <% if task.running? %>
        <%= lucide_icon("loader-2", class: "h-3 w-3 mr-1 animate-spin") %>
      <% end %>
      <%= task.status.humanize %>
    </span>
  </td>
  <td class="whitespace-nowrap px-3 py-2 text-sm text-slate-500" title="<%= task.started_at&.strftime('%Y-%m-%d %H:%M:%S') %>">
    <%= task.started_at ? time_ago_in_words(task.started_at) + " ago" : "Pending" %>
  </td>
  <td class="whitespace-nowrap px-3 py-2 text-sm text-slate-500">
    <%= task.duration ? distance_of_time_in_words(task.duration) : "-" %>
  </td>
  <td class="whitespace-nowrap px-3 py-2 text-right text-sm" data-no-toggle>
    <div class="flex items-center justify-end gap-1">
      <% if task.pending? || task.running? %>
        <%= button_to cancel_task_path(task.to_param),
            method: :post,
            data: { turbo_confirm: "Are you sure you want to cancel this task?", no_toggle: true },
            title: "Cancel",
            class: "p-1.5 text-red-500 hover:text-red-700 hover:bg-red-50 rounded transition-colors" do %>
          <%= lucide_icon("x", class: "h-4 w-4") %>
        <% end %>
      <% end %>
      <%= button_to task_path(task.to_param),
          method: :delete,
          data: { turbo_confirm: "Are you sure you want to delete this task?", no_toggle: true },
          title: "Delete",
          class: "p-1.5 text-slate-400 hover:text-red-600 hover:bg-red-50 rounded transition-colors" do %>
        <%= lucide_icon("trash-2", class: "h-4 w-4") %>
      <% end %>
    </div>
  </td>
</tr>
```

**Step 4: Create task details partial**

```erb
<%# app/views/tasks/_task_details.html.erb %>
<tr id="<%= task.dom_id %>_details" class="hidden bg-slate-50" data-accordion-target="details">
  <td colspan="8" class="px-6 py-4">
    <div class="grid grid-cols-3 gap-6">
      <%# Details Column %>
      <div>
        <h4 class="text-xs font-bold text-slate-500 uppercase mb-2">Details</h4>
        <dl class="space-y-1 text-sm">
          <div class="flex justify-between">
            <dt class="text-slate-500">Started:</dt>
            <dd class="font-medium text-slate-900"><%= task.started_at&.strftime("%b %d, %H:%M") || "Pending" %></dd>
          </div>
          <div class="flex justify-between">
            <dt class="text-slate-500">Finished:</dt>
            <dd class="font-medium text-slate-900"><%= task.finished_at&.strftime("%b %d, %H:%M") || "-" %></dd>
          </div>
          <div class="flex justify-between">
            <dt class="text-slate-500">UUID:</dt>
            <dd class="font-mono text-xs text-slate-700"><%= task.uuid[0..7] %>...</dd>
          </div>
          <div class="flex justify-between">
            <dt class="text-slate-500">Recipe:</dt>
            <dd class="font-medium text-slate-900"><%= task.recipe_name %></dd>
          </div>
        </dl>
      </div>

      <%# Metrics Column %>
      <div>
        <h4 class="text-xs font-bold text-slate-500 uppercase mb-2">Metrics</h4>
        <% if task.metrics.present? %>
          <dl class="space-y-1 text-sm">
            <% task.metrics.each do |key, value| %>
              <div class="flex justify-between">
                <dt class="text-slate-500"><%= key.humanize %>:</dt>
                <dd class="font-mono text-slate-900">
                  <%= value.is_a?(Numeric) ? number_with_precision(value, precision: 2, strip_insignificant_zeros: true) : value %>
                </dd>
              </div>
            <% end %>
          </dl>
        <% else %>
          <p class="text-sm text-slate-400 italic">No metrics available</p>
        <% end %>
      </div>

      <%# Actions Column %>
      <div>
        <h4 class="text-xs font-bold text-slate-500 uppercase mb-2">Actions</h4>
        <div class="space-y-2">
          <%= button_to rerun_task_path(task.to_param),
              method: :post,
              data: { turbo_confirm: "Re-run this task with the same configuration?" },
              class: "w-full btn-secondary text-sm justify-center" do %>
            <%= lucide_icon("refresh-cw", class: "h-4 w-4 mr-1") %>
            Re-run
          <% end %>

          <%= link_to node_path(task.node),
              class: "w-full btn-secondary text-sm justify-center" do %>
            <%= lucide_icon("arrow-right", class: "h-4 w-4 mr-1") %>
            View Node
          <% end %>

          <% if task.pending? || task.running? %>
            <%= button_to cancel_task_path(task.to_param),
                method: :post,
                data: { turbo_confirm: "Cancel this task?" },
                class: "w-full btn-danger text-sm justify-center" do %>
              <%= lucide_icon("x", class: "h-4 w-4 mr-1") %>
              Cancel
            <% end %>
          <% end %>

          <%= button_to task_path(task.to_param),
              method: :delete,
              data: { turbo_confirm: "Delete this task permanently?" },
              class: "w-full btn-danger text-sm justify-center" do %>
            <%= lucide_icon("trash-2", class: "h-4 w-4 mr-1") %>
            Delete
          <% end %>
        </div>
      </div>
    </div>

    <%# Artifacts Section %>
    <% if task.artifacts.any? %>
      <div class="mt-4 pt-4 border-t border-slate-200">
        <h4 class="text-xs font-bold text-slate-500 uppercase mb-2">Artifacts</h4>
        <div class="flex flex-wrap gap-2">
          <% task.artifacts.each do |artifact| %>
            <% artifact_name = artifact.respond_to?(:filename) ? artifact.filename : File.basename(artifact.path) %>
            <% download_path = task.benchmark? ?
                download_artifact_benchmark_run_path(task.source, artifact_id: artifact.id) :
                download_artifact_node_profiling_run_path(task.node, task.source, artifact_id: artifact.id) %>

            <% if artifact.downloadable? %>
              <%= link_to download_path,
                  class: "inline-flex items-center gap-1 px-2 py-1 text-xs font-medium text-teal-700 bg-teal-50 rounded hover:bg-teal-100" do %>
                <%= lucide_icon("download", class: "h-3 w-3") %>
                <%= artifact_name %>
              <% end %>
            <% else %>
              <span class="inline-flex items-center gap-1 px-2 py-1 text-xs font-medium text-slate-400 bg-slate-100 rounded cursor-not-allowed" title="File unavailable">
                <%= lucide_icon("download", class: "h-3 w-3") %>
                <%= artifact_name %>
              </span>
            <% end %>
          <% end %>
        </div>
      </div>
    <% end %>

    <%# Error Message Section %>
    <% if task.error_message.present? %>
      <div class="mt-4 pt-4 border-t border-red-200">
        <h4 class="text-xs font-bold text-red-500 uppercase mb-2">Error</h4>
        <p class="text-sm text-red-700 bg-red-50 rounded p-2"><%= task.error_message %></p>
      </div>
    <% end %>
  </td>
</tr>
```

**Step 5: Add helper method**

```ruby
# app/helpers/application_helper.rb
# Add this method to the existing file:

def task_status_badge_class(status)
  case status.to_s
  when "pending"
    "bg-slate-100 text-slate-700"
  when "running"
    "bg-blue-100 text-blue-700"
  when "success"
    "bg-green-100 text-green-700"
  when "failed"
    "bg-red-100 text-red-700"
  when "cancelled"
    "bg-slate-100 text-slate-500"
  else
    "bg-slate-100 text-slate-700"
  end
end
```

**Step 6: Run tests**

Run: `bin/rspec spec/requests/tasks_spec.rb -v`
Expected: PASS

**Step 7: Commit**

```bash
git add app/views/tasks/ app/helpers/application_helper.rb
git commit -m "feat(tasks): add Tasks index view with filters, accordion rows, and auto-refresh"
```

---

## Task 7: Add Tasks to Sidebar Navigation

**Files:**
- Modify: `app/views/shared/_sidebar.html.erb`

**Step 1: Add Tasks link after Nodes**

In `app/views/shared/_sidebar.html.erb`, add after the Nodes link (around line 49):

```erb
<%# Add after Nodes link, before closing </div> of Organization section %>
        <%= link_to tasks_path,
            class: "flex items-center gap-3 px-3 py-2 text-sm font-bold rounded transition-colors #{request.path.start_with?('/tasks') ? 'bg-slate-800 text-teal-400' : 'hover:bg-slate-800 hover:text-teal-400'}" do %>
          <%= lucide_icon("list-checks", class: "h-5 w-5 opacity-75") %>
          Tasks
        <% end %>
```

**Step 2: Run tests**

Run: `bin/rspec spec/requests/tasks_spec.rb -v`
Expected: PASS

**Step 3: Commit**

```bash
git add app/views/shared/_sidebar.html.erb
git commit -m "feat(tasks): add Tasks link to sidebar navigation"
```

---

## Task 8: Final Integration Test

**Files:**
- Test: `spec/system/tasks_spec.rb`

**Step 1: Write system test**

```ruby
# spec/system/tasks_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Tasks", type: :system do
  let(:user) { create(:user) }
  let(:node) { create(:node, hostname: "test-node-01") }
  let(:benchmark_recipe) { create(:benchmark_recipe, :hpcg) }
  let(:profiling_recipe) { create(:profiling_recipe) }

  before { sign_in user }

  describe "index page" do
    let!(:benchmark_run) { create(:benchmark_run, node: node, benchmark_recipe: benchmark_recipe, status: :success) }
    let!(:profiling_run) { create(:profiling_run, node: node, profiling_recipe: profiling_recipe, status: :running) }

    it "displays tasks from both types" do
      visit tasks_path

      expect(page).to have_content("Tasks")
      expect(page).to have_content("test-node-01")
      expect(page).to have_content("Benchmark")
      expect(page).to have_content("Profiling")
    end

    it "can filter by type" do
      visit tasks_path

      select "Benchmark", from: "type"
      click_button "Search"

      expect(page).to have_content("Benchmark")
      expect(page).not_to have_content("Profiling")
    end

    it "can expand row to see details" do
      visit tasks_path

      # Click on the benchmark row
      find("tr", text: benchmark_recipe.name).click

      # Should see expanded details
      expect(page).to have_content("Details")
      expect(page).to have_content("Metrics")
      expect(page).to have_content("Actions")
    end

    it "shows tasks link in sidebar" do
      visit tasks_path

      within("aside") do
        expect(page).to have_link("Tasks")
      end
    end
  end
end
```

**Step 2: Run test**

Run: `bin/rspec spec/system/tasks_spec.rb -v`
Expected: PASS

**Step 3: Run all tests and lint**

Run: `bin/rspec && bin/rubocop -f github`
Expected: All pass

**Step 4: Final commit**

```bash
git add spec/system/tasks_spec.rb
git commit -m "test(tasks): add system tests for Tasks page"
```

---

## Summary

After completing all tasks, you will have:

1. **Task model** - Virtual wrapper for BenchmarkRun/ProfilingRun
2. **Tasks::FilterQuery** - Combined filtering across both tables
3. **TasksController** - Index, cancel, delete, rerun actions
4. **Stimulus controllers** - Accordion expansion and auto-refresh
5. **Views** - Index page with filter bar, accordion rows, details panel
6. **Navigation** - Tasks link in sidebar
7. **Tests** - Unit, request, and system tests

The feature is complete and ready for review.
