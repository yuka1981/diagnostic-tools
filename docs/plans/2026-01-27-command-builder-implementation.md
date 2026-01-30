# Command Builder Strategy Pattern Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Refactor TriggerRunService to use strategy pattern for benchmark-specific command building, fixing MLC "unknown flag: --build" error.

**Architecture:** Command builders encapsulate benchmark-specific CLI flags. TriggerRunService delegates to the appropriate builder based on recipe.command. Shared logic (base command, common flags) lives in base class.

**Tech Stack:** Ruby, RSpec, Faker for test data

---

### Task 1: Create Base Command Builder

**Files:**
- Create: `app/services/benchmark/command_builders/base.rb`
- Test: `spec/services/benchmark/command_builders/base_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/services/benchmark/command_builders/base_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Benchmark::CommandBuilders::Base do
  let(:agent_bin) { "/usr/local/bin/qis-agent" }
  let(:run_id) { Faker::Alphanumeric.alphanumeric(number: 10) }
  let(:node_uuid) { Faker::Internet.uuid }
  let(:server_url) { "http://localhost:3000" }
  let(:token) { Faker::Alphanumeric.alphanumeric(number: 32) }
  let(:log_path) { "/var/log/benchmark.log" }
  let(:arguments) { { "profile" => "quick" } }

  let(:builder) do
    described_class.new(
      agent_bin: agent_bin,
      run_id: run_id,
      node_uuid: node_uuid,
      arguments: arguments,
      server_url: server_url,
      token: token,
      log_path: log_path
    )
  end

  describe "#build" do
    it "raises NotImplementedError" do
      expect { builder.build }.to raise_error(NotImplementedError)
    end
  end

  describe "#subcommand" do
    it "raises NotImplementedError" do
      expect { builder.subcommand }.to raise_error(NotImplementedError)
    end
  end

  describe "attribute readers" do
    it "exposes agent_bin" do
      expect(builder.agent_bin).to eq(agent_bin)
    end

    it "exposes run_id" do
      expect(builder.run_id).to eq(run_id)
    end

    it "exposes node_uuid" do
      expect(builder.node_uuid).to eq(node_uuid)
    end

    it "exposes arguments" do
      expect(builder.arguments).to eq(arguments)
    end

    it "exposes server_url" do
      expect(builder.server_url).to eq(server_url)
    end

    it "exposes token" do
      expect(builder.token).to eq(token)
    end

    it "exposes log_path" do
      expect(builder.log_path).to eq(log_path)
    end
  end

  describe "#arguments" do
    context "when nil is passed" do
      let(:arguments) { nil }

      it "defaults to empty hash" do
        expect(builder.arguments).to eq({})
      end
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/services/benchmark/command_builders/base_spec.rb -v`
Expected: FAIL with "uninitialized constant"

**Step 3: Write minimal implementation**

```ruby
# app/services/benchmark/command_builders/base.rb
# frozen_string_literal: true

module Benchmark
  module CommandBuilders
    class Base
      attr_reader :agent_bin, :run_id, :node_uuid, :arguments, :server_url, :token, :log_path

      def initialize(agent_bin:, run_id:, node_uuid:, arguments:, server_url:, token:, log_path:)
        @agent_bin = agent_bin
        @run_id = run_id
        @node_uuid = node_uuid
        @arguments = arguments || {}
        @server_url = server_url
        @token = token
        @log_path = log_path
      end

      def build
        raise NotImplementedError
      end

      def subcommand
        raise NotImplementedError
      end

      protected

      def base_command
        cmd = "env OMP_NUM_THREADS=$(nproc) #{esc(agent_bin)}"
        cmd += " --node-uuid #{esc(node_uuid)}" if node_uuid.present?
        cmd += " #{subcommand}"
        cmd += " --id #{esc(run_id)}"
        cmd
      end

      def append_common_flags(cmd)
        cmd += " --server #{esc(server_url)}" if server_url.present?
        cmd += " --token #{esc(token)}" if token.present?
        cmd
      end

      def esc(value)
        Shellwords.escape(value.to_s)
      end
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rspec spec/services/benchmark/command_builders/base_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/services/benchmark/command_builders/base.rb spec/services/benchmark/command_builders/base_spec.rb
git commit -m "feat: add base command builder for benchmark strategy pattern"
```

---

### Task 2: Create HPCG Command Builder

