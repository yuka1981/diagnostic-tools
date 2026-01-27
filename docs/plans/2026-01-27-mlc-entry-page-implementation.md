# MLC Entry Page Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a standalone page at `/mlc_benchmarks/new` for triggering Intel MLC benchmarks with profile card selection.

**Architecture:** Full page with node dropdown, visual profile cards (quick/standard/full/numa/latency), and collapsible advanced options. Reuses existing `Benchmark::TriggerJob` and `BenchmarkRun` infrastructure.

**Tech Stack:** Rails 7.2, ViewComponent, Stimulus, Tailwind CSS

---

## Task 1: Add MLC Profile Constants

**Files:**
- Create: `app/lib/mlc.rb`
- Test: `spec/lib/mlc_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/lib/mlc_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mlc do
  describe "::PROFILES" do
    it "defines five profiles" do
      expect(Mlc::PROFILES.keys).to contain_exactly(:quick, :standard, :full, :numa, :latency)
    end

    it "each profile has required keys" do
      Mlc::PROFILES.each do |name, profile|
        expect(profile).to have_key(:name), "#{name} missing :name"
        expect(profile).to have_key(:runtime), "#{name} missing :runtime"
        expect(profile).to have_key(:description), "#{name} missing :description"
        expect(profile).to have_key(:tests), "#{name} missing :tests"
      end
    end

    it "quick profile includes idle_latency and peak_bandwidth tests" do
      expect(Mlc::PROFILES[:quick][:tests]).to include("idle_latency", "peak_bandwidth")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/lib/mlc_spec.rb -v`
Expected: FAIL with "uninitialized constant Mlc"

**Step 3: Write minimal implementation**

```ruby
# app/lib/mlc.rb
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
```

**Step 4: Run test to verify it passes**

Run: `bin/rspec spec/lib/mlc_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/lib/mlc.rb spec/lib/mlc_spec.rb
git commit -m "feat(mlc): add MLC profile constants"
```

---

## Task 2: Create Mlc::RunForm

**Files:**
- Create: `app/forms/mlc/run_form.rb`
- Test: `spec/forms/mlc/run_form_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/forms/mlc/run_form_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mlc::RunForm do
  let(:node) { create(:node) }

  describe "validations" do
    it "is valid with required attributes" do
      form = described_class.new(node_id: node.id, profile: "quick")
      expect(form).to be_valid
    end

    it "is invalid without node_id" do
      form = described_class.new(node_id: nil, profile: "quick")
      expect(form).not_to be_valid
      expect(form.errors[:node_id]).to include("can't be blank")
    end

    it "is invalid without profile" do
      form = described_class.new(node_id: node.id, profile: nil)
      expect(form).not_to be_valid
      expect(form.errors[:profile]).to include("can't be blank")
    end

    it "is invalid with unknown profile" do
      form = described_class.new(node_id: node.id, profile: "unknown")
      expect(form).not_to be_valid
      expect(form.errors[:profile]).to include("is not a valid profile")
    end

    it "is invalid with non-existent node" do
      form = described_class.new(node_id: 999_999, profile: "quick")
      expect(form).not_to be_valid
      expect(form.errors[:node_id]).to include("node not found")
    end
  end

  describe "#node" do
    it "returns the associated node" do
      form = described_class.new(node_id: node.id, profile: "quick")
      expect(form.node).to eq(node)
    end
  end

  describe "#argument_overrides_hash" do
    it "returns hash with profile" do
      form = described_class.new(node_id: node.id, profile: "standard")
      expect(form.argument_overrides_hash).to include("profile" => "standard")
    end

    it "includes binary_path when provided" do
      form = described_class.new(node_id: node.id, profile: "quick", binary_path: "/opt/mlc")
      expect(form.argument_overrides_hash).to include("binary_path" => "/opt/mlc")
    end

    it "includes modules when provided" do
      form = described_class.new(node_id: node.id, profile: "quick", modules: "intel-mlc/3.12, gcc")
      expect(form.argument_overrides_hash["modules"]).to eq(["intel-mlc/3.12", "gcc"])
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/forms/mlc/run_form_spec.rb -v`
Expected: FAIL with "uninitialized constant Mlc::RunForm"

