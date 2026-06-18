# Epic 1 Selective-Lineage Traceability Matrix

Source brief: [_bmad-output/planning-artifacts/briefs/phase1-epics-and-stories-metadata-driven-oracle-transformation-engine-2026-06-17.md](_bmad-output/planning-artifacts/briefs/phase1-epics-and-stories-metadata-driven-oracle-transformation-engine-2026-06-17.md)

## Matrix

| Criterion ID | Requirement Summary | Primary Metadata Entities | Key Fields | Validation / Control | Runtime Outcome |
|---|---|---|---|---|---|
| Scope-Selective-1 | Process only impacted rules/targets for update/insert/delete/key-change | md_change_event_type, md_rule_dependency, md_rule_target_action | event_type, source_column_id, rule_id, target_column_id | Impact resolver must return direct + transitive rule set | Only impacted target update/insert/delete actions executed |
| 1.1.5 | Link source columns to rule inputs and rule outputs to target columns | md_rule_input, md_rule_output | source_column_id, rule_id, target_column_id | No orphan rule input/output links at publish | Explainable source-column to target-column trace |
| 1.1.6 | Support composite keys and surrogate mappings | md_key_definition, md_key_component, md_key_mapping | key_type, key_id, column_id, ordinal | Every in-scope flow has source+target key mapping | Key-based upsert/delete routing |
| 1.1.7 | Key propagation lineage source->target | md_lineage_key, md_lineage_key_component | source_key_component_id, target_key_component_id | Completeness check for each mapped flow | Key lineage available for impact drilldown |
| 1.2.5 | Block publish if lineage links unresolved | md_publish_validation_result | release_id, validation_code, object_ref | Hard fail on unresolved source-column/rule/target links | No incomplete metadata can run |
| 1.2.6 | Block publish if key mappings missing | md_publish_validation_result, md_key_mapping | release_id, flow_id, key_mapping_status | Hard fail when required key map absent | Prevent non-routable selective events |
| 1.3.5 | Audit selective input/output details | md_audit_event, md_audit_event_detail | run_id, source_key_json, changed_columns_json, selected_rules_json, target_actions_json | Required fields enforced for SELECTIVE_RUN event types | Full forensic replay of selective decisions |
| 1.3.6 | Audit override approvals | md_override_request, md_override_approval, md_audit_event | override_id, approver_id, reason_code | Role and approval evidence required before activation | Governed exception handling |
| 1.4.1 | Standardize change-event types | md_change_event_type | code (UPDATE/INSERT/DELETE/KEY_CHANGE) | Controlled enum with versioning | Uniform event handling behavior |
| 1.4.2 | Event schema includes keys, changed cols, old/new values | md_change_event, md_change_event_column_delta | event_id, source_key_hash, column_id, old_value, new_value | Schema validation on ingestion | Column-level impact resolution input |
| 1.4.3 | Map source column changes to direct + transitive rules | md_rule_dependency, md_rule_graph_edge | source_column_id, upstream_rule_id, downstream_rule_id | Graph closure check at publish | Complete impacted rule set selection |
| 1.4.4 | Map rules to target table/column actions | md_rule_target_action | rule_id, target_table_id, target_column_id, action_type | Every executable rule has at least one target action | Target action plan generated |
| 1.4.5 | Delete behavior configurable per mapping/rule | md_delete_policy | scope_type, scope_id, policy (HARD/SOFT/RULE_DEFINED) | Effective policy resolution test per flow | Correct delete vs soft-delete behavior |
| 1.5.1 | Deterministic ordering for same batch | md_execution_policy | ordering_key, tie_breaker | Determinism test on replay | Stable action sequence |
| 1.5.2 | Idempotent reprocessing | md_processed_event, md_idempotency_token | batch_id, event_fingerprint, processed_at | Duplicate detection before apply | No duplicate side effects |
| 1.5.3 | Distinct key-change semantics from delete+insert | md_change_event, md_lineage_key_change | old_key_json, new_key_json, semantic_type | Semantic consistency checks in validator | Preserved continuity in lineage/audit |
| 1.5.4 | Runtime include/exclude override by role | md_override_request, md_override_scope | principal_id, scope_json, effective_window | Role guard + approval gate | Controlled selective run overrides |
| 1.5.5 | Immutable override evidence in audit | md_audit_event, md_audit_snapshot | event_hash, previous_hash, immutable_flag | Append-only + hash-chain check | Tamper-evident override history |
| 2.1.5 | Mapping pack defines source/target keys | md_mapping_pack, md_key_mapping | mapping_pack_id, source_key_id, target_key_id | Pack completeness gate | Runnable key-aware mappings |
| 2.1.6 | Each target column linked through rule IO | md_column_mapping, md_rule_input, md_rule_output | target_column_id, source_column_id, rule_id | Link integrity validation | End-to-end column traceability |
| 2.2.5 | Rule metadata includes explicit dependencies/outputs | md_rule, md_rule_input, md_rule_output | rule_id, dependency_count, output_count | Rule publish check for missing dependencies | Accurate impact eligibility |
| 2.2.6 | Rule selected only when dependency conditions met | md_rule_dependency_condition | rule_id, condition_sql_or_expr | Condition evaluation tests | Precise rule triggering |
| 2.3.5 | Selective run accepts events with keys+changed values | md_change_event, md_change_event_column_delta | event_id, source_key_json, deltas_json | Ingestion contract tests | Proper event-driven execution input |
| 2.3.6 | Execute only direct+transitive impacted rules | md_run_selected_rule | run_id, rule_id, selection_reason | Rule-set diff test vs expected graph closure | Minimal necessary computation |
| 2.3.7 | Produce only impacted target actions by key | md_run_target_action, md_run_target_value | run_id, target_key_json, action_type, target_column_name, computed_value_txt | Action-set diff test vs expected impacts and computed values | Minimal target writes with queryable computed target values |
| 2.3.8 | Output explainable impact trace | md_impact_trace, md_run_target_value | run_id, source_ref, rule_ref, target_ref, target_column_name | Trace completeness and referential checks | Human-readable explainability with per-column computed values |
| 2.3.9 | Selective rerun is idempotent | md_processed_event, md_run_target_action | event_fingerprint, action_fingerprint | Replay test must produce zero net new effects | Safe replay behavior |

## Suggested Physical Table Starters

1. md_change_event
2. md_change_event_column_delta
3. md_key_definition
4. md_key_component
5. md_key_mapping
6. md_rule_dependency
7. md_rule_target_action
8. md_delete_policy
9. md_execution_policy
10. md_processed_event
11. md_override_request
12. md_override_approval
13. md_impact_trace
14. md_run_selected_rule
15. md_run_target_action
16. md_run_target_value
17. md_publish_validation_result

## Minimum Publish Gates

1. No unresolved source column -> rule input links.
2. No unresolved rule output -> target column links.
3. Every in-scope flow has source and target key mappings.
4. Rule dependency graph is acyclic or explicitly bounded where cycles are allowed.
5. Delete policy resolves deterministically at mapping/rule level.
6. Override scopes are role-restricted and approval-backed.
