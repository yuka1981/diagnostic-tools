# Node Management Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Complete the qis-agent to Salt API migration by removing legacy agent code, adding a `salt_status` enum for node status, adding Salt minion auto-discovery, and updating frontend views.

**Architecture:** The existing Salt API integration (SaltApiClient, SaltCollectService, PresenceCheckService, EventListenerService) remains unchanged. We remove all qis-agent-related code (controllers, jobs, channels, models, views, routes), add a `salt_status` enum column to the Node model for Salt-based status tracking, add a `Salt::MinionDiscoveryService` for auto-discovering unregistered minions, and update frontend views to reflect Salt-based data.

**Tech Stack:** Rails 7.2, Hotwire (Turbo Streams + Stimulus), RSpec, FactoryBot, Tailwind CSS (QPDM design tokens), SaltStack REST API

**Critical ordering notes:**
- Task 7 (update benchmark services) MUST run BEFORE Task 11 (remove `effective_agent_path` from Node)
- Tasks 8-10 (update views) MUST run BEFORE Task 13 (remove routes) to avoid broken intermediate states
- Task 12 (delete legacy files) MUST run BEFORE Task 13 (remove routes) since deleted controllers' routes would error

---

## Task 1: Database Migration — Add `salt_status` to Nodes

**Files:**
- Create: `db/migrate/XXXXXX_add_salt_status_to_nodes.rb`

**Step 1: Generate the migration**

Run:
```bash
bin/rails generate migration AddSaltStatusToNodes salt_status:integer
```
Expected: Creates migration file in `db/migrate/`

**Step 2: Edit the migration**

Edit the generated migration file to set default and add index:

```ruby
class AddSaltStatusToNodes < ActiveRecord::Migration[7.2]
  def change
    add_column :nodes, :salt_status, :integer, default: 0, null: false
    add_index :nodes, :salt_status
  end
end
```

**Step 3: Run the migration**

Run:
```bash
bin/rails db:migrate
```
Expected: Migration succeeds, `db/schema.rb` updated with `salt_status` column

**Step 4: Commit**

```bash
git add db/migrate/*_add_salt_status_to_nodes.rb db/schema.rb
git commit -m "feat: add salt_status column to nodes table"
```

---

## Task 2: Update Node Model — Add `salt_status` Enum and Update `online?`

**Files:**
- Modify: `app/models/node.rb`
- Modify: `spec/models/node_spec.rb`
- Modify: `spec/factories/nodes.rb`

**Important:** Do NOT remove `effective_agent_path` or `DEFAULT_AGENT_PATH` in this task. That happens in Task 11 after benchmark services are updated in Task 7.

**Step 1: Write the failing tests**

Add to `spec/models/node_spec.rb`, inside the top-level `RSpec.describe Node` block, after the existing `describe "enums"` block:

```ruby
describe "salt_status enum" do
  it "defines unknown, connected, disconnected, and pending statuses" do
    expect(Node.salt_statuses).to eq({
      "unknown" => 0, "connected" => 1, "disconnected" => 2, "pending" => 3
    })
  end

  it "defaults to unknown" do
    node = Node.new
    expect(node.salt_status).to eq("unknown")
  end

  it "can be set to connected" do
    node = build(:node, salt_status: :connected)
    expect(node).to be_salt_connected
  end

  it "can be set to disconnected" do
    node = build(:node, salt_status: :disconnected)
    expect(node).to be_salt_disconnected
  end

  it "can be set to pending" do
    node = build(:node, salt_status: :pending)
    expect(node).to be_salt_pending
  end
end

describe "source enum with salt_discovery" do
  it "includes salt_discovery" do
    expect(Node.sources).to include("salt_discovery" => 3)
  end

  it "can be set to salt_discovery" do
    node = build(:node, source: :salt_discovery)
    expect(node).to be_salt_discovery
  end
end
```

Also update the existing `describe "#online?"` block (around lines 167-182) — replace it with:

```ruby
describe "#online?" do
  it "returns true if salt_status is connected" do
    node = build(:node, salt_status: :connected)
    expect(node).to be_online
  end

  it "returns false if salt_status is disconnected" do
    node = build(:node, salt_status: :disconnected)
    expect(node).not_to be_online
  end

  it "returns false if salt_status is unknown" do
    node = build(:node, salt_status: :unknown)
    expect(node).not_to be_online
  end

  it "returns false if salt_status is pending" do
    node = build(:node, salt_status: :pending)
    expect(node).not_to be_online
  end
end
```

Update the existing `describe "source"` test to include `salt_discovery`:

Replace:
```ruby
it "defines manual, csv, and agent_push sources" do
  expect(Node.sources).to eq({ "manual" => 0, "csv" => 1, "agent_push" => 2 })
end
```

With:
```ruby
it "defines manual, csv, agent_push, and salt_discovery sources" do
  expect(Node.sources).to eq({ "manual" => 0, "csv" => 1, "agent_push" => 2, "salt_discovery" => 3 })
end
```

**Step 2: Run tests to verify they fail**

Run:
```bash
bin/rspec spec/models/node_spec.rb
```
Expected: New tests FAIL (salt_status enum not defined yet, online? still uses heartbeat)

**Step 3: Update the Node model**

Modify `app/models/node.rb`:

1. Add the `salt_status` enum after the existing enums (after line 20):

```ruby
enum :salt_status, { unknown: 0, connected: 1, disconnected: 2, pending: 3 }, default: :unknown, prefix: :salt
```

2. Update the `source` enum (line 19) to include `salt_discovery`:

Replace:
```ruby
enum :source, { manual: 0, csv: 1, agent_push: 2 }, default: :manual
```
With:
```ruby
enum :source, { manual: 0, csv: 1, agent_push: 2, salt_discovery: 3 }, default: :manual
```

3. Remove the `HEARTBEAT_ONLINE_THRESHOLD` constant (line 52). Keep `DEFAULT_AGENT_PATH` for now.

4. Update the `.online` scope (line 56):

Replace:
```ruby
scope :online, -> { where(last_heartbeat_at: HEARTBEAT_ONLINE_THRESHOLD.ago..) }
```
With:
```ruby
scope :online, -> { where(salt_status: :connected) }
```

5. Replace the `online?` method (lines 61-65):

Replace:
```ruby
def online?
  return false if last_heartbeat_at.nil?

  last_heartbeat_at > HEARTBEAT_ONLINE_THRESHOLD.ago
end
```
With:
```ruby
def online?
  salt_connected?
end
```

6. Update the `status` method (lines 86-88):

Replace:
```ruby
def status
  online? ? :online : :offline
end
```
With:
```ruby
def status
  salt_status.to_sym
end
```

7. Update the factory in `spec/factories/nodes.rb`:

Add these traits after the existing `:agent_push` trait (after line 28):

```ruby
trait :salt_discovery do
  source { :salt_discovery }
end

trait :salt_connected do
  salt_status { :connected }
end

trait :salt_disconnected do
  salt_status { :disconnected }
end

trait :salt_pending do
  salt_status { :pending }
end
```

Update the existing `:online` trait (lines 30-32) to use salt_status:

Replace:
```ruby
trait :online do
  last_seen_at { 1.minute.ago }
end
```
With:
```ruby
trait :online do
  salt_status { :connected }
  last_seen_at { 1.minute.ago }
end
```

Update the existing `:offline` trait (lines 34-36):

Replace:
```ruby
trait :offline do
  last_seen_at { 10.minutes.ago }
end
```
With:
```ruby
trait :offline do
  salt_status { :disconnected }
  last_seen_at { 10.minutes.ago }
end
```

**Step 4: Run tests to verify they pass**

Run:
```bash
bin/rspec spec/models/node_spec.rb
```
Expected: All tests PASS

**Step 5: Commit**

```bash
git add app/models/node.rb spec/models/node_spec.rb spec/factories/nodes.rb
git commit -m "feat: add salt_status enum to Node model, replace heartbeat-based online?"
```

---

