-- 074_md_sql_select_rule_smoke.sql
-- Smoke test for SQL_SELECT rule mode.
-- Validates:
--   1) Standalone SELECT rule execution without source context/scalar_expr metadata
--   2) Output alias derivation from SELECT result columns
--   3) Allowance for UNION and SQL function expressions
--   4) Allowance for PL/SQL function call in SQL expression
--   5) Guardrail rejection for non-SELECT statement payload
--   6) Cardinality failures for zero-row and multi-row results
--   7) Normal consolidation + consolidated execution for successful rules

whenever sqlerror continue
set serveroutput on

prompt Running SQL_SELECT rule smoke test...

prompt Ensuring prerequisite upgrades for SQL_SELECT smoke...
@C:\Users\imrna\delta\sql\scripts\034_md_rule_priority_upgrade.sql
@C:\Users\imrna\delta\sql\scripts\035_md_target_consolidation_runtime_upgrade.sql
@C:\Users\imrna\delta\sql\scripts\036_md_sql_select_rule_upgrade.sql

begin
  execute immediate 'drop table md_sql_select_smoke_tgt purge';
exception
  when others then
    if sqlcode != -942 then
      raise;
    end if;
end;
/

begin
  execute immediate 'drop function md_sql_select_smoke_fn';
exception
  when others then
    if sqlcode != -4043 then
      raise;
    end if;
end;
/

create table md_sql_select_smoke_tgt (
  smoke_id    number primary key,
  smoke_value varchar2(100) not null
);

create or replace function md_sql_select_smoke_fn(
  p_txt in varchar2
) return varchar2 is
begin
  return 'FN_' || p_txt;
end;
/

insert into md_sql_select_smoke_tgt (smoke_id, smoke_value) values (1, 'BEFORE_1');
insert into md_sql_select_smoke_tgt (smoke_id, smoke_value) values (2, 'BEFORE_2');
insert into md_sql_select_smoke_tgt (smoke_id, smoke_value) values (3, 'BEFORE_3');
insert into md_sql_select_smoke_tgt (smoke_id, smoke_value) values (4, 'BEFORE_4');
insert into md_sql_select_smoke_tgt (smoke_id, smoke_value) values (5, 'BEFORE_5');
insert into md_sql_select_smoke_tgt (smoke_id, smoke_value) values (6, 'BEFORE_6');
insert into md_sql_select_smoke_tgt (smoke_id, smoke_value) values (7, 'BEFORE_7');
commit;

declare
  l_tenant_id             varchar2(64) := 'TENANT_SQL_SELECT_SMOKE';
  l_context_id            varchar2(64) := 'CTX_SQL_SELECT_SMOKE';
  l_schema_name           varchar2(128) := sys_context('USERENV', 'CURRENT_SCHEMA');

  l_release_id            number;
  l_src_object_id         number;
  l_tgt_object_id         number;
  l_src_id_col_id         number;
  l_tgt_id_col_id         number;
  l_tgt_value_col_id      number;
  l_key_def_id            number;
  l_key_comp_id           number;

  l_rule_simple_id        number;
  l_rule_union_id         number;
  l_rule_sql_func_id      number;
  l_rule_plsql_func_id    number;
  l_rule_blocked_id       number;
  l_rule_zero_id          number;
  l_rule_multi_id         number;

  l_run_id                number;
  l_change_event_id       number;
  l_result                md_rule_executor_pkg.run_result_rec;

  l_row_1                 varchar2(100);
  l_row_2                 varchar2(100);
  l_row_3                 varchar2(100);
  l_row_4                 varchar2(100);
  l_row_5                 varchar2(100);
  l_row_6                 varchar2(100);
  l_row_7                 varchar2(100);

  l_computed_out_count    number;
  l_failed_trace_count    number;
  l_cons_exec_count       number;

  procedure execute_run_with_retry is
  begin
    begin
      l_result := md_rule_executor_pkg.execute_run(
        p_run_id          => l_run_id,
        p_change_event_id => l_change_event_id,
        p_tenant_id       => l_tenant_id,
        p_context_id      => l_context_id,
        p_params_json     => '{}'
      );
    exception
      when others then
        if sqlcode in (-4068, -4061, -4065, -6508) then
          execute immediate 'alter package md_rule_executor_pkg compile';
          execute immediate 'alter package md_rule_executor_pkg compile body';

          l_result := md_rule_executor_pkg.execute_run(
            p_run_id          => l_run_id,
            p_change_event_id => l_change_event_id,
            p_tenant_id       => l_tenant_id,
            p_context_id      => l_context_id,
            p_params_json     => '{}'
          );
        else
          raise;
        end if;
    end;
  end execute_run_with_retry;

  procedure create_sql_select_rule(
    p_rule_name   in varchar2,
    p_sql_query   in clob,
    p_target_id   in number,
    o_rule_id     out number
  ) is
    l_action_id number;
  begin
    insert into md_rule (
      rule_id,
      tenant_id,
      context_id,
      release_id,
      rule_name,
      rule_type,
      status,
      rule_payload,
      active_flag,
      created_by
    ) values (
      md_rule_seq.nextval,
      l_tenant_id,
      l_context_id,
      l_release_id,
      p_rule_name,
      'SQL_SELECT',
      'PUBLISHED',
      json_object(
        'sql_query' value p_sql_query,
        'enable_token_substitution' value 'Y'
        returning clob
      ),
      'Y',
      'sql_select_smoke'
    ) returning rule_id into o_rule_id;

    insert into md_rule_input (
      rule_input_id,
      tenant_id,
      context_id,
      rule_id,
      source_column_id,
      required_flag
    ) values (
      md_rule_input_seq.nextval,
      l_tenant_id,
      l_context_id,
      o_rule_id,
      l_src_id_col_id,
      'Y'
    );

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
      o_rule_id,
      l_tgt_object_id,
      l_key_def_id,
      l_tgt_value_col_id,
      'UPDATE',
      'APPLY',
      'SKIP',
      'RULE_DEFINED',
      null,
      systimestamp
    ) returning rule_target_action_id into l_action_id;

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
      l_action_id,
      l_key_comp_id,
      'LITERAL',
      to_char(p_target_id),
      'Y',
      systimestamp
    );

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
      l_action_id,
      l_tgt_value_col_id,
      'COMPUTED_VALUE_TXT',
      null,
      'Y',
      'Y',
      'Y',
      systimestamp
    );
  end create_sql_select_rule;

