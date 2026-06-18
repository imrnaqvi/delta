-- 050_md_pk_triggers.sql
-- BEFORE INSERT triggers to populate PKs from explicit MD_* sequences.

prompt Creating MD PK triggers...

create or replace trigger md_release_bi_trg
before insert on md_release
for each row
when (new.release_id is null)
begin
  :new.release_id := md_release_seq.nextval;
end;
/

create or replace trigger md_object_bi_trg
before insert on md_object
for each row
when (new.object_id is null)
begin
  :new.object_id := md_object_seq.nextval;
end;
/

create or replace trigger md_column_bi_trg
before insert on md_column
for each row
when (new.column_id is null)
begin
  :new.column_id := md_column_seq.nextval;
end;
/

create or replace trigger md_key_definition_bi_trg
before insert on md_key_definition
for each row
when (new.key_id is null)
begin
  :new.key_id := md_key_definition_seq.nextval;
end;
/

create or replace trigger md_key_component_bi_trg
before insert on md_key_component
for each row
when (new.key_component_id is null)
begin
  :new.key_component_id := md_key_component_seq.nextval;
end;
/

create or replace trigger md_key_mapping_bi_trg
before insert on md_key_mapping
for each row
when (new.key_mapping_id is null)
begin
  :new.key_mapping_id := md_key_mapping_seq.nextval;
end;
/

create or replace trigger md_rule_bi_trg
before insert on md_rule
for each row
when (new.rule_id is null)
begin
  :new.rule_id := md_rule_seq.nextval;
end;
/

create or replace trigger md_expr_allowed_fn_bi_trg
before insert on md_expr_allowed_function
for each row
when (new.expr_allowed_function_id is null)
begin
  :new.expr_allowed_function_id := md_expr_allowed_function_seq.nextval;
end;
/

create or replace trigger md_rule_param_req_bi_trg
before insert on md_rule_parameter_requirement
for each row
when (new.rule_parameter_requirement_id is null)
begin
  :new.rule_parameter_requirement_id := md_rule_parameter_requirement_seq.nextval;
end;
/

create or replace trigger md_source_context_bi_trg
before insert on md_source_context
for each row
when (new.source_context_id is null)
begin
  :new.source_context_id := md_source_context_seq.nextval;
end;
/

create or replace trigger md_source_context_object_bi_trg
before insert on md_source_context_object
for each row
when (new.source_context_object_id is null)
begin
  :new.source_context_object_id := md_source_context_object_seq.nextval;
end;
/

create or replace trigger md_source_context_join_bi_trg
before insert on md_source_context_join
for each row
when (new.source_context_join_id is null)
begin
  :new.source_context_join_id := md_source_context_join_seq.nextval;
end;
/

create or replace trigger md_rule_source_context_bi_trg
before insert on md_rule_source_context
for each row
when (new.rule_source_context_id is null)
begin
  :new.rule_source_context_id := md_rule_source_context_seq.nextval;
end;
/

create or replace trigger md_rule_source_object_bi_trg
before insert on md_rule_source_object
for each row
when (new.rule_source_object_id is null)
begin
  :new.rule_source_object_id := md_rule_source_object_seq.nextval;
end;
/

create or replace trigger md_rule_source_join_bi_trg
before insert on md_rule_source_join
for each row
when (new.rule_source_join_id is null)
begin
  :new.rule_source_join_id := md_rule_source_join_seq.nextval;
end;
/

create or replace trigger md_rule_input_bi_trg
before insert on md_rule_input
for each row
when (new.rule_input_id is null)
begin
  :new.rule_input_id := md_rule_input_seq.nextval;
end;
/

create or replace trigger md_rule_output_bi_trg
before insert on md_rule_output
for each row
when (new.rule_output_id is null)
begin
  :new.rule_output_id := md_rule_output_seq.nextval;
end;
/

create or replace trigger md_rule_dependency_bi_trg
before insert on md_rule_dependency
for each row
when (new.rule_dependency_id is null)
begin
  :new.rule_dependency_id := md_rule_dependency_seq.nextval;
end;
/

create or replace trigger md_rule_dep_condition_bi_trg
before insert on md_rule_dependency_condition
for each row
when (new.rule_dependency_condition_id is null)
begin
  :new.rule_dependency_condition_id := md_rule_dep_condition_seq.nextval;
end;
/

create or replace trigger md_rule_target_action_bi_trg
before insert on md_rule_target_action
for each row
when (new.rule_target_action_id is null)
begin
  :new.rule_target_action_id := md_rule_target_action_seq.nextval;
end;
/

create or replace trigger md_rule_target_key_map_bi_trg
before insert on md_rule_target_key_map
for each row
when (new.rule_target_key_map_id is null)
begin
  :new.rule_target_key_map_id := md_rule_target_key_map_seq.nextval;
end;
/

