# Target Consolidation Design

## Status
Draft for implementation.

## Problem Statement
When multiple selected rules execute for the same change event, they can target the same metadata target entity. The engine must preserve per-rule output auditability while producing one deterministic consolidated execution plan per target entity and target key.

## Goals
1. Keep per-rule outputs fully auditable.
2. Consolidate target writes by target entity for each run and change event.
3. Resolve collisions with deterministic precedence.
4. Execute final SQL from consolidated winners only.
5. Continue consolidation for a target entity even if one rule fails.

## Confirmed Decisions
1. Grouping key for same target table is metadata `target_entity_name`.
2. Rule priority lives on `md_rule` and is optional.
3. Effective priority is `nvl(rule_priority_no, 0)`.
4. Collision precedence is:
   1. Higher effective priority wins.
   2. If equal priority, higher `rule_id` wins.
5. Consolidated artifact stores winning values only.
6. Final executed SQL is generated only from consolidated artifact.
7. Existing per-rule runtime rows remain in place.
8. If one rule fails for a target entity, consolidation continues for other rules.

## Scope
### In Scope
1. Metadata extension on `md_rule` for optional priority.
2. New runtime consolidation artifacts.
3. Orchestrator changes in `md_rule_executor_pkg` to consolidate incrementally and execute consolidated plan.
4. Smoke coverage for multi-rule consolidation and deterministic conflict handling.

### Out Of Scope
1. External orchestration changes outside `execute_run` contract.
2. Changes to ingestion path for raw change events.
3. Cross-run consolidation.

## Data Model Changes
### Metadata
1. Add `md_rule.rule_priority_no number null`.
2. Priority semantics:
   1. Effective priority: `nvl(rule_priority_no, 0)`.

### Runtime
1. Add `md_run_target_consolidation` (header per target key).
2. Add `md_run_target_consolidated_value` (winner per target column).
3. Extend `md_run_target_action` with optional link to consolidation header and execution phase marker.

## Consolidation Key Model
1. Consolidation header key:
   1. `tenant_id`
   2. `context_id`
   3. `run_id`
   4. `change_event_id`
   5. `target_entity_name`
   6. `target_key_hash`
2. Winner cell key:
   1. Header key + `target_column_name`

## Precedence Contract
Candidates for the same winner cell are ordered by:
1. `nvl(rule_priority_no, 0) desc`
2. `rule_id desc`

The first candidate in this order is the winner.

## Runtime Flow Changes
### Before
1. Per-rule output evaluated.
2. Per-rule output persisted.
3. Target SQL executed from per-rule path.

### After
1. Per-rule output evaluated.
2. Per-rule output persisted to existing runtime tables.
3. Per-rule candidate values merged into consolidation artifact.
4. After rule loop, final SQL generated and executed from consolidated winners only.

## Auditability Contract
1. Per-rule outputs remain in `md_run_target_value`.
2. Consolidated winners are in `md_run_target_consolidation` and `md_run_target_consolidated_value`.
3. Final execution outcomes remain in `md_run_target_action` and are marked as consolidated execution phase.

## Failure Semantics
1. Rule-level failures continue to be logged at per-rule level.
2. Consolidation continues for other successful rules for the same target entity.
3. Consolidation status should reflect partial outcomes when failures occurred.

## Determinism And Idempotency
1. Deterministic winner selection depends on fixed ordering by priority and rule_id.
2. Consolidation upserts must use stable unique keys and fingerprints to avoid duplicates.

## Implementation Notes
1. Add helper routines in `md_rule_executor_pkg`:
   1. Resolve effective priority.
   2. Upsert consolidation header.
   3. Upsert winner cell by precedence.
   4. Execute consolidated actions.
2. Keep public package signatures stable where possible.

## Migration Plan
1. Apply metadata upgrade script for `md_rule` priority.
2. Apply runtime upgrade script for consolidation artifacts.
3. Deploy package body updates.
4. Run smoke suite including new consolidation smoke script.

## Validation Plan
1. Re-run baseline smoke scripts:
   1. `060_md_selector_smoke.sql`
   2. `061_md_cross_entity_context_smoke.sql`
   3. `064_md_runtime_params_smoke_combined.sql`
   4. `066_md_target_dml_smoke.sql`
   5. `067_md_rule_selection_gate_smoke.sql`
   6. `068_md_expr_validator_smoke.sql`
   7. `069_md_expr_function_registry_smoke.sql`
2. Add and run `073_md_target_consolidation_smoke.sql`.

## Acceptance Criteria
1. Per-rule rows are present for all attempted rule outputs.
2. Consolidated artifact stores only winning values.
3. Collision winner follows `nvl(priority,0) desc, rule_id desc`.
4. Final SQL is executed from consolidated winners only.
5. Rule failure does not prevent consolidation from other rules.
6. New smoke and baseline smokes pass.
