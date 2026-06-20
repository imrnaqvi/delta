# Runtime Flow And Dynamic SQL

## Current Behavior

### Scenario Walkthroughs From Smoke Scripts

| Scenario | Driver Script | Core Path | Pass Criteria (Script Assertions) |
|---|---|---|---|
| Selector persistence | sql/scripts/060_md_selector_smoke.sql | md_rule_selector_pkg.populate_selected_rules | Raises -20620 if gate columns mutate before execution; otherwise selector smoke completes |
| Cross-entity source context | sql/scripts/061_md_cross_entity_context_smoke.sql | md_rule_executor_pkg.execute_run -> md_source_context_resolver_pkg | Raises -20101 when run status unexpected; -20102 when expected target value mismatches |
| Runtime parameters (canonical) | sql/scripts/064_md_runtime_params_smoke_combined.sql (062/063 redirect) | md_rule_executor_pkg.execute_run with early+late params | Raises -20401..-20406 on status/value/snapshot failures |
| Target DML end-to-end | sql/scripts/066_md_target_dml_smoke.sql | execute_run + apply_target_actions | Raises -20501..-20503 on update/insert/action-trace mismatches |
| Selection gate behavior | sql/scripts/067_md_rule_selection_gate_smoke.sql | execute_run + evaluate_selection_gate | Raises -20601..-20605 on selected/gate/executed/value count mismatches |
| Expr validator guardrails | sql/scripts/068_md_expr_validator_smoke.sql | md_expr_executor_pkg.evaluate_expr | Raises -20801..-20803 for unexpected validation behavior |
| Expr function registry governance | sql/scripts/069_md_expr_function_registry_smoke.sql | md_expr_executor_pkg.load_registry_allowed_functions + evaluate_expr | Raises -20901..-20904 for registry allow/deny behavior mismatches |

### Dynamic SQL Inventory

| Location | SQL Type | Construction Inputs | Guardrails/Notes | Failure Mode |
|---|---|---|---|---|
| md_rule_executor_pkg.evaluate_selection_gate | select case when (...) from dual | selection_gate_expr after OLD/NEW + SRC/PARAM substitution | Expression text evaluation; no bind variables | gate status ERROR with message |
| md_rule_executor_pkg.resolve_mapped_value (EXPR) | select <expr> from dual | source_expr after substitute_tokens | Uses substituted literal text | returns null on exception |
| md_rule_executor_pkg.apply_target_actions | update/insert target tables | md_rule_target_action, key maps, column maps | values escaped via enquote_value; object names from md_object/md_column metadata | increments failed count, logs error |
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

### Execution Order In Orchestrator
1. Persist/load params
2. Populate selected rules
3. Prefetch selected contexts (including rule-scoped scalar expression projection merge)
4. Per selected rule: validate required params
5. Resolve prefetched source values
6. Fetch rule metadata/input/output
7. Evaluate selection gate
8. Evaluate output expressions
9. Persist target values
10. Apply target actions
11. Log impact trace
12. Finalize run status

## Suggested Improvements
- Add a metadata flag to require bind-based dynamic SQL generation for target actions to reduce literal SQL generation risk.
- Add deterministic logging toggle for all generated dynamic SQL statements (not only resolver projection SQL).
- Add token substitution collision tests for alias names that overlap with column names.
- Add a dedicated smoke script for md_rule_input_expr projection (multi-expression rows, inline AS aliases, skip-vs-required failure behavior).

## Evidence References
- plsql/packages/md_rule_executor_pkg.pkb :: execute_run, evaluate_selection_gate, substitute_tokens, substitute_change_delta_tokens, resolve_mapped_value, apply_target_actions
- plsql/packages/md_expr_executor_pkg.pkb :: substitute_source_references, substitute_param_references, validate_expression_guardrails, evaluate_expr
- plsql/packages/md_source_context_resolver_pkg.pkb :: build_context_projection_json, clean_identifier, to_sql_literal, prefetch_selected_contexts
- sql/scripts/033_md_rule_input_expr_upgrade.sql :: md_rule_input_expr metadata source
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
