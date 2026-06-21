# Standalone SELECT Rule Design

## Status
Implemented (v1).

## Problem Statement
Today, rule execution expects source values to come from source-context metadata and optional scalar projection expressions. For some use cases, this creates unnecessary modeling overhead when a rule can be fully expressed as one SQL query. The engine needs a rule mode that allows a complete standalone SELECT statement while preserving existing run orchestration, auditability, consolidation, and deterministic target execution.

## Goals
1. Allow a rule to be implemented as one complete SQL query.
2. Remove mandatory dependency on md_rule_source_context and md_rule_input_expr for this rule mode.
3. Derive rule output aliases from SELECT result column names.
4. Enforce SELECT-only guardrails (no DML/DDL/PLSQL block execution).
5. Keep downstream behavior unchanged: target value persistence, consolidation, and consolidated execution.
6. Preserve diagnosability through run traces and action/value runtime tables.

## Non-Goals
1. No change to ingestion path for md_change_event_raw.
2. No cross-run caching or query result reuse.
3. No redesign of consolidation precedence semantics.
4. No replacement of existing EXPRESSION/LOOKUP/COLUMN_TO_ROW/PLSQL_FUNC rule types.

## Scope

### In Scope
1. New rule type for standalone SQL query execution.
2. Metadata contract for storing query text and execution constraints.
3. Runtime executor branch to run query and derive outputs from returned columns.
4. Guardrails to validate SELECT-only query payload.
5. New smoke coverage for happy path, guardrails, and row-cardinality behavior.

### Out Of Scope
1. Reworking source-context resolver behavior for existing rule types.
2. Changing existing md_rule_output semantics for non-standalone rule types.
3. Introducing multi-row output expansion in this first release.

## Functional Contract

### Rule Type And Payload
1. Add new md_rule.rule_type value: SQL_SELECT.
2. For SQL_SELECT, md_rule.rule_payload is JSON and stores query text in sql_query (plus enable_token_substitution flag).
3. Query must represent one SQL query statement whose top-level operation is SELECT (WITH ... SELECT is allowed if enabled by guardrails).

### Input Dependencies
1. md_rule_source_context is optional and not required for SQL_SELECT.
2. md_rule_input_expr is optional and not required for SQL_SELECT.
3. md_rule_input remains required for direct-column selector eligibility in the current selector design.
4. Existing token families may still be used in SQL text (SRC, alias, PARAM, OLD, NEW) if substitution is enabled for this mode.

### Output Derivation
1. Output aliases are derived from query result column names.
2. Alias normalization follows current engine conventions used for output lookup (case-insensitive compare with normalized storage).
3. Derived alias/value pairs are treated as the rule outputs for persistence and target mapping resolution.

### Cardinality Contract
1. SQL_SELECT query must return exactly one row per rule execution.
2. Zero rows is a rule failure.
3. More than one row is a rule failure.
4. Failure reason must be persisted and traceable in existing runtime diagnostics.

## Guardrails

### Statement Type Guardrails
1. Allowed statement class: query-only.
2. Blocked statements and operations include:
   1. INSERT
   2. UPDATE
   3. DELETE
   4. MERGE
   5. CREATE
   6. ALTER
   7. DROP
   8. TRUNCATE
   9. GRANT
   10. REVOKE
3. Block PL/SQL anonymous blocks and procedural wrappers (BEGIN/DECLARE/END execution blocks).
4. Block script delimiters and SQL*Plus command patterns in payload.

### Allowed SQL Constructs
1. SELECT with joins and subqueries.
2. UNION and UNION ALL.
3. SQL built-in functions and analytic/window functions.
4. PL/SQL functions callable from SQL expressions, subject to database privileges and existing governance.
5. Common table expressions (WITH clause), if feature flag ENABLE_SQL_SELECT_WITH is true.

### Safety/Validation Rules
1. Validate query text before dynamic execution.
2. Apply token substitution in a controlled order consistent with existing executor semantics.
3. Preserve logging of generated SQL text for diagnostics in md_impact_trace and/or runtime action traces.
4. Reject payload when guardrails fail with explicit error code and message.

## Metadata Changes

### Core Metadata
1. Extend md_rule.rule_type domain to include SQL_SELECT.
2. Reuse md_rule.rule_payload JSON for v1 and store SQL_SELECT query in payload.sql_query.
3. Optional v2 hardening: add dedicated md_rule_sql_select metadata table if stronger lifecycle/versioning separation is needed.

### Optional Metadata Flags (Recommended)
1. md_rule.sql_select_requires_single_row_flag default Y.
2. md_rule.sql_select_with_clause_enabled_flag default Y.
3. md_rule.sql_select_token_substitution_flag default Y.

Note: These flags are not implemented in v1; current behavior uses payload.enable_token_substitution and fixed one-row guardrails.

### Compatibility Expectations
1. Existing rule types are unaffected.
2. Existing metadata scripts for non-SQL_SELECT rules remain valid.
3. Existing target mapping tables (md_rule_target_action/key_map/column_map) continue to drive final target writes.

## Runtime Flow Changes

### High-Level Flow Delta
Current:
1. Select rule.
2. Resolve source context and scalar projections.
3. Evaluate outputs via configured rule path.
4. Persist target values.
5. Consolidate and execute consolidated target actions.

