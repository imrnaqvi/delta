# Functional Enhancement Template

Use this template for each enhancement request.

## 1) Enhancement Summary
- Enhancement ID:
- Title:
- Requestor:
- Date:
- Business objective:
- Non-goals:

## 2) Current vs Target Behavior

### Current Behavior
- Runtime path today:
- Current metadata dependencies:
- Current package behavior:

### Target Behavior
- Expected runtime path after change:
- Expected metadata changes:
- Expected package behavior:

## 3) Scope and Impact
- Affected metadata tables:
- Affected columns (if any):
- Affected package specs (.pks):
- Affected package bodies (.pkb):
- Affected smoke scripts:
- Out-of-scope items:

## 4) Design Decisions
- Decision 1:
  - Options considered:
  - Chosen option:
  - Why:
- Decision 2:
  - Options considered:
  - Chosen option:
  - Why:

## 5) Change Plan
1. Metadata change steps:
2. Package/spec change steps:
3. Runtime behavior checks:
4. Backward compatibility checks:
5. Observability additions (if any):

## 6) SQL and Token Handling Checklist
- Dynamic SQL affected? (Y/N):
- If yes, where:
- Token families used (SRC/alias/PARAM/OLD/NEW):
- Guardrails preserved:
- Injection-risk review complete: (Y/N)

## 7) Error Handling and Diagnostics
- New/changed error codes:
- Existing error semantics preserved: (Y/N)
- Diagnostics table writes impacted:
- md_impact_trace payload updates (if any):

## 8) Validation Plan

### Required Smoke Sequence
1. sql/scripts/060_md_selector_smoke.sql
2. sql/scripts/061_md_cross_entity_context_smoke.sql
3. sql/scripts/064_md_runtime_params_smoke_combined.sql
4. sql/scripts/066_md_target_dml_smoke.sql
5. sql/scripts/067_md_rule_selection_gate_smoke.sql
6. sql/scripts/068_md_expr_validator_smoke.sql
7. sql/scripts/069_md_expr_function_registry_smoke.sql

### Targeted Tests For This Enhancement
- Script/test:
- Why:
- Expected pass evidence:

## 9) Rollback Plan
- Metadata rollback:
- Package rollback:
- Data cleanup rollback:
- Risk if partial rollback only:

## 10) Evidence References
- Files reviewed:
- Objects/routines reviewed:
- Unknowns needing verification:

## 11) Implementation Readiness Gate
- Scope clarity: PASS/FAIL
- Backward compatibility: PASS/FAIL
- Validation coverage: PASS/FAIL
- Observability coverage: PASS/FAIL
- Ready to implement: YES/NO
