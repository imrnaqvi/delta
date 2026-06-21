# Implementation Readiness Summary

## Current Behavior Snapshot
- The repository has a clear metadata/runtime split (010 core, 020 runtime) and a package orchestration path centered on execute_run.
- Coverage exists for selector, cross-entity context, runtime parameters, target DML, consolidation precedence, gate evaluation, expression validator, and expression function registry via smoke scripts 060-069 plus 073.
- Coverage exists for selector, cross-entity context, runtime parameters, target DML, consolidation precedence, gate evaluation, expression validator, expression function registry, and SQL_SELECT standalone rules via smoke scripts 060-069 plus 073 and 074.
- Runtime diagnostics persist to md_run_target_action and md_impact_trace, including generated SQL traces for context projection and rule source snapshot diagnostics.
- Resolver supports rule-scoped scalar source projection expressions via md_rule_input_expr and merges projected aliases into the same JSON payload used for rule execution.
- SQL_SELECT execution is implemented via md_rule.rule_type='SQL_SELECT' with JSON payload field sql_query, query-only guardrails, one-row cardinality contract, and alias-derived output persistence.
- Target consolidation is implemented with winners-only runtime artifacts and consolidated-only final execution.
- Deterministic precedence is implemented via nvl(md_rule.rule_priority_no, 0) desc then rule_id desc.
- Dedicated consolidation smoke coverage exists in sql/scripts/073_md_target_consolidation_smoke.sql.
- Dedicated SQL_SELECT smoke coverage exists in sql/scripts/074_md_sql_select_rule_smoke.sql.

## Top 10 Hardening/Refactor Opportunities

| Rank | Opportunity | Risk | Effort | Confidence | Affected Files | Test Coverage Gap |
|---|---|---|---|---|---|---|
| 1 | Convert consolidated target SQL generation to bind-based DML | High | Medium | High | plsql/packages/md_rule_executor_pkg.pkb | No dedicated SQL-injection hardening test for consolidated path |
| 2 | Unify token substitution implementation (rule executor vs expr executor) to avoid drift | High | Medium | High | plsql/packages/md_rule_executor_pkg.pkb, plsql/packages/md_expr_executor_pkg.pkb | No parity test for both substitution engines |
| 3 | Introduce explicit transaction policy contract for execute_run and helper packages | High | Low | High | plsql/packages/*.pkb | No transaction-boundary smoke |
| 4 | Add strict diagnostics schema contract for md_impact_trace and consolidation payloads | Medium | Low | High | plsql/packages/md_rule_executor_pkg.pkb, plsql/packages/md_source_context_resolver_pkg.pkb | No payload-schema validation test |
| 5 | Add automated compatibility check for package spec signature changes | Medium | Low | High | plsql/packages/*.pks | No signature regression gate |
| 6 | Strengthen resolver augmentation error handling (currently swallow on augmentation block) | Medium | Medium | High | plsql/packages/md_source_context_resolver_pkg.pkb | No smoke that forces augmentation failure path |
| 7 | Add deterministic tests for output_eval_failure_policy=FAIL_RULE branches | Medium | Low | High | plsql/packages/md_rule_executor_pkg.pkb | Existing smokes do not fully isolate this branch |
| 8 | Add dedicated LOOKUP/COLUMN_TO_ROW/PLSQL_FUNC execute_run smoke flows | Medium | Medium | Medium | plsql/packages/md_lookup_executor_pkg.pkb, plsql/packages/md_column_to_row_executor_pkg.pkb, plsql/packages/md_plsql_func_executor_pkg.pkb | Current smoke focus is mostly EXPRESSION |
| 9 | Add dedicated smoke for md_rule_input_expr scalar projection (multi-expression rows, inline AS aliases, required vs skipped errors) | Medium | Low | High | plsql/packages/md_source_context_resolver_pkg.pkb, sql/scripts/033_md_rule_input_expr_upgrade.sql | No dedicated scalar projection smoke yet |
| 10 | Add schema usage linter from package SQL to DDL columns | Medium | Medium | Medium | sql/scripts/010_md_core.sql, sql/scripts/020_md_runtime.sql, plsql/packages/*.pkb | No automatic table/column drift detection |

## Do First Next Sprint (Max 5)
1. Implement bind-oriented consolidated target DML execution path and regression-test with 066 and 073.
2. Add substitution parity tests for SRC/PARAM/OLD/NEW across executor paths.
3. Add transaction-policy doc + one smoke that validates expected commit behavior in your execution environment.
4. Add dedicated scalar projection smoke for md_rule_input_expr behavior.
5. Add schema drift checker (package SQL references vs 010/020/033 metadata definitions).

## Current Behavior vs Suggested Improvements

### Current Behavior
- Works end-to-end for key EXPRESSION-centric scenarios with metadata-driven selection/context/action.
- Executes final target writes from consolidated winners-only artifacts.
- Error handling is mostly resilient and favors continuation in non-critical diagnostics paths.

### Suggested Improvements
- Prioritize SQL safety and consistency (binds on consolidated execution + substitution unification).
- Expand smoke coverage to non-EXPRESSION runtime paths.
- Add automated contract checks (schema and package signatures) to reduce regression risk.

## Evidence References
- plsql/packages/md_rule_executor_pkg.pkb :: execute_run, consolidate_rule_actions, execute_consolidated_actions_for_run, log_output_eval_failure_trace
- plsql/packages/md_expr_executor_pkg.pkb :: evaluate_expr, substitution/guardrails
- plsql/packages/md_source_context_resolver_pkg.pkb :: build_context_projection_json, prefetch_selected_contexts
- sql/scripts/033_md_rule_input_expr_upgrade.sql
- plsql/packages/md_lookup_executor_pkg.pkb :: execute_lookup
- plsql/packages/md_column_to_row_executor_pkg.pkb :: execute_column_to_row
- plsql/packages/md_plsql_func_executor_pkg.pkb :: execute_plsql_func
- sql/scripts/010_md_core.sql
- sql/scripts/020_md_runtime.sql
- sql/scripts/060_md_selector_smoke.sql
- sql/scripts/061_md_cross_entity_context_smoke.sql
- sql/scripts/064_md_runtime_params_smoke_combined.sql
- sql/scripts/066_md_target_dml_smoke.sql
- sql/scripts/067_md_rule_selection_gate_smoke.sql
- sql/scripts/068_md_expr_validator_smoke.sql
- sql/scripts/069_md_expr_function_registry_smoke.sql
- sql/scripts/073_md_target_consolidation_smoke.sql
- sql/scripts/034_md_rule_priority_upgrade.sql
- sql/scripts/035_md_target_consolidation_runtime_upgrade.sql
- sql/scripts/036_md_sql_select_rule_upgrade.sql
- sql/scripts/074_md_sql_select_rule_smoke.sql