Target for SQL_SELECT:
1. Select rule.
2. If rule_type = SQL_SELECT, bypass source-context graph dependency and scalar-projection dependency.
3. Selector eligibility still uses md_rule_input in the current selector architecture.
4. Validate and execute standalone SELECT query.
5. Derive outputs from returned columns.
6. Persist target values using existing persist_target_value path.
7. Consolidate and execute consolidated target actions using existing logic.

### Package-Level Change Points
1. md_rule_executor_pkg.dispatch_rule_execution:
   1. Add SQL_SELECT branch.
2. md_rule_executor_pkg (new helper suggested):
   1. validate_sql_select_payload
   2. execute_sql_select_and_collect_outputs
   3. normalize_sql_select_output_alias
3. md_source_context_resolver_pkg:
   1. No required change for SQL_SELECT path if bypassed cleanly in orchestrator.

### Observability Expectations
1. On success:
   1. md_run_target_value includes computed values derived from SQL_SELECT result columns.
   2. Consolidation/runtime action traces behave identically to other rule types.
2. On failure:
   1. Rule failure contributes to run error messages and/or FAILED statuses per existing execute_run semantics.
   2. Guardrail/cardinality failures are traceable with clear reason text.

## Error Handling Contract

### New Error Conditions (Proposed)
1. Invalid statement class (non-query payload).
2. Blocked keyword/construct detected by guardrails.
3. SQL_SELECT returned zero rows.
4. SQL_SELECT returned multiple rows.
5. Output alias collision after normalization.

### Error Behavior
1. Rule-level failure follows existing per-rule continuation model in execute_run.
2. Consolidation continues for other successful rules.
3. Run final status semantics remain unchanged.

## Backward Compatibility
1. No behavior change for existing rules not using SQL_SELECT.
2. Existing smoke scripts 060, 061, 064, 066, 067, 068, 069, 073 must continue to pass unchanged.
3. New SQL_SELECT smoke is additive.

## Acceptance Criteria
1. A rule with rule_type = SQL_SELECT executes using md_rule.rule_payload.sql_query.
2. SQL_SELECT rule executes successfully without md_rule_source_context or md_rule_input_expr rows.
3. SQL_SELECT direct-column selector eligibility remains dependent on md_rule_input rows in current implementation.
4. Output aliases are derived from returned SELECT column names and are usable by target mappings.
5. Guardrails reject non-SELECT statements with explicit failure diagnostics.
6. UNION and SQL function usage is supported in SQL_SELECT payload.
7. PL/SQL functions callable from SQL are supported in SQL_SELECT payload.
8. Zero-row and multi-row SQL_SELECT results fail deterministically with clear reason.
9. Successful SQL_SELECT outputs are persisted and participate in consolidation with existing precedence rules.
10. Consolidated target execution remains winners-only and recorded with execution_phase = CONSOLIDATED_EXECUTION.
11. Baseline smoke sequence (060, 061, 064, 066, 067, 068, 069, 073) passes after implementation.
12. New SQL_SELECT smoke passes for happy path, guardrail failures, and cardinality failures.

## Validation Plan
1. Run baseline sequence:
   1. sql/scripts/060_md_selector_smoke.sql
   2. sql/scripts/061_md_cross_entity_context_smoke.sql
   3. sql/scripts/064_md_runtime_params_smoke_combined.sql
   4. sql/scripts/066_md_target_dml_smoke.sql
   5. sql/scripts/073_md_target_consolidation_smoke.sql
   6. sql/scripts/067_md_rule_selection_gate_smoke.sql
   7. sql/scripts/068_md_expr_validator_smoke.sql
   8. sql/scripts/069_md_expr_function_registry_smoke.sql
2. Add new targeted smoke: sql/scripts/074_md_sql_select_rule_smoke.sql covering:
   1. Basic SELECT success with alias derivation.
   2. UNION ALL success.
   3. SQL built-in function success.
   4. PL/SQL function call success.
   5. Blocked DML payload failure.
   6. Zero-row failure.
   7. Multi-row failure.

## Open Decisions
1. Whether WITH clause should be enabled by default in v1.
2. Whether SQL_SELECT should participate in md_expr_allowed_function governance, or use a separate governance table.
3. Whether alias derivation should preserve exact case or normalize to upper-case.
4. Whether to introduce dedicated SQL_SELECT metadata table in v1 or defer to v2.

## Evidence References
1. docs/engine-docs-index.md
2. docs/system-architecture.md
3. docs/runtime-flow-and-dynamic-sql.md
4. docs/metadata-schema-reference.md
5. docs/change-impact-playbook.md
6. docs/error-handling-and-observability.md
7. plsql/packages/md_rule_executor_pkg.pkb
8. plsql/packages/md_source_context_resolver_pkg.pkb
9. sql/scripts/010_md_core.sql
10. sql/scripts/020_md_runtime.sql
11. sql/scripts/060_md_selector_smoke.sql
12. sql/scripts/061_md_cross_entity_context_smoke.sql
13. sql/scripts/064_md_runtime_params_smoke_combined.sql
14. sql/scripts/066_md_target_dml_smoke.sql
15. sql/scripts/067_md_rule_selection_gate_smoke.sql
16. sql/scripts/068_md_expr_validator_smoke.sql
17. sql/scripts/069_md_expr_function_registry_smoke.sql
18. sql/scripts/073_md_target_consolidation_smoke.sql
