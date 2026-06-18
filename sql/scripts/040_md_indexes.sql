-- 040_md_indexes.sql
-- Performance and lookup indexes (Oracle 19c)

prompt Creating MD indexes...

-- Core metadata indexes
create index md_release_tenant_ctx_st_ix on md_release (tenant_id, context_id, status);
create index md_object_release_ix on md_object (release_id, system_name, schema_name, object_name);
create index md_column_object_ix on md_column (object_id, column_name);
create index md_key_def_scope_ix on md_key_definition (release_id, key_scope, system_name, entity_name);
create index md_key_map_release_ix on md_key_mapping (release_id, source_key_id, target_key_id);
create index md_rule_release_status_ix on md_rule (release_id, status, active_flag);
create index md_rule_param_req_rule_ix on md_rule_parameter_requirement (rule_id, param_name, required_flag);
create index md_src_ctx_release_ix on md_source_context (release_id, active_flag);
create index md_src_ctx_obj_ctx_ix on md_source_context_object (source_context_id, object_alias, required_flag);
create index md_src_ctx_join_ctx_ix on md_source_context_join (source_context_id, left_alias, right_alias);
create index md_rule_src_ctx_rule_ix on md_rule_source_context (rule_id, source_context_id, active_flag);
create index md_rule_src_obj_rule_ix on md_rule_source_object (rule_id, source_alias, active_flag);
create index md_rule_src_join_rule_ix on md_rule_source_join (rule_id, join_order, active_flag);
create index md_corr_policy_release_ix on md_correlation_policy (release_id, active_flag, window_minutes);
create index md_rule_input_rule_ix on md_rule_input (rule_id, source_column_id);
create index md_rule_output_rule_ix on md_rule_output (rule_id, target_column_id);
create index md_rule_dep_release_ix on md_rule_dependency (release_id, upstream_rule_id, downstream_rule_id);
create index md_rule_tgt_release_ix on md_rule_target_action (release_id, rule_id, target_object_id);
create index md_rule_tgt_key_ix on md_rule_target_action (target_key_id, execution_mode, action_type);
create index md_rule_tgt_key_map_act_ix on md_rule_target_key_map (tenant_id, context_id, rule_target_action_id);
create index md_rule_tgt_col_map_act_ix on md_rule_target_column_map (tenant_id, context_id, rule_target_action_id);
create index md_pub_val_release_ix on md_publish_validation_result (release_id, severity, blocking_flag);

-- Runtime indexes
create index md_change_event_main_ix on md_change_event (tenant_id, context_id, event_type, event_ts);
create index md_change_event_key_ix on md_change_event (source_key_hash, processing_status);
create index md_change_event_release_ix on md_change_event (release_id);
create index md_change_delta_event_ix on md_change_event_column_delta (change_event_id, source_column_name);
create index md_run_main_ix on md_run (tenant_id, context_id, release_id, run_mode, run_status);
create index md_run_param_run_ix on md_run_parameter (run_id, param_name);
create index md_run_param_snap_run_ix on md_run_parameter_snapshot (run_id, parameter_hash);
create index md_run_corr_group_run_ix on md_run_correlation_group (run_id, correlation_key);
create index md_run_corr_group_evt_ix on md_run_correlation_group (anchor_change_event_id);
create index md_run_src_snap_run_ix on md_run_source_snapshot (run_id, rule_id, change_event_id);
create index md_proc_event_exp_ix on md_processed_event (expires_at, processed_at);
create index md_sel_rule_run_ix on md_run_selected_rule (run_id, rule_id, transitive_flag);
create index md_tgt_action_run_ix on md_run_target_action (run_id, action_type, applied_flag);
create index md_tgt_action_key_ix on md_run_target_action (target_key_hash);
create index md_tgt_action_exec_ix on md_run_target_action (execution_status, applied_flag, applied_at);
create index md_tgt_action_obj_ix on md_run_target_action (run_id, target_object_id, rule_id);
create index md_tgt_value_run_ix on md_run_target_value (run_id, target_column_name, value_status);
create index md_tgt_value_key_ix on md_run_target_value (target_key_hash, applied_flag);
create index md_impact_trace_run_ix on md_impact_trace (run_id, change_event_id);
create index md_override_req_status_ix on md_override_request (status, requested_at);
create index md_override_appr_req_ix on md_override_approval (override_request_id, approval_status);

-- Audit indexes
create index md_audit_evt_main_ix on md_audit_event (tenant_id, context_id, event_ts, event_type);
create index md_audit_evt_corr_ix on md_audit_event (correlation_id, run_id, release_id);
create index md_audit_detail_evt_ix on md_audit_event_detail (audit_event_id, attr_name);

prompt MD indexes script complete.