**Files:**
- Create: `app/services/benchmark/command_builders/hpcg_command_builder.rb`
- Test: `spec/services/benchmark/command_builders/hpcg_command_builder_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/services/benchmark/command_builders/hpcg_command_builder_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Benchmark::CommandBuilders::HpcgCommandBuilder do
  let(:agent_bin) { "/usr/local/bin/qis-agent" }
  let(:run_id) { Faker::Alphanumeric.alphanumeric(number: 10) }
  let(:node_uuid) { Faker::Internet.uuid }
  let(:server_url) { "http://localhost:3000" }
  let(:token) { Faker::Alphanumeric.alphanumeric(number: 32) }
  let(:log_path) { "/var/log/hpcg.log" }
  let(:arguments) { {} }

  let(:builder) do
    described_class.new(
      agent_bin: agent_bin,
      run_id: run_id,
      node_uuid: node_uuid,
      arguments: arguments,
      server_url: server_url,
      token: token,
      log_path: log_path
    )
  end

  describe "#subcommand" do
    it "returns hpcg" do
      expect(builder.subcommand).to eq("hpcg")
    end
  end

  describe "#build" do
    it "includes OMP_NUM_THREADS environment variable" do
      expect(builder.build).to include("env OMP_NUM_THREADS=$(nproc)")
    end

    it "includes agent binary path" do
      expect(builder.build).to include("qis-agent")
    end

    it "includes node-uuid flag" do
      expect(builder.build).to include("--node-uuid #{node_uuid}")
    end

    it "includes hpcg subcommand" do
      expect(builder.build).to match(/qis-agent --node-uuid \S+ hpcg/)
    end

    it "includes run id" do
      expect(builder.build).to include("--id #{run_id}")
    end

    it "includes default build command" do
      expect(builder.build).to include("--build make\\ arch\\=Linux_OpenMP")
    end

    it "includes default run command" do
      expect(builder.build).to include("--run ./bin/xhpcg")
    end

    it "includes default timeout" do
      expect(builder.build).to include("--rt 60")
    end

    it "includes log-path when provided" do
      expect(builder.build).to include("--log-path #{Shellwords.escape(log_path)}")
    end

    it "includes server url when provided" do
      expect(builder.build).to include("--server #{Shellwords.escape(server_url)}")
    end

    it "includes token when provided" do
      expect(builder.build).to include("--token #{token}")
    end

    context "with custom arguments" do
      let(:arguments) do
        {
          "build" => "make arch=AVX2",
          "run" => "./xhpcg_avx2",
          "rt" => 120,
          "nx" => 104,
          "ny" => 104,
          "nz" => 104
        }
      end

      it "uses custom build command" do
        expect(builder.build).to include("--build make\\ arch\\=AVX2")
      end

      it "uses custom run command" do
        expect(builder.build).to include("--run ./xhpcg_avx2")
      end

      it "uses custom timeout" do
        expect(builder.build).to include("--rt 120")
      end

      it "includes nx dimension" do
        expect(builder.build).to include("--nx 104")
      end

      it "includes ny dimension" do
        expect(builder.build).to include("--ny 104")
      end

      it "includes nz dimension" do
        expect(builder.build).to include("--nz 104")
      end
    end

    context "with timeout from arguments" do
      let(:arguments) { { "timeout" => 180 } }

      it "uses timeout key as fallback for rt" do
        expect(builder.build).to include("--rt 180")
      end
    end

    context "without node_uuid" do
      let(:node_uuid) { nil }

      it "omits node-uuid flag" do
        expect(builder.build).not_to include("--node-uuid")
      end
    end

    context "without log_path" do
      let(:log_path) { nil }

      it "omits log-path flag" do
        expect(builder.build).not_to include("--log-path")
      end
    end

    context "without server_url" do
      let(:server_url) { nil }

      it "omits server flag" do
        expect(builder.build).not_to include("--server")
      end
    end

    context "without token" do
      let(:token) { nil }

      it "omits token flag" do
        expect(builder.build).not_to include("--token")
      end
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/services/benchmark/command_builders/hpcg_command_builder_spec.rb -v`
Expected: FAIL with "uninitialized constant"

**Step 3: Write minimal implementation**

