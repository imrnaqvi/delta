# Metadata Schema Reference

## Current Behavior

### Catalog Used By Engine Logic

| Table | Purpose | Key Columns | Critical Columns Used In Code | Read/Write Packages | Lifecycle Stage | Breaking Change Risk |
|---|---|---|---|---|---|---|
| md_rule | Rule definitions | rule_id (PK), tenant_id, context_id, release_id | rule_type (includes SQL_SELECT via 036), rule_payload (JSON; SQL_SELECT uses sql_query and enable_token_substitution), output_eval_failure_policy, selection_gate_expr, selection_gate_enabled_flag, active_flag, status, rule_priority_no | R: md_rule_executor_pkg, md_rule_selector_pkg; W: smoke scripts | Design-time metadata | High |
| md_rule_input | Source inputs per rule | rule_input_id (PK), rule_id, source_column_id | required_flag, output_alias | R: md_rule_executor_pkg, md_rule_selector_pkg, md_source_context_resolver_pkg; W: smoke scripts | Design-time metadata | High |
| md_rule_input_expr | Rule-scoped scalar source projections | rule_input_expr_id (PK), rule_id, output_alias | scalar_expr, expression_order_no, required_flag, active_flag | R: md_source_context_resolver_pkg; W: upgrade script and metadata seed scripts | Design-time metadata | High |
| md_rule_output | Output expressions per rule | rule_output_id (PK), rule_id, target_column_id | output_expr | R: md_rule_executor_pkg; W: smoke scripts | Design-time metadata | High |
| md_rule_dependency | Rule dependency graph | rule_dependency_id (PK), upstream_rule_id, downstream_rule_id | dependency_type, active_flag | R: md_rule_selector_pkg | Design-time metadata | Medium |
| md_rule_parameter_requirement | Required runtime params per rule | rule_parameter_requirement_id (PK), rule_id, param_name | required_flag, default_value_txt | R: md_run_parameter_pkg | Design-time metadata | High |
| md_rule_source_context | Rule to source-context binding | rule_source_context_id (PK), rule_id, source_context_id | active_flag | R: md_source_context_resolver_pkg | Design-time metadata | High |
| md_source_context | Context definition | source_context_id (PK), anchor_object_id | context_name, active_flag | R: md_source_context_resolver_pkg | Design-time metadata | High |
| md_source_context_object | Aliases in context graph | source_context_object_id (PK), source_context_id, object_id | object_alias, role_type, required_flag | R: md_source_context_resolver_pkg | Design-time metadata | High |
| md_source_context_join | Join graph edges | source_context_join_id (PK), source_context_id | left_alias, right_alias, join_type, join_expr, active_flag | R: md_source_context_resolver_pkg | Design-time metadata | High |
| md_source_context_predicate | Predicate metadata | source_context_predicate_id (PK), source_context_id | operator_code, value_source_kind, value_expr, value_expr_to, null_behavior, predicate_group_no | R: md_source_context_resolver_pkg | Design-time metadata | High |
| md_expr_allowed_function | Expression governance registry | expr_allowed_function_id (PK), tenant_id, context_id, function_name | active_flag | R: md_expr_executor_pkg; W: smoke scripts 068/069 | Design-time metadata | Medium |
| md_object | Object registry | object_id (PK), release_id | schema_name, object_name, system_name | R: md_rule_executor_pkg, md_source_context_resolver_pkg, md_rule_selector_pkg | Design-time metadata | High |
| md_column | Column registry | column_id (PK), object_id | column_name, data_type | R: md_rule_executor_pkg, md_source_context_resolver_pkg, md_rule_selector_pkg | Design-time metadata | High |
| md_key_definition | Target/source key metadata | key_id (PK), release_id | key_scope, entity_name | R: md_rule_executor_pkg (through mappings) | Design-time metadata | Medium |
| md_key_component | Key component metadata | key_component_id (PK), key_id, column_id | ordinal_position | R: md_rule_executor_pkg | Design-time metadata | High |
| md_rule_target_action | Target action templates | rule_target_action_id (PK), rule_id, target_object_id | action_type, missing_row_policy, target_column_id | R: md_rule_executor_pkg; W: smoke scripts | Design-time metadata | High |
| md_rule_target_key_map | Key mapping expressions | rule_target_key_map_id (PK), rule_target_action_id | source_kind, source_expr | R: md_rule_executor_pkg | Design-time metadata | High |
| md_rule_target_column_map | Value mapping expressions | rule_target_column_map_id (PK), rule_target_action_id, target_column_id | value_source_kind, value_expr | R: md_rule_executor_pkg | Design-time metadata | High |
| md_run | Run header | run_id (PK), release_id | run_mode, run_status, started_at, ended_at | R/W: md_rule_executor_pkg, md_rule_selector_pkg; W: smoke scripts | Runtime | High |
| md_run_parameter | Parameter instances | run_parameter_id (PK), run_id, param_name | param_value_txt, param_data_type | R/W: md_run_parameter_pkg, md_rule_executor_pkg | Runtime | High |
| md_run_parameter_snapshot | Parameter snapshots | run_parameter_snapshot_id (PK), run_id | parameter_json, parameter_hash | R/W: md_run_parameter_pkg; R: smoke 064 | Runtime | High |
| md_change_event | Normalized change event | change_event_id (PK), event_fingerprint | source_entity_name, source_key_json, old_key_json, new_key_json, source_key_hash, event_ts | R: md_rule_executor_pkg, md_source_context_resolver_pkg, md_rule_selector_pkg; W: smoke scripts | Runtime | High |
| md_change_event_column_delta | Changed columns per event | change_event_column_delta_id (PK), change_event_id | source_column_name, old_value_txt, new_value_txt, value_changed_flag | R: md_rule_selector_pkg, md_rule_executor_pkg | Runtime | High |
| md_run_selected_rule | Selection contract and gate outcomes | run_selected_rule_id (PK), run_id, change_event_id, rule_id | selection_reason, transitive_flag, gate_eval_status, gate_eval_message | R/W: md_rule_selector_pkg, md_rule_executor_pkg, md_source_context_resolver_pkg | Runtime | High |
| md_run_source_snapshot | Rule-level source snapshot | run_source_snapshot_id (PK), run_id/change_event_id/rule_id | source_values_json, source_context_id, correlation_key | W/R: md_source_context_resolver_pkg (now includes scalar projection aliases when configured) | Runtime | High |
| md_run_context_snapshot | Context-level snapshot cache | run_context_snapshot_id (PK), run_id/change_event_id/source_context_id | source_values_json | W/R: md_source_context_resolver_pkg | Runtime | High |
| md_run_target_value | Computed values | run_target_value_id (PK), run_id, value_fingerprint | target_column_name, computed_value_txt/json, value_status | W/R: md_rule_executor_pkg; R: smoke scripts | Runtime | High |
| md_run_target_action | Applied/planned actions trace | run_target_action_id (PK), run_id, action_fingerprint | generated_sql_text, execution_status, error_code, error_message, execution_phase, run_target_consolidation_id | W/R: md_rule_executor_pkg; R: smoke scripts | Runtime | High |
| md_run_target_consolidation | Consolidation header per target key | run_target_consolidation_id (PK), run_id/change_event_id/target_entity_name/target_key_hash (UQ) | consolidation_status, winning_value_count, source_rule_count, target_key_json | W/R: md_rule_executor_pkg; R: 073 smoke | Runtime | High |
| md_run_target_consolidated_value | Winners-only consolidated target cells | run_target_consolidated_value_id (PK), run_target_consolidation_id | target_column_name, computed_value_txt/json, winner_rule_id, winner_priority_no, value_fingerprint | W/R: md_rule_executor_pkg; R: 073 smoke | Runtime | High |
| md_impact_trace | Lineage and diagnostics trace | impact_trace_id (PK), run_id | source_ref_json, rule_ref_json, target_ref_json | W: md_rule_executor_pkg, md_source_context_resolver_pkg | Runtime diagnostics | Medium |
| md_correlation_policy | Correlation policy metadata | correlation_policy_id (PK), policy_name | correlation_mode, window_minutes, active_flag | W: smoke scripts; R: Legacy metadata path only (current resolver code in scope does not query this table) | Design-time metadata | Low-Medium |

