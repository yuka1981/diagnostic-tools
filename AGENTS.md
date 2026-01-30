# Repository Guidelines

## Project Structure & Module Organization
- `app/`: Rails application code (models, controllers, views, jobs, mailers).
- `spec/`: RSpec test suite (including system specs with Capybara).
- `agent/`: Go-based `qis-agent` CLI for node collection and benchmarks.
- `config/`, `db/`, `lib/`: Rails configuration, migrations/schema, and shared libs.
- `scripts/`: helper scripts (e.g., `scripts/run_hpcg_from_source.sh`).
- `public/`, `storage/`, `tmp/`: assets, uploads, and transient files.

## Build, Test, and Development Commands
- `bundle install`: install Ruby dependencies.
- `bin/rails db:create db:migrate`: initialize the PostgreSQL database.
- `bin/dev`: run the Rails server + Tailwind watcher (Procfile in `Procfile.dev`).
- `bin/rspec`: run the full RSpec suite (use `bin/rspec spec/...` for a file).
- `COVERAGE=true bin/rspec`: generate a coverage report.
- `bin/rubocop`: lint Ruby code; `bin/rubocop -a` auto-fixes.
- `bin/brakeman`: Rails security scan.
- `cd agent && go build -o qis-agent .`: build the Go CLI.

## Coding Style & Naming Conventions
- Ruby: 2-space indentation, Rails conventions, Rubocop (Rails Omakase).
- Go: `gofmt`-formatted code and standard Go naming.
- Files: snake_case for Ruby files (`node_config.rb`), CamelCase classes.
- Specs: `*_spec.rb` naming, mirroring `app/` paths (e.g., `spec/models/node_spec.rb`).

## Testing Guidelines
- Primary frameworks: RSpec + FactoryBot; system tests use Capybara.
- Prefer focused specs; add system specs for end-to-end UI behavior.
- Run targeted specs while iterating; full suite before PR.

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

## Commit & Pull Request Guidelines
- Commit style follows Conventional Commits with optional scopes
  Examples: `feat(tasks): add TasksController`, `docs: update PRD`.
- PRs should include: concise summary, testing notes, and linked issue (if any).
- Include screenshots or screen recordings for UI changes.
- Call out migrations, new env vars, or agent CLI changes explicitly.

## Security & Configuration Tips
- SSH settings live in Rails credentials or env vars (`SSH_USER`, `SSH_KEY_PATH`, etc.).
- Avoid committing secrets; use `bin/rails credentials:edit` for updates.
