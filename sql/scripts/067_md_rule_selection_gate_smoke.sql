-- 067_md_rule_selection_gate_smoke.sql
-- Smoke test for post-selection gate evaluation in executor.
-- Proves one selected rule passes gate and one is filtered.

whenever sqlerror continue
set serveroutput on

prompt Running rule selection gate smoke test...

declare
  l_tenant_id            varchar2(64) := 'TENANT_GATE_SMOKE';
  l_context_id           varchar2(64) := 'CTX_GATE_SMOKE';
  l_release_id           number;
  l_src_object_id        number;
  l_tgt_object_id        number;
  l_src_id_col_id        number;
  l_tgt_value_col_id     number;
  l_rule_pass_id         number;
  l_rule_filtered_id     number;
  l_run_id               number;
  l_change_event_id      number;
  l_result               md_rule_executor_pkg.run_result_rec;
  l_selected_count       number;
  l_passed_count         number;
  l_filtered_count       number;
  l_error_count          number;
  l_pass_rule_status     varchar2(20);
  l_filtered_rule_status varchar2(20);
  l_value_row_count      number;
  l_params_json          clob := '{"RUN_MODE":"GO"}';
begin
  insert into md_release (
    release_id, tenant_id, context_id, release_name, semantic_version, status, created_by, published_at
  ) values (
    md_release_seq.nextval, l_tenant_id, l_context_id, 'GATE_SMOKE_RELEASE', '1.0.0', 'PUBLISHED', 'gate_smoke', systimestamp
  ) returning release_id into l_release_id;

  insert into md_object (
    object_id, tenant_id, context_id, release_id, system_name, schema_name, object_name, object_type
  ) values (
    md_object_seq.nextval, l_tenant_id, l_context_id, l_release_id, 'SOURCE', 'IMRAN', 'MD_GATE_SMOKE_SRC', 'TABLE'
  ) returning object_id into l_src_object_id;

  insert into md_object (
    object_id, tenant_id, context_id, release_id, system_name, schema_name, object_name, object_type
  ) values (
    md_object_seq.nextval, l_tenant_id, l_context_id, l_release_id, 'TARGET', 'IMRAN', 'MD_GATE_SMOKE_TGT', 'TABLE'
  ) returning object_id into l_tgt_object_id;

  insert into md_column (
    column_id, tenant_id, context_id, object_id, column_name, data_type, nullable_flag, ordinal_position
  ) values (
    md_column_seq.nextval, l_tenant_id, l_context_id, l_src_object_id, 'ID', 'NUMBER', 'N', 1
  ) returning column_id into l_src_id_col_id;

  insert into md_column (
    column_id, tenant_id, context_id, object_id, column_name, data_type, nullable_flag, ordinal_position
  ) values (
    md_column_seq.nextval, l_tenant_id, l_context_id, l_tgt_object_id, 'GATE_RESULT', 'VARCHAR2', 'Y', 1
  ) returning column_id into l_tgt_value_col_id;

  insert into md_rule (
    rule_id,
    tenant_id,
    context_id,
    release_id,
    rule_name,
    rule_type,
    status,
    rule_payload,
    selection_gate_expr,
    selection_gate_enabled_flag,
    active_flag,
    created_by
  ) values (
    md_rule_seq.nextval,
    l_tenant_id,
    l_context_id,
    l_release_id,
    'R_GATE_PASS',
    'EXPRESSION',
    'PUBLISHED',
    '{}',
    'OLD.ID = ''0'' and NEW.ID = ''1'' and PARAM.RUN_MODE = ''GO'' and SRC.ID = ''1''',
    'Y',
    'Y',
    'gate_smoke'
  ) returning rule_id into l_rule_pass_id;

  insert into md_rule_input (
    rule_input_id, tenant_id, context_id, rule_id, source_column_id, required_flag
  ) values (
    md_rule_input_seq.nextval, l_tenant_id, l_context_id, l_rule_pass_id, l_src_id_col_id, 'Y'
  );

  insert into md_rule_output (
    rule_output_id, tenant_id, context_id, rule_id, target_column_id, output_expr
  ) values (
    md_rule_output_seq.nextval, l_tenant_id, l_context_id, l_rule_pass_id, l_tgt_value_col_id, 'SRC.ID'
  );

  insert into md_rule (
    rule_id,
    tenant_id,
    context_id,
    release_id,
    rule_name,
    rule_type,
    status,
    rule_payload,
    selection_gate_expr,
    selection_gate_enabled_flag,
    active_flag,
    created_by
  ) values (
    md_rule_seq.nextval,
    l_tenant_id,
    l_context_id,
    l_release_id,
    'R_GATE_FILTERED',
    'EXPRESSION',
    'PUBLISHED',
    '{}',
    'NEW.ID = ''2''',
    'Y',
    'Y',
    'gate_smoke'
  ) returning rule_id into l_rule_filtered_id;

  insert into md_rule_input (
    rule_input_id, tenant_id, context_id, rule_id, source_column_id, required_flag
  ) values (
    md_rule_input_seq.nextval, l_tenant_id, l_context_id, l_rule_filtered_id, l_src_id_col_id, 'Y'
  );

  insert into md_rule_output (
    rule_output_id, tenant_id, context_id, rule_id, target_column_id, output_expr
  ) values (
    md_rule_output_seq.nextval, l_tenant_id, l_context_id, l_rule_filtered_id, l_tgt_value_col_id, 'SRC.ID'
  );

  insert into md_run (
    run_id, tenant_id, context_id, release_id, run_mode, run_status, initiated_by, input_summary_json
  ) values (
    md_run_seq.nextval, l_tenant_id, l_context_id, l_release_id, 'SELECTIVE', 'RUNNING', 'gate_smoke', '{"scenario":"rule_gate_smoke"}'
  ) returning run_id into l_run_id;

  insert into md_change_event (
    change_event_id,
    tenant_id,
    context_id,
    release_id,
    event_type,
    source_system_name,
    source_entity_name,
    source_key_json,
    source_key_hash,
    event_ts,
    event_fingerprint,
    processing_status
  ) values (
    md_change_event_seq.nextval,
    l_tenant_id,
    l_context_id,
    l_release_id,
    'UPDATE',
    'SRC',
    'MD_GATE_SMOKE_SRC',
    '{"ID":1}',
    'GATE_SMOKE_HASH_1',
    systimestamp,
    'GATE_SMOKE_EVT_1',
    'NEW'
  ) returning change_event_id into l_change_event_id;

  insert into md_change_event_column_delta (
    change_event_column_delta_id,
    tenant_id,
    context_id,
    change_event_id,
    source_column_name,
    old_value_txt,
    new_value_txt,
    value_changed_flag
  ) values (
    md_change_event_col_delta_seq.nextval,
    l_tenant_id,
    l_context_id,
    l_change_event_id,
    'ID',
    '0',
    '1',
    'Y'
  );

  l_result := md_rule_executor_pkg.execute_run(
    p_run_id          => l_run_id,
    p_change_event_id => l_change_event_id,
    p_tenant_id       => l_tenant_id,
    p_context_id      => l_context_id,
    p_params_json     => l_params_json
  );

  select count(*)
    into l_selected_count
    from md_run_selected_rule
   where tenant_id = l_tenant_id
     and context_id = l_context_id
     and run_id = l_run_id
     and change_event_id = l_change_event_id;

  select count(*)
    into l_passed_count
    from md_run_selected_rule
   where tenant_id = l_tenant_id
     and context_id = l_context_id
     and run_id = l_run_id
     and change_event_id = l_change_event_id
     and gate_eval_status = 'PASSED';

  select count(*)
    into l_filtered_count
    from md_run_selected_rule
   where tenant_id = l_tenant_id
     and context_id = l_context_id
     and run_id = l_run_id
     and change_event_id = l_change_event_id
     and gate_eval_status = 'FILTERED';

  select count(*)
    into l_error_count
    from md_run_selected_rule
   where tenant_id = l_tenant_id
     and context_id = l_context_id
     and run_id = l_run_id
     and change_event_id = l_change_event_id
     and gate_eval_status = 'ERROR';

  select gate_eval_status
    into l_pass_rule_status
    from md_run_selected_rule
   where tenant_id = l_tenant_id
     and context_id = l_context_id
     and run_id = l_run_id
     and change_event_id = l_change_event_id
     and rule_id = l_rule_pass_id;

  select gate_eval_status
    into l_filtered_rule_status
    from md_run_selected_rule
   where tenant_id = l_tenant_id
     and context_id = l_context_id
     and run_id = l_run_id
     and change_event_id = l_change_event_id
     and rule_id = l_rule_filtered_id;

  select count(*)
    into l_value_row_count
    from md_run_target_value
   where tenant_id = l_tenant_id
     and context_id = l_context_id
     and run_id = l_run_id
     and change_event_id is null;

  dbms_output.put_line('run_status=' || l_result.run_status);
  dbms_output.put_line('rules_selected=' || l_result.metrics.rules_selected);
  dbms_output.put_line('rules_executed=' || l_result.metrics.rules_executed);
  dbms_output.put_line('selected_rule_rows=' || l_selected_count);
  dbms_output.put_line('passed_gate_count=' || l_passed_count);
  dbms_output.put_line('filtered_gate_count=' || l_filtered_count);
  dbms_output.put_line('error_gate_count=' || l_error_count);
  dbms_output.put_line('pass_rule_gate_status=' || l_pass_rule_status);
  dbms_output.put_line('filtered_rule_gate_status=' || l_filtered_rule_status);
  dbms_output.put_line('persisted_target_values=' || l_value_row_count);

  if l_selected_count <> 2 then
    raise_application_error(-20601, 'Expected two selected rules; found ' || l_selected_count);
  end if;

  if l_passed_count <> 1 or l_filtered_count <> 1 then
    raise_application_error(-20602, 'Expected one PASSED and one FILTERED gate status; found passed=' || l_passed_count || ', filtered=' || l_filtered_count);
  end if;

  if l_error_count <> 0 then
    raise_application_error(-20603, 'Expected zero gate errors; found ' || l_error_count);
  end if;

  if l_result.metrics.rules_executed <> 1 then
    raise_application_error(-20604, 'Expected exactly one executed rule; found ' || l_result.metrics.rules_executed);
  end if;

  if l_value_row_count <> 1 then
    raise_application_error(-20605, 'Expected exactly one persisted target value from passed rule; found ' || l_value_row_count);
  end if;

  delete from md_run_target_action where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_run_target_value where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_impact_trace where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_run_selected_rule where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_run_source_snapshot where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_run_correlation_group where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_change_event_column_delta where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_change_event where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_run_parameter where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_run_parameter_snapshot where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_rule_output where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_rule_input where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_rule where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_column where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_object where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_run where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_release where tenant_id = l_tenant_id and context_id = l_context_id;

  commit;
exception
  when others then
    dbms_output.put_line('rule_selection_gate_smoke failed: ' || sqlerrm);
    rollback;
    raise;
end;
/

prompt Rule selection gate smoke test complete.
