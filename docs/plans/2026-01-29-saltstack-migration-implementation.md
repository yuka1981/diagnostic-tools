# SaltStack REST API Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the custom Go agent (`qis-agent`) and SSH-based node management with SaltStack salt-api REST interface, using Salt minions on compute nodes and custom execution modules for inventory and benchmarks.

**Architecture:** Rails communicates with nodes exclusively through a `SaltApiClient` service that talks to salt-api (CherryPy) on the admin node. Inventory uses Salt grains + custom execution modules mapped to the existing `ProcessStateService` schema. Benchmarks use Salt `state.apply` with async job tracking and event bus streaming. Presence detection replaces heartbeat.

**Tech Stack:** Rails 7.2 + Hotwire (backend), Python 3 (Salt custom modules), SaltStack 3006+ (salt-master, salt-api, salt-minion), RSpec (tests)

**Design Document:** `docs/plans/2026-01-29-saltstack-migration-design.md`

---

## Phase 1: Salt API Client (Core Communication Layer)

### Task 1.1: Create SaltApiClient with token authentication

**Files:**
- Create: `app/services/salt_api_client.rb`
- Test: `spec/services/salt_api_client_spec.rb`

**Step 1: Write the failing test**

Create `spec/services/salt_api_client_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe SaltApiClient do
  let(:base_url) { "https://salt-master.example.com:8000" }
  let(:username) { "rails_salt_user" }
  let(:password) { "secret" }
  let(:client) { described_class.new(base_url: base_url, username: username, password: password) }

  describe "#authenticate" do
    it "obtains a token from salt-api" do
      stub_request(:post, "#{base_url}/login")
        .with(body: { username: username, password: password, eauth: "pam" })
        .to_return(
          status: 200,
          body: { return: [{ token: "abc123", expire: (Time.current + 12.hours).to_f }] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      token = client.authenticate
      expect(token).to eq("abc123")
    end

    it "raises AuthenticationError on 401" do
      stub_request(:post, "#{base_url}/login")
        .to_return(status: 401, body: "Unauthorized")

      expect { client.authenticate }.to raise_error(SaltApiClient::AuthenticationError)
    end
  end

  describe "#run" do
    before do
      stub_request(:post, "#{base_url}/login")
        .to_return(
          status: 200,
          body: { return: [{ token: "abc123", expire: (Time.current + 12.hours).to_f }] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "executes a synchronous command on a target minion" do
      stub_request(:post, "#{base_url}/")
        .with(
          body: { client: "local", tgt: "node-01", fun: "test.ping" }.to_json,
          headers: { "X-Auth-Token" => "abc123", "Content-Type" => "application/json" }
        )
        .to_return(
          status: 200,
          body: { return: [{ "node-01" => true }] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = client.run("node-01", "test.ping")
      expect(result).to eq(true)
    end

    it "passes keyword arguments to the Salt function" do
      stub_request(:post, "#{base_url}/")
        .with(
          body: { client: "local", tgt: "node-01", fun: "grains.item", arg: ["os", "cpuarch"] }.to_json,
          headers: { "X-Auth-Token" => "abc123" }
        )
        .to_return(
          status: 200,
          body: { return: [{ "node-01" => { "os" => "CentOS", "cpuarch" => "x86_64" } }] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = client.run("node-01", "grains.item", arg: ["os", "cpuarch"])
      expect(result).to eq({ "os" => "CentOS", "cpuarch" => "x86_64" })
    end

    it "raises TargetUnreachable when minion is not connected" do
      stub_request(:post, "#{base_url}/")
        .to_return(
          status: 200,
          body: { return: [{ "node-01" => false }] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      expect { client.run("node-01", "test.ping") }
        .to raise_error(SaltApiClient::TargetUnreachable)
    end

    it "raises TargetUnreachable when minion is not in the result" do
      stub_request(:post, "#{base_url}/")
        .to_return(
          status: 200,
          body: { return: [{}] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      expect { client.run("node-01", "grains.items") }
        .to raise_error(SaltApiClient::TargetUnreachable)
    end
  end

  describe "token auto-renewal" do
    it "re-authenticates when token is near expiry" do
      # First auth returns token expiring soon
      stub_request(:post, "#{base_url}/login")
        .to_return(
          status: 200,
          body: { return: [{ token: "token1", expire: (Time.current + 30.seconds).to_f }] }.to_json,
          headers: { "Content-Type" => "application/json" }
        ).then
        .to_return(
          status: 200,
          body: { return: [{ token: "token2", expire: (Time.current + 12.hours).to_f }] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      stub_request(:post, "#{base_url}/")
        .to_return(
          status: 200,
          body: { return: [{ "node-01" => true }] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      client.run("node-01", "test.ping")
      # Second call should re-authenticate
      client.run("node-01", "test.ping")

      expect(WebMock).to have_requested(:post, "#{base_url}/login").twice
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/services/salt_api_client_spec.rb`
Expected: FAIL — `uninitialized constant SaltApiClient`

**Step 3: Write minimal implementation**

Create `app/services/salt_api_client.rb`:

```ruby
require "net/http"
require "json"
require "uri"

class SaltApiClient
  class AuthenticationError < StandardError; end
  class TargetUnreachable < StandardError; end
  class TimeoutError < StandardError; end
  class ApiError < StandardError; end

  TOKEN_RENEWAL_BUFFER = 60.seconds

  def initialize(base_url: nil, username: nil, password: nil)
    @base_url = base_url || salt_config[:base_url]
    @username = username || salt_config[:username]
    @password = password || salt_config[:password]
    @token = nil
    @token_expires_at = nil
  end

  def authenticate
    response = post("/login", {
      username: @username,
      password: @password,
      eauth: "pam"
    }, authenticated: false)

    data = parse_response(response)
    result = data.dig("return", 0)
    raise AuthenticationError, "Invalid credentials" unless result&.key?("token")

    @token = result["token"]
    @token_expires_at = Time.at(result["expire"])
    @token
  end

  def run(target, function, **kwargs)
    ensure_authenticated
    body = { client: "local", tgt: target, fun: function }.merge(kwargs)
    response = post("/", body)
    data = parse_response(response)
    result = data.dig("return", 0)

    unless result.is_a?(Hash) && result.key?(target)
      raise TargetUnreachable, "Minion '#{target}' did not return a result"
    end

    minion_result = result[target]

    if minion_result == false && function == "test.ping"
      raise TargetUnreachable, "Minion '#{target}' is not responding"
    end

    minion_result
  end

  def run_async(target, function, **kwargs)
    ensure_authenticated
    body = { client: "local_async", tgt: target, fun: function }.merge(kwargs)
    response = post("/", body)
    data = parse_response(response)
    jid = data.dig("return", 0, "jid")
    raise ApiError, "No job ID returned" unless jid

    jid
  end

  def job_result(jid)
    ensure_authenticated
    response = get("/jobs/#{jid}")
    data = parse_response(response)
    data.dig("return", 0)
  end

  def run_runner(function, **kwargs)
    ensure_authenticated
    body = { client: "runner", fun: function }.merge(kwargs)
    response = post("/", body)
    data = parse_response(response)
    data.dig("return", 0)
  end

  private

  def ensure_authenticated
    if @token.nil? || token_near_expiry?
      authenticate
    end
  end

  def token_near_expiry?
    @token_expires_at.nil? || Time.current >= (@token_expires_at - TOKEN_RENEWAL_BUFFER)
  end

  def post(path, body, authenticated: true)
    uri = URI.parse("#{@base_url}#{path}")
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["X-Auth-Token"] = @token if authenticated && @token
    request.body = body.to_json

    execute_request(uri, request)
  end

  def get(path)
    uri = URI.parse("#{@base_url}#{path}")
    request = Net::HTTP::Get.new(uri)
    request["Content-Type"] = "application/json"
    request["X-Auth-Token"] = @token

    execute_request(uri, request)
  end

  def execute_request(uri, request)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 10
    http.read_timeout = 300

    response = http.request(request)

    case response
    when Net::HTTPUnauthorized
      raise AuthenticationError, "Authentication failed: #{response.body}"
    when Net::HTTPSuccess
      response
    else
      raise ApiError, "HTTP #{response.code}: #{response.body}"
    end
  rescue ::Net::OpenTimeout, ::Net::ReadTimeout => e
    raise TimeoutError, e.message
  end

  def parse_response(response)
    JSON.parse(response.body)
  rescue JSON::ParserError => e
    raise ApiError, "Invalid JSON response: #{e.message}"
  end

  def salt_config
    @salt_config ||= {
      base_url: Rails.application.credentials.dig(:salt_api, :base_url) || ENV["SALT_API_URL"],
      username: Rails.application.credentials.dig(:salt_api, :username) || ENV["SALT_API_USERNAME"],
      password: Rails.application.credentials.dig(:salt_api, :password) || ENV["SALT_API_PASSWORD"]
    }
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rspec spec/services/salt_api_client_spec.rb`
Expected: All PASS

**Step 5: Commit**

```bash
git add app/services/salt_api_client.rb spec/services/salt_api_client_spec.rb
git commit -m "feat(salt): add SaltApiClient with token auth and auto-renewal"
```

---

### Task 1.2: Add async execution and job polling to SaltApiClient

**Files:**
- Modify: `app/services/salt_api_client.rb`
- Modify: `spec/services/salt_api_client_spec.rb`

**Step 1: Write the failing tests**

Append to `spec/services/salt_api_client_spec.rb`:

