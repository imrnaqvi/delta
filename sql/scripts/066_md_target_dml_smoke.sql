-- 066_md_target_dml_smoke.sql
-- Smoke test for end-to-end target DML execution.
-- Proves one UPDATE and one INSERT against a real target table.

whenever sqlerror continue
set serveroutput on

prompt Running target DML smoke test...

begin
  execute immediate 'drop table md_target_dml_smoke_tgt purge';
exception
  when others then
    if sqlcode != -942 then
      raise;
    end if;
end;
/

create table md_target_dml_smoke_tgt (
  smoke_id    number primary key,
  smoke_value varchar2(100) not null
);

insert into md_target_dml_smoke_tgt (smoke_id, smoke_value) values (1, 'BEFORE_UPDATE');
commit;

declare
  l_tenant_id            varchar2(64) := 'TENANT_TGT_SMOKE';
  l_context_id           varchar2(64) := 'CTX_TGT_SMOKE';
  l_release_id           number;
  l_src_object_id        number;
  l_tgt_object_id        number;
  l_src_id_col_id        number;
  l_tgt_id_col_id        number;
  l_tgt_value_col_id     number;
  l_key_def_id           number;
  l_key_comp_id          number;
  l_rule_id              number;
  l_run_id               number;
  l_change_event_id      number;
  l_rule_output_id       number;
  l_update_action_id     number;
  l_insert_action_id     number;
  l_update_key_map_id    number;
  l_insert_key_map_id    number;
  l_update_col_map_id    number;
  l_insert_col_map_id    number;
  l_result               md_rule_executor_pkg.run_result_rec;
  l_update_count         number;
  l_insert_count         number;
  l_update_status        varchar2(20);
  l_insert_status        varchar2(20);
  l_update_sql_text      clob;
  l_insert_sql_text      clob;
  l_target_1_value       varchar2(100);
  l_target_2_value       varchar2(100);
  l_params_json          clob := '{"UPDATE_VALUE":"UPDATED_BY_SMOKE"}';
  l_selected_count       number;