begin
  insert into md_release (
    release_id, tenant_id, context_id, release_name, semantic_version, status, created_by, published_at
  ) values (
    md_release_seq.nextval, l_tenant_id, l_context_id, 'SQL_SELECT_SMOKE_RELEASE', '1.0.0', 'PUBLISHED', 'sql_select_smoke', systimestamp
  ) returning release_id into l_release_id;

  insert into md_object (
    object_id, tenant_id, context_id, release_id, system_name, schema_name, object_name, object_type
  ) values (
    md_object_seq.nextval, l_tenant_id, l_context_id, l_release_id, 'SOURCE', l_schema_name, 'MD_SQL_SELECT_SMOKE_SRC', 'TABLE'
  ) returning object_id into l_src_object_id;

  insert into md_object (
    object_id, tenant_id, context_id, release_id, system_name, schema_name, object_name, object_type
  ) values (
    md_object_seq.nextval, l_tenant_id, l_context_id, l_release_id, 'TARGET', l_schema_name, 'MD_SQL_SELECT_SMOKE_TGT', 'TABLE'
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
    md_key_definition_seq.nextval, l_tenant_id, l_context_id, l_release_id, 'TARGET', l_schema_name, 'MD_SQL_SELECT_SMOKE_TGT', 'PK_SQL_SELECT_SMOKE', 'SURROGATE', 'Y'
  ) returning key_id into l_key_def_id;

  insert into md_key_component (
    key_component_id, tenant_id, context_id, key_id, column_id, ordinal_position
  ) values (
    md_key_component_seq.nextval, l_tenant_id, l_context_id, l_key_def_id, l_tgt_id_col_id, 1
  ) returning key_component_id into l_key_comp_id;

  create_sql_select_rule(
    p_rule_name => 'R_SQL_SELECT_SIMPLE',
    p_sql_query => q'[select 'SIMPLE_' || SRC.ID as OUT_VAL from dual]',
    p_target_id => 1,
    o_rule_id   => l_rule_simple_id
  );

  create_sql_select_rule(
    p_rule_name => 'R_SQL_SELECT_UNION',
    p_sql_query => q'[select max(v) as OUT_VAL from (select 'UNION_OK' v from dual union all select 'UNION_OK' v from dual)]',
    p_target_id => 2,
    o_rule_id   => l_rule_union_id
  );

  create_sql_select_rule(
    p_rule_name => 'R_SQL_SELECT_SQL_FUNC',
    p_sql_query => q'[select upper('sql_func_ok') as OUT_VAL from dual]',
    p_target_id => 3,
    o_rule_id   => l_rule_sql_func_id
  );

  create_sql_select_rule(
    p_rule_name => 'R_SQL_SELECT_PLSQL_FUNC',
    p_sql_query => q'[select md_sql_select_smoke_fn('OK') as OUT_VAL from dual]',
    p_target_id => 4,
    o_rule_id   => l_rule_plsql_func_id
  );

  create_sql_select_rule(
    p_rule_name => 'R_SQL_SELECT_BLOCKED',
    p_sql_query => q'[update md_sql_select_smoke_tgt set smoke_value = 'HACK' where smoke_id = 5]',
    p_target_id => 5,
    o_rule_id   => l_rule_blocked_id
  );

  create_sql_select_rule(
    p_rule_name => 'R_SQL_SELECT_ZERO_ROW',
    p_sql_query => q'[select 'ZERO' as OUT_VAL from dual where 1 = 0]',
    p_target_id => 6,
    o_rule_id   => l_rule_zero_id
  );

  create_sql_select_rule(
    p_rule_name => 'R_SQL_SELECT_MULTI_ROW',
    p_sql_query => q'[select 'A' as OUT_VAL from dual union all select 'B' as OUT_VAL from dual]',
    p_target_id => 7,
    o_rule_id   => l_rule_multi_id
  );

  insert into md_run (
    run_id, tenant_id, context_id, release_id, run_mode, run_status, initiated_by, input_summary_json
  ) values (
    md_run_seq.nextval, l_tenant_id, l_context_id, l_release_id, 'SELECTIVE', 'RUNNING', 'sql_select_smoke', '{"scenario":"sql_select_rule_smoke"}'
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
    'MD_SQL_SELECT_SMOKE_SRC',
    '{"ID":42}',
    'SQL_SELECT_SMOKE_HASH_42',
    systimestamp,
    'SQL_SELECT_SMOKE_EVT_42',
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
    '42',
    'Y'
  );

  execute_run_with_retry;

  dbms_output.put_line('sql_select_rule_smoke run_status=' || nvl(l_result.run_status, '<null>'));
  dbms_output.put_line('sql_select_rule_smoke metrics selected/executed/computed/failed/skipped='
    || nvl(to_char(l_result.metrics.rules_selected), '0') || '/'
    || nvl(to_char(l_result.metrics.rules_executed), '0') || '/'
    || nvl(to_char(l_result.metrics.values_computed), '0') || '/'
    || nvl(to_char(l_result.metrics.values_failed), '0') || '/'
    || nvl(to_char(l_result.metrics.values_skipped), '0'));

  if l_result.error_messages is not null then
    for i in 1 .. l_result.error_messages.count loop
      dbms_output.put_line('sql_select_rule_smoke error[' || i || ']=' || l_result.error_messages(i));
    end loop;
  end if;

  select smoke_value into l_row_1 from md_sql_select_smoke_tgt where smoke_id = 1;
  select smoke_value into l_row_2 from md_sql_select_smoke_tgt where smoke_id = 2;
  select smoke_value into l_row_3 from md_sql_select_smoke_tgt where smoke_id = 3;
  select smoke_value into l_row_4 from md_sql_select_smoke_tgt where smoke_id = 4;
  select smoke_value into l_row_5 from md_sql_select_smoke_tgt where smoke_id = 5;
  select smoke_value into l_row_6 from md_sql_select_smoke_tgt where smoke_id = 6;
  select smoke_value into l_row_7 from md_sql_select_smoke_tgt where smoke_id = 7;

  if l_row_1 <> 'SIMPLE_42' then
    raise_application_error(-20881, 'Simple SQL_SELECT expected SIMPLE_42, got=' || nvl(l_row_1, '<null>'));
  end if;

  if l_row_2 <> 'UNION_OK' then
    raise_application_error(-20882, 'UNION SQL_SELECT expected UNION_OK, got=' || nvl(l_row_2, '<null>'));
  end if;

  if l_row_3 <> 'SQL_FUNC_OK' then
    raise_application_error(-20883, 'SQL function SQL_SELECT expected SQL_FUNC_OK, got=' || nvl(l_row_3, '<null>'));
  end if;

  if l_row_4 <> 'FN_OK' then
    raise_application_error(-20884, 'PL/SQL function SQL_SELECT expected FN_OK, got=' || nvl(l_row_4, '<null>'));
  end if;

  if l_row_5 <> 'BEFORE_5' then
    raise_application_error(-20885, 'Blocked SQL_SELECT should not update target key 5, got=' || nvl(l_row_5, '<null>'));
  end if;

  if l_row_6 <> 'BEFORE_6' then
    raise_application_error(-20886, 'Zero-row SQL_SELECT should not update target key 6, got=' || nvl(l_row_6, '<null>'));
  end if;

  if l_row_7 <> 'BEFORE_7' then
    raise_application_error(-20887, 'Multi-row SQL_SELECT should not update target key 7, got=' || nvl(l_row_7, '<null>'));
  end if;

  select count(*)
    into l_computed_out_count
    from md_run_target_value
   where tenant_id = l_tenant_id
     and context_id = l_context_id
     and run_id = l_run_id
     and target_column_name = 'OUT_VAL'
     and value_status = 'COMPUTED';

  if l_computed_out_count < 4 then
    raise_application_error(-20888, 'Expected at least 4 computed OUT_VAL rows, got=' || l_computed_out_count);
  end if;

  select count(*)
    into l_failed_trace_count
    from md_run_target_action
   where tenant_id = l_tenant_id
     and context_id = l_context_id
     and run_id = l_run_id
     and execution_status = 'FAILED'
     and target_entity_name = 'RULE_OUTPUT_EVAL'
     and target_column_name = 'SQL_SELECT';

  if l_failed_trace_count < 3 then
    raise_application_error(-20889, 'Expected >=3 SQL_SELECT failure traces, got=' || l_failed_trace_count);
  end if;

  select count(*)
    into l_cons_exec_count
    from md_run_target_action
   where tenant_id = l_tenant_id
     and context_id = l_context_id
     and run_id = l_run_id
     and execution_phase = 'CONSOLIDATED_EXECUTION'
     and execution_status = 'EXECUTED';

  if l_cons_exec_count < 4 then
    raise_application_error(-20890, 'Expected >=4 consolidated executed actions, got=' || l_cons_exec_count);
  end if;

  dbms_output.put_line('074_md_sql_select_rule_smoke PASSED');

  delete from md_run_target_action where tenant_id = l_tenant_id and context_id = l_context_id and run_id = l_run_id;
  delete from md_run_target_consolidated_value where tenant_id = l_tenant_id and context_id = l_context_id and run_id = l_run_id;
  delete from md_run_target_consolidation where tenant_id = l_tenant_id and context_id = l_context_id and run_id = l_run_id;
  delete from md_run_target_value where tenant_id = l_tenant_id and context_id = l_context_id and run_id = l_run_id;
  delete from md_run_source_snapshot where tenant_id = l_tenant_id and context_id = l_context_id and run_id = l_run_id;
  delete from md_run_context_snapshot where tenant_id = l_tenant_id and context_id = l_context_id and run_id = l_run_id;
  delete from md_impact_trace where tenant_id = l_tenant_id and context_id = l_context_id and run_id = l_run_id;
  delete from md_run_selected_rule where tenant_id = l_tenant_id and context_id = l_context_id and run_id = l_run_id;
  delete from md_change_event_column_delta where tenant_id = l_tenant_id and context_id = l_context_id and change_event_id = l_change_event_id;
  delete from md_change_event where tenant_id = l_tenant_id and context_id = l_context_id and change_event_id = l_change_event_id;
  delete from md_run_parameter_snapshot where tenant_id = l_tenant_id and context_id = l_context_id and run_id = l_run_id;
  delete from md_run_parameter where tenant_id = l_tenant_id and context_id = l_context_id and run_id = l_run_id;
  delete from md_run where tenant_id = l_tenant_id and context_id = l_context_id and run_id = l_run_id;

  delete from md_rule_target_column_map where tenant_id = l_tenant_id and context_id = l_context_id and rule_target_action_id in (
    select rule_target_action_id from md_rule_target_action where tenant_id = l_tenant_id and context_id = l_context_id
  );
  delete from md_rule_target_key_map where tenant_id = l_tenant_id and context_id = l_context_id and rule_target_action_id in (
    select rule_target_action_id from md_rule_target_action where tenant_id = l_tenant_id and context_id = l_context_id
  );
  delete from md_rule_target_action where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_rule_input where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_rule where tenant_id = l_tenant_id and context_id = l_context_id;

  delete from md_key_component where tenant_id = l_tenant_id and context_id = l_context_id and key_id = l_key_def_id;
  delete from md_key_definition where tenant_id = l_tenant_id and context_id = l_context_id and key_id = l_key_def_id;

  delete from md_column where tenant_id = l_tenant_id and context_id = l_context_id and object_id in (l_src_object_id, l_tgt_object_id);
  delete from md_object where tenant_id = l_tenant_id and context_id = l_context_id and object_id in (l_src_object_id, l_tgt_object_id);
  delete from md_release where tenant_id = l_tenant_id and context_id = l_context_id and release_id = l_release_id;

  commit;
end;
/

begin
  execute immediate 'drop function md_sql_select_smoke_fn';
exception
  when others then
    if sqlcode != -4043 then
      raise;
    end if;
end;
/

begin
  execute immediate 'drop table md_sql_select_smoke_tgt purge';
exception
  when others then
    if sqlcode != -942 then
      raise;
    end if;
end;
/
