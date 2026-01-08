# AGENT.md - Project Guidelines & Rules

## 🛡️ Quality Assurance Protocols (Strict)

**CRITICAL RULE:** The following checks must be **PASSING** before any:

1. `git commit`
2. `git push`
3. Pull Request creation

### 🔧 Command Reference

Depending on which part of the stack you are modifying, run the following commands to verify system integrity:

#### 💎 Ruby on Rails Backend

| Type | Command | Requirement |
| :--- | :--- | :--- |
| **Lint** | `bin/rubocop -f github` | Must report **no offenses**. |
| **Test** | `bin/rspec` | All examples must be **green**. |

#### 🐹 Go Agent

| Type | Command | Requirement |
| :--- | :--- | :--- |
| **Lint** | `golangci-lint run` | Must report **no issues**. |
| **Test** | `go test ./...` | All tests must **pass**. |

> *Note: If modifying both stacks, ALL commands above must pass.*

---

## 🤖 AI Interaction Guidelines

When assisting with this project, **Gemini must**:

1. **Validation Check:** Before suggesting a commit message or summarizing a PR, explicitly ask:
    > *"Did `bin/rspec` and `bin/rubocop` (for Rails) or `go test` and `golangci-lint` (for Go) pass without errors?"*
2. **Code Generation:** Ensure generated Ruby code is RuboCop compliant and Go code satisfies standard `golangci-lint` rules (e.g., error handling, formatting).
3. **TDD Workflow:** When asked to implement a feature, prioritize creating the `rspec` or `go test` case first.
