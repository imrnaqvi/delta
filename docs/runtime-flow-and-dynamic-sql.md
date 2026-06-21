# Runtime Flow And Dynamic SQL

## Current Behavior

### Scenario Walkthroughs From Smoke Scripts

| Scenario | Driver Script | Core Path | Pass Criteria (Script Assertions) |
|---|---|---|---|
| Selector persistence | sql/scripts/060_md_selector_smoke.sql | md_rule_selector_pkg.populate_selected_rules | Raises -20620 if gate columns mutate before execution; otherwise selector smoke completes |
| Cross-entity source context | sql/scripts/061_md_cross_entity_context_smoke.sql | md_rule_executor_pkg.execute_run -> md_source_context_resolver_pkg | Raises -20101 when run status unexpected; -20102 when expected target value mismatches |
| Runtime parameters (canonical) | sql/scripts/064_md_runtime_params_smoke_combined.sql (062/063 redirect) | md_rule_executor_pkg.execute_run with early+late params | Raises -20401..-20406 on status/value/snapshot failures |
| Target DML end-to-end | sql/scripts/066_md_target_dml_smoke.sql | execute_run + consolidate_rule_actions + execute_consolidated_actions_for_run | Raises -20501..-20503 on consolidated execution/action-trace mismatches |
| Target consolidation precedence | sql/scripts/073_md_target_consolidation_smoke.sql | execute_run + consolidation artifacts | Raises -20901..-20913 for precedence, winners-only, and consolidated execution invariants |
| Selection gate behavior | sql/scripts/067_md_rule_selection_gate_smoke.sql | execute_run + evaluate_selection_gate | Raises -20601..-20605 on selected/gate/executed/value count mismatches |
| Expr validator guardrails | sql/scripts/068_md_expr_validator_smoke.sql | md_expr_executor_pkg.evaluate_expr | Raises -20801..-20803 for unexpected validation behavior |
| Expr function registry governance | sql/scripts/069_md_expr_function_registry_smoke.sql | md_expr_executor_pkg.load_registry_allowed_functions + evaluate_expr | Raises -20901..-20904 for registry allow/deny behavior mismatches |
| SQL_SELECT standalone rules | sql/scripts/074_md_sql_select_rule_smoke.sql | execute_run SQL_SELECT branch + consolidate_rule_actions + execute_consolidated_actions_for_run | Emits PASSED marker after expected 4 success paths and expected guardrail/cardinality failures |

### Dynamic SQL Inventory

| Location | SQL Type | Construction Inputs | Guardrails/Notes | Failure Mode |
|---|---|---|---|---|
| md_rule_executor_pkg.evaluate_selection_gate | select case when (...) from dual | selection_gate_expr after OLD/NEW + SRC/PARAM substitution | Expression text evaluation; no bind variables | gate status ERROR with message |
| md_rule_executor_pkg.resolve_mapped_value (EXPR) | select <expr> from dual | source_expr after substitute_tokens | Uses substituted literal text | returns null on exception |
| md_rule_executor_pkg.validate_sql_select_query | lexical guardrail validation | rule_payload.sql_query | Enforces query-only shape, blocks statement delimiters and DML/DDL/procedural wrappers, 4000-char v1 cap | raises -20803 on guardrail rejection |
| md_rule_executor_pkg.execute_sql_select_to_json | dynamic query via dbms_sql + describe/fetch | rule_payload.sql_query (after optional substitution) | Requires exactly one row; derives output aliases from result columns normalized to upper-case | raises -20804/-20805/-20806 |
| md_rule_executor_pkg.consolidate_rule_actions | metadata-driven key/value projection | md_rule_target_action, md_rule_target_key_map, md_rule_target_column_map, rule outputs | winner selection via nvl(rule_priority_no,0) desc then rule_id desc | increments failed count, marks partial consolidation |
| md_rule_executor_pkg.execute_consolidated_actions_for_run | update/insert target tables | md_run_target_consolidation + md_run_target_consolidated_value winners | emits md_run_target_action with execution_phase=CONSOLIDATED_EXECUTION | increments failed/skipped counters and writes FAILED consolidated traces |
| md_expr_executor_pkg.evaluate_expr | select <evaluated expr> from dual | p_expr + source/param substitution | validate_expression_guardrails before execute immediate | returns FAILED with validation/evaluation reason |
| md_source_context_resolver_pkg.build_context_projection_json | select json_object(...) from dynamic join graph | md_source_context_object/join/predicate + rule-scoped md_rule_input + md_rule_input_expr | clean_identifier for identifiers; to_sql_literal for predicate values; blocks risky SQL tokens in scalar_expr; SQL text logged in md_impact_trace | returns {} on no rows; predicate errors raise app errors; required scalar expr failures raise app errors |
| md_lookup_executor_pkg.execute_lookup | dynamic select with dbms_sql binds | lookup_table, return_columns, join_key | clean_identifier + bind variables | returns SKIPPED/FAILED |
| md_column_to_row_executor_pkg.execute_column_to_row | dynamic select with dbms_sql binds | source_table, pk_columns, row_filters | clean_identifier + bind variables | returns FAILED |
| md_plsql_func_executor_pkg.execute_plsql_func | select owner.function(args) from dual | function_owner/name + param refs | clean_identifier on owner/function; arguments inlined as quoted literals | returns FAILED |