```ruby
describe "#run_async" do
  before do
    stub_request(:post, "#{base_url}/login")
      .to_return(
        status: 200,
        body: { return: [{ token: "abc123", expire: (Time.current + 12.hours).to_f }] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  it "returns a job ID for async execution" do
    stub_request(:post, "#{base_url}/")
      .with(body: hash_including(client: "local_async"))
      .to_return(
        status: 200,
        body: { return: [{ jid: "20260129120000123456" }] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    jid = client.run_async("node-01", "state.apply", mods: "benchmark.hpcg")
    expect(jid).to eq("20260129120000123456")
  end
end

describe "#job_result" do
  before do
    stub_request(:post, "#{base_url}/login")
      .to_return(
        status: 200,
        body: { return: [{ token: "abc123", expire: (Time.current + 12.hours).to_f }] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  it "retrieves job results by JID" do
    stub_request(:get, "#{base_url}/jobs/20260129120000123456")
      .to_return(
        status: 200,
        body: { return: [{ "node-01" => { "retcode" => 0, "return" => "success" } }] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = client.job_result("20260129120000123456")
    expect(result).to eq({ "node-01" => { "retcode" => 0, "return" => "success" } })
  end
end

describe "#run_runner" do
  before do
    stub_request(:post, "#{base_url}/login")
      .to_return(
        status: 200,
        body: { return: [{ token: "abc123", expire: (Time.current + 12.hours).to_f }] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  it "executes a runner module" do
    stub_request(:post, "#{base_url}/")
      .with(body: hash_including(client: "runner", fun: "manage.status"))
      .to_return(
        status: 200,
        body: { return: [{ "up" => ["node-01", "node-02"], "down" => ["node-03"] }] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = client.run_runner("manage.status")
    expect(result["up"]).to contain_exactly("node-01", "node-02")
    expect(result["down"]).to contain_exactly("node-03")
  end
end
```

**Step 2: Run test to verify they pass**

Run: `bin/rspec spec/services/salt_api_client_spec.rb`
Expected: All PASS (implementation already exists from Task 1.1)

**Step 3: Commit**

```bash
git add spec/services/salt_api_client_spec.rb
git commit -m "test(salt): add async execution and runner specs for SaltApiClient"
```

---

## Phase 2: Inventory Mapping Layer

### Task 2.1: Create Salt::InventoryMapper

**Files:**
- Create: `app/services/salt/inventory_mapper.rb`
- Test: `spec/services/salt/inventory_mapper_spec.rb`

**Step 1: Write the failing test**

Create `spec/services/salt/inventory_mapper_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Salt::InventoryMapper do
  describe "#call" do
    let(:grains) do
      {
        "host" => "node-01",
        "fqdn" => "node-01.cluster.local",
        "ip4_interfaces" => { "eth0" => ["10.0.1.1"], "lo" => ["127.0.0.1"] },
        "cpuarch" => "x86_64",
        "kernel" => "Linux",
        "kernelrelease" => "5.15.0-generic",
        "os" => "CentOS",
        "osrelease" => "8.5",
        "cpu_model" => "Intel(R) Xeon(R) Gold 6248 CPU @ 2.50GHz",
        "num_cpus" => 40,
        "mem_total" => 256000,
        "disks" => ["sda", "sdb"],
        "SSDs" => ["sda"],
        "gpus" => []
      }
    end

    let(:dmi_data) do
      {
        "bios" => { "vendor" => "AMI", "version" => "1.2", "release_date" => "01/15/2024" },
        "system" => { "manufacturer" => "QCT", "product_name" => "QuantaPlex T42S-2U" },
        "baseboard" => { "manufacturer" => "QCT", "product_name" => "S6Q" }
      }
    end

    let(:numa_data) do
      {
        "node_count" => 2,
        "nodes" => {
          "0" => { "cpus" => [0, 1, 2, 3], "memory_mb" => 128000 },
          "1" => { "cpus" => [4, 5, 6, 7], "memory_mb" => 128000 }
        }
      }
    end

    let(:network_v2_data) do
      {
        "devices" => [
          { "name" => "eth0", "driver" => "i40e", "speed" => "25Gbit/s", "mac" => "aa:bb:cc:dd:ee:ff" }
        ]
      }
    end

    let(:mapper) do
      described_class.new(
        grains: grains,
        dmi: dmi_data,
        numa: numa_data,
        network_v2: network_v2_data
      )
    end

    it "maps grains to host_info" do
      result = mapper.call
      expect(result[:host][:hostname]).to eq("node-01")
      expect(result[:host][:ip]).to eq("10.0.1.1")
      expect(result[:host][:arch]).to eq("x86_64")
    end

    it "maps grains to cpu_info" do
      result = mapper.call
      expect(result[:cpu][:model]).to eq("Intel(R) Xeon(R) Gold 6248 CPU @ 2.50GHz")
      expect(result[:cpu][:cores]).to eq(40)
    end

    it "maps grains to memory_info" do
      result = mapper.call
      expect(result[:memory][:total_kb]).to eq(256000 * 1024)
    end

    it "maps dmi data" do
      result = mapper.call
      expect(result[:dmi]["bios"]["vendor"]).to eq("AMI")
      expect(result[:dmi]["system"]["manufacturer"]).to eq("QCT")
    end

    it "maps network_v2 data" do
      result = mapper.call
      expect(result[:network_v2]["devices"].first["name"]).to eq("eth0")
    end

    it "produces output compatible with ProcessStateService" do
      result = mapper.call
      expect(result).to have_key(:host)
      expect(result).to have_key(:cpu)
      expect(result).to have_key(:memory)
      expect(result).to have_key(:disks)
      expect(result).to have_key(:network)
      expect(result).to have_key(:network_v2)
      expect(result).to have_key(:dmi)
    end

    it "handles missing optional data gracefully" do
      mapper = described_class.new(grains: grains, dmi: nil, numa: nil, network_v2: nil)
      result = mapper.call
      expect(result[:host][:hostname]).to eq("node-01")
      expect(result[:dmi]).to eq({})
      expect(result[:network_v2]).to eq({})
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/services/salt/inventory_mapper_spec.rb`
Expected: FAIL — `uninitialized constant Salt::InventoryMapper`

**Step 3: Write minimal implementation**

Create `app/services/salt/inventory_mapper.rb`:

```ruby
module Salt
  class InventoryMapper
    def initialize(grains:, dmi: nil, numa: nil, network_v2: nil)
      @grains = grains || {}
      @dmi = dmi
      @numa = numa
      @network_v2 = network_v2
    end

    def call
      {
        host: map_host_info,
        cpu: map_cpu_info,
        memory: map_memory_info,
        disks: map_disk_info,
        network: map_network_info,
        network_v2: map_network_v2_info,
        dmi: map_dmi_info
      }
    end

    private

    def map_host_info
      primary_ip = @grains.dig("ip4_interfaces")
        &.reject { |iface, _| iface == "lo" }
        &.values&.flatten&.first

      {
        hostname: @grains["host"],
        ip: primary_ip,
        arch: @grains["cpuarch"],
        kernel: @grains["kernel"],
        kernel_release: @grains["kernelrelease"],
        os: @grains["os"],
        os_release: @grains["osrelease"]
      }
    end

    def map_cpu_info
      {
        model: @grains["cpu_model"],
        cores: @grains["num_cpus"],
        numa_nodes: @numa&.dig("node_count"),
        numa_topology: @numa&.dig("nodes")
      }.compact
    end

    def map_memory_info
      total_mb = @grains["mem_total"]
      {
        total_kb: total_mb ? total_mb * 1024 : nil
      }.compact
    end

    def map_disk_info
      disk_names = @grains["disks"] || []
      ssds = @grains["SSDs"] || []

      disk_names.map do |name|
        {
          name: name,
          type: ssds.include?(name) ? "SSD" : "HDD"
        }
      end
    end

    def map_network_info
      interfaces = @grains.dig("ip4_interfaces") || {}
      interfaces.reject { |iface, _| iface == "lo" }.map do |iface, ips|
        { interface: iface, ip: ips.first }
      end
    end

    def map_network_v2_info
      return {} unless @network_v2

      @network_v2
    end

    def map_dmi_info
      return {} unless @dmi

      @dmi
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rspec spec/services/salt/inventory_mapper_spec.rb`
Expected: All PASS

**Step 5: Commit**

```bash
git add app/services/salt/inventory_mapper.rb spec/services/salt/inventory_mapper_spec.rb
git commit -m "feat(salt): add InventoryMapper for grains-to-ProcessStateService translation"
```

---

### Task 2.2: Create Inventory::SaltCollectService

**Files:**
- Create: `app/services/inventory/salt_collect_service.rb`
- Test: `spec/services/inventory/salt_collect_service_spec.rb`

**Step 1: Write the failing test**

Create `spec/services/inventory/salt_collect_service_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Inventory::SaltCollectService do
  let(:node) { create(:node, hostname: "node-01") }
  let(:salt_client) { instance_double(SaltApiClient) }
  let(:service) { described_class.new(node, salt_client: salt_client) }

  let(:grains_response) do
    {
      "host" => "node-01",
      "fqdn" => "node-01.cluster.local",
      "ip4_interfaces" => { "eth0" => ["10.0.1.1"] },
      "cpuarch" => "x86_64",
      "kernel" => "Linux",
      "kernelrelease" => "5.15.0",
      "os" => "CentOS",
      "osrelease" => "8.5",
      "cpu_model" => "Intel Xeon Gold 6248",
      "num_cpus" => 40,
      "mem_total" => 256000,
      "disks" => ["sda"],
      "SSDs" => ["sda"],
      "gpus" => []
    }
  end

  let(:dmi_response) do
    { "bios" => { "vendor" => "AMI" }, "system" => {}, "baseboard" => {} }
  end

  let(:numa_response) do
    { "node_count" => 2, "nodes" => {} }
  end

  let(:network_v2_response) do
    { "devices" => [] }
  end

  describe "#call" do
    before do
      allow(salt_client).to receive(:run)
        .with("node-01", "grains.items")
        .and_return(grains_response)
      allow(salt_client).to receive(:run)
        .with("node-01", "inventory.collect_dmi")
        .and_return(dmi_response)
      allow(salt_client).to receive(:run)
        .with("node-01", "inventory.collect_numa")
        .and_return(numa_response)
      allow(salt_client).to receive(:run)
        .with("node-01", "inventory.collect_network_v2")
        .and_return(network_v2_response)
    end

    it "collects inventory and creates a node state" do
      result = service.call
      expect(result.success?).to be true
    end

    it "delegates to ProcessStateService with mapped data" do
      mock_result = Inventory::ProcessStateService::Result.new(
        success: true, state_created: true, node_state: nil, error: nil, error_code: nil
      )
      mock_service = instance_double(Inventory::ProcessStateService, call: mock_result)
      expect(Inventory::ProcessStateService).to receive(:new).with(
        hash_including(node_id: node.id, raw_json: hash_including(:host, :cpu, :memory))
      ).and_return(mock_service)

      service.call
    end

    it "handles SaltApiClient::TargetUnreachable" do
      allow(salt_client).to receive(:run)
        .with("node-01", "grains.items")
        .and_raise(SaltApiClient::TargetUnreachable, "Minion not responding")

      result = service.call
      expect(result.success?).to be false
      expect(result.error).to include("not responding")
    end

    it "handles SaltApiClient::TimeoutError" do
      allow(salt_client).to receive(:run)
        .with("node-01", "grains.items")
        .and_raise(SaltApiClient::TimeoutError, "Connection timed out")

      result = service.call
      expect(result.success?).to be false
      expect(result.error).to include("timed out")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/services/inventory/salt_collect_service_spec.rb`
