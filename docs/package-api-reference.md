# Package API Reference

## Current Behavior

### Shared Result Types
| Package | Type | Fields | Notes |
|---|---|---|---|
| md_rule_executor_pkg | computed_value_rec | computed_value_txt, computed_value_json, value_data_type, value_status, failure_reason | Orchestration-level computed value record |
| md_rule_executor_pkg | run_metrics_rec | rules_selected, rules_executed, values_computed, values_failed, values_skipped | Run counters |
| md_rule_executor_pkg | run_result_rec | run_id, run_status, metrics, error_messages | Returned by execute_run |
| md_expr_executor_pkg / md_lookup_executor_pkg / md_column_to_row_executor_pkg / md_plsql_func_executor_pkg | computed_value_rec | computed_value_txt, computed_value_json, value_data_type, value_status, failure_reason | Executor-specific result record |

### md_rule_executor_pkg

#### Public API (Spec)
| Routine | Signature Summary | Side Effects | Errors/Status |
|---|---|---|---|
| execute_run | (run_id, change_event_id, tenant_id, context_id, params_json?) -> run_result_rec | Writes md_run_selected_rule, md_run_target_value, md_run_target_consolidation, md_run_target_consolidated_value, md_run_target_action, md_impact_trace, md_run status; reads selection/context/rule metadata | Sets run_status SUCCEEDED/FAILED/PARTIAL; accumulates error_messages |
| execute_rule | (rule_id, tenant_id, context_id, source_values) -> computed_value_rec | No direct persistence in function itself | Returns FAILED with sqlerrm on exception |
| persist_target_value | (run_id, rule_id, target_column_name, computed_value, tenant_id, context_id) | Inserts md_run_target_value idempotently by fingerprint | Re-raises after log_error on failure |
| log_impact_trace | (run_id, rule_id, source_json, tenant_id, context_id) | Inserts md_impact_trace | Swallows errors after log_error |
| update_run_status | (run_id, status, tenant_id, context_id) | Updates md_run | Re-raises on failure |
| generate_fingerprint | (run_id, rule_id, target_column_name, value) -> varchar2 | None | Re-raises on failure |

#### Body-Local Routines (Operationally Important)
| Routine | Purpose | Side Effects |
|---|---|---|
| evaluate_selection_gate | Evaluates md_rule.selection_gate_expr after token substitution | Updates output status/message via caller update on md_run_selected_rule |
| validate_sql_select_query | Validates SQL_SELECT payload query-only guardrails | Raises application errors for guardrail/cardinality preconditions |
| apply_sql_select_tokens | Applies SRC/alias/PARAM/OLD/NEW substitutions to SQL_SELECT query text | None |
| execute_sql_select_to_json | Executes SQL_SELECT query and returns one-row alias/value JSON | Raises on zero/multi-row or alias conflicts |
| consolidate_rule_actions | Builds/merges winner candidates into consolidated runtime artifacts | Writes md_run_target_consolidation and md_run_target_consolidated_value |
| execute_consolidated_actions_for_run | Executes final UPDATE/INSERT from consolidated winners only | Target table DML via execute immediate; writes md_run_target_action with execution_phase=CONSOLIDATED_EXECUTION |
| upsert_target_consolidation | Ensures consolidation header exists and status is updated | Writes md_run_target_consolidation |
| upsert_consolidated_winner | Applies deterministic precedence and upserts winners-only value cells | Writes md_run_target_consolidated_value |
| resolve_mapped_value | Resolves source expressions for key/value mappings | May execute immediate for EXPR source kind |
| log_output_eval_failure_trace | Writes synthetic failed action row for output_expr evaluation failures | Inserts md_run_target_action |
| substitute_tokens | SRC./alias./PARAM. substitution | None |
| substitute_change_delta_tokens | OLD./NEW. substitution from md_change_event_column_delta | None |

### md_rule_selector_pkg
| Routine | Signature Summary | Side Effects | Errors |
|---|---|---|---|
| populate_selected_rules | (run_id, change_event_id, tenant_id, context_id, purge_existing='Y') | Deletes/inserts/merges md_run_selected_rule with DIRECT_COLUMN_LINK and TRANSITIVE_DEPENDENCY rows | -20021 if run not found |

### md_source_context_resolver_pkg
| Routine | Signature Summary | Side Effects | Errors |
|---|---|---|---|
| resolve_rule_source_values | (run_id, change_event_id, rule_id, tenant_id, context_id, params_json?) -> clob | Writes md_run_source_snapshot | -20031 change event missing; -20032 missing required correlated alias; -20041 invalid identifier; -20042 required predicate missing |
| prefetch_selected_contexts | (run_id, change_event_id, tenant_id, context_id, params_json?) | Writes md_run_context_snapshot and md_run_source_snapshot; calls resolve_rule_source_values; merges rule-scoped scalar projections | Swallows non-required scalar projection augmentation errors in build_context_projection_json merge block |
| get_prefetched_rule_source_values | (run_id, change_event_id, rule_id, tenant_id, context_id, params_json?) -> clob | Reads md_run_source_snapshot first; reads/writes md_run_context_snapshot; may call resolve_rule_source_values | Falls back to resolve when no snapshot |