**Step 3: Write minimal implementation**

```ruby
# app/forms/mlc/run_form.rb
# frozen_string_literal: true

module Mlc
  class RunForm
    include ActiveModel::Model

    attr_accessor :node_id, :profile, :binary_path, :modules, :log_path

    validates :node_id, presence: true
    validates :profile, presence: true
    validate :validate_profile_exists
    validate :validate_node_exists

    def node
      return @node if defined?(@node)

      @node = Node.find_by(id: node_id) if node_id.present?
    end

    def argument_overrides_hash
      overrides = { "profile" => profile }
      overrides["binary_path"] = binary_path if binary_path.present?
      overrides["modules"] = parse_modules if modules.present?
      overrides
    end

    private

    def validate_profile_exists
      return if profile.blank?
      return if Mlc::PROFILES.key?(profile.to_sym)

      errors.add(:profile, "is not a valid profile")
    end

    def validate_node_exists
      return if node_id.blank?
      return if node.present?

      errors.add(:node_id, "node not found")
    end

    def parse_modules
      modules.split(",").map(&:strip).reject(&:blank?)
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rspec spec/forms/mlc/run_form_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/forms/mlc/run_form.rb spec/forms/mlc/run_form_spec.rb
git commit -m "feat(mlc): add Mlc::RunForm for validation"
```

---

## Task 3: Create ProfileCardComponent

**Files:**
- Create: `app/components/mlc/profile_card_component.rb`
- Create: `app/components/mlc/profile_card_component.html.erb`
- Test: `spec/components/mlc/profile_card_component_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/components/mlc/profile_card_component_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mlc::ProfileCardComponent, type: :component do
  let(:profile) { Mlc::PROFILES[:quick] }

  it "renders profile name" do
    render_inline(described_class.new(key: :quick, profile: profile, selected: false))
    expect(page).to have_text("Quick")
  end

  it "renders runtime badge" do
    render_inline(described_class.new(key: :quick, profile: profile, selected: false))
    expect(page).to have_text("~4 min")
  end

  it "renders description" do
    render_inline(described_class.new(key: :quick, profile: profile, selected: false))
    expect(page).to have_text("Fast health check")
  end

  it "renders test list" do
    render_inline(described_class.new(key: :quick, profile: profile, selected: false))
    expect(page).to have_text("idle_latency")
    expect(page).to have_text("peak_bandwidth")
  end

  it "includes hidden radio input" do
    render_inline(described_class.new(key: :quick, profile: profile, selected: false))
    expect(page).to have_css("input[type='radio'][name='mlc_run_form[profile]'][value='quick']", visible: :hidden)
  end

  it "applies selected styling when selected" do
    render_inline(described_class.new(key: :quick, profile: profile, selected: true))
    expect(page).to have_css(".ring-2.ring-primary-5")
  end

  it "does not apply selected styling when not selected" do
    render_inline(described_class.new(key: :quick, profile: profile, selected: false))
    expect(page).not_to have_css(".ring-2.ring-primary-5")
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/components/mlc/profile_card_component_spec.rb -v`
Expected: FAIL with "uninitialized constant Mlc::ProfileCardComponent"

**Step 3: Write minimal implementation**

```ruby
# app/components/mlc/profile_card_component.rb
# frozen_string_literal: true

module Mlc
  class ProfileCardComponent < ViewComponent::Base
    def initialize(key:, profile:, selected: false)
      @key = key
      @profile = profile
      @selected = selected
    end

    def card_classes
      base = "relative cursor-pointer rounded-lg border p-4 hover:border-primary-5 transition-colors"
      if selected
        "#{base} border-primary-5 ring-2 ring-primary-5 bg-primary-1"
      else
        "#{base} border-neutral-15 bg-white"
      end
    end

    private

    attr_reader :key, :profile, :selected
  end
end
```

