# Command Builder Strategy Pattern Design

## Overview

Refactor `TriggerRunService` to use strategy pattern for benchmark-specific command building. This allows different benchmarks (HPCG, MLC) to have different CLI interfaces while sharing SSH orchestration logic.

## Problem

`TriggerRunService.build_agent_command` hardcodes HPCG-specific flags (`--build`, `--run`, `--rt`) that don't exist in the MLC agent CLI, causing "unknown flag" errors when triggering MLC benchmarks.

## Architecture

```
app/services/benchmark/
├── trigger_run_service.rb              # Orchestrates SSH, delegates to builder
├── command_builders/
│   ├── base.rb                         # Abstract interface + shared logic
│   ├── hpcg_command_builder.rb         # HPCG: --build, --run, --rt, --nx/ny/nz
│   └── mlc_command_builder.rb          # MLC: --profile, --binary, --module
└── argument_builder_service.rb         # (existing) merges recipe defaults + overrides
```

## Flow

1. `TriggerRunService` receives `benchmark_recipe`
2. Looks up command builder by `recipe.command` ("hpcg" → `HpcgCommandBuilder`, "mlc" → `MlcCommandBuilder`)
3. Builder receives: `agent_bin`, `run_id`, `node_uuid`, `merged_arguments`, `server_url`, `token`, `log_path`
4. Builder returns the full command string
5. `TriggerRunService` executes via SSH as before

## Base Builder

```ruby
# app/services/benchmark/command_builders/base.rb
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

## HPCG Command Builder

```ruby
# app/services/benchmark/command_builders/hpcg_command_builder.rb
module Benchmark
  module CommandBuilders
    class HpcgCommandBuilder < Base
      def subcommand
        "hpcg"
      end

      def build
        cmd = base_command
        cmd += " --build #{esc(build_cmd)}" if build_cmd.present?
        cmd += " --run #{esc(run_cmd)}" if run_cmd.present?
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

## MLC Command Builder

```ruby
# app/services/benchmark/command_builders/mlc_command_builder.rb
module Benchmark
  module CommandBuilders
    class MlcCommandBuilder < Base
      def subcommand
        "mlc"
      end

      def build
        cmd = base_command
        cmd += " --profile #{esc(profile)}" if profile.present?
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

## TriggerRunService Changes

Replace hardcoded `build_agent_command` with builder delegation:

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

## File Structure

```
app/services/benchmark/
├── command_builders/
│   ├── base.rb
│   ├── hpcg_command_builder.rb
│   └── mlc_command_builder.rb
└── trigger_run_service.rb (modified)

spec/services/benchmark/
├── command_builders/
│   ├── base_spec.rb
│   ├── hpcg_command_builder_spec.rb
│   └── mlc_command_builder_spec.rb
└── trigger_run_service_spec.rb (add builder selection tests)
```

## Testing Strategy

Unit tests for each builder using Faker for dynamic test data:

```ruby
RSpec.describe Benchmark::CommandBuilders::MlcCommandBuilder do
  let(:run_id) { Faker::Alphanumeric.alphanumeric(number: 10) }
  let(:node_uuid) { Faker::Internet.uuid }
  let(:builder) do
    described_class.new(
      agent_bin: "/usr/local/bin/qis-agent",
      run_id: run_id,
      node_uuid: node_uuid,
      arguments: { "profile" => "full", "modules" => ["intel-mlc"] },
      server_url: "http://localhost:3000",
      token: Faker::Alphanumeric.alphanumeric(number: 32),
      log_path: nil
    )
  end

  describe "#build" do
    it "builds correct command" do
      cmd = builder.build
      expect(cmd).to include("qis-agent")
      expect(cmd).to include("--node-uuid #{node_uuid}")
      expect(cmd).to include("mlc")
      expect(cmd).to include("--id #{run_id}")
      expect(cmd).to include("--profile full")
      expect(cmd).to include("--module intel-mlc")
      expect(cmd).not_to include("--build")
    end
  end
end
```

## Backwards Compatibility

- Default subcommand is `"hpcg"` so existing recipes without explicit command continue working
- HPCG command builder preserves current defaults (`make arch=Linux_OpenMP`, `./bin/xhpcg`)