begin
  insert into md_release (
    release_id, tenant_id, context_id, release_name, semantic_version, status, created_by, published_at
  ) values (
    md_release_seq.nextval, l_tenant_id, l_context_id, 'TGT_SMOKE_RELEASE', '1.0.0', 'PUBLISHED', 'target_smoke', systimestamp
  ) returning release_id into l_release_id;

  insert into md_object (
    object_id, tenant_id, context_id, release_id, system_name, schema_name, object_name, object_type
  ) values (
    md_object_seq.nextval, l_tenant_id, l_context_id, l_release_id, 'SOURCE', 'IMRAN', 'MD_TARGET_DML_SMOKE_SRC', 'TABLE'
  ) returning object_id into l_src_object_id;

  insert into md_object (
    object_id, tenant_id, context_id, release_id, system_name, schema_name, object_name, object_type
  ) values (
    md_object_seq.nextval, l_tenant_id, l_context_id, l_release_id, 'TARGET', 'IMRAN', 'MD_TARGET_DML_SMOKE_TGT', 'TABLE'
  ) returning object_id into l_tgt_object_id;

  insert into md_column (
    column_id, tenant_id, context_id, object_id, column_name, data_type, nullable_flag, ordinal_position
  ) values (
    md_column_seq.nextval, l_tenant_id, l_context_id, l_src_object_id, 'ID', 'NUMBER', 'N', 1
  ) returning column_id into l_src_id_col_id;

  insert into md_column (
    column_id, tenant_id, context_id, object_id, column_name, data_type, nullable_flag, ordinal_position
  ) values (
    md_column_seq.nextval, l_tenant_id, l_context_id, l_tgt_object_id, 'SMOKE_ID', 'NUMBER', 'N', 1
  ) returning column_id into l_tgt_id_col_id;

  insert into md_column (
    column_id, tenant_id, context_id, object_id, column_name, data_type, nullable_flag, ordinal_position
  ) values (
    md_column_seq.nextval, l_tenant_id, l_context_id, l_tgt_object_id, 'SMOKE_VALUE', 'VARCHAR2', 'N', 2
  ) returning column_id into l_tgt_value_col_id;

  insert into md_key_definition (
    key_id, tenant_id, context_id, release_id, key_scope, system_name, entity_name, key_name, key_type, active_flag
  ) values (
    md_key_definition_seq.nextval, l_tenant_id, l_context_id, l_release_id, 'TARGET', 'IMRAN', 'MD_TARGET_DML_SMOKE_TGT', 'PK_SMOKE', 'SURROGATE', 'Y'
  ) returning key_id into l_key_def_id;

  insert into md_key_component (
    key_component_id, tenant_id, context_id, key_id, column_id, ordinal_position
  ) values (
    md_key_component_seq.nextval, l_tenant_id, l_context_id, l_key_def_id, l_tgt_id_col_id, 1
  ) returning key_component_id into l_key_comp_id;

  insert into md_rule (
    rule_id, tenant_id, context_id, release_id, rule_name, rule_type, status, rule_payload, active_flag, created_by
  ) values (
    md_rule_seq.nextval,
    l_tenant_id,
    l_context_id,
    l_release_id,
    'R_TGT_SMOKE_UPDATE_INSERT',
    'EXPRESSION',
    'PUBLISHED',
    '{}',
    'Y',
    'target_smoke'
  ) returning rule_id into l_rule_id;

  insert into md_rule_input (
    rule_input_id, tenant_id, context_id, rule_id, source_column_id, required_flag
  ) values (
    md_rule_input_seq.nextval, l_tenant_id, l_context_id, l_rule_id, l_src_id_col_id, 'Y'
  );

  insert into md_rule_output (
    rule_output_id, tenant_id, context_id, rule_id, target_column_id, output_expr
  ) values (
    md_rule_output_seq.nextval, l_tenant_id, l_context_id, l_rule_id, l_tgt_value_col_id, 'SRC.ID'
  ) returning rule_output_id into l_rule_output_id;

  insert into md_rule_target_action (
    rule_target_action_id,
    tenant_id,
    context_id,
    release_id,
    rule_id,
    target_object_id,
    target_key_id,
    target_column_id,
    action_type,
    execution_mode,
    missing_row_policy,
    delete_policy,
    action_condition_expr,
    created_at
  ) values (
    md_rule_target_action_seq.nextval,
    l_tenant_id,
    l_context_id,
    l_release_id,
    l_rule_id,
    l_tgt_object_id,
    l_key_def_id,
    l_tgt_value_col_id,
    'UPDATE',
    'APPLY',
    'INSERT',
    'RULE_DEFINED',
    null,
    systimestamp
  ) returning rule_target_action_id into l_update_action_id;

  insert into md_rule_target_action (
    rule_target_action_id,
    tenant_id,
    context_id,
    release_id,
    rule_id,
    target_object_id,
    target_key_id,
    target_column_id,
    action_type,
    execution_mode,
    missing_row_policy,
    delete_policy,
    action_condition_expr,
    created_at
  ) values (
    md_rule_target_action_seq.nextval,
    l_tenant_id,
    l_context_id,
    l_release_id,
    l_rule_id,
    l_tgt_object_id,
    l_key_def_id,
    l_tgt_value_col_id,
    'INSERT',
    'APPLY',
    'SKIP',
    'RULE_DEFINED',
    null,
    systimestamp
  ) returning rule_target_action_id into l_insert_action_id;

  insert into md_rule_target_key_map (
    rule_target_key_map_id,
    tenant_id,
    context_id,
    release_id,
    rule_target_action_id,
    target_key_component_id,
    source_kind,
    source_expr,
    required_flag,
    created_at
  ) values (
    md_rule_target_key_map_seq.nextval,
    l_tenant_id,
    l_context_id,
    l_release_id,
    l_update_action_id,
    l_key_comp_id,
    'LITERAL',
    '1',
    'Y',
    systimestamp
  ) returning rule_target_key_map_id into l_update_key_map_id;

  insert into md_rule_target_key_map (
    rule_target_key_map_id,
    tenant_id,
    context_id,
    release_id,
    rule_target_action_id,
    target_key_component_id,
    source_kind,
    source_expr,
    required_flag,
    created_at
  ) values (
    md_rule_target_key_map_seq.nextval,
    l_tenant_id,
    l_context_id,
    l_release_id,
    l_insert_action_id,
    l_key_comp_id,
    'LITERAL',
    '2',
    'Y',
    systimestamp
  ) returning rule_target_key_map_id into l_insert_key_map_id;

  insert into md_rule_target_column_map (
    rule_target_column_map_id,
    tenant_id,
    context_id,
    release_id,
    rule_target_action_id,
    target_column_id,
    value_source_kind,
    value_expr,
    required_flag,
    write_on_insert_flag,
    write_on_update_flag,
    created_at
  ) values (
    md_rule_target_column_map_seq.nextval,
    l_tenant_id,
    l_context_id,
    l_release_id,
    l_update_action_id,
    l_tgt_value_col_id,
    'PARAM',
    'UPDATE_VALUE',
    'Y',
    'Y',
    'Y',
    systimestamp
  ) returning rule_target_column_map_id into l_update_col_map_id;

  insert into md_rule_target_column_map (
    rule_target_column_map_id,
    tenant_id,
    context_id,
    release_id,
    rule_target_action_id,
    target_column_id,
    value_source_kind,
    value_expr,
    required_flag,
    write_on_insert_flag,
    write_on_update_flag,
    created_at
  ) values (
    md_rule_target_column_map_seq.nextval,
    l_tenant_id,
    l_context_id,
    l_release_id,
    l_insert_action_id,
    l_tgt_value_col_id,
    'LITERAL',
    'INSERTED_BY_SMOKE',
    'Y',
    'Y',
    'Y',
    systimestamp
  ) returning rule_target_column_map_id into l_insert_col_map_id;

  insert into md_run (
    run_id, tenant_id, context_id, release_id, run_mode, run_status, initiated_by, input_summary_json
  ) values (
    md_run_seq.nextval, l_tenant_id, l_context_id, l_release_id, 'SELECTIVE', 'RUNNING', 'target_smoke', '{"scenario":"target_dml_smoke"}'
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
    'MD_TARGET_DML_SMOKE_SRC',
    '{"ID":1}',
    'SMOKE_HASH_1',
    systimestamp,
    'SMOKE_EVT_1',
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

  dbms_output.put_line('run_status=' || l_result.run_status);
  dbms_output.put_line('rules_selected=' || l_result.metrics.rules_selected);
  dbms_output.put_line('rules_executed=' || l_result.metrics.rules_executed);
  dbms_output.put_line('selected_rule_rows=' || l_selected_count);
  if l_result.error_messages is not null and l_result.error_messages.count > 0 then
    for i in 1 .. l_result.error_messages.count loop
      dbms_output.put_line('run_error=' || l_result.error_messages(i));
    end loop;
  end if;

  select max(case when smoke_id = 1 then smoke_value end),
         max(case when smoke_id = 2 then smoke_value end)
    into l_target_1_value,
         l_target_2_value
    from md_target_dml_smoke_tgt;

  select count(*) into l_update_count
    from md_run_target_action
   where tenant_id = l_tenant_id
     and context_id = l_context_id
     and run_id = l_run_id
     and action_type = 'UPDATE'
     and execution_status = 'EXECUTED';

  select count(*) into l_insert_count
    from md_run_target_action
   where tenant_id = l_tenant_id
     and context_id = l_context_id
     and run_id = l_run_id
     and action_type = 'INSERT'
     and execution_status = 'EXECUTED';

  if l_update_count > 0 then
    select execution_status, dbms_lob.substr(generated_sql_text, 4000, 1)
      into l_update_status, l_update_sql_text
      from md_run_target_action
     where tenant_id = l_tenant_id
       and context_id = l_context_id
       and run_id = l_run_id
       and action_type = 'UPDATE'
       fetch first 1 row only;
  end if;

  if l_insert_count > 0 then
    select execution_status, dbms_lob.substr(generated_sql_text, 4000, 1)
      into l_insert_status, l_insert_sql_text
      from md_run_target_action
     where tenant_id = l_tenant_id
       and context_id = l_context_id
       and run_id = l_run_id
       and action_type = 'INSERT'
       fetch first 1 row only;
  end if;

  dbms_output.put_line('update_action_status=' || nvl(l_update_status, 'NULL'));
  dbms_output.put_line('insert_action_status=' || nvl(l_insert_status, 'NULL'));
  dbms_output.put_line('update_action_sql=' || substr(l_update_sql_text, 1, 4000));
  dbms_output.put_line('insert_action_sql=' || substr(l_insert_sql_text, 1, 4000));

  if l_target_1_value <> 'UPDATED_BY_SMOKE' then
    raise_application_error(-20501, 'UPDATE did not apply as expected; found ' || l_target_1_value);
  end if;

  if l_target_2_value <> 'INSERTED_BY_SMOKE' then
    raise_application_error(-20502, 'INSERT did not apply as expected; found ' || l_target_2_value);
  end if;

  if l_update_count <> 1 or l_insert_count <> 1 then
    raise_application_error(-20503, 'Expected one executed UPDATE and one executed INSERT; found update=' || l_update_count || ', insert=' || l_insert_count);
  end if;

  dbms_output.put_line('target_dml_smoke status=' || l_result.run_status);
  dbms_output.put_line('target_row_1=' || l_target_1_value);
  dbms_output.put_line('target_row_2=' || l_target_2_value);
  dbms_output.put_line('executed_update_actions=' || l_update_count);
  dbms_output.put_line('executed_insert_actions=' || l_insert_count);

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
  delete from md_rule_target_column_map where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_rule_target_key_map where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_rule_target_action where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_rule_output where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_rule_input where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_rule where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_key_component where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_key_definition where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_column where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_object where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_run where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_release where tenant_id = l_tenant_id and context_id = l_context_id;

  commit;
exception
  when others then
    dbms_output.put_line('target_dml_smoke failed: ' || sqlerrm);
    rollback;
    raise;
end;
/

begin
  execute immediate 'drop table md_target_dml_smoke_tgt purge';
exception
  when others then
    if sqlcode != -942 then
      raise;
    end if;
end;
/

prompt Target DML smoke test complete.