```erb
<%# app/components/mlc/profile_card_component.html.erb %>
<label class="<%= card_classes %>"
       data-action="click->mlc-profile#select"
       data-mlc-profile-key-param="<%= key %>">
  <input type="radio"
         name="mlc_run_form[profile]"
         value="<%= key %>"
         class="sr-only"
         <%= "checked" if selected %>>

  <div class="flex items-start justify-between mb-2">
    <span class="text-sm font-bold text-neutral-85"><%= profile[:name] %></span>
    <span class="inline-flex items-center rounded-full bg-neutral-4 px-2 py-0.5 text-[10px] font-medium text-neutral-65">
      <%= profile[:runtime] %>
    </span>
  </div>

  <p class="text-xs text-neutral-45 mb-3"><%= profile[:description] %></p>

  <div class="text-[10px] text-neutral-45">
    <span class="font-medium">Tests:</span>
    <%= profile[:tests].join(", ") %>
  </div>

  <% if selected %>
    <div class="absolute top-2 right-2">
      <%= lucide_icon("circle-check", class: "h-5 w-5 text-primary-5") %>
    </div>
  <% end %>
</label>
```

**Step 4: Run test to verify it passes**

Run: `bin/rspec spec/components/mlc/profile_card_component_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/components/mlc/profile_card_component.rb app/components/mlc/profile_card_component.html.erb spec/components/mlc/profile_card_component_spec.rb
git commit -m "feat(mlc): add ProfileCardComponent"
```

---

## Task 4: Create ProfileSelectorComponent

**Files:**
- Create: `app/components/mlc/profile_selector_component.rb`
- Create: `app/components/mlc/profile_selector_component.html.erb`
- Test: `spec/components/mlc/profile_selector_component_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/components/mlc/profile_selector_component_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mlc::ProfileSelectorComponent, type: :component do
  it "renders all five profile cards" do
    render_inline(described_class.new(selected: "quick"))

    expect(page).to have_text("Quick")
    expect(page).to have_text("Standard")
    expect(page).to have_text("Full")
    expect(page).to have_text("NUMA")
    expect(page).to have_text("Latency")
  end

  it "marks the selected profile" do
    render_inline(described_class.new(selected: "standard"))

    # Standard should be selected (has ring)
    expect(page).to have_css("input[value='standard'][checked]", visible: :hidden)
  end

  it "renders section label" do
    render_inline(described_class.new(selected: "quick"))
    expect(page).to have_text("Select Profile")
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/components/mlc/profile_selector_component_spec.rb -v`
Expected: FAIL with "uninitialized constant Mlc::ProfileSelectorComponent"

**Step 3: Write minimal implementation**

```ruby
# app/components/mlc/profile_selector_component.rb
# frozen_string_literal: true

module Mlc
  class ProfileSelectorComponent < ViewComponent::Base
    def initialize(selected: "quick")
      @selected = selected.to_sym
    end

    def profiles
      Mlc::PROFILES
    end

    def selected?(key)
      key == @selected
    end

    private

    attr_reader :selected
  end
end
```

```erb
<%# app/components/mlc/profile_selector_component.html.erb %>
<div data-controller="mlc-profile">
  <label class="block text-sm font-bold text-neutral-85 mb-3">Select Profile</label>

  <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3" data-mlc-profile-target="container">
    <% profiles.each do |key, profile| %>
      <%= render Mlc::ProfileCardComponent.new(key: key, profile: profile, selected: selected?(key)) %>
    <% end %>
  </div>
</div>
```

**Step 4: Run test to verify it passes**

Run: `bin/rspec spec/components/mlc/profile_selector_component_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/components/mlc/profile_selector_component.rb app/components/mlc/profile_selector_component.html.erb spec/components/mlc/profile_selector_component_spec.rb
git commit -m "feat(mlc): add ProfileSelectorComponent"
```

---

## Task 5: Create AdvancedOptionsComponent