## Task 3: Update `node_status_badge` Helper for Salt Status Values

**Files:**
- Modify: `app/helpers/application_helper.rb:26-43`
- Modify: `app/helpers/dashboard_helper.rb:32-44`

**Note:** `unknown` status maps to `:muted` (gray) consistently across both helpers.

**Step 1: Update the `node_status_badge` helper**

In `app/helpers/application_helper.rb`, update the `node_status_badge` method (lines 26-43):

Replace:
```ruby
def node_status_badge(status)
  base_classes = "px-2 py-0.5 rounded text-xs font-bold shadow-sm"

  color_class = case status.to_s
  when "online", "success", "passed"
    "bg-success-2 text-success-7 border border-success-2"
  when "offline", "failed", "error"
    "bg-error-1 text-error-7 border border-error-2"
  when "running"
    "bg-primary-1 text-primary-7 border border-primary-2 animate-pulse"
  when "unknown", "warning"
    "bg-warning-1 text-warning-7 border border-warning-2"
  else
    "bg-neutral-4 text-neutral-85 border border-neutral-8"
  end

  content_tag(:span, status.to_s.humanize, class: "#{base_classes} #{color_class}")
end
```

With:
```ruby
def node_status_badge(status)
  base_classes = "px-2 py-0.5 rounded text-xs font-bold shadow-sm"

  color_class = case status.to_s
  when "connected", "online", "success", "passed"
    "bg-success-2 text-success-7 border border-success-2"
  when "disconnected", "offline", "failed", "error"
    "bg-error-1 text-error-7 border border-error-2"
  when "running"
    "bg-primary-1 text-primary-7 border border-primary-2 animate-pulse"
  when "pending"
    "bg-warning-1 text-warning-7 border border-warning-2"
  when "warning"
    "bg-warning-1 text-warning-7 border border-warning-2"
  when "unknown"
    "bg-neutral-4 text-neutral-85 border border-neutral-8"
  else
    "bg-neutral-4 text-neutral-85 border border-neutral-8"
  end

  content_tag(:span, status.to_s.humanize, class: "#{base_classes} #{color_class}")
end
```

**Step 2: Update `STATUS_COLORS` in `DashboardHelper`**

In `app/helpers/dashboard_helper.rb`, update `STATUS_COLORS` (lines 32-45):

Replace:
```ruby
STATUS_COLORS = {
  "success" => :success,
  "completed" => :success,
  "passed" => :success,
  "online" => :success,
  "failed" => :error,
  "offline" => :error,
  "error" => :error,
  "running" => :running,
  "pending" => :warning,
  "warning" => :warning,
  "unknown" => :warning,
  "cancelled" => :muted
}.freeze
```

With:
```ruby
STATUS_COLORS = {
  "success" => :success,
  "completed" => :success,
  "passed" => :success,
  "online" => :success,
  "connected" => :success,
  "failed" => :error,
  "offline" => :error,
  "disconnected" => :error,
  "error" => :error,
  "running" => :running,
  "pending" => :warning,
  "warning" => :warning,
  "unknown" => :muted,
  "cancelled" => :muted
}.freeze
```

**Step 3: Run tests**

Run:
```bash
bin/rspec spec/helpers/
```
Expected: PASS

**Step 4: Commit**

```bash
git add app/helpers/application_helper.rb app/helpers/dashboard_helper.rb
git commit -m "feat: update status badge helpers for salt_status enum values"
```

---

## Task 4: Update PresenceCheckService and EventListenerService to Set `salt_status`

**Files:**
- Modify: `app/services/salt/presence_check_service.rb`
- Modify: `app/services/salt/event_listener_service.rb`
- Modify: `spec/services/salt/presence_check_service_spec.rb`
- Modify: `spec/services/salt/event_listener_service_spec.rb`

**Step 1: Update the presence check spec**

Replace the entire content of `spec/services/salt/presence_check_service_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Salt::PresenceCheckService do
  let(:salt_client) { instance_double(SaltApiClient) }
  let(:service) { described_class.new(salt_client: salt_client) }

  describe "#call" do
    let!(:node_01) { create(:node, hostname: "node-01", salt_status: :connected) }
    let!(:node_02) { create(:node, hostname: "node-02", salt_status: :connected) }
    let!(:node_03) { create(:node, hostname: "node-03", salt_status: :connected) }

    before do
      allow(salt_client).to receive(:run_runner)
        .with("manage.status")
        .and_return({
          "up" => [ "node-01", "node-02" ],
          "down" => [ "node-03" ]
        })
    end

    it "marks up nodes as salt_connected" do
      service.call
      expect(node_01.reload.salt_status).to eq("connected")
    end

    it "updates last_seen_at for up nodes" do
      service.call
      expect(node_01.reload.last_seen_at).to be_within(2.seconds).of(Time.current)
    end

    it "marks down nodes as salt_disconnected" do
      service.call
      expect(node_03.reload.salt_status).to eq("disconnected")
    end

    it "does not flip unknown nodes to disconnected" do
      unknown_node = create(:node, hostname: "node-04", salt_status: :unknown)
      service.call
      expect(unknown_node.reload.salt_status).to eq("unknown")
    end

    it "returns counts of up and down nodes" do
      result = service.call
      expect(result[:up]).to eq(2)
      expect(result[:down]).to eq(1)
    end

    it "handles SaltApiClient errors" do
      allow(salt_client).to receive(:run_runner)
        .and_raise(SaltApiClient::TimeoutError, "timeout")

      result = service.call
      expect(result[:error]).to include("timeout")
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run:
```bash
bin/rspec spec/services/salt/presence_check_service_spec.rb
```
Expected: FAIL (service still uses `last_heartbeat_at`)

**Step 3: Update the PresenceCheckService**

Replace the entire content of `app/services/salt/presence_check_service.rb`:

```ruby
# frozen_string_literal: true

module Salt
  class PresenceCheckService
    def initialize(salt_client: nil)
      @salt_client = salt_client || SaltApiClient.new
    end

    def call
      status = @salt_client.run_runner("manage.status")
      up_minions = status["up"] || []
      down_minions = status["down"] || []

      Node.where(hostname: up_minions).update_all(
        salt_status: Node.salt_statuses[:connected],
        last_seen_at: Time.current
      )

      Node.where(hostname: down_minions)
          .where.not(salt_status: Node.salt_statuses[:unknown])
          .update_all(salt_status: Node.salt_statuses[:disconnected])

      { up: up_minions.size, down: down_minions.size }
    rescue SaltApiClient::TimeoutError, SaltApiClient::ApiError => e
      Rails.logger.error("Salt presence check failed: #{e.message}")
      { error: e.message }
    end
  end
end
```

**Step 4: Update EventListenerService `update_presence`**

In `app/services/salt/event_listener_service.rb`, replace the `update_presence` method (lines 34-37):

Replace:
```ruby
def update_presence(new_minions: [], lost_minions: [])
  Node.where(hostname: lost_minions).update_all(last_heartbeat_at: nil) if lost_minions.any?
  Node.where(hostname: new_minions).update_all(last_heartbeat_at: Time.current) if new_minions.any?
end
```

With:
```ruby
def update_presence(new_minions: [], lost_minions: [])
  if lost_minions.any?
    Node.where(hostname: lost_minions)
        .where.not(salt_status: Node.salt_statuses[:unknown])
        .update_all(salt_status: Node.salt_statuses[:disconnected])
  end
  if new_minions.any?
    Node.where(hostname: new_minions).update_all(
      salt_status: Node.salt_statuses[:connected],
      last_seen_at: Time.current
    )
  end
