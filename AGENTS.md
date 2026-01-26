# Repository Guidelines

## Project Structure & Module Organization
- `app/`: Rails application code (models, controllers, views, jobs, mailers).
- `spec/`: RSpec test suite (including system specs with Capybara).
- `agent/`: Go-based `hpc-agent` CLI for node collection and benchmarks.
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
- `cd agent && go build -o hpc-agent .`: build the Go CLI.

## Coding Style & Naming Conventions
- Ruby: 2-space indentation, Rails conventions, Rubocop (Rails Omakase).
- Go: `gofmt`-formatted code and standard Go naming.
- Files: snake_case for Ruby files (`node_config.rb`), CamelCase classes.
- Specs: `*_spec.rb` naming, mirroring `app/` paths (e.g., `spec/models/node_spec.rb`).

## Testing Guidelines
- Primary frameworks: RSpec + FactoryBot; system tests use Capybara.
- Prefer focused specs; add system specs for end-to-end UI behavior.
- Run targeted specs while iterating; full suite before PR.

## Commit & Pull Request Guidelines
- Commit style follows Conventional Commits with optional scopes  
  Examples: `feat(tasks): add TasksController`, `docs: update PRD`.
- PRs should include: concise summary, testing notes, and linked issue (if any).
- Include screenshots or screen recordings for UI changes.
- Call out migrations, new env vars, or agent CLI changes explicitly.

## Security & Configuration Tips
- SSH settings live in Rails credentials or env vars (`SSH_USER`, `SSH_KEY_PATH`, etc.).
- Avoid committing secrets; use `bin/rails credentials:edit` for updates.

## Task Implementation with Subagents
- Always use subagents (Task tool) when implementing tasks.
- Launch multiple subagents in parallel for independent tasks to maximize efficiency.
- Use appropriate subagent types:
  - `Explore`: For codebase exploration and understanding structure.
  - `Plan`: For designing implementation strategies.
  - `Bash`: For git operations and command execution.
  - `general-purpose`: For orchestrating multi-step workflows that may involve other subagent types.
- Provide clear, detailed prompts so subagents can work autonomously.
- Review subagent results and summarize findings for the user.
