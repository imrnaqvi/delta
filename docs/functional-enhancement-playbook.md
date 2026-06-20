# Functional Enhancement Playbook

This playbook is tailored to this repository and the generated docs set.

## Goal
Deliver functional enhancements safely across metadata, orchestration packages, dynamic SQL paths, and smoke-validation coverage.

## Inputs You Already Have
1. docs/engine-docs-index.md
2. docs/system-architecture.md
3. docs/metadata-schema-reference.md
4. docs/package-api-reference.md
5. docs/runtime-flow-and-dynamic-sql.md
6. docs/error-handling-and-observability.md
7. docs/change-impact-playbook.md
8. docs/implementation-readiness-summary.md

## Enhancement Lifecycle

### Phase 1: Triage (10-20 min)
1. Read docs/engine-docs-index.md and docs/change-impact-playbook.md.
2. Classify change type:
   - Metadata-only
   - Package behavior change
   - Dynamic SQL/token behavior change
   - Gate/params/context semantics change
3. Fill sections 1-3 in docs/functional-enhancement-template.md.

Exit criteria:
- Affected tables, packages, and smoke scripts are identified.

### Phase 2: Design (20-45 min)
1. Use docs/system-architecture.md to map where in execute_run flow the change lands.
2. Use docs/metadata-schema-reference.md to evaluate schema risk and constraints.
3. Use docs/package-api-reference.md to identify caller/callee and side effects.
4. Document decisions in template section 4.

Exit criteria:
- Current vs Target behavior is explicit and bounded.

### Phase 3: Implementation Plan (15-30 min)
1. Write exact edit list by file:
   - plsql/packages/*.pks/.pkb
   - sql/scripts/* (if needed)
2. Use docs/runtime-flow-and-dynamic-sql.md token map to avoid substitution drift.
3. Use docs/error-handling-and-observability.md to keep status/error/diagnostics behavior consistent.
4. Complete template sections 5-7.

Exit criteria:
- Stepwise implementation plan is complete with diagnostics strategy.

### Phase 4: Build + Validate
1. Implement smallest safe change set.
2. Run required smoke sequence from docs/change-impact-playbook.md:
   - 060
   - 061
   - 064
   - 066
   - 067
   - 068
   - 069
3. Add targeted script checks for changed feature.
4. Complete template section 8 with concrete evidence.

Exit criteria:
- Required smoke scripts pass and targeted checks pass.

### Phase 5: Release Readiness
1. Review docs/implementation-readiness-summary.md for relevant hardening items.
2. Apply at least one low-effort hardening improvement if risk justifies.
3. Complete template sections 9-11.

Exit criteria:
- Ready-to-implement gate is YES and rollback plan is documented.

## Repo-Specific Design Guardrails

### Metadata Guardrails
- Respect constraints in sql/scripts/010_md_core.sql and sql/scripts/020_md_runtime.sql.
- Treat md_rule, md_rule_input, md_rule_output, md_run_selected_rule, md_run_target_action, and md_run_target_value as high-change-risk entities.

### Orchestration Guardrails
- Keep execute_run ordering intact unless explicitly changing architecture.
- Preserve md_run_selected_rule gate status update semantics.
- Preserve idempotency behavior in persist_target_value and action/value fingerprints.

### Token/Dynamic SQL Guardrails
- output_expr path:
  - substitution in md_expr_executor_pkg (SRC/alias/PARAM)
- gate/mapping path:
  - substitution in md_rule_executor_pkg (SRC/alias/PARAM + OLD/NEW)
- If changing token behavior, test both paths.

### Error/Observability Guardrails
- Keep existing status patterns (COMPUTED/FAILED/SKIPPED and RUNNING/SUCCEEDED/FAILED/PARTIAL).
- Keep diagnostics usable in md_impact_trace and md_run_target_action.
- Avoid introducing silent failures in critical execution paths.

## Common Enhancement Patterns

### Pattern A: Add new expression-driven output behavior
1. Update md_rule_output metadata usage or evaluator behavior.
2. Validate with 067, 068, 069 and relevant targeted case.

### Pattern B: Add/modify selection gate behavior
1. Update gate expression semantics carefully in evaluate_selection_gate path.
2. Validate with 067 first, then 060 and 066.

### Pattern C: Add runtime parameter behavior
1. Update md_rule_parameter_requirement and/or run parameter handling.
2. Validate with 064 canonical combined script.

### Pattern D: Add source context join/predicate behavior
1. Update md_source_context* metadata and resolver logic if required.
2. Validate with 061 then 064.

### Pattern E: Add target action mapping behavior
1. Update md_rule_target_action/key_map/column_map behavior.
2. Validate with 066 and inspect md_run_target_action records.

## Quick-Start Checklist
1. Copy docs/functional-enhancement-template.md for the enhancement.
2. Fill sections 1-4 before coding.
3. Implement minimal file set.
4. Run smoke sequence (060, 061, 064, 066, 067, 068, 069).
5. Fill sections 8-11 with actual evidence.

## Evidence References
- docs/engine-docs-index.md
- docs/system-architecture.md
- docs/metadata-schema-reference.md
- docs/package-api-reference.md
- docs/runtime-flow-and-dynamic-sql.md
- docs/error-handling-and-observability.md
- docs/change-impact-playbook.md
- docs/implementation-readiness-summary.md
- sql/scripts/010_md_core.sql
- sql/scripts/020_md_runtime.sql
- sql/scripts/060_md_selector_smoke.sql
- sql/scripts/061_md_cross_entity_context_smoke.sql
- sql/scripts/064_md_runtime_params_smoke_combined.sql
- sql/scripts/066_md_target_dml_smoke.sql
- sql/scripts/067_md_rule_selection_gate_smoke.sql
- sql/scripts/068_md_expr_validator_smoke.sql
- sql/scripts/069_md_expr_function_registry_smoke.sql