end
```

**Step 5: Update EventListenerService spec**

In `spec/services/salt/event_listener_service_spec.rb`, update node creation (line 50) from `last_heartbeat_at: 1.minute.ago` to `salt_status: :connected`:

Replace:
```ruby
let!(:node) { create(:node, hostname: "node-01", last_heartbeat_at: 1.minute.ago) }
```
With:
```ruby
let!(:node) { create(:node, hostname: "node-01", salt_status: :connected) }
```

Also update any assertions in this spec that check `last_heartbeat_at` to check `salt_status` instead. For example, replace assertions like:
```ruby
expect(node.reload.last_heartbeat_at).to be_nil
```
With:
```ruby
expect(node.reload.salt_status).to eq("disconnected")
```

And replace:
```ruby
expect(node.reload.last_heartbeat_at).to be_within(2.seconds).of(Time.current)
```
With:
```ruby
expect(node.reload.salt_status).to eq("connected")
```

**Step 6: Run tests to verify they pass**

Run:
```bash
bin/rspec spec/services/salt/presence_check_service_spec.rb spec/services/salt/event_listener_service_spec.rb
```
Expected: All PASS

**Step 7: Commit**

```bash
git add app/services/salt/presence_check_service.rb app/services/salt/event_listener_service.rb spec/services/salt/presence_check_service_spec.rb spec/services/salt/event_listener_service_spec.rb
git commit -m "feat: update PresenceCheckService and EventListenerService to use salt_status"
```

---

## Task 5: Add `get_minions` to SaltApiClient

**Files:**
- Modify: `app/services/salt_api_client.rb`
- Modify: `spec/services/salt_api_client_spec.rb`

**Step 1: Write the failing test**

Add to `spec/services/salt_api_client_spec.rb`, inside the top-level `describe` block:

```ruby
describe "#get_minions" do
  before do
    stub_request(:post, "#{base_url}/login")
      .to_return(
        status: 200,
        body: { return: [{ token: "test-token", expire: (Time.current + 1.hour).to_f }] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  it "returns all minions with grains" do
    minion_data = {
      "node-01" => { "os" => "Rocky", "cpuarch" => "x86_64" },
      "node-02" => { "os" => "Ubuntu", "cpuarch" => "aarch64" }
    }

    stub_request(:get, "#{base_url}/minions")
      .to_return(
        status: 200,
        body: { return: [minion_data] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = client.get_minions
    expect(result).to eq(minion_data)
  end

  it "returns empty hash when no minions" do
    stub_request(:get, "#{base_url}/minions")
      .to_return(
        status: 200,
        body: { return: [{}] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = client.get_minions
    expect(result).to eq({})
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
bin/rspec spec/services/salt_api_client_spec.rb -e "get_minions"
```
Expected: FAIL with "undefined method 'get_minions'"

**Step 3: Add `get_minions` method to SaltApiClient**

In `app/services/salt_api_client.rb`, add this method after the `run_runner` method (before the `events` method):

```ruby
def get_minions
  ensure_authenticated
  response = get("/minions")
  data = parse_response(response)
  data.dig("return", 0) || {}
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
bin/rspec spec/services/salt_api_client_spec.rb -e "get_minions"
```
Expected: PASS

**Step 5: Commit**

```bash
git add app/services/salt_api_client.rb spec/services/salt_api_client_spec.rb
git commit -m "feat: add get_minions method to SaltApiClient"
```

---

## Task 6: Create Salt::MinionDiscoveryService

**Files:**
- Create: `app/services/salt/minion_discovery_service.rb`
- Create: `spec/services/salt/minion_discovery_service_spec.rb`

**Step 1: Write the test first**

Create `spec/services/salt/minion_discovery_service_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Salt::MinionDiscoveryService do
  let(:salt_client) { instance_double(SaltApiClient) }
  let(:service) { described_class.new(salt_client: salt_client) }

  describe "#call" do
    let!(:existing_node) { create(:node, hostname: "node-01") }

    let(:minion_data) do
      {
        "node-01" => {
          "os" => "Rocky", "osrelease" => "8.9", "cpuarch" => "x86_64",
          "ipv4" => ["127.0.0.1", "192.168.1.10"],
          "kernelrelease" => "4.18.0-513.el8.x86_64",
          "cpu_model" => "Intel Xeon Gold 6248R",
          "mem_total" => 32768, "num_cpus" => 48
        },
        "node-02" => {
          "os" => "Rocky", "osrelease" => "8.9", "cpuarch" => "x86_64",
          "ipv4" => ["127.0.0.1", "192.168.1.11"],
          "kernelrelease" => "4.18.0-513.el8.x86_64",
          "cpu_model" => "Intel Xeon Gold 6248R",
          "mem_total" => 65536, "num_cpus" => 96
        },
        "node-03" => {
          "os" => "Ubuntu", "osrelease" => "22.04", "cpuarch" => "aarch64",
          "ipv4" => ["127.0.0.1", "10.0.0.5"],
          "kernelrelease" => "5.15.0-91-generic",
          "cpu_model" => "Ampere Altra Q80-30",
          "mem_total" => 131072, "num_cpus" => 80
        }
      }
    end

    before do
      allow(salt_client).to receive(:get_minions).and_return(minion_data)
    end

    it "returns success" do
      result = service.call
      expect(result).to be_success
    end

    it "identifies existing nodes" do
      result = service.call
      expect(result.existing).to eq(["node-01"])
    end

    it "discovers new nodes" do
      result = service.call
      hostnames = result.discovered.map { |d| d[:hostname] }
      expect(hostnames).to contain_exactly("node-02", "node-03")
    end

    it "extracts grains into discovery records" do
      result = service.call
      node_02 = result.discovered.find { |d| d[:hostname] == "node-02" }

      expect(node_02[:ip]).to eq("192.168.1.11")
      expect(node_02[:arch]).to eq("x86_64")
      expect(node_02[:os]).to eq("Rocky")
      expect(node_02[:os_release]).to eq("8.9")
      expect(node_02[:kernel]).to eq("4.18.0-513.el8.x86_64")
      expect(node_02[:cpu_model]).to eq("Intel Xeon Gold 6248R")
      expect(node_02[:mem_total]).to eq(65536)
      expect(node_02[:num_cpus]).to eq(96)
    end

    it "excludes 127.0.0.1 from IP selection" do
      result = service.call
      node_03 = result.discovered.find { |d| d[:hostname] == "node-03" }
      expect(node_03[:ip]).to eq("10.0.0.5")
    end

    context "when all minions are already registered" do
      let(:minion_data) { { "node-01" => { "os" => "Rocky" } } }

      it "returns empty discovered list" do
        result = service.call
        expect(result.discovered).to be_empty
      end

      it "returns existing count" do
        result = service.call
        expect(result.existing).to eq(["node-01"])
      end
    end

    context "when Salt API fails" do
      before do
        allow(salt_client).to receive(:get_minions)
          .and_raise(SaltApiClient::ApiError, "connection refused")
      end

      it "returns failure" do
        result = service.call
        expect(result).not_to be_success
      end

      it "includes error message" do
        result = service.call
        expect(result.error).to eq("connection refused")
      end

      it "returns empty lists" do
        result = service.call
        expect(result.discovered).to eq([])
        expect(result.existing).to eq([])
      end
    end

    context "when Salt API returns empty" do
      before do
        allow(salt_client).to receive(:get_minions).and_return({})
      end

      it "returns success with empty results" do
        result = service.call
        expect(result).to be_success
        expect(result.discovered).to be_empty
        expect(result.existing).to be_empty
      end
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
bin/rspec spec/services/salt/minion_discovery_service_spec.rb
```
Expected: FAIL with "uninitialized constant Salt::MinionDiscoveryService"

**Step 3: Create the service**

Create `app/services/salt/minion_discovery_service.rb`:

```ruby
# frozen_string_literal: true

module Salt
  class MinionDiscoveryService
    Result = Struct.new(:success, :discovered, :existing, :error, keyword_init: true) do
      def success? = success
    end

    def initialize(salt_client: nil)
      @salt_client = salt_client || SaltApiClient.new
    end

    def call
      minions = @salt_client.get_minions
      existing_hostnames = Node.pluck(:hostname).to_set

      discovered = []
      existing = []

      minions.each do |minion_id, grains|
        if existing_hostnames.include?(minion_id)
          existing << minion_id
        else
          discovered << build_discovery_record(minion_id, grains)
        end
      end

      Result.new(success: true, discovered: discovered, existing: existing)
    rescue SaltApiClient::ApiError, SaltApiClient::AuthenticationError, SaltApiClient::TimeoutError => e
      Result.new(success: false, error: e.message, discovered: [], existing: [])
    end

    private

    def build_discovery_record(minion_id, grains)
      {
        hostname: minion_id,
        ip: grains.dig("ipv4")&.reject { |ip| ip == "127.0.0.1" }&.first,
        arch: grains["cpuarch"],
        os: grains["os"],
        os_release: grains["osrelease"],
        kernel: grains["kernelrelease"],
        cpu_model: grains["cpu_model"],
        mem_total: grains["mem_total"],
        num_cpus: grains["num_cpus"]
      }
    end
  end
end
```

**Step 4: Run tests to verify they pass**

Run:
```bash
bin/rspec spec/services/salt/minion_discovery_service_spec.rb
```
Expected: All PASS

**Step 5: Commit**

```bash
git add app/services/salt/minion_discovery_service.rb spec/services/salt/minion_discovery_service_spec.rb
git commit -m "feat: add Salt::MinionDiscoveryService for minion auto-discovery"
```

---

## Task 7: Update Benchmark Services — Remove `effective_agent_path` Dependency

**Files:**
- Modify: `app/services/benchmark/preflight_service.rb:22,74,264-272`
- Modify: `app/services/benchmark/cancel_run_service.rb:5,13,78-87`
- Modify: `app/services/mlc/trigger_install_service.rb:77-79`
- Modify: `spec/services/benchmark/cancel_run_service_spec.rb:242-271,274-286`

These three services call `node.effective_agent_path`, which will be removed in Task 11. Update them to inline the fallback logic using `SshSetting::DEFAULT_AGENT_PATH`.

**Step 1: Update PreflightService**

In `app/services/benchmark/preflight_service.rb`:

Replace line 22:
```ruby
@agent_path = @target_node.try(:effective_agent_path) || "qis-agent"
```
With:
```ruby
@agent_path = @target_node.try(:agent_path).presence || SshSetting::DEFAULT_AGENT_PATH
```

Replace line 74:
```ruby
agent_path: resolve_agent_path,
```
With:
```ruby
agent_path: @agent_path,
```

Remove the `resolve_agent_path` method (lines 264-272) and replace it with:
```ruby
def resolve_agent_path
  @agent_path
end
```

Note: The `check_agent_binary` method (line 185) calls `resolve_agent_path`, and `build_config_info` (line 74) also uses it. By simplifying resolve_agent_path to just return `@agent_path`, we keep the same interface. The agent path from SshSetting is already an absolute path (`/usr/local/bin/qis-agent`), so no relative path resolution needed.

Also update the `suggest_work_dir_fix` method at line 279 — replace "Settings > Agents" with "SSH Settings":
```ruby
"This directory is set in SSH Settings. Change it there or override it in the node settings."
```

**Step 2: Update CancelRunService**

In `app/services/benchmark/cancel_run_service.rb`:

Remove the local `DEFAULT_AGENT_PATH` constant (line 5):
```ruby
DEFAULT_AGENT_PATH = "qis-agent"
```

Replace line 13:
```ruby
@agent_path = agent_path || benchmark_run.node.try(:effective_agent_path) || DEFAULT_AGENT_PATH
```
With:
```ruby
@agent_path = agent_path || benchmark_run.node.try(:agent_path).presence || SshSetting::DEFAULT_AGENT_PATH
```

Update `resolve_agent_path` (lines 78-87) — since `SshSetting::DEFAULT_AGENT_PATH` is already `/usr/local/bin/qis-agent` (absolute), simplify:
```ruby
def resolve_agent_path
  if @agent_path.start_with?("/")
    @agent_path
  else
    "/usr/local/bin/#{@agent_path}"
  end
end
```

**Step 3: Update TriggerInstallService**

In `app/services/mlc/trigger_install_service.rb`, replace line 78:
```ruby
@installation_node.node.effective_agent_path || "/usr/local/bin/qis-agent"
```
With:
```ruby
@installation_node.node.agent_path.presence || SshSetting::DEFAULT_AGENT_PATH
```

**Step 4: Update CancelRunService spec**

In `spec/services/benchmark/cancel_run_service_spec.rb`:

Update the `resolve_agent_path` tests (lines 255-272). Replace the test at line 258:
```ruby
it "resolves default qis-agent to /usr/local/bin" do
  service = described_class.new(benchmark_run, agent_path: "qis-agent")
  expect(service.send(:resolve_agent_path)).to eq("/usr/local/bin/qis-agent")
end
```
With:
```ruby
it "resolves relative path by prepending /usr/local/bin" do
  service = described_class.new(benchmark_run, agent_path: "qis-agent")
  expect(service.send(:resolve_agent_path)).to eq("/usr/local/bin/qis-agent")
end
```

Update the "integration with node effective_agent_path" context (lines 274+). Replace:
```ruby
allow(node).to receive(:effective_agent_path).and_return("/custom/path/agent")
```
With:
```ruby
allow(node).to receive(:agent_path).and_return("/custom/path/agent")
```

**Step 5: Run affected tests**

Run:
```bash
bin/rspec spec/services/benchmark/preflight_service_spec.rb spec/services/benchmark/cancel_run_service_spec.rb spec/services/mlc/trigger_install_service_spec.rb
```
Expected: All PASS

**Step 6: Commit**

```bash
git add app/services/benchmark/preflight_service.rb app/services/benchmark/cancel_run_service.rb app/services/mlc/trigger_install_service.rb spec/services/benchmark/cancel_run_service_spec.rb
git commit -m "refactor: update benchmark services to use SshSetting::DEFAULT_AGENT_PATH instead of effective_agent_path"
```

---

## Task 8: Update NodeFormWizardComponent — Remove Agent Path Field

**Files:**
- Modify: `app/components/node_form_wizard_component.rb:42-44`
- Modify: `app/components/node_form_wizard_component.html.erb:267-278`
- Modify: `spec/components/node_form_wizard_component_spec.rb:87-91,178-194`

**Step 1: Remove `default_agent_path` method from component**

In `app/components/node_form_wizard_component.rb`, delete lines 42-44:
```ruby
def default_agent_path
  agent_config&.default_agent_path.presence || SshSetting::DEFAULT_AGENT_PATH
end
```

**Step 2: Remove agent_path field from template**

In `app/components/node_form_wizard_component.html.erb`, the section around lines 267-278 has "Agent & Benchmark Configuration" card. Update the card header and remove the agent_path field.

Replace the card header (line 269):
```erb
<h3 class="card-title">Agent & Benchmark Configuration</h3>
```
With:
```erb
<h3 class="card-title">Benchmark Configuration</h3>
```

Remove the agent_path field div (lines 272-278):
```erb
<div>
  <%= f.label :agent_path, "Agent Path", class: "block text-sm font-bold text-neutral-85 mb-1" %>
  <%= f.text_field :agent_path,
      placeholder: default_agent_path,
      class: "block w-full rounded-md border-neutral-15 shadow-sm focus:border-primary-5 focus:ring-primary-5 sm:text-sm font-mono" %>
  <p class="mt-1 text-xs text-neutral-45">Path to the qis-agent binary on this node. Leave blank to use default.</p>
</div>
```

**Step 3: Update component spec**

In `spec/components/node_form_wizard_component_spec.rb`:

Remove the agent_path field test (lines 87-90):
```ruby
it "has agent_path field" do
  step3 = rendered.css("[data-wizard-target='step']")[2]
  expect(step3.css("input[name='node[agent_path]']")).to be_present
end
```

Remove the `describe "#default_agent_path"` block (lines 178-194):
```ruby
describe "#default_agent_path" do
  context "with agent_config" do
    let(:agent_config) { double(default_agent_path: "/custom/path/agent") }

    it "returns path from agent_config" do
      expect(component.send(:default_agent_path)).to eq("/custom/path/agent")
    end
  end

  context "without agent_config" do
    let(:agent_config) { nil }

    it "returns constant default" do
      expect(component.send(:default_agent_path)).to eq(SshSetting::DEFAULT_AGENT_PATH)
    end
  end
end
```

**Step 4: Run tests**

Run:
```bash
bin/rspec spec/components/node_form_wizard_component_spec.rb
```
Expected: PASS

**Step 5: Commit**

```bash
git add app/components/node_form_wizard_component.rb app/components/node_form_wizard_component.html.erb spec/components/node_form_wizard_component_spec.rb
git commit -m "refactor: remove agent_path field from NodeFormWizardComponent"
```

---

## Task 9: Update Benchmark Runs New View — Remove Agent References

**Files:**
- Modify: `app/views/nodes/benchmark_runs/new.html.erb:25-28,99-101`

**Step 1: Remove agent_path config row**

In `app/views/nodes/benchmark_runs/new.html.erb`, remove the "Agent Path" table row (lines 25-28):

```erb
<tr>
  <td class="px-3 py-2 text-neutral-45 font-medium">Agent Path</td>
  <td class="px-3 py-2 font-mono text-neutral-85" colspan="2" data-testid="nodes-benchmark-agentpath"><%= @preflight.config[:agent_path] %></td>
</tr>
```

**Step 2: Replace `settings_agent_path` link**

In lines 99-101, replace the "Global Settings" link that uses `settings_agent_path`:

Replace:
```erb
<%= link_to "Global Settings", settings_agent_path,
    class: "inline-flex items-center rounded-md bg-warning-1 px-2.5 py-1.5 text-xs font-semibold text-warning-8 hover:bg-warning-2",
    data: { turbo_frame: "_top" } %>
```

With:
```erb
<%= link_to "SSH Settings", settings_ssh_defaults_path,
    class: "inline-flex items-center rounded-md bg-warning-1 px-2.5 py-1.5 text-xs font-semibold text-warning-8 hover:bg-warning-2",
    data: { turbo_frame: "_top" } %>
```

**Step 3: Run tests**

Run:
```bash
bin/rspec spec/system/benchmark_run_spec.rb
```
Expected: PASS (or fix any assertions that expect "Agent Path" text)

**Step 4: Commit**

```bash
git add app/views/nodes/benchmark_runs/new.html.erb
git commit -m "refactor: remove agent_path display and settings_agent_path link from benchmark modal"
```

---

## Task 10: Update Node Views — Remove Agent UI, Add Discover Button

**Files:**
- Modify: `app/views/nodes/index.html.erb`
- Modify: `app/views/nodes/_table.html.erb`
- Modify: `app/views/nodes/_node.html.erb`
- Modify: `app/views/nodes/show.html.erb`

**Step 1: Add "Discover Minions" button to index**

In `app/views/nodes/index.html.erb`, add a Discover button after the "Add Node" button (after line 14). Inside the `<% if current_user.approver? %>` block, after the "Add Node" link:

```erb
      <%= link_to discover_nodes_path,
          class: "btn-secondary",
          data: { testid: "nodes-button-discover" } do %>
        <%= lucide_icon("search", class: "h-4 w-4") %>
        Discover Minions
      <% end %>
```

Remove the agent-related turbo frame tags at the bottom (lines 34-36):

Delete:
```erb
<%= turbo_frame_tag "install_modal" %>
<%= turbo_frame_tag "uninstall_modal" %>
<%= turbo_frame_tag "update_modal" %>
```

**Step 2: Remove Agent column from table header**

In `app/views/nodes/_table.html.erb`, remove the Agent column header (lines 59-61):

Delete:
```erb
            <% if current_user.approver? %>
              <th scope="col" class="px-3 py-2 text-center text-xs font-bold uppercase tracking-wider text-neutral-45 border-b">Agent</th>
            <% end %>
```

**Step 3: Update node row partial — remove agent actions**

In `app/views/nodes/_node.html.erb`, remove the entire agent column `<td>` block (lines 38-94 approximately) that contains the install/update/uninstall buttons. Keep the CRUD actions column (collect, edit, delete).

The node partial should display these columns:
- Checkbox (approver only)
- Hostname + IP
- Role badge
- Architecture
- Salt Status (using `node_status_badge(node.status)`)
- Last Seen
- Actions (Collect, Edit, Delete)

**Step 4: Update node show page — remove agent UI**

In `app/views/nodes/show.html.erb`:

Remove agent version display (lines 21-23). Delete:
```erb
      <% if @node.agent_version.present? %>
        <span class="font-mono text-primary-6">Agent <%= @node.agent_version %></span>
      <% end %>
```

Remove agent_push conditional block with uninstall script link (lines 26-37). Delete:
```erb
      <% if @node.agent_push? && current_user.approver? %>
        <span>•</span>
        <%= link_to "/uninstall-qis-agent.sh",
            class: "text-neutral-25 hover:text-error-6 transition-colors",
            title: "Download manual uninstall script",
            download: "uninstall-qis-agent.sh" do %>
          <span class="flex items-center gap-1">
            <%= lucide_icon("download", class: "h-3 w-3") %>
            Uninstall Script
          </span>
        <% end %>
      <% end %>
```

Replace the agent_push conditional buttons block (lines 51-65) — remove the `if @node.agent_push?` guard so Benchmark is always available. Replace:

```erb
      <% if @node.agent_push? %>
        <%= link_to new_node_benchmark_run_path(@node),
            class: "btn-secondary",
            data: { turbo_frame: "modal", testid: "nodes-show-button-benchmark" } do %>
          <%= lucide_icon("zap", class: "h-4 w-4 text-login-5") %>
          Benchmark
        <% end %>

        <%= link_to new_node_update_path(@node),
            class: "btn-secondary",
            data: { turbo_frame: "update_modal", testid: "nodes-show-button-update" } do %>
          <%= lucide_icon("upload", class: "h-4 w-4 text-success-5") %>
          Update Agent
        <% end %>
      <% end %>
```

With (just the benchmark button, no agent_push guard):
```erb
      <%= link_to new_node_benchmark_run_path(@node),
          class: "btn-secondary",
          data: { turbo_frame: "modal", testid: "nodes-show-button-benchmark" } do %>
        <%= lucide_icon("zap", class: "h-4 w-4 text-login-5") %>
        Benchmark
      <% end %>
```

Remove the `update_modal` turbo frame tag (line 171). Delete:
```erb
<%= turbo_frame_tag "update_modal" %>
```

**Step 5: Run tests**

Run:
```bash
bin/rspec spec/system/ spec/requests/nodes_spec.rb
```
Expected: PASS (or may need minor system test updates — addressed in Task 15)

**Step 6: Commit**

```bash
git add app/views/nodes/index.html.erb app/views/nodes/_table.html.erb app/views/nodes/_node.html.erb app/views/nodes/show.html.erb
git commit -m "feat: update node views - remove agent UI, add discover button"
```

---

## Task 11: Remove `effective_agent_path` and `DEFAULT_AGENT_PATH` from Node Model

**Files:**
- Modify: `app/models/node.rb:53-54,76-78`

**Prerequisite:** Task 7 must be complete (benchmark services no longer call `effective_agent_path`).

**Step 1: Remove constants and method**

In `app/models/node.rb`:

Remove `DEFAULT_AGENT_PATH` constant (line 53):
```ruby
DEFAULT_AGENT_PATH = "qis-agent"
```

Remove `effective_agent_path` method (lines 76-78):
```ruby
def effective_agent_path
  agent_path.presence || DEFAULT_AGENT_PATH
end
```

**Step 2: Run tests**

Run:
```bash
bin/rspec spec/models/node_spec.rb
```
Expected: PASS (no specs should reference effective_agent_path anymore)

**Step 3: Commit**

```bash
git add app/models/node.rb
git commit -m "chore: remove effective_agent_path and DEFAULT_AGENT_PATH from Node model"
```

---

## Task 12: Delete Legacy Agent Code — Files

**Files:**
- Delete: `app/controllers/nodes/installs_controller.rb`
- Delete: `app/controllers/nodes/uninstalls_controller.rb`
- Delete: `app/controllers/nodes/updates_controller.rb`
- Delete: `app/controllers/settings/agents_controller.rb`
- Delete: `app/controllers/settings/agent_releases_controller.rb`
- Delete: `app/controllers/settings/agent_binaries_controller.rb`
- Delete: `app/jobs/agent/install_job.rb`
- Delete: `app/jobs/agent/uninstall_job.rb`
- Delete: `app/jobs/agent/update_job.rb`
- Delete: `app/channels/agent_channel.rb`
- Delete: `app/models/agent_release.rb`
- Delete: `app/models/agent_binary.rb`
- Delete: `app/models/agent_event.rb`
- Delete: All files in `app/views/nodes/installs/`
- Delete: All files in `app/views/nodes/uninstalls/`
- Delete: All files in `app/views/nodes/updates/`
- Delete: All files in `app/views/settings/agents/`
- Delete: All files in `app/views/settings/agent_releases/`
- Delete: All files in `app/views/settings/agent_binaries/`
- Delete: Matching spec files

**Step 1: Delete controllers**

Run:
```bash
rm -f app/controllers/nodes/installs_controller.rb app/controllers/nodes/uninstalls_controller.rb app/controllers/nodes/updates_controller.rb app/controllers/settings/agents_controller.rb app/controllers/settings/agent_releases_controller.rb app/controllers/settings/agent_binaries_controller.rb
```

**Step 2: Delete jobs**

Run:
```bash
rm -rf app/jobs/agent/
```

**Step 3: Delete channel**

Run:
```bash
rm -f app/channels/agent_channel.rb
```

**Step 4: Delete models**

Run:
```bash
rm -f app/models/agent_release.rb app/models/agent_binary.rb app/models/agent_event.rb
```

**Step 5: Delete views**

Run:
```bash
rm -rf app/views/nodes/installs/ app/views/nodes/uninstalls/ app/views/nodes/updates/ app/views/settings/agents/ app/views/settings/agent_releases/ app/views/settings/agent_binaries/
```

**Step 6: Delete specs and factories for removed code**

Run:
```bash
rm -f spec/requests/nodes/uninstalls_spec.rb spec/models/agent_release_spec.rb spec/models/agent_event_spec.rb spec/channels/agent_channel_spec.rb spec/system/agent_release_checksum_copy_spec.rb spec/factories/agent_releases.rb spec/factories/agent_binaries.rb spec/factories/agent_events.rb
```

**Step 7: Commit**

```bash
git add -A
git commit -m "chore: delete legacy agent controllers, jobs, channels, models, views, and specs"
```

---

## Task 13: Remove Agent Routes, Update Sidebar, Add Discovery Routes

**Files:**
- Modify: `config/routes.rb:48-64,91,95-96`
- Modify: `app/views/shared/_sidebar.html.erb:138-143`

**Prerequisite:** Task 12 must be complete (controllers deleted). Task 10 must be complete (views no longer reference agent routes).

**Step 1: Remove agent routes from `config/routes.rb`**

Remove the settings/agent routes (lines 50-58):

Delete these lines:
```ruby
    resource :agent, only: [ :show, :update ], controller: :agents
    resources :agent_releases do
      member do
        patch :deprecate
        patch :activate
        patch :recall
      end
      resources :binaries, only: %i[new create destroy], controller: "agent_binaries"
    end
```

Remove the node agent lifecycle routes. Delete line 91:
```ruby
    resource :update, only: %i[new create], controller: "nodes/updates"
```

Delete lines 95-96:
```ruby
      resources :installs, only: %i[new create], controller: "nodes/installs", as: :node_install
      resources :uninstalls, only: %i[new create], controller: "nodes/uninstalls", as: :node_uninstall
```

Add the new discovery routes in the `resources :nodes` collection block, after the existing `delete :bulk_destroy` line:

```ruby
      get :discover
      post :import_minions
```

**Step 2: Remove "Agent Config" from sidebar**

In `app/views/shared/_sidebar.html.erb`, delete lines 138-143 (the Agent Config link):

```erb
          <%= link_to settings_agent_path,
              data: { turbo_prefetch: false },
              class: "flex items-center gap-3 px-5 py-2 text-sm font-bold rounded transition-colors #{request.path.start_with?('/settings/agent') ? 'bg-primary-1 text-primary-6' : 'hover:bg-neutral-4 hover:text-primary-6'}" do %>
            <%= lucide_icon("settings", class: "h-5 w-5 opacity-75") %>
            Agent Config
          <% end %>
```

**Step 3: Verify routes compile**

Run:
```bash
bin/rails routes | head -50
```
Expected: No errors, agent routes are gone, `discover_nodes` and `import_minions_nodes` routes exist

**Step 4: Commit**

```bash
git add config/routes.rb app/views/shared/_sidebar.html.erb
git commit -m "chore: remove agent routes and sidebar link, add discovery routes"
```

---

## Task 14: Clean Up ApplicationCable::Connection and Remove `agent_path` from Params

**Files:**
- Modify: `app/channels/application_cable/connection.rb`
- Modify: `app/controllers/nodes_controller.rb:150-156`

**Step 1: Simplify ApplicationCable::Connection to user-only authentication**

Replace the entire content of `app/channels/application_cable/connection.rb`:

```ruby
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      if (user = env["warden"]&.user)
        user
      else
        reject_unauthorized_connection
      end
    end
  end
end
```

**Step 2: Remove `agent_path` from permitted params**

In `app/controllers/nodes_controller.rb`, update the `node_params` method (lines 149-157).

Remove `:agent_path` from the permitted list:

Replace:
```ruby
  def node_params
    params.require(:node).permit(
      :hostname, :ip, :role, :arch, :ssh_port, :ssh_user, :ssh_key, :ssh_password,
      :sudo_credential, :ssh_connect_method, :agent_path, :benchmark_work_dir,
      :api_key_id, :rack_id, :rack_position, :rack_height, :server_product_id,
      :ssh_user_override, :ssh_port_override, :ssh_key_override, :ssh_password_override,
      :sudo_credential_override, :ssh_connect_method_override
    )
  end
```

With:
```ruby
  def node_params
    params.require(:node).permit(
      :hostname, :ip, :role, :arch, :ssh_port, :ssh_user, :ssh_key, :ssh_password,
      :sudo_credential, :ssh_connect_method, :benchmark_work_dir,
      :api_key_id, :rack_id, :rack_position, :rack_height, :server_product_id,
      :ssh_user_override, :ssh_port_override, :ssh_key_override, :ssh_password_override,
      :sudo_credential_override, :ssh_connect_method_override
    )
  end
```

**Step 3: Run tests**

Run:
```bash
bin/rspec
```
Expected: PASS (agent channel tests were already deleted in Task 12)

**Step 4: Commit**

```bash
git add app/channels/application_cable/connection.rb app/controllers/nodes_controller.rb
git commit -m "chore: simplify ApplicationCable::Connection to user-only auth, remove agent_path from params"
```

---

## Task 15: Add `discover` and `import_minions` Controller Actions

**Files:**
- Modify: `app/controllers/nodes_controller.rb`
- Create: `app/views/nodes/discover.html.erb`
- Create: `spec/requests/nodes/discover_spec.rb`

**Step 1: Write the request spec**

Create `spec/requests/nodes/discover_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Nodes Discovery", type: :request do
  let(:approver) { create(:user, :approver) }
  let(:viewer) { create(:user) }

  describe "GET /nodes/discover" do
    context "when authenticated as approver" do
      before { sign_in approver }

      it "returns success" do
        salt_client = instance_double(SaltApiClient)
        allow(SaltApiClient).to receive(:new).and_return(salt_client)
        allow(salt_client).to receive(:get_minions).and_return({})

        get discover_nodes_path
        expect(response).to have_http_status(:ok)
      end

      it "assigns discovered minions" do
        salt_client = instance_double(SaltApiClient)
        allow(SaltApiClient).to receive(:new).and_return(salt_client)
        allow(salt_client).to receive(:get_minions).and_return({
          "new-node" => { "os" => "Rocky", "cpuarch" => "x86_64", "ipv4" => ["10.0.0.1"] }
        })

        get discover_nodes_path
        expect(response.body).to include("new-node")
      end
    end

    context "when authenticated as viewer" do
      before { sign_in viewer }

      it "redirects with unauthorized message" do
        get discover_nodes_path
        expect(response).to redirect_to(nodes_path)
      end
    end
  end

  describe "POST /nodes/import_minions" do
    before { sign_in approver }

    it "creates nodes from selected hostnames" do
      expect {
        post import_minions_nodes_path, params: { hostnames: ["import-node-01", "import-node-02"] }
      }.to change(Node, :count).by(2)
    end

    it "sets source to salt_discovery" do
      post import_minions_nodes_path, params: { hostnames: ["import-node-01"] }
      node = Node.find_by(hostname: "import-node-01")
      expect(node.source).to eq("salt_discovery")
    end

    it "sets salt_status to connected" do
      post import_minions_nodes_path, params: { hostnames: ["import-node-01"] }
      node = Node.find_by(hostname: "import-node-01")
      expect(node.salt_status).to eq("connected")
    end

    it "enqueues InventoryCollectJob for each imported node" do
      expect {
        post import_minions_nodes_path, params: { hostnames: ["import-node-01"] }
      }.to have_enqueued_job(InventoryCollectJob)
    end

    it "redirects with success notice" do
      post import_minions_nodes_path, params: { hostnames: ["import-node-01"] }
      expect(response).to redirect_to(nodes_path)
      follow_redirect!
      expect(response.body).to include("imported")
    end

    it "handles empty selection" do
      post import_minions_nodes_path, params: { hostnames: [] }
      expect(response).to redirect_to(nodes_path)
    end

    it "handles duplicate hostnames gracefully" do
      create(:node, hostname: "existing-node")
      post import_minions_nodes_path, params: { hostnames: ["existing-node"] }
      expect(response).to redirect_to(nodes_path)
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run:
```bash
bin/rspec spec/requests/nodes/discover_spec.rb
```
Expected: FAIL (actions don't exist yet)

**Step 3: Add controller actions**

In `app/controllers/nodes_controller.rb`, update the `before_action` for `authorize_approver!` to include the new actions:

Replace:
```ruby
before_action :authorize_approver!, only: %i[new create edit update destroy bulk_destroy test_connection collect run_benchmark]
```
With:
```ruby
before_action :authorize_approver!, only: %i[new create edit update destroy bulk_destroy test_connection collect run_benchmark discover import_minions]
```

Add the `discover` and `import_minions` methods after the `bulk_destroy` method:

```ruby
  def discover
    result = Salt::MinionDiscoveryService.new.call

    if result.success?
      @discovered = result.discovered
      @existing_count = result.existing.size
    else
      @error = result.error
      @discovered = []
      @existing_count = 0
    end
  end

  def import_minions
    hostnames = params[:hostnames] || []
    if hostnames.empty?
      redirect_to nodes_path, alert: "No minions selected"
      return
    end

    imported = []
    errors = []

    hostnames.each do |hostname|
      node = Node.new(hostname: hostname, source: :salt_discovery, salt_status: :connected)
      if node.save
        imported << node
        InventoryCollectJob.perform_later(node.id, user_id: current_user.id)
      else
        errors << { hostname: hostname, error: node.errors.full_messages.join(", ") }
      end
    end

    if errors.empty?
      redirect_to nodes_path, notice: "#{imported.size} minion(s) imported successfully"
    else
      redirect_to nodes_path, alert: "#{imported.size} imported, #{errors.size} failed"
    end
  end
```

**Step 4: Create the discover view**

Create `app/views/nodes/discover.html.erb`:

```erb
<% content_for(:page_title) { "Discover Minions" } %>

<div class="max-w-4xl mx-auto">
  <div class="card-netbox">
    <div class="card-header">
      <h3 class="card-title text-xs font-bold text-neutral-45 uppercase">Discover Salt Minions</h3>
    </div>

    <% if @error %>
      <div class="p-6 text-center">
        <div class="inline-flex items-center gap-2 text-error-6 mb-2">
          <%= lucide_icon("alert-circle", class: "h-5 w-5") %>
          <span class="font-bold">Salt API Error</span>
        </div>
        <p class="text-sm text-neutral-45"><%= @error %></p>
        <div class="mt-4">
          <%= link_to "Back to Nodes", nodes_path, class: "btn-secondary" %>
        </div>
      </div>
    <% elsif @discovered.empty? %>
      <div class="p-6 text-center">
        <div class="inline-flex items-center gap-2 text-success-6 mb-2">
          <%= lucide_icon("check-circle", class: "h-5 w-5") %>
          <span class="font-bold">All minions registered</span>
        </div>
        <p class="text-sm text-neutral-45">All <%= @existing_count %> connected minion(s) are already in the system.</p>
        <div class="mt-4">
          <%= link_to "Back to Nodes", nodes_path, class: "btn-secondary" %>
        </div>
      </div>
    <% else %>
      <div class="p-4">
        <p class="text-sm text-neutral-45 mb-4">
          Found <span class="font-bold text-neutral-85"><%= @discovered.size %></span> unregistered minion(s).
          <span class="text-neutral-25"><%= @existing_count %> already registered.</span>
        </p>
      </div>

      <%= form_with url: import_minions_nodes_path, method: :post do |f| %>
        <div class="overflow-x-auto" data-controller="bulk-select" data-bulk-select-item-name-value="minion" data-bulk-select-param-name-value="hostnames">
          <table class="min-w-full divide-y divide-neutral-8 text-sm">
            <thead class="bg-neutral-2">
              <tr>
                <th scope="col" class="w-10 border-b">
                  <div class="flex items-center justify-center h-full py-2">
                    <input type="checkbox"
                           data-bulk-select-target="selectAll"
                           data-action="change->bulk-select#toggleAll"
                           class="rounded border-neutral-15 text-primary-6 focus:ring-primary-5">
                  </div>
                </th>
                <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-neutral-45 border-b">Hostname</th>
                <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-neutral-45 border-b">IP</th>
                <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-neutral-45 border-b">OS</th>
                <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-neutral-45 border-b">Arch</th>
                <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-neutral-45 border-b">CPUs</th>
                <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-neutral-45 border-b">Memory</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-neutral-4 bg-white">
              <% @discovered.each do |minion| %>
                <tr class="hover:bg-primary-1">
                  <td class="whitespace-nowrap">
                    <div class="flex items-center justify-center h-full py-2">
                      <input type="checkbox"
                             name="hostnames[]"
                             value="<%= minion[:hostname] %>"
                             data-bulk-select-target="checkbox"
                             data-action="change->bulk-select#toggle"
                             class="rounded border-neutral-15 text-primary-6 focus:ring-primary-5">
                    </div>
                  </td>
                  <td class="whitespace-nowrap px-3 py-2 font-bold text-neutral-85"><%= minion[:hostname] %></td>
                  <td class="whitespace-nowrap px-3 py-2 font-mono text-neutral-45 text-xs"><%= minion[:ip] || "—" %></td>
                  <td class="whitespace-nowrap px-3 py-2 text-neutral-85"><%= [minion[:os], minion[:os_release]].compact.join(" ") %></td>
                  <td class="whitespace-nowrap px-3 py-2 text-neutral-85"><%= minion[:arch] || "—" %></td>
                  <td class="whitespace-nowrap px-3 py-2 text-neutral-85"><%= minion[:num_cpus] || "—" %></td>
                  <td class="whitespace-nowrap px-3 py-2 text-neutral-85"><%= minion[:mem_total] ? number_to_human_size(minion[:mem_total].to_i * 1.megabyte) : "—" %></td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>

        <div class="flex items-center justify-between p-4 border-t border-neutral-8">
          <%= link_to "Cancel", nodes_path, class: "btn-secondary" %>
          <button type="submit" class="btn-primary">
            <%= lucide_icon("download", class: "h-4 w-4") %>
            Import Selected
          </button>
        </div>
      <% end %>
    <% end %>
  </div>
</div>
```

**Step 5: Run tests to verify they pass**

Run:
```bash
bin/rspec spec/requests/nodes/discover_spec.rb
```
Expected: All PASS

**Step 6: Commit**

```bash
git add app/controllers/nodes_controller.rb app/views/nodes/discover.html.erb spec/requests/nodes/discover_spec.rb
git commit -m "feat: add discover and import_minions actions for Salt minion discovery"
```

---

## Task 16: Update Remaining Spec Files — `last_heartbeat_at` and Agent References

**Files:**
- Modify: `spec/services/dashboard/metrics_service_spec.rb`
- Modify: `spec/helpers/dashboard_helper_spec.rb`
- Modify: `spec/system/dashboard_heatmap_spec.rb`
- Modify: `spec/requests/mlc_installations_spec.rb`
- Modify: `spec/system/settings/ssh_settings_spec.rb`
- Modify: `spec/requests/nodes_spec.rb`
- Modify: `spec/system/node_management_spec.rb`

**Step 1: Update dashboard metrics service spec**

In `spec/services/dashboard/metrics_service_spec.rb`, replace all `last_heartbeat_at: 1.minute.ago` with `salt_status: :connected` and `last_heartbeat_at: nil` or `last_heartbeat_at: 10.minutes.ago` with `salt_status: :disconnected`.

For example, at lines 36-38:
```ruby
# Replace:
create(:node, last_heartbeat_at: 1.minute.ago)
# With:
create(:node, salt_status: :connected)

# Replace:
create(:node, last_heartbeat_at: nil)
# With:
create(:node, salt_status: :unknown)
```

**Step 2: Update dashboard helper spec**

In `spec/helpers/dashboard_helper_spec.rb`, update lines 115-119 to use `salt_status` instead of `last_heartbeat_at`.

**Step 3: Update dashboard heatmap system spec**

In `spec/system/dashboard_heatmap_spec.rb`, replace all `last_heartbeat_at: 1.minute.ago` with `salt_status: :connected` and `last_heartbeat_at: 10.minutes.ago` with `salt_status: :disconnected`.

Lines to change: 25-28, 63-64, 104, 120, 125, 130, 134, 141-142.

**Step 4: Update MLC installations spec**

In `spec/requests/mlc_installations_spec.rb`, replace line 17:
```ruby
# Replace:
create(:node, last_heartbeat_at: 1.minute.ago)
# With:
create(:node, salt_status: :connected)
```

**Step 5: Update SSH settings system spec**

In `spec/system/settings/ssh_settings_spec.rb`, line 37 visits `settings_agent_path` which will no longer exist. Either:
- Delete the entire test block that visits `settings_agent_path` (if it only tests agent config), OR
- If the test also tests SSH settings, update it to use the correct path

Looking at the test, it tests "updating global Agent settings" including reporting settings. Since the Agent Config page is being removed, delete the test block (lines 36-49):
```ruby
it "allows updating global Agent settings" do
  visit settings_agent_path
  # ...
end
```

**Step 6: Update node request spec**

In `spec/requests/nodes_spec.rb`, search for any references to agent-related routes or actions and remove them:
- Remove tests for `new_node_install_path`, `new_node_uninstall_path`, `new_node_update_path`
- Remove tests for `settings_agent_path`
- Update any node creation that uses `last_heartbeat_at` to use `salt_status`

**Step 7: Update node management system spec**

In `spec/system/node_management_spec.rb`, remove assertions about:
- Agent installation buttons
- Agent update buttons
- Agent-related UI elements

Update any node creation that uses `last_heartbeat_at` to use `salt_status`.

**Step 8: Run all specs**

Run:
```bash
bin/rspec
```
Expected: All PASS

**Step 9: Commit**

```bash
git add spec/services/dashboard/metrics_service_spec.rb spec/helpers/dashboard_helper_spec.rb spec/system/dashboard_heatmap_spec.rb spec/requests/mlc_installations_spec.rb spec/system/settings/ssh_settings_spec.rb spec/requests/nodes_spec.rb spec/system/node_management_spec.rb
git commit -m "test: update specs to use salt_status instead of last_heartbeat_at, remove agent references"
```

---

## Task 17: Run Quality Gates

**Files:** None (verification only)

**Step 1: Run RuboCop**

Run:
```bash
bin/rubocop -f github
```
Expected: No new offenses. Fix any that appear.

**Step 2: Run RuboCop auto-fix if needed**

Run:
```bash
bin/rubocop -a
```

**Step 3: Run full test suite**

Run:
```bash
bin/rspec
```
Expected: All green

**Step 4: Run Brakeman security scan**

Run:
```bash
bin/brakeman
```
Expected: No new warnings

**Step 5: Final commit if any lint fixes were needed**

```bash
git add -A
git commit -m "style: fix rubocop offenses from node management redesign"
```

---

## Summary

| Task | Description | Key Files |
|------|-------------|-----------|
| 1 | DB migration: add `salt_status` | `db/migrate/`, `db/schema.rb` |
| 2 | Node model: `salt_status` enum, update `online?` (keep `effective_agent_path`) | `app/models/node.rb`, `spec/models/node_spec.rb`, `spec/factories/nodes.rb` |
| 3 | Update status badge helpers (`unknown` → gray/muted) | `app/helpers/application_helper.rb`, `app/helpers/dashboard_helper.rb` |
| 4 | Update PresenceCheckService + EventListenerService | `app/services/salt/`, `spec/services/salt/` |
| 5 | Add `get_minions` to SaltApiClient | `app/services/salt_api_client.rb`, `spec/services/salt_api_client_spec.rb` |
| 6 | Create MinionDiscoveryService | `app/services/salt/minion_discovery_service.rb`, spec |
| 7 | Update benchmark services (preflight, cancel, trigger) | Services use `SshSetting::DEFAULT_AGENT_PATH` now |
| 8 | Update NodeFormWizardComponent (remove agent_path field) | Component `.rb`, `.html.erb`, spec |
| 9 | Update benchmark_runs/new.html.erb (remove agent refs) | `app/views/nodes/benchmark_runs/new.html.erb` |
| 10 | Update node views — remove agent UI, add discover button | `index`, `_table`, `_node`, `show` views |
| 11 | Remove `effective_agent_path` from Node model | `app/models/node.rb` |
| 12 | Delete legacy agent files (~50 files) | Controllers, jobs, channels, models, views, specs |
| 13 | Remove agent routes, update sidebar, add discovery routes | `config/routes.rb`, `_sidebar.html.erb` |
| 14 | Simplify ApplicationCable + remove agent_path from params | `connection.rb`, `nodes_controller.rb` |
| 15 | Add discover/import controller actions + view + spec | `nodes_controller.rb`, `discover.html.erb`, spec |
| 16 | Update remaining specs (8 files with `last_heartbeat_at`) | `spec/` directory |
| 17 | Quality gates | rubocop, rspec, brakeman |

## Dependency Graph

```
Task 1 → Task 2 → Tasks 3,4 (parallel) → Tasks 5,6 (parallel) → Task 7 → Tasks 8,9 (parallel)
→ Task 10 → Task 11 → Task 12 → Task 13 → Task 14 → Task 15 → Task 16 → Task 17
```

Key constraints:
- **Task 7 before Task 11**: Benchmark services must stop using `effective_agent_path` before it's removed
- **Tasks 8-10 before Task 13**: Views must stop referencing agent routes before routes are removed
- **Task 12 before Task 13**: Agent controller files must be deleted before their routes are removed
