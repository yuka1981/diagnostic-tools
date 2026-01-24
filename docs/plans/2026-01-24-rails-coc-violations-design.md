# Rails Convention over Configuration Violations

**Date:** 2026-01-24
**Status:** Implementation Complete
**Purpose:** Document Rails CoC violations found in codebase and plan remediation

## Overview

A comprehensive review of the HPC System Detection & Benchmark Tool Rails application identified several Convention over Configuration violations. This document catalogs the violations and provides a remediation plan.

## Critical Violations

### 1. Missing SshProfile Model

**Severity:** CRITICAL
**Location:** `db/schema.rb` defines `ssh_profiles` table, no corresponding model exists

The `ssh_profiles` table was created in migration `20260122024144_create_ssh_profiles.rb` with foreign key constraints, but `app/models/ssh_profile.rb` does not exist.

**Impact:** Orphaned table, potential runtime errors if code attempts to use the model.

**Fix:** Create the missing model or remove the table if unused.

### 2. Form Objects in Inconsistent Locations

**Severity:** HIGH
**Locations:**
- `app/models/benchmark/run_form.rb` - Wrong location
- `app/forms/profiling/run_form.rb` - Correct location

**Impact:** Inconsistent codebase structure, confusing for developers.

**Fix:** Move `Benchmark::RunForm` from `app/models/` to `app/forms/benchmark/run_form.rb`.

## High Severity Violations

### 3. Fat Controller - BenchmarkRunsController

**Severity:** HIGH
**Location:** `app/controllers/benchmark_runs_controller.rb:89-155`

The `download_artifact` action contains business logic:
- Path validation methods (`validated_artifact_path`, `validate_stored_path`, `validate_legacy_path`)
- MIME type mapping with 10+ case branches

**Fix:** Extract to `ArtifactIndex` model methods:
- `ArtifactIndex#safe_download_path` - validates and returns path
- `ArtifactIndex#mime_type` - returns MIME type for file

### 4. Fat Controller - API BenchmarkRunsController

**Severity:** HIGH
**Location:** `app/controllers/api/v1/benchmark_runs_controller.rb:82-121`

The `process_artifact_uploads` method handles file I/O, Base64 decoding, path sanitization, and database persistence.

**Fix:** Extract to `Artifacts::UploadService` with single responsibility.

### 5. Duplicate Validation Logic

**Severity:** HIGH
**Locations:**
- `app/models/node.rb:169-181` - `no_overlapping_nodes` validation
- `app/services/racks/validate_layout_service.rb:39-42` - Duplicated logic

**Fix:** Remove duplication from service, call model validation instead. Extract shared `ranges_overlap?` to a concern.

## Medium Severity Violations

### 6. Table Name Override

**Severity:** MEDIUM
**Location:** `app/models/server_rack.rb:4`

```ruby
self.table_name = "racks"
```

Model `ServerRack` overrides to use `racks` table instead of conventional `server_racks`.

**Fix:** This is acceptable if intentional, but consider renaming table in future migration for consistency.

### 7. Status Mapping in Controller

**Severity:** MEDIUM
**Location:** `app/controllers/api/v1/benchmark_runs_controller.rb:32-41`

Status mapping hash defined in controller action.

**Fix:** Move to model constant `BenchmarkRun::AGENT_STATUS_MAP` with class method `BenchmarkRun.status_from_agent(status)`.

### 8. Query Logic in Controllers

**Severity:** MEDIUM
**Locations:**
- `app/controllers/dashboard_controller.rb:26-29`

Query composition in controller instead of named scopes.

**Fix:** Create `BenchmarkRun.recent_for_dashboard(node = nil)` scope.

### 9. Duplicate Utility Method

**Severity:** MEDIUM
**Locations:**
- `app/models/node.rb:183`
- `app/services/racks/validate_layout_service.rb:71`

Both define identical `ranges_overlap?` method.

**Fix:** Extract to `app/models/concerns/range_overlap.rb` and include in both.

### 10. Service Duplicates Model Validation

**Severity:** MEDIUM
**Location:** `app/services/inventory/import_csv_service.rb:89-130`

Role validation logic duplicates Node model validation.

**Fix:** Remove validation logic from service, let model validations handle it via `node.save`.

### 11. Inconsistent Column Naming

**Severity:** MEDIUM
**Location:** `db/schema.rb` - `ssh_settings` vs `ssh_profiles` tables

- `ssh_settings`: `bastion_host`, `bastion_port`
- `ssh_profiles`: `jump_host`, `jump_port`

**Fix:** Standardize on one term (recommend `jump_*` as more common in SSH terminology).

### 12. Non-Standard Column Names

**Severity:** MEDIUM
**Location:** `db/schema.rb` - `racks` table

- `u_height` should be `unit_height`
- `desc_units` should be `descending_units`
- `width_mm`, `depth_mm`, `max_weight_kg` embed units in names

**Fix:** Consider renaming in future migration for clarity, or document units elsewhere.

## Summary

| Priority | Count | Description |
|----------|-------|-------------|
| CRITICAL | 1 | Missing model file |
| HIGH | 4 | Fat controllers, duplicate validation, form location |
| MEDIUM | 7 | Naming, scopes, DRY violations |

## Implementation Priority

1. **Immediate:** Create missing `SshProfile` model (or drop table)
2. **High:** Fix form object location, extract controller logic to models/services
3. **Medium:** Refactor duplicated code, add missing scopes
4. **Low:** Column renaming (requires migration, can defer)

## Files Affected

- `app/models/ssh_profile.rb` - CREATE
- `app/models/benchmark/run_form.rb` - MOVE to `app/forms/`
- `app/models/artifact_index.rb` - ADD methods
- `app/models/benchmark_run.rb` - ADD constant and method
- `app/models/concerns/range_overlap.rb` - CREATE
- `app/models/node.rb` - REFACTOR to use concern
- `app/controllers/benchmark_runs_controller.rb` - REFACTOR
- `app/controllers/api/v1/benchmark_runs_controller.rb` - REFACTOR
- `app/services/racks/validate_layout_service.rb` - REFACTOR
- `app/services/inventory/import_csv_service.rb` - REFACTOR
- `app/services/artifacts/upload_service.rb` - CREATE