#### Resolver Scalar Projection Behavior (Body)
| Behavior | Source |
|---|---|
| Reads rule-scoped scalar projections from md_rule_input_expr | build_context_projection_json |
| Supports one or more scalar expressions per metadata row (comma-separated at top level) | build_context_projection_json |
| Supports inline alias syntax using AS and optional output_alias column fallback | build_context_projection_json |
| Skips invalid/non-required expression items and logs diagnostics; required expressions raise error | build_context_projection_json |
| New resolver errors for required scalar expression failures | -20043, -20044, -20045 |

### md_run_parameter_pkg
| Routine | Signature Summary | Side Effects | Errors |
|---|---|---|---|
| load_run_parameters | (run_id, tenant_id, context_id) -> clob | Reads md_run_parameter | Returns {} when no rows |
| persist_run_parameters | (run_id, tenant_id, context_id, params_json) | Replaces md_run_parameter rows; upserts md_run_parameter_snapshot | Propagates parse/insert errors |
| get_parameter_value | (params_json, param_name) -> varchar2 | None | Returns null on parse/access error |
| validate_required_parameters | (run_id, rule_id, tenant_id, context_id, params_json) | Reads md_rule_parameter_requirement and params | -20111 on missing required params |

### md_expr_executor_pkg
| Routine | Signature Summary | Side Effects | Errors/Status |
|---|---|---|---|
| evaluate_expr | (expr, source_values, params_json?, tenant_id?, context_id?) -> computed_value_rec | Dynamic SQL select from dual after substitutions | Returns FAILED with validation/evaluation reason |
| execute_expression | (rule_payload, source_values, params_json?, tenant_id?, context_id?) -> computed_value_rec | Delegates to evaluate_expr | Returns FAILED when expr missing or exception |

### md_lookup_executor_pkg
| Routine | Signature Summary | Side Effects | Errors/Status |
|---|---|---|---|
| execute_lookup | (rule_payload, source_values) -> computed_value_rec | Dynamic query via DBMS_SQL | SKIPPED when no row; FAILED on exception |

### md_column_to_row_executor_pkg
| Routine | Signature Summary | Side Effects | Errors/Status |
|---|---|---|---|
| execute_column_to_row | (rule_payload, source_values) -> computed_value_rec | Dynamic query via DBMS_SQL and JSON aggregation | FAILED on exception |

### md_plsql_func_executor_pkg
| Routine | Signature Summary | Side Effects | Errors/Status |
|---|---|---|---|
| execute_plsql_func | (rule_payload, source_values) -> computed_value_rec | Dynamic function invocation via execute immediate | FAILED on exception |

### Transaction Behavior
- No COMMIT/ROLLBACK statements found in analyzed package specs/bodies.
- Effective transaction boundary appears to be caller/session controlled.

## Suggested Improvements
- Promote key private routines (token substitution, gate evaluation, and consolidation precedence contracts) into explicit design docs with examples.
- Add a package-level error-code registry appendix to reduce duplicated ad-hoc code ranges.
- Add unit-level API compatibility checks for pks signatures.

## Evidence References
- plsql/packages/md_rule_executor_pkg.pks :: execute_run, execute_rule, persist_target_value, log_impact_trace, update_run_status, generate_fingerprint, record types
- plsql/packages/md_rule_executor_pkg.pkb :: evaluate_selection_gate, validate_sql_select_query, apply_sql_select_tokens, execute_sql_select_to_json, consolidate_rule_actions, execute_consolidated_actions_for_run, upsert_target_consolidation, upsert_consolidated_winner, substitute_tokens, substitute_change_delta_tokens, resolve_mapped_value
- plsql/packages/md_rule_selector_pkg.pks and plsql/packages/md_rule_selector_pkg.pkb :: populate_selected_rules
- plsql/packages/md_source_context_resolver_pkg.pks and plsql/packages/md_source_context_resolver_pkg.pkb :: resolve_rule_source_values, prefetch_selected_contexts, get_prefetched_rule_source_values
- sql/scripts/033_md_rule_input_expr_upgrade.sql :: md_rule_input_expr metadata structure
- plsql/packages/md_run_parameter_pkg.pks and plsql/packages/md_run_parameter_pkg.pkb :: load_run_parameters, persist_run_parameters, get_parameter_value, validate_required_parameters
- plsql/packages/md_expr_executor_pkg.pks and plsql/packages/md_expr_executor_pkg.pkb :: evaluate_expr, execute_expression
- plsql/packages/md_lookup_executor_pkg.pks and plsql/packages/md_lookup_executor_pkg.pkb :: execute_lookup
- plsql/packages/md_column_to_row_executor_pkg.pks and plsql/packages/md_column_to_row_executor_pkg.pkb :: execute_column_to_row
- plsql/packages/md_plsql_func_executor_pkg.pks and plsql/packages/md_plsql_func_executor_pkg.pkb :: execute_plsql_func
