# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

HPC System Detection & Benchmark Tool - A web application for monitoring HPC cluster nodes and managing benchmark runs. Consists of two main components:

1. **Web Application (Rails)**: Dashboard for node inventory, benchmark management, and visualization
2. **Agent (Go)**: CLI tool deployed on compute nodes for system info collection and benchmark execution

## Development Commands

### Rails Backend

```bash
# Start development server
bin/dev

# Run all tests
bin/rspec

# Run specific test
bin/rspec spec/models/node_spec.rb

# Lint
bin/rubocop -f github

# Auto-fix lint issues
bin/rubocop -a

# Security scan
bin/brakeman

# Database operations
bin/rails db:migrate
bin/rails db:rollback
```

### Go Agent (run from `agent/` directory)

```bash
cd agent

# Build
go build -o qis-agent .

# Run tests
go test ./...

# Lint
golangci-lint run
```

## Architecture

### Rails Application (Hotwire + Tailwind)

- **Framework**: Rails 7.2.3 with Hotwire (Turbo + Stimulus)
- **Database**: PostgreSQL 16+
- **Styling**: Tailwind CSS with NetBox-inspired design (slate sidebar, teal accents)
- **Testing**: RSpec with FactoryBot and Capybara

Key directories:
- `app/services/` - Business logic (SSH collection, inventory services)
- `app/jobs/` - Background jobs for async operations
- `app/components/` - ViewComponents
- `app/views/shared/` - Reusable partials including sidebar and modals

### Go Agent (Cobra CLI)

- **Framework**: Cobra for CLI
- **Module**: `github.com/yuka1981/diagnostic-tools/agent`

Key directories:
- `agent/cmd/` - CLI commands (collect, inventory push, hpcg)
- `agent/core/model/` - Data structures for inventory
- `agent/core/ports/` - Interface definitions
- `agent/inventory/collector/linux/` - System info collectors (CPU, memory, disk, network, DMI)
- `agent/hpcg/` - HPCG benchmark workflow

Agent commands:
- `qis-agent collect` - Output system info JSON to stdout
- `qis-agent inventory push --server URL --token TOKEN` - Push inventory to API
- `qis-agent hpcg` - Run HPCG benchmark workflow

### Data Flow

1. **Pull (Server-initiated)**: Rails SSH to Admin Node → Admin Node SSH to Compute Node → `qis-agent collect` → JSON returned → DB update
2. **Push (Agent-initiated)**: Agent runs `qis-agent inventory push` → POST to Rails API → DB update
3. **Benchmarks**: Slurm Job triggers Agent → Agent builds/runs benchmark → Results uploaded to API + artifacts to shared storage

### Node State Versioning

Each inventory collection creates a new `node_state` record (versioned history), not overwrites. The latest record represents current state.

## Main Agent Context Management

The main agent operates as an orchestrator only. It must NOT directly read files,
write files, edit files, run bash commands, or perform grep/glob searches.
All such work is delegated to subagents.

### Whitelist (direct use by main agent)
- `AskUserQuestion` — gather requirements and decisions from the user
- `Task` — launch subagents (primary orchestration tool)
- `TaskCreate` / `TaskUpdate` / `TaskList` / `TaskGet` — manage the todo list
- `Skill` — invoke skills
- `EnterPlanMode` / `ExitPlanMode` — plan mode transitions

The main agent may also communicate directly with the user via text responses.
This does not require delegation.

### Delegation to subagents
- File reading → `Explore` subagent
- File writing / editing → `general-purpose` or `Bash` subagent
- Grep / Glob searches → `Explore` subagent
- Git operations → `Bash` subagent
- Running tests / lint → `Bash` subagent
- Web searches / fetches (`WebSearch`, `WebFetch`) → `general-purpose` subagent
- Design/architecture analysis → `Plan` subagent

If a subagent fails or returns unexpected results, the main agent should
inform the user and either retry with a refined prompt or ask for guidance.

### Subagent usage guidelines
- Launch multiple subagents in parallel for independent tasks.
- Provide clear, detailed prompts so subagents can work autonomously.
- Review subagent results and summarize findings for the user.

## Development Workflow

Non-trivial tasks follow a 5-stage pipeline. Simple tasks may skip to implementation.

### Stage 1 — Brainstorming
- Use `superpowers:brainstorming` skill.
- Main agent asks clarifying questions via `AskUserQuestion`.
- `Explore` and `Plan` subagents gather codebase context and analyze
  architecture as needed.
- Output: shared understanding of what to build.

### Stage 2 — Write Implementation Document
- Use `superpowers:writing-plans` skill.
- A `general-purpose` subagent writes the design doc to
  `docs/plans/YYYY-MM-DD-<topic>-design.md`.
- Another subagent writes the implementation plan to
  `docs/plans/YYYY-MM-DD-<topic>-implementation.md`.
- For medium-complexity tasks where design and implementation details can be
  covered concisely, a single combined document is acceptable.

### Stage 3 — Review
- Use `superpowers:code-reviewer` subagent to review both documents.
- Check for: completeness, consistency, missing edge cases, alignment with
  existing patterns.
- Output: list of issues or approval.

### Stage 4 — Fix Issues
- A `general-purpose` subagent addresses each review issue.
- If changes are significant, loop back to Stage 3 for re-review.
- If re-review is needed more than twice, escalate to the user for a decision
  on whether to proceed or adjust scope.

### Stage 5 — Implement
- Main agent confirms the plan is approved.
- Use `superpowers:subagent-driven-development` or `superpowers:executing-plans`
  to execute.
- Before marking implementation as complete, subagents must pass all quality
  gates defined in CLAUDE.md (rubocop, rspec for Rails; golangci-lint, go test
  for Go).

### Simple task exemption
Skip stages 1–4 when ALL of these are true:
- The change is obvious and well-defined (no ambiguity).
- The total number of files created or modified (including test files) is
  fewer than 3.
- No new models, migrations, or architectural decisions.
- No new dependencies or API changes.

The main agent still delegates execution to subagents but skips the
brainstorming/design doc/review stages.

## Quality Gates

Before committing, ensure:

**Rails**: `bin/rubocop -f github` (no offenses) AND `bin/rspec` (all green)

**Go**: `golangci-lint run` (no issues) AND `go test ./...` (all pass)

## Configuration

SSH settings via Rails credentials or environment variables:
- `SSH_USER`, `SSH_KEY_PATH`, `SSH_TIMEOUT`, `SSH_VERIFY_HOST_KEY`
- Jump host: `JUMP_HOST`, `JUMP_USER`, `JUMP_PORT`

Agent token via `AGENT_TOKEN` environment variable.