create or replace trigger md_rule_target_col_map_bi_trg
before insert on md_rule_target_column_map
for each row
when (new.rule_target_column_map_id is null)
begin
  :new.rule_target_column_map_id := md_rule_target_column_map_seq.nextval;
end;
/

create or replace trigger md_delete_policy_bi_trg
before insert on md_delete_policy
for each row
when (new.delete_policy_id is null)
begin
  :new.delete_policy_id := md_delete_policy_seq.nextval;
end;
/

create or replace trigger md_publish_validation_bi_trg
before insert on md_publish_validation_result
for each row
when (new.publish_validation_result_id is null)
begin
  :new.publish_validation_result_id := md_publish_validation_result_seq.nextval;
end;
/

create or replace trigger md_override_request_bi_trg
before insert on md_override_request
for each row
when (new.override_request_id is null)
begin
  :new.override_request_id := md_override_request_seq.nextval;
end;
/

create or replace trigger md_correlation_policy_bi_trg
before insert on md_correlation_policy
for each row
when (new.correlation_policy_id is null)
begin
  :new.correlation_policy_id := md_correlation_policy_seq.nextval;
end;
/

create or replace trigger md_change_event_raw_bi_trg
before insert on md_change_event_raw
for each row
when (new.change_event_raw_id is null)
begin
  :new.change_event_raw_id := md_change_event_raw_seq.nextval;
end;
/

create or replace trigger md_change_event_bi_trg
before insert on md_change_event
for each row
when (new.change_event_id is null)
begin
  :new.change_event_id := md_change_event_seq.nextval;
end;
/

create or replace trigger md_change_event_delta_bi_trg
before insert on md_change_event_column_delta
for each row
when (new.change_event_column_delta_id is null)
begin
  :new.change_event_column_delta_id := md_change_event_col_delta_seq.nextval;
end;
/

create or replace trigger md_execution_policy_bi_trg
before insert on md_execution_policy
for each row
when (new.execution_policy_id is null)
begin
  :new.execution_policy_id := md_execution_policy_seq.nextval;
end;
/

create or replace trigger md_run_bi_trg
before insert on md_run
for each row
when (new.run_id is null)
begin
  :new.run_id := md_run_seq.nextval;
end;
/

create or replace trigger md_run_param_bi_trg
before insert on md_run_parameter
for each row
when (new.run_parameter_id is null)
begin
  :new.run_parameter_id := md_run_parameter_seq.nextval;
end;
/

create or replace trigger md_run_param_snap_bi_trg
before insert on md_run_parameter_snapshot
for each row
when (new.run_parameter_snapshot_id is null)
begin
  :new.run_parameter_snapshot_id := md_run_parameter_snapshot_seq.nextval;
end;
/

create or replace trigger md_run_corr_group_bi_trg
before insert on md_run_correlation_group
for each row
when (new.run_correlation_group_id is null)
begin
  :new.run_correlation_group_id := md_run_correlation_group_seq.nextval;
end;
/

create or replace trigger md_run_source_snapshot_bi_trg
before insert on md_run_source_snapshot
for each row
when (new.run_source_snapshot_id is null)
begin
  :new.run_source_snapshot_id := md_run_source_snapshot_seq.nextval;
end;
/

create or replace trigger md_processed_event_bi_trg
before insert on md_processed_event
for each row
when (new.processed_event_id is null)
begin
  :new.processed_event_id := md_processed_event_seq.nextval;
end;
/

create or replace trigger md_run_selected_rule_bi_trg
before insert on md_run_selected_rule
for each row
when (new.run_selected_rule_id is null)
begin
  :new.run_selected_rule_id := md_run_selected_rule_seq.nextval;
end;
/

create or replace trigger md_run_target_action_bi_trg
before insert on md_run_target_action
for each row
when (new.run_target_action_id is null)
begin
  :new.run_target_action_id := md_run_target_action_seq.nextval;
end;
/

create or replace trigger md_run_target_value_bi_trg
before insert on md_run_target_value
for each row
when (new.run_target_value_id is null)
begin
  :new.run_target_value_id := md_run_target_value_seq.nextval;
end;
/

create or replace trigger md_impact_trace_bi_trg
before insert on md_impact_trace
for each row
when (new.impact_trace_id is null)
begin
  :new.impact_trace_id := md_impact_trace_seq.nextval;
end;
/

create or replace trigger md_override_approval_bi_trg
before insert on md_override_approval
for each row
when (new.override_approval_id is null)
begin
  :new.override_approval_id := md_override_approval_seq.nextval;
end;
/

create or replace trigger md_audit_event_bi_trg
before insert on md_audit_event
for each row
when (new.audit_event_id is null)
begin
  :new.audit_event_id := md_audit_event_seq.nextval;
end;
/

create or replace trigger md_audit_event_detail_bi_trg
before insert on md_audit_event_detail
for each row
when (new.audit_event_detail_id is null)
begin
  :new.audit_event_detail_id := md_audit_event_detail_seq.nextval;
end;
/

prompt MD PK trigger script complete.
