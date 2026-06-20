# Error Handling And Observability

## Current Behavior

### Exception Strategy Matrix

| Location | Strategy | Behavior |
|---|---|---|
| md_rule_executor_pkg.execute_run | Catch-all per rule and top-level | Per-rule failure appends error_messages and continues; top-level sets run_status FAILED |
| md_rule_executor_pkg.evaluate_selection_gate | Catch-all -> ERROR status | Returns gate_eval_status=ERROR and gate_eval_message |
| md_rule_executor_pkg.apply_target_actions | Per-action block catch-all | Increments failed counter and logs error |
| md_rule_executor_pkg.persist_target_value | Catch-all with re-raise | Logs then raises |
| md_rule_executor_pkg.log_impact_trace | Catch-all swallow | Logs error and does not re-raise |
| md_rule_selector_pkg.populate_selected_rules | no_data_found mapped | Raises -20021 for missing run |
| md_source_context_resolver_pkg.resolve_rule_source_values | no_data_found mapped + explicit app errors | Raises -20031 (event missing), -20032 (required alias missing), -20041/-20042 as applicable |
| md_source_context_resolver_pkg.build_context_projection_json | local diagnostic insert wrapped in swallow + selective required-expression hard-fail | Diagnostics insert failures are ignored; non-required scalar expression items can be skipped; required scalar expression issues raise errors |
| md_source_context_resolver_pkg.prefetch_selected_contexts | augmentation block catch-all swallow | build_context_projection_json failure does not stop prefetch |
| md_run_parameter_pkg.get_parameter_value | catch-all return null | Parameter parse/access failures degrade to null |
| md_run_parameter_pkg.validate_required_parameters | explicit app error | Raises -20111 for missing required params |
| md_expr_executor_pkg.evaluate_expr | validation and execution wrapped | Returns FAILED with failure_reason instead of raising |
| md_lookup_executor_pkg / md_column_to_row_executor_pkg / md_plsql_func_executor_pkg | catch-all return FAILED | failure_reason carries SQLERRM |

### Oracle/Application Error Codes Found

| Code | Source | Meaning |
|---|---|---|
| -20001 | md_rule_executor_pkg.fetch_rule | Rule not found |
| -20002 | md_rule_executor_pkg.fetch_source_values | Change event not found |
| -20003 | md_rule_executor_pkg.dispatch_rule_execution | Unknown rule type |
| -20010 | md_rule_executor_pkg.apply_target_actions | No target key mapping |
| -20011 | md_rule_executor_pkg.apply_target_actions | Target row not found for update |
| -20012 | md_rule_executor_pkg.apply_target_actions | Insert column list build failure |
| -20021 | md_rule_selector_pkg.populate_selected_rules | Run not found |
| -20031 | md_source_context_resolver_pkg.resolve_rule_source_values | Change event not found |
| -20032 | md_source_context_resolver_pkg.resolve_rule_source_values | Required context alias missing |
| -20041 | md_source_context_resolver_pkg.clean_identifier, md_column_to_row_executor_pkg.clean_identifier | Invalid identifier |
| -20042 | md_source_context_resolver_pkg.build_context_projection_json | Required predicate value missing |
| -20043 | md_source_context_resolver_pkg.build_context_projection_json | Required scalar expression alias missing |
| -20044 | md_source_context_resolver_pkg.build_context_projection_json | Required scalar expression blocked by guardrails |
| -20045 | md_source_context_resolver_pkg.build_context_projection_json | Required scalar expression alias conflict |
| -20051 | md_plsql_func_executor_pkg.clean_identifier | Invalid identifier |
| -20111 | md_run_parameter_pkg.validate_required_parameters | Missing required runtime parameter(s) |
| -20101/-20102 | 061 smoke | Cross-entity validation failures |
| -20401..-20406 | 064 smoke | Runtime param combined failure set |
| -20501..-20503 | 066 smoke | Target DML validation failures |
| -20601..-20605, -20620 | 067/060 smoke | Selection/gate/selector failures |
| -20801..-20803 | 068 smoke | Expr validator guardrail failures |
| -20901..-20904 | 069 smoke | Expr function registry failures |