### Column/Data Type Anchors (DDL Source of Truth)
- Core metadata tables are defined in sql/scripts/010_md_core.sql.
- Runtime tables are defined in sql/scripts/020_md_runtime.sql.
- Incremental scalar-projection metadata upgrade is defined in sql/scripts/033_md_rule_input_expr_upgrade.sql.
- Incremental rule-priority metadata upgrade is defined in sql/scripts/034_md_rule_priority_upgrade.sql.
- Incremental consolidation runtime upgrade is defined in sql/scripts/035_md_target_consolidation_runtime_upgrade.sql.
- Incremental SQL_SELECT rule-type enablement is defined in sql/scripts/036_md_sql_select_rule_upgrade.sql.
- For tables above, data types should be taken from those scripts when implementing changes.

## Suggested Improvements
- Add a generated machine-readable schema map (table->column->datatype->referenced_by_packages) to reduce manual drift.
- Add explicit deprecation notes for legacy correlation metadata if runtime path remains single-event-only.
- Add automated check that all package table references resolve to existing columns in 010/020 scripts.

## Evidence References
- sql/scripts/010_md_core.sql :: md_rule, md_rule_input, md_rule_input_expr, md_rule_output, md_rule_dependency, md_rule_parameter_requirement, md_rule_source_context, md_source_context, md_source_context_object, md_source_context_join, md_source_context_predicate, md_expr_allowed_function, md_object, md_column, md_key_definition, md_key_component, md_rule_target_action, md_rule_target_key_map, md_rule_target_column_map, md_correlation_policy
- sql/scripts/033_md_rule_input_expr_upgrade.sql :: md_rule_input_expr incremental creation and indexes
- sql/scripts/034_md_rule_priority_upgrade.sql :: md_rule.rule_priority_no
- sql/scripts/020_md_runtime.sql :: md_run, md_run_parameter, md_run_parameter_snapshot, md_change_event, md_change_event_column_delta, md_run_selected_rule, md_run_source_snapshot, md_run_context_snapshot, md_run_target_value, md_run_target_action, md_impact_trace
- sql/scripts/035_md_target_consolidation_runtime_upgrade.sql :: md_run_target_consolidation, md_run_target_consolidated_value, md_run_target_action.execution_phase, md_run_target_action.run_target_consolidation_id
- sql/scripts/036_md_sql_select_rule_upgrade.sql :: md_rule.rule_type constraint update for SQL_SELECT and rule_payload comment contract
- plsql/packages/md_rule_executor_pkg.pkb :: fetch_rule, fetch_rule_inputs, fetch_rule_outputs, evaluate_selection_gate, consolidate_rule_actions, execute_consolidated_actions_for_run, persist_target_value, log_impact_trace
- plsql/packages/md_source_context_resolver_pkg.pkb :: resolve_rule_source_values, build_context_projection_json, prefetch_selected_contexts, get_prefetched_rule_source_values
- plsql/packages/md_rule_selector_pkg.pkb :: populate_selected_rules
- plsql/packages/md_run_parameter_pkg.pkb :: load_run_parameters, persist_run_parameters, validate_required_parameters
- plsql/packages/md_expr_executor_pkg.pkb :: load_registry_allowed_functions
- sql/scripts/061_md_cross_entity_context_smoke.sql, sql/scripts/064_md_runtime_params_smoke_combined.sql, sql/scripts/066_md_target_dml_smoke.sql, sql/scripts/067_md_rule_selection_gate_smoke.sql, sql/scripts/068_md_expr_validator_smoke.sql, sql/scripts/069_md_expr_function_registry_smoke.sql, sql/scripts/073_md_target_consolidation_smoke.sql, sql/scripts/074_md_sql_select_rule_smoke.sql :: runtime usage and validation expectations