Expected: FAIL — `uninitialized constant Inventory::SaltCollectService`

**Step 3: Write minimal implementation**

Create `app/services/inventory/salt_collect_service.rb`:

```ruby
module Inventory
  class SaltCollectService
    Result = Struct.new(:success, :error, :state_created, :node_state, :error_code, keyword_init: true) do
      def success?
        success
      end
    end

    def initialize(target_node, salt_client: nil)
      @target_node = target_node
      @salt_client = salt_client || SaltApiClient.new
    end

    def call
      grains = @salt_client.run(@target_node.hostname, "grains.items")
      dmi = safe_collect("inventory.collect_dmi")
      numa = safe_collect("inventory.collect_numa")
      network_v2 = safe_collect("inventory.collect_network_v2")

      mapped = Salt::InventoryMapper.new(
        grains: grains,
        dmi: dmi,
        numa: numa,
        network_v2: network_v2
      ).call

      process_result = Inventory::ProcessStateService.new(
        node_id: @target_node.id,
        raw_json: mapped
      ).call

      Result.new(
        success: process_result.success?,
        error: process_result.error,
        state_created: process_result.state_created,
        node_state: process_result.node_state
      )
    rescue SaltApiClient::TargetUnreachable => e
      Result.new(success: false, error: e.message)
    rescue SaltApiClient::TimeoutError => e
      Result.new(success: false, error: e.message)
    rescue SaltApiClient::AuthenticationError => e
      Result.new(success: false, error: "Salt API authentication failed: #{e.message}")
    end

    private

    def safe_collect(function)
      @salt_client.run(@target_node.hostname, function)
    rescue SaltApiClient::ApiError => e
      Rails.logger.warn("Salt custom module #{function} failed: #{e.message}")
      nil
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rspec spec/services/inventory/salt_collect_service_spec.rb`
Expected: All PASS

**Step 5: Commit**

```bash
git add app/services/inventory/salt_collect_service.rb spec/services/inventory/salt_collect_service_spec.rb
git commit -m "feat(salt): add Inventory::SaltCollectService using Salt grains + custom modules"
```

---

## Phase 3: Benchmark Orchestration

### Task 3.1: Create Benchmark::SaltTriggerRunService

**Files:**
- Create: `app/services/benchmark/salt_trigger_run_service.rb`
- Test: `spec/services/benchmark/salt_trigger_run_service_spec.rb`

**Step 1: Write the failing test**

Create `spec/services/benchmark/salt_trigger_run_service_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Benchmark::SaltTriggerRunService do
  let(:node) { create(:node, hostname: "node-01") }
  let(:recipe) { create(:benchmark_recipe, benchmark_type: :mlc) }
  let(:run) { create(:benchmark_run, node: node, benchmark_recipe: recipe) }
  let(:salt_client) { instance_double(SaltApiClient) }
  let(:service) do
    described_class.new(
      node,
      benchmark_run: run,
      salt_client: salt_client
    )
  end

  describe "#call" do
    it "triggers an async Salt state.apply job" do
      expect(salt_client).to receive(:run_async)
        .with(
          "node-01",
          "state.apply",
          mods: "benchmark.mlc",
          pillar: hash_including(run_id: run.uuid)
        )
        .and_return("20260129120000123456")

      result = service.call
      expect(result.success?).to be true
      expect(result.jid).to eq("20260129120000123456")
    end

    it "updates the benchmark run to running status" do
      allow(salt_client).to receive(:run_async).and_return("20260129120000123456")

      service.call
      run.reload
      expect(run.status).to eq("running")
      expect(run.started_at).to be_present
    end

    it "handles TargetUnreachable errors" do
      allow(salt_client).to receive(:run_async)
        .and_raise(SaltApiClient::TargetUnreachable, "Minion not responding")

      result = service.call
      expect(result.success?).to be false
      run.reload
      expect(run.status).to eq("failed")
      expect(run.error_message).to include("not responding")
    end

    it "handles TimeoutError" do
      allow(salt_client).to receive(:run_async)
        .and_raise(SaltApiClient::TimeoutError, "Request timed out")

      result = service.call
      expect(result.success?).to be false
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/services/benchmark/salt_trigger_run_service_spec.rb`
Expected: FAIL — `uninitialized constant Benchmark::SaltTriggerRunService`

**Step 3: Write minimal implementation**

Create `app/services/benchmark/salt_trigger_run_service.rb`:

```ruby
module Benchmark
  class SaltTriggerRunService
    Result = Struct.new(:success, :error, :jid, keyword_init: true) do
      def success?
        success
      end
    end

    def initialize(target_node, benchmark_run:, salt_client: nil, argument_overrides: {})
      @target_node = target_node
      @benchmark_run = benchmark_run
      @salt_client = salt_client || SaltApiClient.new
      @argument_overrides = argument_overrides
    end

    def call
      jid = @salt_client.run_async(
        @target_node.hostname,
        "state.apply",
        mods: state_mod,
        pillar: pillar_data
      )

      @benchmark_run.update!(
        status: :running,
        started_at: Time.current
      )

      Result.new(success: true, jid: jid)
    rescue SaltApiClient::TargetUnreachable, SaltApiClient::TimeoutError, SaltApiClient::ApiError => e
      @benchmark_run.update!(
        status: :failed,
        error_message: e.message,
        finished_at: Time.current
      )
      Result.new(success: false, error: e.message)
    end

    private

    def state_mod
      benchmark_type = @benchmark_run.benchmark_recipe.benchmark_type
      "benchmark.#{benchmark_type}"
    end

    def pillar_data
      {
        run_id: @benchmark_run.uuid,
        work_dir: BenchmarkConfig.work_dir_for(@target_node),
        arguments: merged_arguments
      }
    end

    def merged_arguments
      defaults = @benchmark_run.benchmark_recipe.default_profile || {}
      defaults.deep_merge(@argument_overrides)
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rspec spec/services/benchmark/salt_trigger_run_service_spec.rb`
Expected: All PASS

**Step 5: Commit**

```bash
git add app/services/benchmark/salt_trigger_run_service.rb spec/services/benchmark/salt_trigger_run_service_spec.rb
git commit -m "feat(salt): add Benchmark::SaltTriggerRunService for Salt-based benchmarks"
```

---

### Task 3.2: Create Salt::BenchmarkResultService

**Files:**
- Create: `app/services/salt/benchmark_result_service.rb`
- Test: `spec/services/salt/benchmark_result_service_spec.rb`

**Step 1: Write the failing test**

Create `spec/services/salt/benchmark_result_service_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Salt::BenchmarkResultService do
  let(:node) { create(:node, hostname: "node-01") }
  let(:recipe) { create(:benchmark_recipe, benchmark_type: :hpcg) }
  let(:run) { create(:benchmark_run, :running, node: node, benchmark_recipe: recipe) }
  let(:salt_client) { instance_double(SaltApiClient) }

  let(:job_return_data) do
    {
      "node-01" => {
        "retcode" => 0,
        "return" => {
          "status" => "PASS",
          "metrics" => { "gflops" => 45.67, "time" => 1823.45 },
          "start_time" => "2026-01-29T12:00:00Z",
          "end_time" => "2026-01-29T12:30:00Z",
          "log_content" => "Benchmark completed successfully",
          "artifacts" => ["/tmp/hpcg/HPCG-Benchmark.txt"]
        }
      }
    }
  end

  let(:service) do
    described_class.new(
      benchmark_run: run,
      job_return: job_return_data,
      salt_client: salt_client
    )
  end

  describe "#call" do
    before do
      allow(salt_client).to receive(:run)
        .with("node-01", "cp.push", path: "/tmp/hpcg/HPCG-Benchmark.txt")
        .and_return(true)
    end

    it "updates the benchmark run with results" do
      service.call
      run.reload
      expect(run.status).to eq("success")
      expect(run.metrics["gflops"]).to eq(45.67)
      expect(run.finished_at).to be_present
      expect(run.log_path).to be_present
    end

    it "maps FAIL status correctly" do
      job_return_data["node-01"]["return"]["status"] = "FAIL"
      job_return_data["node-01"]["return"]["error_message"] = "Residual check failed"

      service.call
      run.reload
      expect(run.status).to eq("failed")
      expect(run.error_message).to eq("Residual check failed")
    end

    it "handles missing return data gracefully" do
      bad_data = { "node-01" => { "retcode" => 1, "return" => "Error: state not found" } }
      service = described_class.new(benchmark_run: run, job_return: bad_data, salt_client: salt_client)

      service.call
      run.reload
      expect(run.status).to eq("failed")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/services/salt/benchmark_result_service_spec.rb`
Expected: FAIL — `uninitialized constant Salt::BenchmarkResultService`

**Step 3: Write minimal implementation**

Create `app/services/salt/benchmark_result_service.rb`:

```ruby
module Salt
  class BenchmarkResultService
    def initialize(benchmark_run:, job_return:, salt_client: nil)
      @benchmark_run = benchmark_run
      @job_return = job_return
      @salt_client = salt_client || SaltApiClient.new
    end

    def call
      node_hostname = @benchmark_run.node.hostname
      minion_return = @job_return.dig(node_hostname)

      unless minion_return.is_a?(Hash) && minion_return["return"].is_a?(Hash)
        @benchmark_run.update!(
          status: :failed,
          error_message: "Invalid job return data: #{minion_return.inspect.truncate(500)}",
          finished_at: Time.current
        )
        return
      end

      result = minion_return["return"]
      status = BenchmarkRun.status_from_agent(result["status"]) || :failed
      log_file_path = write_log_content(result["log_content"])

      @benchmark_run.update!(
        status: status,
        metrics: result["metrics"] || {},
        started_at: parse_time(result["start_time"]) || @benchmark_run.started_at,
        finished_at: parse_time(result["end_time"]) || Time.current,
        log_path: log_file_path,
        error_message: result["error_message"]
      )

      fetch_artifacts(result["artifacts"] || [])
    end

    private

    def write_log_content(content)
      return nil unless content.present?
      log_dir = Rails.root.join("storage", "benchmark_logs")
      FileUtils.mkdir_p(log_dir)
      path = log_dir.join("#{@benchmark_run.uuid}.log")
      File.write(path, content)
      path.to_s
    end

    def fetch_artifacts(artifact_paths)
      artifact_paths.each do |path|
        @salt_client.run(@benchmark_run.node.hostname, "cp.push", path: path)
      rescue SaltApiClient::ApiError => e
        Rails.logger.warn("Failed to fetch artifact #{path}: #{e.message}")
      end
    end

    def parse_time(time_string)
      return nil unless time_string.present?
      Time.parse(time_string)
    rescue ArgumentError
      nil
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rspec spec/services/salt/benchmark_result_service_spec.rb`
Expected: All PASS

**Step 5: Commit**

```bash
git add app/services/salt/benchmark_result_service.rb spec/services/salt/benchmark_result_service_spec.rb
git commit -m "feat(salt): add BenchmarkResultService for processing Salt job returns"
```

---

## Phase 4: Event Streaming & Presence Detection

### Task 4.1: Create Salt::EventListenerService

**Files:**
- Create: `app/services/salt/event_listener_service.rb`
- Test: `spec/services/salt/event_listener_service_spec.rb`

**Step 1: Write the failing test**

Create `spec/services/salt/event_listener_service_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Salt::EventListenerService do
  let(:salt_client) { instance_double(SaltApiClient) }
  let(:service) { described_class.new(salt_client: salt_client) }

  describe "#dispatch_event" do
    let(:node) { create(:node, hostname: "node-01") }

    it "routes benchmark job returns to BenchmarkResultService" do
      run = create(:benchmark_run, :running, node: node)
      event_tag = "salt/job/ret/20260129120000123456"
      event_data = {
        "fun" => "state.apply",
        "fun_args" => [{ "mods" => "benchmark.hpcg", "pillar" => { "run_id" => run.uuid } }],
        "return" => {
          "status" => "PASS",
          "metrics" => { "gflops" => 45.67 }
        },
        "id" => "node-01",
        "retcode" => 0
      }

      expect(Salt::BenchmarkResultService).to receive(:new).and_call_original
      service.dispatch_event(event_tag, event_data)
    end

    it "routes presence change events to node status updates" do
      event_tag = "salt/presence/change"
      event_data = {
        "new" => [],
        "lost" => ["node-01"]
      }

      service.dispatch_event(event_tag, event_data)
      # Node presence is handled - no error raised
    end

    it "ignores unrecognized event tags" do
      service.dispatch_event("salt/auth/something", { "id" => "node-01" })
      # No error, no action
    end
  end

  describe "#update_presence" do
    it "marks lost nodes as offline" do
      node = create(:node, hostname: "node-01", last_heartbeat_at: 1.minute.ago)

      service.update_presence(new_minions: [], lost_minions: ["node-01"])
      node.reload
      expect(node.online?).to be false
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/services/salt/event_listener_service_spec.rb`
Expected: FAIL — `uninitialized constant Salt::EventListenerService`

**Step 3: Write minimal implementation**

Create `app/services/salt/event_listener_service.rb`:

```ruby
module Salt
  class EventListenerService
    BENCHMARK_JOB_PATTERN = /\Asalt\/job\/ret\//.freeze
    PRESENCE_CHANGE_TAG = "salt/presence/change"

    def initialize(salt_client: nil)
      @salt_client = salt_client || SaltApiClient.new
    end

    def listen
      @salt_client.events do |tag, data|
        dispatch_event(tag, data)
      rescue StandardError => e
        Rails.logger.error("Salt event dispatch error for tag=#{tag}: #{e.message}")
      end
    end

    def dispatch_event(tag, data)
      case tag
      when BENCHMARK_JOB_PATTERN
        handle_benchmark_return(data) if benchmark_event?(data)
      when PRESENCE_CHANGE_TAG
        handle_presence_change(data)
      end
    end

    def update_presence(new_minions: [], lost_minions: [])
      lost_minions.each do |hostname|
        node = Node.find_by(hostname: hostname)
        node&.update(last_heartbeat_at: nil)
      end

      new_minions.each do |hostname|
        node = Node.find_by(hostname: hostname)
        node&.update(last_heartbeat_at: Time.current)
      end
    end

    private

    def benchmark_event?(data)
      fun = data["fun"]
      fun == "state.apply" && data.dig("fun_args")&.any? { |arg|
        arg.is_a?(Hash) && arg["mods"]&.start_with?("benchmark.")
      }
    end

    def handle_benchmark_return(data)
      run_id = extract_run_id(data)
      return unless run_id

      benchmark_run = BenchmarkRun.find_by(uuid: run_id)
      return unless benchmark_run

      minion_id = data["id"]
      job_return = { minion_id => { "retcode" => data["retcode"], "return" => data["return"] } }

      Salt::BenchmarkResultService.new(
        benchmark_run: benchmark_run,
        job_return: job_return,
        salt_client: @salt_client
      ).call
    end

    def handle_presence_change(data)
      update_presence(
        new_minions: data["new"] || [],
        lost_minions: data["lost"] || []
      )
    end

    def extract_run_id(data)
      data.dig("fun_args")&.each do |arg|
        next unless arg.is_a?(Hash)
        run_id = arg.dig("pillar", "run_id") || arg.dig(:pillar, :run_id)
        return run_id if run_id
      end
      nil
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rspec spec/services/salt/event_listener_service_spec.rb`
Expected: All PASS

**Step 5: Commit**

```bash
git add app/services/salt/event_listener_service.rb spec/services/salt/event_listener_service_spec.rb
git commit -m "feat(salt): add EventListenerService for Salt event bus dispatch"
```

---

### Task 4.2: Add SSE event streaming to SaltApiClient

**Files:**
- Modify: `app/services/salt_api_client.rb`
- Modify: `spec/services/salt_api_client_spec.rb`

**Step 1: Write the failing test**

Append to `spec/services/salt_api_client_spec.rb`:

```ruby
describe "#events" do
  before do
    stub_request(:post, "#{base_url}/login")
      .to_return(
        status: 200,
        body: { return: [{ token: "abc123", expire: (Time.current + 12.hours).to_f }] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  it "parses SSE event stream and yields tag/data pairs" do
    sse_body = "retry: 400\ntag: salt/job/ret/123\ndata: {\"fun\": \"test.ping\", \"id\": \"node-01\"}\n\n"

    stub_request(:get, "#{base_url}/events")
      .to_return(
        status: 200,
        body: sse_body,
        headers: { "Content-Type" => "text/event-stream" }
      )

    events = []
    client.events do |tag, data|
      events << [tag, data]
      break # Stop after first event for test
    end

    expect(events.length).to eq(1)
    expect(events[0][0]).to eq("salt/job/ret/123")
    expect(events[0][1]["fun"]).to eq("test.ping")
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/services/salt_api_client_spec.rb`
Expected: FAIL — `NoMethodError: undefined method 'events'`

**Step 3: Add events method to SaltApiClient**

Add to `app/services/salt_api_client.rb`:

```ruby
def events(&block)
  ensure_authenticated
  # salt-api accepts token via X-Auth-Token header or ?token= query param.
  # Using header approach for consistency with other methods.
  uri = URI.parse("#{@base_url}/events")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == "https"
  http.read_timeout = 0 # Infinite for SSE

  request = Net::HTTP::Get.new(uri)
  request["X-Auth-Token"] = @token

  http.request(request) do |response|
    raise AuthenticationError, "SSE auth failed" unless response.is_a?(Net::HTTPSuccess)

    parse_sse_stream(response, &block)
  end
rescue ::Net::OpenTimeout => e
  raise TimeoutError, e.message
end

private

def parse_sse_stream(response, &block)
  tag = nil
  response.read_body do |chunk|
    chunk.each_line do |line|
      line = line.strip
      if line.start_with?("tag: ")
        tag = line.sub("tag: ", "")
      elsif line.start_with?("data: ") && tag
        data = JSON.parse(line.sub("data: ", ""))
        block.call(tag, data)
        tag = nil
      end
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rspec spec/services/salt_api_client_spec.rb`
Expected: All PASS

**Step 5: Commit**

```bash
git add app/services/salt_api_client.rb spec/services/salt_api_client_spec.rb
git commit -m "feat(salt): add SSE event streaming to SaltApiClient"
```

---

## Phase 5: Presence Detection

### Task 5.1: Create Salt::PresenceCheckService

**Files:**
- Create: `app/services/salt/presence_check_service.rb`
- Test: `spec/services/salt/presence_check_service_spec.rb`

**Step 1: Write the failing test**

Create `spec/services/salt/presence_check_service_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Salt::PresenceCheckService do
  let(:salt_client) { instance_double(SaltApiClient) }
  let(:service) { described_class.new(salt_client: salt_client) }

  describe "#call" do
    let!(:node_01) { create(:node, hostname: "node-01", last_heartbeat_at: 1.minute.ago) }
    let!(:node_02) { create(:node, hostname: "node-02", last_heartbeat_at: 1.minute.ago) }
    let!(:node_03) { create(:node, hostname: "node-03", last_heartbeat_at: 1.minute.ago) }

    before do
      allow(salt_client).to receive(:run_runner)
        .with("manage.status")
        .and_return({
          "up" => ["node-01", "node-02"],
          "down" => ["node-03"]
        })
    end

    it "marks up nodes with current heartbeat" do
      service.call
      node_01.reload
      expect(node_01.online?).to be true
    end

    it "clears heartbeat for down nodes" do
      service.call
      node_03.reload
      expect(node_03.online?).to be false
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

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/services/salt/presence_check_service_spec.rb`
Expected: FAIL — `uninitialized constant Salt::PresenceCheckService`