```ruby
# app/services/benchmark/command_builders/hpcg_command_builder.rb
# frozen_string_literal: true

module Benchmark
  module CommandBuilders
    class HpcgCommandBuilder < Base
      def subcommand
        "hpcg"
      end

      def build
        cmd = base_command
        cmd += " --build #{esc(build_cmd)}"
        cmd += " --run #{esc(run_cmd)}"
        cmd += " --rt #{timeout}"
        cmd += " --nx #{nx}" if nx.present?
        cmd += " --ny #{ny}" if ny.present?
        cmd += " --nz #{nz}" if nz.present?
        cmd += " --log-path #{esc(log_path)}" if log_path.present?
        append_common_flags(cmd)
      end

      private

      def build_cmd
        arguments["build"] || "make arch=Linux_OpenMP"
      end

      def run_cmd
        arguments["run"] || "./bin/xhpcg"
      end

      def timeout
        arguments["rt"] || arguments["timeout"] || 60
      end

      def nx
        arguments["nx"]
      end

      def ny
        arguments["ny"]
      end

      def nz
        arguments["nz"]
      end
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rspec spec/services/benchmark/command_builders/hpcg_command_builder_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/services/benchmark/command_builders/hpcg_command_builder.rb spec/services/benchmark/command_builders/hpcg_command_builder_spec.rb
git commit -m "feat: add HPCG command builder with benchmark-specific flags"
```

---

### Task 3: Create MLC Command Builder

**Files:**
- Create: `app/services/benchmark/command_builders/mlc_command_builder.rb`
- Test: `spec/services/benchmark/command_builders/mlc_command_builder_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/services/benchmark/command_builders/mlc_command_builder_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Benchmark::CommandBuilders::MlcCommandBuilder do
  let(:agent_bin) { "/usr/local/bin/qis-agent" }
  let(:run_id) { Faker::Alphanumeric.alphanumeric(number: 10) }
  let(:node_uuid) { Faker::Internet.uuid }
  let(:server_url) { "http://localhost:3000" }
  let(:token) { Faker::Alphanumeric.alphanumeric(number: 32) }
  let(:log_path) { "/var/log/mlc" }
  let(:arguments) { {} }

  let(:builder) do
    described_class.new(
      agent_bin: agent_bin,
      run_id: run_id,
      node_uuid: node_uuid,
      arguments: arguments,
      server_url: server_url,
      token: token,
      log_path: log_path
    )
  end

  describe "#subcommand" do
    it "returns mlc" do
      expect(builder.subcommand).to eq("mlc")
    end
  end

  describe "#build" do
    it "includes OMP_NUM_THREADS environment variable" do
      expect(builder.build).to include("env OMP_NUM_THREADS=$(nproc)")
    end

    it "includes agent binary path" do
      expect(builder.build).to include("qis-agent")
    end

    it "includes node-uuid flag" do
      expect(builder.build).to include("--node-uuid #{node_uuid}")
    end

    it "includes mlc subcommand" do
      expect(builder.build).to match(/qis-agent --node-uuid \S+ mlc/)
    end

    it "includes run id" do
      expect(builder.build).to include("--id #{run_id}")
    end

    it "includes default profile" do
      expect(builder.build).to include("--profile quick")
    end

    it "includes log-dir when provided" do
      expect(builder.build).to include("--log-dir #{Shellwords.escape(log_path)}")
    end

    it "includes server url when provided" do
      expect(builder.build).to include("--server #{Shellwords.escape(server_url)}")
    end

    it "includes token when provided" do
      expect(builder.build).to include("--token #{token}")
    end

    it "does not include HPCG-specific flags" do
      cmd = builder.build
      expect(cmd).not_to include("--build")
      expect(cmd).not_to include("--run")
      expect(cmd).not_to include("--rt")
      expect(cmd).not_to include("--nx")
      expect(cmd).not_to include("--ny")
      expect(cmd).not_to include("--nz")
    end

    context "with custom profile" do
      let(:arguments) { { "profile" => "full" } }

      it "uses custom profile" do
        expect(builder.build).to include("--profile full")
      end
    end

    context "with binary_path" do
      let(:arguments) { { "binary_path" => "/opt/mlc/mlc" } }

      it "includes binary flag" do
        expect(builder.build).to include("--binary /opt/mlc/mlc")
      end
    end

    context "with modules" do
      let(:arguments) { { "modules" => ["intel-mlc", "hwloc"] } }

      it "includes module flags for each module" do
        cmd = builder.build
        expect(cmd).to include("--module intel-mlc")
        expect(cmd).to include("--module hwloc")
      end
    end

    context "with tests" do
      let(:arguments) { { "tests" => %w[idle_latency peak_bandwidth] } }

      it "includes tests as comma-separated list" do
        expect(builder.build).to include("--tests idle_latency,peak_bandwidth")
      end
    end

    context "without node_uuid" do
      let(:node_uuid) { nil }

      it "omits node-uuid flag" do
        expect(builder.build).not_to include("--node-uuid")
      end
    end

    context "without log_path" do
      let(:log_path) { nil }

      it "omits log-dir flag" do
        expect(builder.build).not_to include("--log-dir")
      end
    end

    context "without server_url" do
      let(:server_url) { nil }

      it "omits server flag" do
        expect(builder.build).not_to include("--server")
      end
    end

    context "without token" do
      let(:token) { nil }

      it "omits token flag" do
        expect(builder.build).not_to include("--token")
      end
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/services/benchmark/command_builders/mlc_command_builder_spec.rb -v`
Expected: FAIL with "uninitialized constant"