### Token Substitution Map

| Token Family | Where Substituted | Notes |
|---|---|---|
| SRC.column and alias.column | md_expr_executor_pkg.substitute_source_references | Used by output_expr evaluation path via evaluate_expr |
| PARAM.path | md_expr_executor_pkg.substitute_param_references | Used by output_expr evaluation path via evaluate_expr |
| SRC./alias./PARAM. (generic gate/mapping path) | md_rule_executor_pkg.substitute_tokens | Used in gate evaluation and target mapping expression resolution |
| OLD.column / NEW.column | md_rule_executor_pkg.substitute_change_delta_tokens | Used before evaluate_selection_gate execution |
| SRC./alias./PARAM./OLD./NEW. in SQL_SELECT payload | md_rule_executor_pkg.apply_sql_select_tokens | Applied only when rule_payload.enable_token_substitution is true (default true) |

### Execution Order In Orchestrator
1. Persist/load params
2. Populate selected rules
3. Prefetch selected contexts (including rule-scoped scalar expression projection merge)
4. Per selected rule: validate required params
5. Resolve prefetched source values
6. Fetch rule metadata/input/output
7. Evaluate selection gate
8. Evaluate output expressions or SQL_SELECT payload (query-only, one-row contract)
9. Persist target values
10. Build/merge consolidated winners (per target_entity_name + target key + target column)
11. Execute consolidated target actions
12. Log impact trace
13. Finalize run status

## Suggested Improvements
- Add a per-consolidation conflict trace payload for winner/loser explainability when collisions occur.
- Add deterministic logging toggle for all generated dynamic SQL statements (not only resolver projection SQL).
- Add token substitution collision tests for alias names that overlap with column names.
- Add performance baseline smoke for high cardinality consolidation.

## Evidence References
- plsql/packages/md_rule_executor_pkg.pkb :: execute_run, evaluate_selection_gate, substitute_tokens, substitute_change_delta_tokens, resolve_mapped_value, consolidate_rule_actions, execute_consolidated_actions_for_run
- plsql/packages/md_rule_executor_pkg.pkb :: execute_run, evaluate_selection_gate, substitute_tokens, substitute_change_delta_tokens, apply_sql_select_tokens, validate_sql_select_query, execute_sql_select_to_json, resolve_mapped_value, consolidate_rule_actions, execute_consolidated_actions_for_run
- plsql/packages/md_expr_executor_pkg.pkb :: substitute_source_references, substitute_param_references, validate_expression_guardrails, evaluate_expr
- plsql/packages/md_source_context_resolver_pkg.pkb :: build_context_projection_json, clean_identifier, to_sql_literal, prefetch_selected_contexts
- sql/scripts/033_md_rule_input_expr_upgrade.sql :: md_rule_input_expr metadata source
- sql/scripts/036_md_sql_select_rule_upgrade.sql :: md_rule.rule_type SQL_SELECT enablement
- plsql/packages/md_lookup_executor_pkg.pkb :: execute_lookup
- plsql/packages/md_column_to_row_executor_pkg.pkb :: execute_column_to_row
- plsql/packages/md_plsql_func_executor_pkg.pkb :: execute_plsql_func
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
- sql/scripts/074_md_sql_select_rule_smoke.sql