**Step 3: Write minimal implementation**

Create `app/services/salt/presence_check_service.rb`:

```ruby
module Salt
  class PresenceCheckService
    def initialize(salt_client: nil)
      @salt_client = salt_client || SaltApiClient.new
    end

    def call
      status = @salt_client.run_runner("manage.status")
      up_minions = status["up"] || []
      down_minions = status["down"] || []

      up_minions.each do |hostname|
        Node.where(hostname: hostname).update_all(last_heartbeat_at: Time.current)
      end

      down_minions.each do |hostname|
        Node.where(hostname: hostname).update_all(last_heartbeat_at: nil)
      end

      { up: up_minions.size, down: down_minions.size }
    rescue SaltApiClient::TimeoutError, SaltApiClient::ApiError => e
      Rails.logger.error("Salt presence check failed: #{e.message}")
      { error: e.message }
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rspec spec/services/salt/presence_check_service_spec.rb`
Expected: All PASS

**Step 5: Commit**

```bash
git add app/services/salt/presence_check_service.rb spec/services/salt/presence_check_service_spec.rb
git commit -m "feat(salt): add PresenceCheckService replacing heartbeat polling"
```

---

## Phase 6: Controller Integration

### Task 6.1: Update NodesController to use Salt for inventory collection

**Files:**
- Modify: `app/controllers/nodes_controller.rb` (the `collect` action)
- Modify: `app/jobs/inventory_collect_job.rb`
- Test: `spec/controllers/nodes_controller_spec.rb` (if exists) or integration test

**Step 1: Write the failing test**

Create or update the relevant spec. The key change is that `collect` now uses `SaltCollectService` instead of SSH:

```ruby
# In spec/jobs/inventory_collect_job_spec.rb (new or update existing)
require "rails_helper"

RSpec.describe InventoryCollectJob, type: :job do
  let(:node) { create(:node, hostname: "node-01") }
  let(:salt_client) { instance_double(SaltApiClient) }

  before do
    allow(SaltApiClient).to receive(:new).and_return(salt_client)
    allow(salt_client).to receive(:run).and_return({})
  end

  it "delegates to Inventory::SaltCollectService" do
    service = instance_double(Inventory::SaltCollectService)
    allow(Inventory::SaltCollectService).to receive(:new)
      .with(node, salt_client: salt_client)
      .and_return(service)
    allow(service).to receive(:call).and_return(
      Inventory::SaltCollectService::Result.new(success: true, state_created: true)
    )

    described_class.perform_now(node.id)

    expect(service).to have_received(:call)
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/jobs/inventory_collect_job_spec.rb`
Expected: FAIL — job still uses SSH-based service

**Step 3: Update InventoryCollectJob**

Modify `app/jobs/inventory_collect_job.rb` to use the Salt service:

```ruby
class InventoryCollectJob < ApplicationJob
  queue_as :default

  def perform(target_node_id, user_id: nil)
    node = Node.find(target_node_id)
    notification = create_notification(node, user_id) if user_id

    result = Inventory::SaltCollectService.new(node).call

    if result.success?
      complete_notification(notification, :success, "Inventory collected for #{node.hostname}")
    else
      complete_notification(notification, :failure, "Failed: #{result.error}")
    end
  rescue StandardError => e
    complete_notification(notification, :failure, "Error: #{e.message}")
    raise
  end

  private

  def create_notification(node, user_id)
    return nil unless defined?(Notification)
    Notification.create(
      user_id: user_id,
      category: :inventory,
      title: "Collecting inventory for #{node.hostname}",
      status: :in_progress
    )
  rescue StandardError
    nil
  end

  def complete_notification(notification, status, message)
    return unless notification
    notification.update(status: status, message: message)
  rescue StandardError
    nil
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rspec spec/jobs/inventory_collect_job_spec.rb`
Expected: All PASS

**Step 5: Commit**

```bash
git add app/jobs/inventory_collect_job.rb spec/jobs/inventory_collect_job_spec.rb
git commit -m "refactor(salt): update InventoryCollectJob to use SaltCollectService"
```

---

### Task 6.2: Update BenchmarkRunsController and Benchmark::TriggerJob

**Files:**
- Modify: `app/jobs/benchmark/trigger_job.rb`
- Test: `spec/jobs/benchmark/trigger_job_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/jobs/benchmark/trigger_job_spec.rb
require "rails_helper"

RSpec.describe Benchmark::TriggerJob, type: :job do
  let(:node) { create(:node, hostname: "node-01") }
  let(:recipe) { create(:benchmark_recipe, benchmark_type: :hpcg) }
  let(:run) { create(:benchmark_run, node: node, benchmark_recipe: recipe) }
  let(:salt_client) { instance_double(SaltApiClient) }

  before do
    allow(SaltApiClient).to receive(:new).and_return(salt_client)
  end

  it "delegates to Benchmark::SaltTriggerRunService" do
    service = instance_double(Benchmark::SaltTriggerRunService)
    allow(Benchmark::SaltTriggerRunService).to receive(:new)
      .with(node, benchmark_run: run, salt_client: salt_client, argument_overrides: {})
      .and_return(service)
    allow(service).to receive(:call).and_return(
      Benchmark::SaltTriggerRunService::Result.new(success: true, jid: "123")
    )

    described_class.perform_now(node, run)

    expect(service).to have_received(:call)
  end

  it "handles service failures" do
    service = instance_double(Benchmark::SaltTriggerRunService)
    allow(Benchmark::SaltTriggerRunService).to receive(:new).and_return(service)
    allow(service).to receive(:call).and_return(
      Benchmark::SaltTriggerRunService::Result.new(success: false, error: "Minion offline")
    )

    described_class.perform_now(node, run)

    run.reload
    expect(run.status).to eq("failed")
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/jobs/benchmark/trigger_job_spec.rb`
Expected: FAIL — job still uses SSH-based service

**Step 3: Update Benchmark::TriggerJob**

Modify `app/jobs/benchmark/trigger_job.rb`:

```ruby
module Benchmark
  class TriggerJob < ApplicationJob
    queue_as :default

    def perform(node, run, argument_overrides = {}, user_id: nil)
      notification = create_notification(node, run, user_id) if user_id

      service = Benchmark::SaltTriggerRunService.new(
        node,
        benchmark_run: run,
        argument_overrides: argument_overrides
      )

      result = service.call

      if result.success?
        complete_notification(notification, :success, "Benchmark started on #{node.hostname}")
      else
        run.reload
        complete_notification(notification, :failure, "Failed: #{result.error}")
      end
    rescue StandardError => e
      run.update!(status: :failed, error_message: e.message, finished_at: Time.current) unless run.completed?
      complete_notification(notification, :failure, "Error: #{e.message}")
      raise
    end

    private

    def create_notification(node, run, user_id)
      return nil unless defined?(Notification)
      Notification.create(
        user_id: user_id,
        category: :benchmark,
        title: "Starting benchmark on #{node.hostname}",
        status: :in_progress
      )
    rescue StandardError
      nil
    end

    def complete_notification(notification, status, message)
      return unless notification
      notification.update(status: status, message: message)
    rescue StandardError
      nil
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rspec spec/jobs/benchmark/trigger_job_spec.rb`
Expected: All PASS

**Step 5: Commit**

```bash
git add app/jobs/benchmark/trigger_job.rb spec/jobs/benchmark/trigger_job_spec.rb
git commit -m "refactor(salt): update Benchmark::TriggerJob to use SaltTriggerRunService"
```

---

## Phase 7: Salt Custom Execution Modules (Python)

### Task 7.1: Create consolidated inventory collection module

> **Note:** All inventory functions (`collect_dmi`, `collect_numa`, `collect_network_v2`) live in a single `inventory.py` module because Salt only loads one module per `__virtualname__`. Multiple files sharing `__virtualname__ = 'inventory'` would silently override each other.

**Files:**
- Create: `salt/modules/inventory.py`
- Test: `salt/modules/tests/test_inventory.py`

**Step 1: Write the failing test**

Create `salt/modules/tests/test_inventory.py`:

```python
import json
import subprocess
from unittest import mock

import pytest

# We test the module functions directly
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

import inventory


class TestCollectDmi:
    SAMPLE_DMIDECODE_BIOS = """
BIOS Information
\tVendor: American Megatrends Inc.
\tVersion: 3.3a
\tRelease Date: 01/15/2024
"""

    SAMPLE_DMIDECODE_SYSTEM = """
System Information
\tManufacturer: QCT
\tProduct Name: QuantaPlex T42S-2U
\tSerial Number: ABC123
"""

    SAMPLE_DMIDECODE_BASEBOARD = """
Base Board Information
\tManufacturer: QCT
\tProduct Name: S6Q
"""

    @mock.patch('inventory._run_dmidecode')
    def test_collect_dmi_returns_structured_data(self, mock_run):
        mock_run.side_effect = lambda t: {
            'bios': self.SAMPLE_DMIDECODE_BIOS,
            'system': self.SAMPLE_DMIDECODE_SYSTEM,
            'baseboard': self.SAMPLE_DMIDECODE_BASEBOARD,
        }[t]

        result = inventory.collect_dmi()

        assert result['bios']['vendor'] == 'American Megatrends Inc.'
        assert result['system']['manufacturer'] == 'QCT'
        assert result['system']['product_name'] == 'QuantaPlex T42S-2U'
        assert result['baseboard']['manufacturer'] == 'QCT'

    @mock.patch('inventory._run_dmidecode')
    def test_collect_dmi_handles_missing_dmidecode(self, mock_run):
        mock_run.side_effect = FileNotFoundError("dmidecode not found")

        result = inventory.collect_dmi()
        assert result == {'error': 'dmidecode not found'}


class TestCollectNuma:
    @mock.patch('inventory._read_file')
    @mock.patch('inventory._list_numa_nodes')
    def test_collect_numa_returns_topology(self, mock_list, mock_read):
        mock_list.return_value = ['node0', 'node1']
        mock_read.side_effect = lambda path: {
            '/sys/devices/system/node/node0/cpulist': '0-19',
            '/sys/devices/system/node/node0/meminfo': 'Node 0 MemTotal:       131072000 kB',
            '/sys/devices/system/node/node1/cpulist': '20-39',
            '/sys/devices/system/node/node1/meminfo': 'Node 1 MemTotal:       131072000 kB',
        }.get(path, '')

        result = inventory.collect_numa()

        assert result['node_count'] == 2
        assert result['nodes']['0']['cpulist'] == '0-19'
        assert result['nodes']['1']['cpulist'] == '20-39'
        assert result['nodes']['0']['memory_kb'] == 131072000

    @mock.patch('inventory._list_numa_nodes')
    def test_collect_numa_handles_no_numa(self, mock_list):
        mock_list.return_value = []

        result = inventory.collect_numa()
        assert result['node_count'] == 0
        assert result['nodes'] == {}


class TestCollectNetworkV2:
    SAMPLE_LSHW_OUTPUT = json.dumps([
        {
            "id": "network:0",
            "class": "network",
            "handle": "PCI:0000:3b:00.0",
            "description": "Ethernet interface",
            "product": "Ethernet Controller XXV710",
            "vendor": "Intel Corporation",
            "logicalname": "eth0",
            "serial": "aa:bb:cc:dd:ee:ff",
            "configuration": {
                "driver": "i40e",
                "speed": "25Gbit/s",
                "link": "yes"
            }
        }
    ])

    @mock.patch('inventory._run_lshw')
    def test_collect_network_v2_returns_devices(self, mock_run):
        mock_run.return_value = self.SAMPLE_LSHW_OUTPUT

        result = inventory.collect_network_v2()

        assert len(result['devices']) == 1
        dev = result['devices'][0]
        assert dev['name'] == 'eth0'
        assert dev['driver'] == 'i40e'
        assert dev['speed'] == '25Gbit/s'
        assert dev['mac'] == 'aa:bb:cc:dd:ee:ff'
        assert dev['vendor'] == 'Intel Corporation'

    @mock.patch('inventory._run_lshw')
    def test_collect_network_v2_handles_lshw_failure(self, mock_run):
        mock_run.side_effect = FileNotFoundError("lshw not found")

        result = inventory.collect_network_v2()
        assert result == {'error': 'lshw not found'}
```

**Step 2: Run test to verify it fails**

Run: `cd salt/modules && python -m pytest tests/test_inventory.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'inventory'`

**Step 3: Write minimal implementation**

Create `salt/modules/inventory.py`:

```python
"""
Salt custom execution module for system inventory collection.
Collects DMI, NUMA topology, and advanced network device information.

Usage via salt-api:
    salt 'minion-id' inventory.collect_dmi
    salt 'minion-id' inventory.collect_numa
    salt 'minion-id' inventory.collect_network_v2
"""

import json
import os
import re
import subprocess


__virtualname__ = 'inventory'


def __virtual__():
    return __virtualname__


# --- DMI Collection ---

def collect_dmi():
    """Collect DMI information from the system using dmidecode."""
    try:
        return {
            'bios': _parse_dmi_section(_run_dmidecode('bios')),
            'system': _parse_dmi_section(_run_dmidecode('system')),
            'baseboard': _parse_dmi_section(_run_dmidecode('baseboard')),
        }
    except FileNotFoundError as e:
        return {'error': str(e)}
    except subprocess.CalledProcessError as e:
        return {'error': f'dmidecode failed: {e.returncode}'}


def _run_dmidecode(dmi_type):
    """Run dmidecode for a specific type."""
    type_map = {'bios': '0', 'system': '1', 'baseboard': '2'}
    result = subprocess.run(
        ['dmidecode', '-t', type_map[dmi_type]],
        capture_output=True, text=True, timeout=10
    )
    return result.stdout


def _parse_dmi_section(output):
    """Parse dmidecode output into a dict of key-value pairs."""
    data = {}
    for line in output.splitlines():
        line = line.strip()
        if ':' in line and not line.endswith(':'):
            key, _, value = line.partition(':')
            key = key.strip().lower().replace(' ', '_')
            value = value.strip()
            if value:
                data[key] = value
    return data


# --- NUMA Topology ---

def collect_numa():
    """Collect NUMA topology from /sys/devices/system/node/."""
    numa_nodes = _list_numa_nodes()
    nodes = {}

    for node_dir in numa_nodes:
        node_num = node_dir.replace('node', '')
        base_path = f'/sys/devices/system/node/{node_dir}'
        cpulist = _read_file(f'{base_path}/cpulist').strip()
        meminfo = _read_file(f'{base_path}/meminfo')
        memory_kb = _parse_memtotal(meminfo)
        nodes[node_num] = {'cpulist': cpulist, 'memory_kb': memory_kb}

    return {'node_count': len(numa_nodes), 'nodes': nodes}


def _list_numa_nodes():
    base = '/sys/devices/system/node'
    if not os.path.isdir(base):
        return []
    return sorted([d for d in os.listdir(base) if d.startswith('node') and d[4:].isdigit()])


def _read_file(path):
    try:
        with open(path, 'r') as f:
            return f.read()
    except (IOError, OSError):
        return ''


def _parse_memtotal(meminfo):
    match = re.search(r'MemTotal:\s+(\d+)\s+kB', meminfo)
    return int(match.group(1)) if match else 0


# --- Network V2 (lshw) ---

def collect_network_v2():
    """Collect advanced network device information using lshw."""
    try:
        raw = _run_lshw()
        entries = json.loads(raw)
        devices = []
        for entry in entries:
            config = entry.get('configuration', {})
            devices.append({
                'name': entry.get('logicalname', ''),
                'product': entry.get('product', ''),
                'vendor': entry.get('vendor', ''),
                'mac': entry.get('serial', ''),
                'driver': config.get('driver', ''),
                'speed': config.get('speed', ''),
                'link': config.get('link', ''),
                'pci_slot': entry.get('handle', ''),
            })
        return {'devices': devices}
    except FileNotFoundError as e:
        return {'error': str(e)}
    except (json.JSONDecodeError, subprocess.CalledProcessError) as e:
        return {'error': f'lshw failed: {e}'}


def _run_lshw():
    result = subprocess.run(
        ['lshw', '-class', 'network', '-json'],
        capture_output=True, text=True, timeout=30
    )
    return result.stdout
```

**Step 4: Run test to verify it passes**

Run: `cd salt/modules && python -m pytest tests/test_inventory.py -v`
Expected: All PASS

**Step 5: Commit**

```bash
git add salt/modules/inventory.py salt/modules/tests/test_inventory.py
git commit -m "feat(salt): add consolidated inventory custom execution module (DMI, NUMA, network_v2)"
```

---

### Task 7.2: Create benchmark execution module

**Files:**
- Create: `salt/modules/benchmark.py`
- Test: `salt/modules/tests/test_benchmark.py`

**Step 1: Write the failing test**

Create `salt/modules/tests/test_benchmark.py`:

```python
from unittest import mock
import os
import sys
import signal
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

import benchmark


class TestRunHpcg:
    @mock.patch('benchmark._run_command')
    def test_run_hpcg_returns_results(self, mock_run):
        mock_run.return_value = {
            'retcode': 0,
            'stdout': 'HPCG result is VALID\nGFLOP/s: 45.67',
            'stderr': '',
        }

        result = benchmark.run_hpcg(
            work_dir='/tmp/hpcg',
            run_id='test-uuid-123'
        )

        assert result['status'] == 'PASS'
        assert 'metrics' in result
        assert result['run_id'] == 'test-uuid-123'

    @mock.patch('benchmark._run_command')
    def test_run_hpcg_handles_failure(self, mock_run):
        mock_run.return_value = {
            'retcode': 1,
            'stdout': '',
            'stderr': 'Error: binary not found',
        }

        result = benchmark.run_hpcg(work_dir='/tmp/hpcg', run_id='test-uuid')
        assert result['status'] == 'FAIL'
        assert 'error_message' in result


class TestCancel:
    @mock.patch('os.kill')
    @mock.patch('benchmark._find_benchmark_pid')
    def test_cancel_sends_sigterm(self, mock_find, mock_kill):
        mock_find.return_value = 12345

        result = benchmark.cancel()

        mock_kill.assert_called_once_with(12345, signal.SIGTERM)
        assert result['success'] is True

    @mock.patch('benchmark._find_benchmark_pid')
    def test_cancel_returns_error_when_no_process(self, mock_find):
        mock_find.return_value = None

        result = benchmark.cancel()
        assert result['success'] is False
```

**Step 2: Run test to verify it fails**

Run: `cd salt/modules && python -m pytest tests/test_benchmark.py -v`
Expected: FAIL — `ModuleNotFoundError`

**Step 3: Write minimal implementation**

Create `salt/modules/benchmark.py`:

```python
"""
Salt custom execution module for benchmark execution.
Handles HPCG and MLC benchmark lifecycle.

Usage via salt-api:
    salt 'minion-id' benchmark.run_hpcg work_dir=/tmp/hpcg run_id=uuid
    salt 'minion-id' benchmark.run_mlc work_dir=/tmp/mlc run_id=uuid
    salt 'minion-id' benchmark.cancel
"""

import json
import os
import re
import signal
import subprocess
import time


__virtualname__ = 'benchmark'


def __virtual__():
    return __virtualname__


def run_hpcg(work_dir='/tmp/hpcg', run_id=None, **kwargs):
    """Run HPCG benchmark and return structured results."""
    start_time = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())

    result = _run_command(
        ['hpcg'],
        cwd=work_dir,
        timeout=kwargs.get('timeout', 3600)
    )

    end_time = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    status = 'PASS' if result['retcode'] == 0 else 'FAIL'

    return {
        'status': status,
        'metrics': _parse_hpcg_metrics(result['stdout']),
        'start_time': start_time,
        'end_time': end_time,
        'log_content': result['stdout'] + result['stderr'],
        'error_message': result['stderr'] if status == 'FAIL' else None,
        'run_id': run_id,
        'artifacts': _find_artifacts(work_dir),
    }


def run_mlc(work_dir='/tmp/mlc', run_id=None, binary_path='mlc', profile='quick', **kwargs):
    """Run MLC benchmark and return structured results."""
    start_time = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())

    cmd = [binary_path]
    if profile == 'quick':
        cmd.extend(['--idle_latency', '--peak_injection_bandwidth'])

    result = _run_command(cmd, cwd=work_dir, timeout=kwargs.get('timeout', 3600))

    end_time = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    status = 'PASS' if result['retcode'] == 0 else 'FAIL'

    return {
        'status': status,
        'metrics': _parse_mlc_metrics(result['stdout']),
        'start_time': start_time,
        'end_time': end_time,
        'log_content': result['stdout'] + result['stderr'],
        'error_message': result['stderr'] if status == 'FAIL' else None,
        'run_id': run_id,
        'artifacts': _find_artifacts(work_dir),
    }


def cancel():
    """Cancel a running benchmark process."""
    pid = _find_benchmark_pid()
    if pid is None:
        return {'success': False, 'error': 'No benchmark process found'}

    try:
        os.kill(pid, signal.SIGTERM)
        return {'success': True, 'pid': pid}
    except ProcessLookupError:
        return {'success': False, 'error': f'Process {pid} not found'}
    except PermissionError:
        return {'success': False, 'error': f'Permission denied for PID {pid}'}


def _run_command(cmd, cwd=None, timeout=3600):
    """Run a command and capture output."""
    try:
        proc = subprocess.run(
            cmd, capture_output=True, text=True,
            cwd=cwd, timeout=timeout
        )
        return {
            'retcode': proc.returncode,
            'stdout': proc.stdout,
            'stderr': proc.stderr,
        }
    except subprocess.TimeoutExpired:
        return {
            'retcode': -1,
            'stdout': '',
            'stderr': f'Command timed out after {timeout}s',
        }
    except FileNotFoundError as e:
        return {
            'retcode': -1,
            'stdout': '',
            'stderr': str(e),
        }


def _find_benchmark_pid():
    """Find a running benchmark process PID."""
    try:
        result = subprocess.run(
            ['pgrep', '-f', '(hpcg|mlc)'],
            capture_output=True, text=True
        )
        if result.returncode == 0 and result.stdout.strip():
            return int(result.stdout.strip().splitlines()[0])
    except (ValueError, FileNotFoundError):
        pass
    return None


def _parse_hpcg_metrics(stdout):
    """Parse HPCG output for metrics."""
    metrics = {}
    gflops_match = re.search(r'GFLOP/s:\s+([\d.]+)', stdout)
    if gflops_match:
        metrics['gflops'] = float(gflops_match.group(1))
    return metrics


def _parse_mlc_metrics(stdout):
    """Parse MLC output for metrics."""
    metrics = {}
    latency_match = re.search(r'Each iteration took\s+([\d.]+)\s+', stdout)
    if latency_match:
        metrics['idle_latency_ns'] = float(latency_match.group(1))
    return metrics


def _find_artifacts(work_dir):
    """Find artifact files in the work directory."""
    artifacts = []
    if not os.path.isdir(work_dir):
        return artifacts
    for f in os.listdir(work_dir):
        filepath = os.path.join(work_dir, f)
        if os.path.isfile(filepath) and f.endswith(('.txt', '.yaml', '.log', '.dat')):
            artifacts.append(filepath)
    return artifacts
```

**Step 4: Run test to verify it passes**

Run: `cd salt/modules && python -m pytest tests/test_benchmark.py -v`
Expected: All PASS

**Step 5: Commit**

```bash
git add salt/modules/benchmark.py salt/modules/tests/test_benchmark.py
git commit -m "feat(salt): add benchmark execution module for HPCG and MLC"
```

---

## Phase 8: Salt State Files for Benchmark Orchestration

### Task 8.1: Create HPCG benchmark orchestration states

**Files:**
- Create: `salt/states/benchmark/hpcg/init.sls`
- Create: `salt/states/benchmark/hpcg/prepare.sls`
- Create: `salt/states/benchmark/hpcg/execute.sls`
- Create: `salt/states/benchmark/hpcg/collect.sls`

**Step 1: Create the state files**

Create `salt/states/benchmark/hpcg/init.sls`:

```yaml
# HPCG Benchmark Orchestration
# Applied via: salt 'node-01' state.apply benchmark.hpcg pillar='{"run_id": "uuid", "work_dir": "/tmp/hpcg"}'

include:
  - benchmark.hpcg.prepare
  - benchmark.hpcg.execute
  - benchmark.hpcg.collect
```

Create `salt/states/benchmark/hpcg/prepare.sls`:

```yaml
hpcg_work_dir:
  file.directory:
    - name: {{ pillar.get('work_dir', '/tmp/hpcg') }}
    - makedirs: True

hpcg_binary_check:
  cmd.run:
    - name: which hpcg || echo "HPCG binary not found"
    - require:
      - file: hpcg_work_dir
```

Create `salt/states/benchmark/hpcg/execute.sls`:

```yaml
run_hpcg:
  module.run:
    - benchmark.run_hpcg:
      - work_dir: {{ pillar.get('work_dir', '/tmp/hpcg') }}
      - run_id: {{ pillar.get('run_id', '') }}
    - require:
      - cmd: hpcg_binary_check
```

Create `salt/states/benchmark/hpcg/collect.sls`:

```yaml
# Results are returned inline from the execute module
# Artifacts can be pushed to master via cp.push
push_hpcg_artifacts:
  module.run:
    - cp.push_dir:
      - path: {{ pillar.get('work_dir', '/tmp/hpcg') }}
      - glob: "*"
    - require:
      - module: run_hpcg
```

**Step 2: Commit**

```bash
git add salt/states/benchmark/hpcg/
git commit -m "feat(salt): add HPCG benchmark orchestration states"
```

---

### Task 8.2: Create MLC benchmark orchestration states

**Files:**
- Create: `salt/states/benchmark/mlc/init.sls`
- Create: `salt/states/benchmark/mlc/prepare.sls`
- Create: `salt/states/benchmark/mlc/execute.sls`
- Create: `salt/states/benchmark/mlc/collect.sls`

**Step 1: Create the state files**

Create `salt/states/benchmark/mlc/init.sls`:

```yaml
# MLC Benchmark Orchestration
# Applied via: salt 'node-01' state.apply benchmark.mlc pillar='{"run_id": "uuid", "work_dir": "/tmp/mlc", "binary_path": "mlc", "profile": "quick"}'

include:
  - benchmark.mlc.prepare
  - benchmark.mlc.execute
  - benchmark.mlc.collect
```

Create `salt/states/benchmark/mlc/prepare.sls`:

```yaml
mlc_work_dir:
  file.directory:
    - name: {{ pillar.get('work_dir', '/tmp/mlc') }}
    - makedirs: True

mlc_binary_check:
  cmd.run:
    - name: which {{ pillar.get('binary_path', 'mlc') }} || echo "MLC binary not found"
    - require:
      - file: mlc_work_dir
```

Create `salt/states/benchmark/mlc/execute.sls`:

```yaml
run_mlc:
  module.run:
    - benchmark.run_mlc:
      - work_dir: {{ pillar.get('work_dir', '/tmp/mlc') }}
      - run_id: {{ pillar.get('run_id', '') }}
      - binary_path: {{ pillar.get('binary_path', 'mlc') }}
      - profile: {{ pillar.get('profile', 'quick') }}
    - require:
      - cmd: mlc_binary_check
```

Create `salt/states/benchmark/mlc/collect.sls`:

```yaml
push_mlc_artifacts:
  module.run:
    - cp.push_dir:
      - path: {{ pillar.get('work_dir', '/tmp/mlc') }}
      - glob: "*"
    - require:
      - module: run_mlc
```

**Step 2: Commit**

```bash
git add salt/states/benchmark/mlc/
git commit -m "feat(salt): add MLC benchmark orchestration states"
```

---

## Phase 9: Salt Master Configuration Files

### Task 9.1: Create Salt Master configuration

**Files:**
- Create: `salt/master.d/api.conf`
- Create: `salt/reactor/job_return.sls`
- Create: `salt/reactor/presence_change.sls`

**Step 1: Create configuration files**

Create `salt/master.d/api.conf`:

```yaml
# Salt API Configuration
# Deploy to: /etc/salt/master.d/api.conf on the admin node

rest_cherrypy:
  port: 8000
  ssl_crt: /etc/salt/pki/api/cert.crt
  ssl_key: /etc/salt/pki/api/key.key

netapi_enable_clients:
  - local
  - local_async
  - runner

# Enable presence detection events on the event bus
presence_events: True

# Allow minions to push files to the master via cp.push
file_recv: True

# PAM auth for Rails service account
external_auth:
  pam:
    rails_salt_user:
      - '*':
        - grains.items
        - inventory.collect_dmi
        - inventory.collect_numa
        - inventory.collect_network_v2
        - benchmark.run_hpcg
        - benchmark.run_mlc
        - benchmark.cancel
        - test.ping
        - state.apply
        - cp.push
        - cp.push_dir
      - '@runner':
        - manage.status

# Custom modules path
module_dirs:
  - /srv/salt/modules

# File roots for states
file_roots:
  base:
    - /srv/salt/states

# Reactor configuration
reactor:
  - 'salt/job/ret/*':
    - /srv/salt/reactor/job_return.sls
  - 'salt/presence/change':
    - /srv/salt/reactor/presence_change.sls
```

Create `salt/reactor/job_return.sls`:

```yaml
# Reactor: forward benchmark job returns to Rails webhook
# This reactor fires when any job completes on a minion
{% if 'benchmark' in data.get('fun', '') or 'state.apply' in data.get('fun', '') %}
notify_rails:
  runner.http.query:
    - url: {{ salt['config.get']('rails_webhook_url', 'http://localhost:3000/api/v1/salt/events') }}
    - method: POST
    - header_dict:
        Content-Type: application/json
        Authorization: "Bearer {{ salt['config.get']('rails_api_token', '') }}"
    - data: {{ {"tag": tag, "fun": data['fun'], "id": data['id'], "jid": data['jid'], "retcode": data.get('retcode', -1), "return": data.get('return', {})} | tojson }}
{% endif %}
```