### Diagnostics And Logging Tables

| Table | Produced By | Payload Convention |
|---|---|---|
| md_impact_trace | md_rule_executor_pkg.log_impact_trace; md_source_context_resolver_pkg.build_context_projection_json; execute_run diagnostic insert for RULE_SOURCE_VALUES | JSON blobs in source_ref_json/rule_ref_json/target_ref_json; resolver uses diagnostic_type=SOURCE_CONTEXT_SQL and RULE_SCALAR_EXPR_SKIPPED; executor logs diagnostic_type=RULE_SOURCE_VALUES |
| md_run_target_action | md_rule_executor_pkg.apply_target_actions; md_rule_executor_pkg.log_output_eval_failure_trace | execution_status, generated_sql_text, bind_payload_json, error_code/error_message, action_fingerprint |
| md_run_target_value | md_rule_executor_pkg.persist_target_value | computed_value_txt/json, value_status, value_fingerprint |
| md_run_selected_rule | md_rule_selector_pkg + md_rule_executor_pkg | selection_reason, transitive_flag, gate_eval_status/message |

### Transaction Control
- No explicit COMMIT/ROLLBACK statements found in analyzed package code.
- Runtime scripts perform setup/cleanup DML directly; transactional boundaries depend on script/session execution mode.

### Operational Troubleshooting Checklist
1. Check md_run.run_status and run_id scope.
2. Check md_run_selected_rule for gate_eval_status distribution.
3. Check md_run_target_value for computed statuses.
4. Check md_run_target_action for execution_status, generated_sql_text, error_message.
5. Check md_impact_trace diagnostics for SOURCE_CONTEXT_SQL, RULE_SOURCE_VALUES, and RULE_SCALAR_EXPR_SKIPPED payloads.
6. Re-run focused smoke script for failing subsystem:
   - selector: 060
   - context: 061
   - params: 064
   - target dml: 066
   - gate: 067
   - expr guardrails: 068
   - function registry: 069

## Suggested Improvements
- Add severity and subsystem fields to md_impact_trace payload convention for easier filtering.
- Introduce a shared error-code catalog package to prevent overlap.
- Add optional hard-fail mode for currently swallowed diagnostic writes.

## Evidence References
- plsql/packages/md_rule_executor_pkg.pkb :: execute_run, evaluate_selection_gate, apply_target_actions, persist_target_value, log_impact_trace, log_output_eval_failure_trace
- plsql/packages/md_rule_selector_pkg.pkb :: populate_selected_rules
- plsql/packages/md_source_context_resolver_pkg.pkb :: resolve_rule_source_values, build_context_projection_json, prefetch_selected_contexts
- sql/scripts/033_md_rule_input_expr_upgrade.sql :: md_rule_input_expr metadata for scalar projection
- plsql/packages/md_run_parameter_pkg.pkb :: get_parameter_value, validate_required_parameters
- plsql/packages/md_expr_executor_pkg.pkb :: evaluate_expr
- plsql/packages/md_lookup_executor_pkg.pkb :: execute_lookup
- plsql/packages/md_column_to_row_executor_pkg.pkb :: execute_column_to_row
- plsql/packages/md_plsql_func_executor_pkg.pkb :: execute_plsql_func
- sql/scripts/060_md_selector_smoke.sql
- sql/scripts/061_md_cross_entity_context_smoke.sql
- sql/scripts/064_md_runtime_params_smoke_combined.sql
- sql/scripts/066_md_target_dml_smoke.sql
- sql/scripts/067_md_rule_selection_gate_smoke.sql
- sql/scripts/068_md_expr_validator_smoke.sql
- sql/scripts/069_md_expr_function_registry_smoke.sql
- sql/scripts/020_md_runtime.sql :: md_impact_trace, md_run_target_action, md_run_target_value, md_run_selected_rule
