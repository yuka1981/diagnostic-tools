# AGENTS.md Workflow Update Design

**Date:** 2026-01-30
**Status:** Draft
**Author:** Claude Code

## Overview

Update AGENTS.md with two structural changes: (1) replace the "Task Implementation with Subagents" section with a strict whitelist-based context management model for the main agent, and (2) add a 5-stage development workflow for non-trivial tasks.

The goal is to enforce the main agent as a pure orchestrator that never directly reads, writes, searches, or executes commands. All heavy work flows through subagents.

## Current State

AGENTS.md section 7 ("Task Implementation with Subagents") contains loose guidance:

```markdown
## Task Implementation with Subagents
- Always use subagents (Task tool) when implementing tasks.
- Launch multiple subagents in parallel for independent tasks to maximize efficiency.
- Use appropriate subagent types:
  - `Explore`: For codebase exploration and understanding structure.
  - `Plan`: For designing implementation strategies.
  - `Bash`: For git operations and command execution.
  - `general-purpose`: For orchestrating multi-step workflows...
- Provide clear, detailed prompts so subagents can work autonomously.
- Review subagent results and summarize findings for the user.
```

Problems with the current approach:
- No enforcement that the main agent avoids direct tool use
- No defined workflow stages for planning, review, and execution
- No criteria for when the full workflow can be skipped

## Change 1: Main Agent Context Management (Whitelist Approach)

Replace "Task Implementation with Subagents" with a new section titled "Main Agent Context Management."

### Principle

The main agent is an orchestrator. It delegates all file I/O, search, and command execution to subagents. It never touches the filesystem or shell directly.

### Main Agent Whitelist

These are the only tools the main agent may use directly:

| Tool | Purpose |
|------|---------|
| `AskUserQuestion` | Gather requirements and decisions from the user |
| `Task` | Launch subagents (primary orchestration tool) |
| `TaskCreate` / `TaskUpdate` / `TaskList` / `TaskGet` | Manage the todo list |
| `Skill` | Invoke skills (brainstorming, writing-plans, etc.) |
| `EnterPlanMode` / `ExitPlanMode` | Plan mode transitions |

The main agent may also communicate directly with the user via text responses. This does not require delegation.

### Delegation Rules

Everything not on the whitelist must be delegated to a subagent:

| Operation | Subagent Type |
|-----------|---------------|
| File reading | `Explore` |
| File writing / editing | `general-purpose` or `Bash` |
| Grep / Glob searches | `Explore` |
| Git operations | `Bash` |
| Running tests / lint | `Bash` |
| Web searches / fetches | `general-purpose` |
| Design/architecture analysis | `Plan` |

`WebSearch` and `WebFetch` are delegated to `general-purpose` subagents to keep the main agent's context clean and focused on orchestration.

If a subagent fails or returns unexpected results, the main agent should inform the user and either retry with a refined prompt or ask for guidance.

### Rationale

- Forces the main agent to maintain a high-level view of the task
- Prevents the main agent from getting lost in implementation details
- Subagents receive focused prompts and operate autonomously within their scope
- The main agent's context window stays clean for orchestration decisions

## Change 2: Development Workflow for Non-Trivial Tasks

Add a new section titled "Development Workflow" immediately after "Main Agent Context Management."

### 5-Stage Pipeline

```
Stage 1          Stage 2          Stage 3          Stage 4          Stage 5
Brainstorming -> Write Docs   -> Review Docs  -> Fix Issues   -> Implement
                                      ^               |
                                      |               |
                                      +--- re-review--+
                                     (if significant changes)
```

### Stage 1: Brainstorming

- Invoke `superpowers:brainstorming` skill
- Main agent asks clarifying questions via `AskUserQuestion`
- `Explore` and `Plan` subagents gather codebase context and analyze architecture as needed
- **Output:** Shared understanding of what to build

### Stage 2: Write Implementation Document

- Invoke `superpowers:writing-plans` skill
- A `general-purpose` subagent writes the design doc to `docs/plans/YYYY-MM-DD-<topic>-design.md`
- Another `general-purpose` subagent writes the implementation plan to `docs/plans/YYYY-MM-DD-<topic>-implementation.md`
- Both subagents can run in parallel since they produce independent documents
- For medium-complexity tasks where design and implementation details can be covered concisely, a single combined document is acceptable

### Stage 3: Review the Implementation Document

- Invoke `superpowers:code-reviewer` subagent to review both documents
- The reviewer checks for:
  - Completeness: are all requirements addressed?
  - Consistency: do the design and implementation docs agree?
  - Missing edge cases: error handling, validation, rollback scenarios
  - Alignment with existing patterns: naming, file structure, test conventions
- **Output:** List of issues or explicit approval

### Stage 4: Fix Issues

- A `general-purpose` subagent addresses each issue found in the review
- If changes are significant (new models, changed APIs, altered data flow), loop back to Stage 3 for re-review
- Minor fixes (typos, clarifications, missing details) do not require re-review
- If re-review is needed more than twice, escalate to the user for a decision on whether to proceed or adjust scope

### Stage 5: Ready to Implement

- Main agent confirms the plan is approved and ready
- Invoke `superpowers:subagent-driven-development` or `superpowers:executing-plans` to execute the approved plan
- Implementation subagents reference the design and implementation docs as their source of truth
- Before marking implementation as complete, subagents must pass all quality gates defined in CLAUDE.md (rubocop, rspec for Rails; golangci-lint, go test for Go)

### Simple Task Exemption

Skip stages 1 through 4 when ALL of these conditions are true:

| Condition | Rationale |
|-----------|-----------|
| The change is obvious and well-defined (no ambiguity) | No brainstorming needed |
| The total number of files created or modified (including test files) is fewer than 3 | Scope is small enough to hold in one subagent's context |
| No new models, migrations, or architectural decisions | No design decisions to review |
| No new dependencies or API changes | No integration risk |

When the exemption applies, the main agent still delegates execution to subagents but proceeds directly to implementation without producing design documents.

## Updated AGENTS.md Section Order

| # | Section | Status |
|---|---------|--------|
| 1 | Project Structure & Module Organization | Existing, unchanged |
| 2 | Build, Test, and Development Commands | Existing, unchanged |
| 3 | Coding Style & Naming Conventions | Existing, unchanged |
| 4 | Testing Guidelines | Existing, unchanged |
| 5 | **Main Agent Context Management** | New (replaces "Task Implementation with Subagents") |
| 6 | **Development Workflow** | New |
| 7 | Commit & Pull Request Guidelines | Existing, unchanged |
| 8 | Security & Configuration Tips | Existing, unchanged |

## Concrete AGENTS.md Diff

The change removes the existing "Task Implementation with Subagents" section (lines 43-52) and inserts two new sections between "Testing Guidelines" and "Commit & Pull Request Guidelines."

### Section 5: Main Agent Context Management (new content)

```markdown
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
```

### Section 6: Development Workflow (new content)

```markdown
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
```

## Impact

- **Main agent behavior:** Strictly limited to orchestration. No more direct file reads or bash commands from the top-level agent.
- **Subagent usage:** Unchanged. Subagents continue to use all available tools within their scope.
- **Existing sections:** Sections 1-4 are unchanged in content; sections 5-6 (Commit/PR Guidelines and Security/Configuration Tips) are unchanged in content but shift to positions 7-8.
- **Workflow overhead:** The 5-stage pipeline adds planning and review steps. The simple task exemption prevents this from slowing down trivial changes.