Create `salt/reactor/presence_change.sls`:

```yaml
# Reactor: notify Rails when minion presence changes
notify_rails_presence:
  runner.http.query:
    - url: {{ salt['config.get']('rails_webhook_url', 'http://localhost:3000/api/v1/salt/events') }}
    - method: POST
    - header_dict:
        Content-Type: application/json
        Authorization: "Bearer {{ salt['config.get']('rails_api_token', '') }}"
    - data: {{ {"tag": "salt/presence/change", "new": data.get('new', []), "lost": data.get('lost', [])} | tojson }}
```

**Step 2: Commit**

```bash
git add salt/master.d/ salt/reactor/
git commit -m "feat(salt): add Salt Master config and reactor templates"
```

---

## Phase 10: Cleanup — Remove Legacy Code

### Task 10.1: Remove SSH-based services

**Files to delete:**
- `app/services/ssh_execution_service.rb`
- `app/services/inventory/trigger_collect_service.rb`
- `app/services/benchmark/trigger_run_service.rb`
- `app/services/agent/install_service.rb`
- `app/services/agent/update_service.rb`
- `app/services/agent/uninstall_service.rb`
- `app/services/agent/lifecycle_service.rb`
- `app/services/agent/credential_checker.rb`

**Step 1: Remove the files**

```bash
git rm app/services/ssh_execution_service.rb
git rm app/services/inventory/trigger_collect_service.rb
git rm app/services/benchmark/trigger_run_service.rb
git rm -r app/services/agent/
```

**Step 2: Remove corresponding specs**

```bash
git rm spec/services/ssh_execution_service_spec.rb 2>/dev/null || true
git rm spec/services/inventory/trigger_collect_service_spec.rb 2>/dev/null || true
git rm spec/services/benchmark/trigger_run_service_spec.rb 2>/dev/null || true
git rm -r spec/services/agent/ 2>/dev/null || true
```

**Step 3: Run tests to ensure nothing else breaks**

Run: `bin/rspec`
Expected: All PASS (no references to removed services remain)

If tests fail, fix references in controllers/jobs that still import removed services.

**Step 4: Commit**

```bash
git commit -m "refactor(salt): remove SSH-based services replaced by Salt"
```

---

### Task 10.2: Remove legacy API endpoints

**Files:**
- Modify: `config/routes.rb` — remove agent callback routes
- Delete: `app/controllers/api/v1/heartbeats_controller.rb`
- Delete: `app/controllers/api/v1/inventory_controller.rb` (the push endpoint)

**Step 1: Remove controller files**

```bash
git rm app/controllers/api/v1/heartbeats_controller.rb
```

**Step 2: Update routes**

Remove from `config/routes.rb`:
- `post "inventory/push", to: "inventory#push"`
- `post "nodes/:id/heartbeat", to: "heartbeats#create"`

Keep:
- `resources :benchmark_runs` (still used for internal status tracking)
- Health check endpoint

**Step 3: Remove corresponding specs**

```bash
git rm spec/controllers/api/v1/heartbeats_controller_spec.rb 2>/dev/null || true
git rm spec/controllers/api/v1/inventory_controller_spec.rb 2>/dev/null || true
```

**Step 4: Run tests**

Run: `bin/rspec`
Expected: All PASS

**Step 5: Commit**

```bash
git add -A
git commit -m "refactor(salt): remove legacy agent API endpoints"
```

---

### Task 10.3: Add Salt event webhook endpoint

**Files:**
- Create: `app/controllers/api/v1/salt_events_controller.rb`
- Test: `spec/controllers/api/v1/salt_events_controller_spec.rb`
- Modify: `config/routes.rb`

**Step 1: Write the failing test**

Create `spec/controllers/api/v1/salt_events_controller_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Api::V1::SaltEventsController, type: :controller do
  let(:api_key) { create(:api_key) }

  before do
    request.headers["Authorization"] = "Bearer #{api_key.token}"
    request.headers["Content-Type"] = "application/json"
  end

  describe "POST #create" do
    let(:node) { create(:node, hostname: "node-01") }
    let(:run) { create(:benchmark_run, :running, node: node) }

    it "dispatches benchmark events" do
      post :create, body: {
        tag: "salt/job/ret/123",
        fun: "state.apply",
        fun_args: [{ "mods" => "benchmark.hpcg", "pillar" => { "run_id" => run.uuid } }],
        id: "node-01",
        retcode: 0,
        return: { "status" => "PASS", "metrics" => {} }
      }.to_json

      expect(response).to have_http_status(:ok)
    end

    it "dispatches presence events" do
      post :create, body: {
        tag: "salt/presence/change",
        new: [],
        lost: ["node-01"]
      }.to_json

      expect(response).to have_http_status(:ok)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/controllers/api/v1/salt_events_controller_spec.rb`
Expected: FAIL — `uninitialized constant`

**Step 3: Write minimal implementation**

Create `app/controllers/api/v1/salt_events_controller.rb`:

```ruby
module Api
  module V1
    class SaltEventsController < BaseController
      def create
        body = JSON.parse(request.body.read)
        tag = body["tag"]

        Salt::EventListenerService.new.dispatch_event(tag, body)

        render json: { success: true }
      rescue JSON::ParserError => e
        render json: { error: "Invalid JSON: #{e.message}" }, status: :bad_request
      end
    end
  end
end
```

Add route to `config/routes.rb` inside the `api/v1` namespace:

```ruby
post "salt/events", to: "salt_events#create"
```

**Step 4: Run test to verify it passes**

Run: `bin/rspec spec/controllers/api/v1/salt_events_controller_spec.rb`
Expected: All PASS

**Step 5: Commit**

```bash
git add app/controllers/api/v1/salt_events_controller.rb spec/controllers/api/v1/salt_events_controller_spec.rb config/routes.rb
git commit -m "feat(salt): add webhook endpoint for Salt reactor events"
```

---

## Phase 11: Final Integration

### Task 11.1: Run full test suite and fix any failures

**Step 1: Run rubocop**

Run: `bin/rubocop -f github`
Expected: No offenses. Fix any that appear.

**Step 2: Run full test suite**

Run: `bin/rspec`
Expected: All PASS. Fix any failures from stale references to removed code.

**Step 3: Run Python tests**

Run: `cd salt/modules && python -m pytest tests/ -v`
Expected: All PASS.

**Step 4: Commit any fixes**

```bash
git add -A
git commit -m "fix: resolve test failures from Salt migration cleanup"
```

---

### Task 11.2: Update NodesController collect action

**Files:**
- Modify: `app/controllers/nodes_controller.rb` — update `collect` action

**Step 1: Update the collect action**

The `collect` action currently calls `InventoryCollectJob` which we already updated in Task 6.1. Verify the controller action still works with the updated job:

```ruby
# In nodes_controller.rb, the collect action should still work as-is
# since it just enqueues InventoryCollectJob which now uses Salt internally.
# Verify no direct SSH references remain in the controller.
```

**Step 2: Run controller tests**

Run: `bin/rspec spec/controllers/nodes_controller_spec.rb` (if exists)
Expected: PASS

**Step 3: Commit if changes needed**

```bash
git add app/controllers/nodes_controller.rb
git commit -m "refactor(salt): verify NodesController collect uses Salt path"
```

---

### Task 11.3: Final commit and verification

**Step 1: Run all quality gates**

```bash
bin/rubocop -f github
bin/rspec
cd salt/modules && python -m pytest tests/ -v
```

**Step 2: Review git log for clean history**

```bash
git log --oneline -20
```

Expected: Clean sequence of commits following the phase structure.

---

## Appendix: File Inventory

### New Files Created

| File | Purpose |
|------|---------|
| `app/services/salt_api_client.rb` | Core HTTP client for salt-api |
| `app/services/salt/inventory_mapper.rb` | Grains → ProcessStateService schema |
| `app/services/salt/event_listener_service.rb` | SSE/webhook event dispatch |
| `app/services/salt/benchmark_result_service.rb` | Job return → BenchmarkRun update |
| `app/services/salt/presence_check_service.rb` | Minion presence → Node status |
| `app/services/inventory/salt_collect_service.rb` | Salt-based inventory collection |
| `app/services/benchmark/salt_trigger_run_service.rb` | Salt-based benchmark trigger |
| `app/controllers/api/v1/salt_events_controller.rb` | Webhook for Salt reactor |
| `salt/modules/inventory.py` | Consolidated inventory module (DMI, NUMA, network_v2) |
| `salt/modules/benchmark.py` | Benchmark execution module |
| `salt/states/benchmark/hpcg/*.sls` | HPCG orchestration states |
| `salt/states/benchmark/mlc/*.sls` | MLC orchestration states |
| `salt/master.d/api.conf` | Salt Master configuration |
| `salt/reactor/*.sls` | Event reactor templates |

### Files Deleted

| File | Replaced By |
|------|-------------|
| `app/services/ssh_execution_service.rb` | `SaltApiClient` |
| `app/services/inventory/trigger_collect_service.rb` | `Inventory::SaltCollectService` |
| `app/services/benchmark/trigger_run_service.rb` | `Benchmark::SaltTriggerRunService` |
| `app/services/agent/install_service.rb` | Salt minion package management |
| `app/services/agent/update_service.rb` | Salt minion package management |
| `app/services/agent/uninstall_service.rb` | Salt minion package management |
| `app/services/agent/lifecycle_service.rb` | N/A (base class removed) |
| `app/services/agent/credential_checker.rb` | Salt eauth |
| `app/controllers/api/v1/heartbeats_controller.rb` | `Salt::PresenceCheckService` |

### Files Modified

| File | Change |
|------|--------|
| `app/jobs/inventory_collect_job.rb` | Use `SaltCollectService` instead of SSH |
| `app/jobs/benchmark/trigger_job.rb` | Use `SaltTriggerRunService` instead of SSH |
| `config/routes.rb` | Remove agent endpoints, add Salt webhook |
