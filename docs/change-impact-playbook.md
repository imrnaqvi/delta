# Change Impact Playbook

## Current Behavior

### A) Metadata Table/Column Change Impact Matrix

| Change Area | Directly Impacted Packages | Smoke Scripts To Re-run |
|---|---|---|
| md_rule (including rule_priority_no and SQL_SELECT rule_type), md_rule_input, md_rule_output, md_rule_input_expr | md_rule_executor_pkg, md_rule_selector_pkg, md_source_context_resolver_pkg | 060, 061, 064, 066, 067, 073, 074 |
| md_rule_dependency | md_rule_selector_pkg | 060, 067 |
| md_rule_parameter_requirement, md_run_parameter* | md_run_parameter_pkg, md_rule_executor_pkg, md_source_context_resolver_pkg | 064 (canonical), 062/063 wrappers |
| md_source_context*, md_source_context_predicate, md_rule_source_context | md_source_context_resolver_pkg, md_rule_executor_pkg | 061, 064 |
| md_expr_allowed_function | md_expr_executor_pkg | 068, 069 |
| md_rule_target_action, md_rule_target_key_map, md_rule_target_column_map | md_rule_executor_pkg | 066 |
| md_change_event, md_change_event_column_delta | md_rule_selector_pkg, md_source_context_resolver_pkg, md_rule_executor_pkg | 060, 061, 066, 067 |
| md_run_selected_rule | md_rule_selector_pkg, md_rule_executor_pkg, md_source_context_resolver_pkg | 060, 067 |
| md_run_context_snapshot, md_run_source_snapshot | md_source_context_resolver_pkg, md_rule_executor_pkg | 061, 064 |
| md_run_target_action, md_run_target_value, md_impact_trace | md_rule_executor_pkg, md_source_context_resolver_pkg | 066, 061, 064 |
| md_run_target_consolidation, md_run_target_consolidated_value | md_rule_executor_pkg | 066, 073 |

### B) Package Signature Change Impact Matrix

| Package Changed | Immediate Callers | Suggested Regression Scope |
|---|---|---|
| md_rule_executor_pkg | smoke scripts 061, 064, 066, 067, 073 | Full suite 060-069 plus 073 |
| md_rule_selector_pkg | md_rule_executor_pkg.execute_run, smoke 060 | 060, 067, 066 |
| md_source_context_resolver_pkg | md_rule_executor_pkg.execute_run | 061, 064, 066 |
| md_run_parameter_pkg | md_rule_executor_pkg, md_source_context_resolver_pkg | 064, 066, 067 |
| md_expr_executor_pkg | md_rule_executor_pkg output_expr path, smoke 068/069 | 068, 069, plus 066/067 if output_expr used |
| md_lookup_executor_pkg | md_rule_executor_pkg.dispatch_rule_execution (execute_rule path) | Targeted execute_rule tests (Unknown in current smoke set) |
| md_column_to_row_executor_pkg | md_rule_executor_pkg.dispatch_rule_execution (execute_rule path) | Targeted execute_rule tests (Unknown in current smoke set) |
| md_plsql_func_executor_pkg | md_rule_executor_pkg.dispatch_rule_execution (execute_rule path) | Targeted execute_rule tests (Unknown in current smoke set) |

### C) Runtime Semantics Change Checklist

| Semantic Change | Required Checks |
|---|---|
| Gate semantics or token substitution changes | Re-run 067 and inspect md_run_selected_rule.gate_eval_status/message |
| Runtime parameter behavior changes | Re-run 064 and verify both early/late pass and snapshot existence |
| Source-context resolution changes | Re-run 061 and verify expected derived value and run status |
| Scalar source projection (md_rule_input_expr) changes | Re-run 061 and 064; verify projected aliases appear in run source/context snapshots and downstream rule behavior |
| output_eval_failure_policy behavior changes | Re-run 066 and inspect md_run_target_action failure traces |
| SQL_SELECT payload/guardrail/cardinality changes | Re-run 074 and validate 4 success paths plus expected blocked/zero-row/multi-row failures |
| Target consolidation precedence/execution changes | Re-run 066 and 073; validate winners-only artifact, execution_phase=CONSOLIDATED_EXECUTION, and deterministic precedence (nvl(priority,0) desc, rule_id desc) |
| Selector logic changes | Re-run 060 and verify selection counts/reasons |
| Expr governance changes | Re-run 068 and 069 |

## How-To Playbooks

### Add A New Rule Type
1. Extend md_rule.rule_type check constraint in metadata DDL/migration.
2. Add executor package spec/body for new type.
3. Add branch in md_rule_executor_pkg.dispatch_rule_execution.
4. Add smoke script for happy path and failure path.
5. Validate with 066/067 plus new smoke.