**Files:**
- Create: `app/components/mlc/advanced_options_component.rb`
- Create: `app/components/mlc/advanced_options_component.html.erb`
- Test: `spec/components/mlc/advanced_options_component_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/components/mlc/advanced_options_component_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mlc::AdvancedOptionsComponent, type: :component do
  let(:form) { Mlc::RunForm.new }

  it "renders binary path field" do
    render_inline(described_class.new(form: form))
    expect(page).to have_text("MLC Binary Path")
    expect(page).to have_css("input[name='mlc_run_form[binary_path]']")
  end

  it "renders modules field" do
    render_inline(described_class.new(form: form))
    expect(page).to have_text("Lmod Modules")
    expect(page).to have_css("input[name='mlc_run_form[modules]']")
  end

  it "renders log path field" do
    render_inline(described_class.new(form: form))
    expect(page).to have_text("Custom Log Path")
    expect(page).to have_css("input[name='mlc_run_form[log_path]']")
  end

  it "is collapsed by default" do
    render_inline(described_class.new(form: form))
    expect(page).to have_css("[data-collapsible-target='content'].hidden")
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/components/mlc/advanced_options_component_spec.rb -v`
Expected: FAIL with "uninitialized constant Mlc::AdvancedOptionsComponent"

**Step 3: Write minimal implementation**

```ruby
# app/components/mlc/advanced_options_component.rb
# frozen_string_literal: true

module Mlc
  class AdvancedOptionsComponent < ViewComponent::Base
    def initialize(form:)
      @form = form
    end

    private

    attr_reader :form
  end
end
```

```erb
<%# app/components/mlc/advanced_options_component.html.erb %>
<div class="border border-neutral-15 rounded-lg" data-controller="collapsible">
  <button type="button"
          class="flex items-center justify-between w-full px-4 py-3 text-sm font-bold text-neutral-85 hover:bg-neutral-2"
          data-action="click->collapsible#toggle">
    <span>Advanced Options</span>
    <span data-collapsible-target="icon">
      <%= lucide_icon("chevron-down", class: "h-4 w-4 transition-transform") %>
    </span>
  </button>

  <div class="hidden px-4 pb-4 space-y-4" data-collapsible-target="content">
    <div>
      <label for="mlc_run_form_binary_path" class="block text-sm font-medium text-neutral-85 mb-1">
        MLC Binary Path <span class="text-neutral-45 font-normal">(optional)</span>
      </label>
      <input type="text"
             name="mlc_run_form[binary_path]"
             id="mlc_run_form_binary_path"
             value="<%= form.binary_path %>"
             placeholder="/opt/intel/mlc/mlc"
             class="block w-full rounded-md border-neutral-15 shadow-sm focus:border-primary-5 focus:ring-primary-5 sm:text-sm font-mono">
      <p class="mt-1 text-[10px] text-neutral-45 italic">
        Leave empty to use PATH or module-loaded binary
      </p>
    </div>

    <div>
      <label for="mlc_run_form_modules" class="block text-sm font-medium text-neutral-85 mb-1">
        Lmod Modules <span class="text-neutral-45 font-normal">(optional)</span>
      </label>
      <input type="text"
             name="mlc_run_form[modules]"
             id="mlc_run_form_modules"
             value="<%= form.modules %>"
             placeholder="intel-mlc/3.12, gcc/11.2"
             class="block w-full rounded-md border-neutral-15 shadow-sm focus:border-primary-5 focus:ring-primary-5 sm:text-sm font-mono">
      <p class="mt-1 text-[10px] text-neutral-45 italic">
        Comma-separated module names to load before running
      </p>
    </div>

    <div>
      <label for="mlc_run_form_log_path" class="block text-sm font-medium text-neutral-85 mb-1">
        Custom Log Path <span class="text-neutral-45 font-normal">(optional)</span>
      </label>
      <input type="text"
             name="mlc_run_form[log_path]"
             id="mlc_run_form_log_path"
             value="<%= form.log_path %>"
             placeholder="/shared/logs/mlc"
             class="block w-full rounded-md border-neutral-15 shadow-sm focus:border-primary-5 focus:ring-primary-5 sm:text-sm font-mono">
      <p class="mt-1 text-[10px] text-neutral-45 italic">
        Leave empty to use the default log location
      </p>
    </div>
  </div>
</div>
```