**Step 3: Write minimal implementation**

```ruby
# app/services/benchmark/command_builders/mlc_command_builder.rb
# frozen_string_literal: true

module Benchmark
  module CommandBuilders
    class MlcCommandBuilder < Base
      def subcommand
        "mlc"
      end

      def build
        cmd = base_command
        cmd += " --profile #{esc(profile)}"
        cmd += " --binary #{esc(binary_path)}" if binary_path.present?
        cmd += modules_flags
        cmd += tests_flags
        cmd += " --log-dir #{esc(log_path)}" if log_path.present?
        append_common_flags(cmd)
      end

      private

      def profile
        arguments["profile"] || "quick"
      end

      def binary_path
        arguments["binary_path"]
      end

      def modules
        arguments["modules"] || []
      end

      def tests
        arguments["tests"] || []
      end

      def modules_flags
        return "" if modules.empty?

        modules.map { |m| " --module #{esc(m)}" }.join
      end

      def tests_flags
        return "" if tests.empty?

        " --tests #{esc(tests.join(','))}"
      end
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rspec spec/services/benchmark/command_builders/mlc_command_builder_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/services/benchmark/command_builders/mlc_command_builder.rb spec/services/benchmark/command_builders/mlc_command_builder_spec.rb
git commit -m "feat: add MLC command builder with profile and module flags"
```

---

### Task 4: Refactor TriggerRunService to Use Builders

**Files:**
- Modify: `app/services/benchmark/trigger_run_service.rb:175-205`
- Test: `spec/services/benchmark/trigger_run_service_spec.rb`

**Step 1: Write the failing test for builder selection**

Add to existing spec file:

```ruby
# Add these tests to spec/services/benchmark/trigger_run_service_spec.rb

describe "#command_builder_class" do
  let(:service) do
    described_class.new(
      node,
      ssh_config: ssh_config,
      benchmark_recipe: recipe
    )
  end

  context "when recipe command is hpcg" do
    let(:recipe) { create(:benchmark_recipe, command: "hpcg") }

    it "returns HpcgCommandBuilder" do
      expect(service.send(:command_builder_class)).to eq(Benchmark::CommandBuilders::HpcgCommandBuilder)
    end
  end

  context "when recipe command is mlc" do
    let(:recipe) { create(:benchmark_recipe, command: "mlc") }

    it "returns MlcCommandBuilder" do
      expect(service.send(:command_builder_class)).to eq(Benchmark::CommandBuilders::MlcCommandBuilder)
    end
  end

  context "when recipe is nil" do
    let(:recipe) { nil }

    it "defaults to HpcgCommandBuilder" do
      expect(service.send(:command_builder_class)).to eq(Benchmark::CommandBuilders::HpcgCommandBuilder)
    end
  end

  context "when recipe command is unknown" do
    let(:recipe) { create(:benchmark_recipe, command: "unknown") }

    it "raises ArgumentError" do
      expect { service.send(:command_builder_class) }.to raise_error(ArgumentError, /Unknown benchmark command/)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/services/benchmark/trigger_run_service_spec.rb -v --example "command_builder_class"`
Expected: FAIL

**Step 3: Refactor TriggerRunService**

Replace `build_agent_command` method (lines 175-205) with:

```ruby
def build_agent_command(agent_bin)
  builder = command_builder_for(agent_bin)
  builder.build
end

def command_builder_for(agent_bin)
  builder_class = command_builder_class
  builder_class.new(
    agent_bin: agent_bin,
    run_id: @run_id || generate_run_id,
    node_uuid: @target_node&.uuid,
    arguments: argument_builder.merged_arguments,
    server_url: @server_url,
    token: @agent_token,
    log_path: @log_path
  )
end

def command_builder_class
  subcommand = @benchmark_recipe&.command || "hpcg"
  case subcommand
  when "hpcg"
    CommandBuilders::HpcgCommandBuilder
  when "mlc"
    CommandBuilders::MlcCommandBuilder
  else
    raise ArgumentError, "Unknown benchmark command: #{subcommand}"
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rspec spec/services/benchmark/trigger_run_service_spec.rb -v`
Expected: PASS

**Step 5: Run full test suite**

Run: `bin/rspec`
Expected: All green

**Step 6: Commit**

```bash
git add app/services/benchmark/trigger_run_service.rb spec/services/benchmark/trigger_run_service_spec.rb
git commit -m "refactor: TriggerRunService uses command builder strategy pattern"
```

---

### Task 5: Integration Test - MLC Benchmark Triggering

**Files:**
- Modify: `spec/services/benchmark/trigger_run_service_spec.rb`

**Step 1: Add integration test for MLC command generation**

```ruby
describe "MLC benchmark command generation" do
  let(:mlc_recipe) { create(:benchmark_recipe, command: "mlc", name: "Intel MLC") }
  let(:argument_overrides) { { "profile" => "full", "modules" => ["intel-mlc"] } }

  let(:service) do
    described_class.new(
      node,
      ssh_config: ssh_config,
      run_id: "test-run-123",
      server_url: "http://localhost:3000",
      agent_token: "test-token",
      benchmark_recipe: mlc_recipe,
      argument_overrides: argument_overrides
    )
  end

  it "generates MLC-specific command without HPCG flags" do
    cmd = service.send(:build_agent_command, "/usr/bin/qis-agent")

    # MLC-specific flags present
    expect(cmd).to include("mlc")
    expect(cmd).to include("--profile full")
    expect(cmd).to include("--module intel-mlc")

    # HPCG-specific flags absent
    expect(cmd).not_to include("--build")
    expect(cmd).not_to include("--run")
    expect(cmd).not_to include("--rt")
  end
end

describe "HPCG benchmark command generation" do
  let(:hpcg_recipe) { create(:benchmark_recipe, command: "hpcg", name: "HPCG") }
  let(:argument_overrides) { { "nx" => 104, "ny" => 104, "nz" => 104 } }

  let(:service) do
    described_class.new(
      node,
      ssh_config: ssh_config,
      run_id: "test-run-456",
      server_url: "http://localhost:3000",
      agent_token: "test-token",
      benchmark_recipe: hpcg_recipe,
      argument_overrides: argument_overrides
    )
  end

  it "generates HPCG-specific command with build/run flags" do
    cmd = service.send(:build_agent_command, "/usr/bin/qis-agent")

    # HPCG-specific flags present
    expect(cmd).to include("hpcg")
    expect(cmd).to include("--build")
    expect(cmd).to include("--run")
    expect(cmd).to include("--rt")
    expect(cmd).to include("--nx 104")

    # MLC-specific flags absent
    expect(cmd).not_to include("--profile")
    expect(cmd).not_to include("--module")
  end
end
```

**Step 2: Run test to verify it passes**

Run: `bin/rspec spec/services/benchmark/trigger_run_service_spec.rb -v`
Expected: PASS

**Step 3: Commit**

```bash
git add spec/services/benchmark/trigger_run_service_spec.rb
git commit -m "test: add integration tests for MLC and HPCG command generation"
```

---

### Task 6: Final Verification and Lint

**Step 1: Run full test suite**

Run: `bin/rspec`
Expected: All green

**Step 2: Run linter**

Run: `bin/rubocop -f github`
Expected: No offenses

**Step 3: Fix any lint issues if needed**

Run: `bin/rubocop -a` if there are auto-fixable issues

**Step 4: Commit any lint fixes**

```bash
git add -A
git commit -m "style: fix rubocop offenses in command builders"
```