### Add A SQL_SELECT Rule
1. Ensure 036_md_sql_select_rule_upgrade.sql is applied in the target environment.
2. Insert md_rule with rule_type='SQL_SELECT' and JSON payload containing sql_query.
3. Keep md_rule_input coverage for selector eligibility (direct-column selection still uses md_rule_input).
4. Configure target action/key/value mappings as usual.
5. Validate with 074 and then regression sequence.

### Add A New Source Context Mapping
1. Insert md_source_context row.
2. Insert md_source_context_object aliases (ANCHOR/JOINED).
3. Insert md_source_context_join rows.
4. Insert md_rule_source_context binding.
5. Optionally insert md_source_context_predicate rows.
6. Validate with 061 and targeted execute_run.

### Add Rule-Scoped Scalar Source Projections
1. Insert md_rule_input_expr row(s) for the rule.
2. Use output_alias column and/or inline AS aliases in scalar_expr.
3. Keep expressions scalar-only (no SELECT/FROM/UNION/JOIN/WITH, no comment markers, no statement delimiters).
4. Mark required expressions with required_flag='Y' only when failure should fail projection.
5. Validate resolver snapshot JSON contains projected aliases and downstream consumers can read them.

### Add A New Target Action Mapping
1. Insert md_rule_target_action.
2. Insert md_rule_target_key_map for key components.
3. Insert md_rule_target_column_map for value mapping.
4. Validate consolidation + consolidated execution behavior with 066 and 073.

### Add/Adjust Consolidation Precedence
1. Set md_rule.rule_priority_no (optional).
2. Remember effective precedence: nvl(rule_priority_no, 0) desc, then rule_id desc.
3. Validate winners in md_run_target_consolidated_value.
4. Validate final action rows in md_run_target_action with execution_phase=CONSOLIDATED_EXECUTION.

### Add A New Expression Function Allowlist Entry
1. Insert md_expr_allowed_function for tenant/context and function_name.
2. Validate allow path with 068/069 patterns.
3. Validate blocked path still fails for disallowed function.

## Required Validation Sequence
1. sql/scripts/060_md_selector_smoke.sql
2. sql/scripts/061_md_cross_entity_context_smoke.sql
3. sql/scripts/064_md_runtime_params_smoke_combined.sql
4. sql/scripts/066_md_target_dml_smoke.sql
5. sql/scripts/073_md_target_consolidation_smoke.sql
6. sql/scripts/067_md_rule_selection_gate_smoke.sql
7. sql/scripts/068_md_expr_validator_smoke.sql
8. sql/scripts/069_md_expr_function_registry_smoke.sql
9. sql/scripts/074_md_sql_select_rule_smoke.sql

Expected pass criteria:
- No raise_application_error in each script.
- Each script emits its PASSED marker message.
- For 064/066/067, script-specific row-count/value assertions hold.

## Suggested Improvements
- Add a single master smoke runner script that executes 060-069 plus 073 in order with summarized pass/fail report.
- Add package signature contract tests that diff pks signatures between releases.
- Add table-column usage linter to detect metadata changes that break package SQL.

## Evidence References
- plsql/packages/md_rule_executor_pkg.pkb :: execute_run, dispatch_rule_execution, consolidate_rule_actions, execute_consolidated_actions_for_run
- plsql/packages/md_rule_selector_pkg.pkb :: populate_selected_rules
- plsql/packages/md_source_context_resolver_pkg.pkb :: resolve_rule_source_values, prefetch_selected_contexts, get_prefetched_rule_source_values
- sql/scripts/033_md_rule_input_expr_upgrade.sql
- plsql/packages/md_run_parameter_pkg.pkb :: validate_required_parameters, load/persist
- plsql/packages/md_expr_executor_pkg.pkb :: load_registry_allowed_functions, validate_expression_guardrails
- sql/scripts/060_md_selector_smoke.sql
- sql/scripts/061_md_cross_entity_context_smoke.sql
- sql/scripts/062_md_runtime_params_smoke.sql
- sql/scripts/063_md_runtime_params_smoke_late.sql
- sql/scripts/064_md_runtime_params_smoke_combined.sql
- sql/scripts/066_md_target_dml_smoke.sql
- sql/scripts/067_md_rule_selection_gate_smoke.sql
- sql/scripts/068_md_expr_validator_smoke.sql
- sql/scripts/069_md_expr_function_registry_smoke.sql
- sql/scripts/073_md_target_consolidation_smoke.sql
- sql/scripts/010_md_core.sql
- sql/scripts/020_md_runtime.sql
- sql/scripts/034_md_rule_priority_upgrade.sql
- sql/scripts/035_md_target_consolidation_runtime_upgrade.sql
- sql/scripts/036_md_sql_select_rule_upgrade.sql
- sql/scripts/074_md_sql_select_rule_smoke.sql