**Step 4: Run test to verify it passes**

Run: `bin/rspec spec/components/mlc/advanced_options_component_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/components/mlc/advanced_options_component.rb app/components/mlc/advanced_options_component.html.erb spec/components/mlc/advanced_options_component_spec.rb
git commit -m "feat(mlc): add AdvancedOptionsComponent"
```

---

## Task 6: Create mlc-profile Stimulus Controller

**Files:**
- Create: `app/javascript/controllers/mlc_profile_controller.js`

**Step 1: Write the controller**

```javascript
// app/javascript/controllers/mlc_profile_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container"]

  select(event) {
    const key = event.params.key

    // Update radio buttons
    const radios = this.containerTarget.querySelectorAll("input[type='radio']")
    radios.forEach(radio => {
      radio.checked = radio.value === key
    })

    // Update card styling
    const cards = this.containerTarget.querySelectorAll("label")
    cards.forEach(card => {
      const cardKey = card.dataset.mlcProfileKeyParam
      const isSelected = cardKey === key

      // Remove all selection classes
      card.classList.remove("border-primary-5", "ring-2", "ring-primary-5", "bg-primary-1")
      card.classList.add("border-neutral-15", "bg-white")

      if (isSelected) {
        card.classList.remove("border-neutral-15", "bg-white")
        card.classList.add("border-primary-5", "ring-2", "ring-primary-5", "bg-primary-1")
      }

      // Toggle checkmark icon
      const checkIcon = card.querySelector("[data-check-icon]")
      if (checkIcon) {
        checkIcon.classList.toggle("hidden", !isSelected)
      }
    })
  }
}
```

**Step 2: Update ProfileCardComponent to include data-check-icon**

Update `app/components/mlc/profile_card_component.html.erb` checkmark div:

```erb
  <div class="absolute top-2 right-2 <%= 'hidden' unless selected %>" data-check-icon>
    <%= lucide_icon("circle-check", class: "h-5 w-5 text-primary-5") %>
  </div>
```

(Move outside the `<% if selected %>` block and add hidden class conditionally)

**Step 3: Commit**

```bash
git add app/javascript/controllers/mlc_profile_controller.js app/components/mlc/profile_card_component.html.erb
git commit -m "feat(mlc): add mlc-profile Stimulus controller for card selection"
```

---

## Task 7: Create MlcBenchmarksController

**Files:**
- Create: `app/controllers/mlc_benchmarks_controller.rb`
- Test: `spec/requests/mlc_benchmarks_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/requests/mlc_benchmarks_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MlcBenchmarks" do
  let(:user) { create(:user, :approver) }
  let(:node) { create(:node) }
  let!(:mlc_recipe) { create(:benchmark_recipe, slug: "mlc", name: "Intel MLC", command: "mlc") }

  before { sign_in user }

  describe "GET /mlc_benchmarks/new" do
    it "returns http success" do
      get new_mlc_benchmark_path
      expect(response).to have_http_status(:success)
    end

    it "renders profile selector" do
      get new_mlc_benchmark_path
      expect(response.body).to include("Select Profile")
      expect(response.body).to include("Quick")
    end

    it "renders node selector" do
      get new_mlc_benchmark_path
      expect(response.body).to include("Target Node")
    end

    context "when user is not approver" do
      let(:user) { create(:user, :viewer) }

      it "redirects with unauthorized message" do
        get new_mlc_benchmark_path
        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe "POST /mlc_benchmarks" do
    let(:valid_params) do
      {
        mlc_run_form: {
          node_id: node.id,
          profile: "quick"
        }
      }
    end

    it "creates benchmark run and redirects" do
      expect {
        post mlc_benchmarks_path, params: valid_params
      }.to change(BenchmarkRun, :count).by(1)

      expect(response).to redirect_to(node_path(node))
    end

    it "enqueues trigger job" do
      expect {
        post mlc_benchmarks_path, params: valid_params
      }.to have_enqueued_job(Benchmark::TriggerJob)
    end

    it "sets profile in arguments" do
      post mlc_benchmarks_path, params: valid_params
      run = BenchmarkRun.last
      expect(run.arguments["profile"]).to eq("quick")
    end

    context "with invalid params" do
      it "re-renders form with errors" do
        post mlc_benchmarks_path, params: { mlc_run_form: { node_id: nil, profile: nil } }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("can&#39;t be blank")
      end
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/requests/mlc_benchmarks_spec.rb -v`
Expected: FAIL with routing error

**Step 3: Add route**

Edit `config/routes.rb`, add after `resources :benchmark_recipes`:

```ruby
  resources :mlc_benchmarks, only: %i[new create]
```

**Step 4: Write controller implementation**

```ruby
# app/controllers/mlc_benchmarks_controller.rb
# frozen_string_literal: true

class MlcBenchmarksController < ApplicationController
  layout "dashboard"
  before_action :authenticate_user!
  before_action :authorize_approver!

  def new
    @form = Mlc::RunForm.new(profile: "quick")
    @nodes = Node.order(:hostname)
  end

  def create
    @form = Mlc::RunForm.new(form_params)

    if @form.valid?
      recipe = BenchmarkRecipe.find_by!(slug: "mlc")
      argument_overrides = @form.argument_overrides_hash

      argument_builder = Benchmark::ArgumentBuilderService.new(
        defaults: recipe.default_profile,
        overrides: argument_overrides
      )

      run = @form.node.benchmark_runs.create!(
        benchmark_recipe: recipe,
        log_path: @form.log_path,
        arguments: argument_builder.merged_arguments,
        status: :pending
      )

      Benchmark::TriggerJob.perform_later(
        @form.node,
        run,
        request.base_url,
        agent_token(@form.node),
        argument_overrides,
        user_id: current_user.id
      )

      redirect_to node_path(@form.node), notice: "MLC benchmark triggered successfully."
    else
      @nodes = Node.order(:hostname)
      render :new, status: :unprocessable_entity
    end
  end

  private

  def authorize_approver!
    return if current_user.approver?

    redirect_to root_path, alert: "You are not authorized to run benchmarks."
  end

  def form_params
    params.require(:mlc_run_form).permit(:node_id, :profile, :binary_path, :modules, :log_path)
  end

  def agent_token(node)
    node.effective_api_token.presence ||
      Rails.application.credentials.dig(:api, :agent_token) ||
      ENV["API_AGENT_TOKEN"]
  end
end
```

**Step 5: Run test to verify it passes**

Run: `bin/rspec spec/requests/mlc_benchmarks_spec.rb -v`
Expected: PASS

**Step 6: Commit**

```bash
git add config/routes.rb app/controllers/mlc_benchmarks_controller.rb spec/requests/mlc_benchmarks_spec.rb
git commit -m "feat(mlc): add MlcBenchmarksController with new/create actions"
```

---

## Task 8: Create View Template

**Files:**
- Create: `app/views/mlc_benchmarks/new.html.erb`

**Step 1: Write the view**

```erb
<%# app/views/mlc_benchmarks/new.html.erb %>
<div class="max-w-4xl mx-auto">
  <div class="mb-6">
    <h1 class="text-2xl font-bold text-neutral-85">MLC Benchmark</h1>
    <p class="text-sm text-neutral-45 mt-1">Run Intel Memory Latency Checker on a cluster node</p>
  </div>

  <%= form_with model: @form, url: mlc_benchmarks_path, method: :post, class: "space-y-6" do |f| %>
    <% if @form.errors.any? %>
      <div class="rounded-md bg-error-1 p-4 border border-error-2">
        <h3 class="text-sm font-bold text-error-8">Please correct the errors below</h3>
        <div class="mt-2 text-xs text-error-7">
          <ul role="list" class="list-disc pl-5 space-y-1">
            <% @form.errors.full_messages.each do |msg| %>
              <li><%= msg %></li>
            <% end %>
          </ul>
        </div>
      </div>
    <% end %>

    <%# Target Node %>
    <div class="card-netbox">
      <div class="card-header">
        <h3 class="card-title">Target Node</h3>
      </div>
      <div class="p-4">
        <%= f.label :node_id, "Select Node", class: "block text-sm font-bold text-neutral-85 mb-1" %>
        <%= f.select :node_id,
            options_from_collection_for_select(@nodes, :id, :hostname, @form.node_id),
            { prompt: "Select a node..." },
            { class: "block w-full rounded-md border-neutral-15 shadow-sm focus:border-primary-5 focus:ring-primary-5 sm:text-sm" } %>
      </div>
    </div>

    <%# Profile Selector %>
    <div class="card-netbox">
      <div class="card-header">
        <h3 class="card-title">Benchmark Profile</h3>
      </div>
      <div class="p-4">
        <%= render Mlc::ProfileSelectorComponent.new(selected: @form.profile || "quick") %>
      </div>
    </div>

    <%# Advanced Options %>
    <div class="card-netbox p-0">
      <%= render Mlc::AdvancedOptionsComponent.new(form: @form) %>
    </div>

    <%# Actions %>
    <div class="flex items-center justify-end gap-3">
      <%= link_to "Cancel", :back, class: "btn-secondary" %>
      <%= f.submit "Run MLC Benchmark", class: "btn-primary" %>
    </div>
  <% end %>
</div>
```

**Step 2: Commit**

```bash
git add app/views/mlc_benchmarks/new.html.erb
git commit -m "feat(mlc): add new.html.erb view template"
```

---

## Task 9: Add Sidebar Entry

**Files:**
- Modify: `app/views/shared/_sidebar.html.erb`

**Step 1: Add MLC Benchmark link to Benchmarks section**

In `app/views/shared/_sidebar.html.erb`, find the Benchmarks section and add after the "Recipes" link:

```erb
        <%= link_to new_mlc_benchmark_path,
            data: { turbo_prefetch: false },
            class: "flex items-center gap-3 px-5 py-2 text-sm font-bold rounded transition-colors #{request.path.start_with?('/mlc_benchmarks') ? 'bg-primary-1 text-primary-6' : 'hover:bg-neutral-4 hover:text-primary-6'}" do %>
          <%= lucide_icon("cpu", class: "h-5 w-5 opacity-75") %>
          MLC Benchmark
        <% end %>
```

**Step 2: Commit**

```bash
git add app/views/shared/_sidebar.html.erb
git commit -m "feat(mlc): add MLC Benchmark to sidebar navigation"
```

---

## Task 10: Run Full Test Suite and Lint

**Step 1: Run RuboCop**

Run: `bin/rubocop -f github`
Expected: No offenses

If there are offenses, fix them with `bin/rubocop -a`

**Step 2: Run full test suite**

Run: `bin/rspec`
Expected: All tests pass

**Step 3: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "fix: address lint and test issues"
```

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | MLC Profile Constants | `app/lib/mlc.rb` |
| 2 | Mlc::RunForm | `app/forms/mlc/run_form.rb` |
| 3 | ProfileCardComponent | `app/components/mlc/` |
| 4 | ProfileSelectorComponent | `app/components/mlc/` |
| 5 | AdvancedOptionsComponent | `app/components/mlc/` |
| 6 | Stimulus Controller | `app/javascript/controllers/` |
| 7 | MlcBenchmarksController | `app/controllers/` |
| 8 | View Template | `app/views/mlc_benchmarks/` |
| 9 | Sidebar Entry | `app/views/shared/_sidebar.html.erb` |
| 10 | Lint & Tests | - |
