-- 073_md_target_consolidation_smoke.sql
-- Full smoke test for target consolidation behavior.
-- Validates:
--   1) Priority winner selection using nvl(rule_priority_no, 0) desc
--   2) Equal-priority tie-break using rule_id desc
--   3) Per-rule output audit retention
--   4) Consolidated winners-only artifact
--   5) Final SQL execution from consolidated actions
--   6) Continue-on-failure for one contributing rule

whenever sqlerror continue
set serveroutput on

prompt Running target consolidation smoke test...

prompt Ensuring prerequisite upgrades for consolidation smoke...
@C:\Users\imrna\delta\sql\scripts\034_md_rule_priority_upgrade.sql
@C:\Users\imrna\delta\sql\scripts\035_md_target_consolidation_runtime_upgrade.sql

begin
  execute immediate 'drop table md_target_cons_smoke_tgt purge';
exception
  when others then
    if sqlcode != -942 then
      raise;
    end if;
end;
/

create table md_target_cons_smoke_tgt (
  smoke_id    number primary key,
  smoke_value varchar2(100) not null
);

insert into md_target_cons_smoke_tgt (smoke_id, smoke_value) values (1, 'BEFORE_1');
insert into md_target_cons_smoke_tgt (smoke_id, smoke_value) values (2, 'BEFORE_2');
insert into md_target_cons_smoke_tgt (smoke_id, smoke_value) values (3, 'BEFORE_3');
commit;

declare
  l_tenant_id                    varchar2(64) := 'TENANT_TGT_CONS_SMOKE';
  l_context_id                   varchar2(64) := 'CTX_TGT_CONS_SMOKE';
  l_schema_name                  varchar2(128) := sys_context('USERENV', 'CURRENT_SCHEMA');

  l_release_id                   number;
  l_src_object_id                number;
  l_tgt_object_id                number;
  l_src_id_col_id                number;
  l_tgt_id_col_id                number;
  l_tgt_value_col_id             number;
  l_key_def_id                   number;
  l_key_comp_id                  number;
  l_run_id                       number;
  l_change_event_id              number;

  l_rule_hi_pri_id               number;
  l_rule_lo_pri_id               number;
  l_rule_eq_pri_low_id           number;
  l_rule_eq_pri_high_id          number;
  l_rule_fail_id                 number;

  l_result                       md_rule_executor_pkg.run_result_rec;

  l_winner_hi_rule_id            number;
  l_winner_eq_rule_id            number;
  l_consolidated_exec_count      number;
  l_per_rule_exec_count          number;
  l_per_rule_output_count        number;
  l_failed_output_count          number;
  l_consolidated_value_count     number;
  l_loser_value_count            number;
  l_partial_status_count         number;

  l_row_1_value                  varchar2(100);
  l_row_2_value                  varchar2(100);
  l_row_3_value                  varchar2(100);

  l_required_col_count           number;

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

  procedure create_update_rule(
    p_rule_name     in varchar2,
    p_priority_no   in number,
    p_output_expr   in varchar2,
    p_key_literal   in varchar2,
    o_rule_id       out number
  ) is
    l_rule_output_id      number;
    l_action_id           number;
    l_key_map_id          number;
    l_col_map_id          number;
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
      rule_priority_no,
      active_flag,
      created_by
    ) values (
      md_rule_seq.nextval,
      l_tenant_id,
      l_context_id,
      l_release_id,
      p_rule_name,
      'EXPRESSION',
      'PUBLISHED',
      '{}',
      p_priority_no,
      'Y',
      'target_cons_smoke'
    ) returning rule_id into o_rule_id;

    insert into md_rule_input (
      rule_input_id, tenant_id, context_id, rule_id, source_column_id, required_flag
    ) values (
      md_rule_input_seq.nextval, l_tenant_id, l_context_id, o_rule_id, l_src_id_col_id, 'Y'
    );

    insert into md_rule_output (
      rule_output_id, tenant_id, context_id, rule_id, target_column_id, output_expr
    ) values (
      md_rule_output_seq.nextval, l_tenant_id, l_context_id, o_rule_id, l_tgt_value_col_id, p_output_expr
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
      p_key_literal,
      'Y',
      systimestamp
    ) returning rule_target_key_map_id into l_key_map_id;

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
    ) returning rule_target_column_map_id into l_col_map_id;
  end create_update_rule;
begin
  -- Preconditions for this smoke: upgrades 034 and 035 must have been applied.
  select count(*)
    into l_required_col_count
    from user_tab_cols
   where table_name = 'MD_RULE'
     and column_name = 'RULE_PRIORITY_NO';

  if l_required_col_count = 0 then
    raise_application_error(-21090, 'Missing md_rule.rule_priority_no. Run 034_md_rule_priority_upgrade.sql first.');
  end if;

  select count(*)
    into l_required_col_count
    from user_tables
   where table_name = 'MD_RUN_TARGET_CONSOLIDATION';

  if l_required_col_count = 0 then
    raise_application_error(-21091, 'Missing md_run_target_consolidation. Run 035_md_target_consolidation_runtime_upgrade.sql first.');
  end if;

  select count(*)
    into l_required_col_count
    from user_tables
   where table_name = 'MD_RUN_TARGET_CONSOLIDATED_VALUE';

  if l_required_col_count = 0 then
    raise_application_error(-21092, 'Missing md_run_target_consolidated_value. Run 035_md_target_consolidation_runtime_upgrade.sql first.');
  end if;

  select count(*)
    into l_required_col_count
    from user_tab_cols
   where table_name = 'MD_RUN_TARGET_ACTION'
     and column_name = 'EXECUTION_PHASE';

  if l_required_col_count = 0 then
    raise_application_error(-21093, 'Missing md_run_target_action.execution_phase. Run 035_md_target_consolidation_runtime_upgrade.sql first.');
  end if;

  insert into md_release (
    release_id, tenant_id, context_id, release_name, semantic_version, status, created_by, published_at
  ) values (
    md_release_seq.nextval, l_tenant_id, l_context_id, 'TGT_CONS_SMOKE_RELEASE', '1.0.0', 'PUBLISHED', 'target_cons_smoke', systimestamp
  ) returning release_id into l_release_id;

  insert into md_object (
    object_id, tenant_id, context_id, release_id, system_name, schema_name, object_name, object_type
  ) values (
    md_object_seq.nextval, l_tenant_id, l_context_id, l_release_id, 'SOURCE', l_schema_name, 'MD_TARGET_CONS_SMOKE_SRC', 'TABLE'
  ) returning object_id into l_src_object_id;

  insert into md_object (
    object_id, tenant_id, context_id, release_id, system_name, schema_name, object_name, object_type
  ) values (
    md_object_seq.nextval, l_tenant_id, l_context_id, l_release_id, 'TARGET', l_schema_name, 'MD_TARGET_CONS_SMOKE_TGT', 'TABLE'
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
    md_key_definition_seq.nextval, l_tenant_id, l_context_id, l_release_id, 'TARGET', l_schema_name, 'MD_TARGET_CONS_SMOKE_TGT', 'PK_TGT_CONS', 'SURROGATE', 'Y'
  ) returning key_id into l_key_def_id;

  insert into md_key_component (
    key_component_id, tenant_id, context_id, key_id, column_id, ordinal_position
  ) values (
    md_key_component_seq.nextval, l_tenant_id, l_context_id, l_key_def_id, l_tgt_id_col_id, 1
  ) returning key_component_id into l_key_comp_id;

  -- Priority collision on key=1: high priority should win.
  create_update_rule('R_TGT_CONS_LOW_PRI', 1, '''LOW_LOSES''', '1', l_rule_lo_pri_id);
  create_update_rule('R_TGT_CONS_HIGH_PRI', 10, '''HIGH_WINS''', '1', l_rule_hi_pri_id);

  -- Equal priority collision on key=2: higher rule_id should win.
  create_update_rule('R_TGT_CONS_EQ_PRI_LOW_ID', 5, '''EQ_OLD_LOSES''', '2', l_rule_eq_pri_low_id);
  create_update_rule('R_TGT_CONS_EQ_PRI_HIGH_ID', 5, '''EQ_NEW_WINS''', '2', l_rule_eq_pri_high_id);

  -- Failing contributor on key=3: should not block consolidation for other keys.
  create_update_rule('R_TGT_CONS_FAILING', 20, '1/0', '3', l_rule_fail_id);

  insert into md_run (
    run_id, tenant_id, context_id, release_id, run_mode, run_status, initiated_by, input_summary_json
  ) values (
    md_run_seq.nextval, l_tenant_id, l_context_id, l_release_id, 'SELECTIVE', 'RUNNING', 'target_cons_smoke', '{"scenario":"target_consolidation_smoke"}'
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
    'MD_TARGET_CONS_SMOKE_SRC',
    '{"ID":1}',
    'TGT_CONS_HASH_1',
    systimestamp,
    'TGT_CONS_EVT_1',
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

  execute_run_with_retry;

  dbms_output.put_line('target_consolidation_smoke run_status=' || nvl(l_result.run_status, '<null>'));
  dbms_output.put_line('target_consolidation_smoke rule_ids low/high/eq_low/eq_high/fail='
    || l_rule_lo_pri_id || '/' || l_rule_hi_pri_id || '/' || l_rule_eq_pri_low_id || '/' || l_rule_eq_pri_high_id || '/' || l_rule_fail_id);

  -- Winner provenance assertions in consolidated artifact.
  select max(case when cv.computed_value_txt = 'HIGH_WINS' then cv.winner_rule_id end),
         max(case when cv.computed_value_txt = 'EQ_NEW_WINS' then cv.winner_rule_id end)
    into l_winner_hi_rule_id,
         l_winner_eq_rule_id
    from md_run_target_consolidated_value cv
   where cv.tenant_id = l_tenant_id
     and cv.context_id = l_context_id
     and cv.run_id = l_run_id
     and cv.change_event_id = l_change_event_id
     and cv.target_entity_name = 'MD_TARGET_CONS_SMOKE_TGT'
     and cv.target_column_name = 'SMOKE_VALUE';

  dbms_output.put_line('target_consolidation_smoke winner_rule_for_HIGH_WINS=' || nvl(to_char(l_winner_hi_rule_id), '<null>'));
  dbms_output.put_line('target_consolidation_smoke winner_rule_for_EQ_NEW_WINS=' || nvl(to_char(l_winner_eq_rule_id), '<null>'));

  select count(*)
    into l_consolidated_value_count
    from md_run_target_consolidated_value cv
   where cv.tenant_id = l_tenant_id
     and cv.context_id = l_context_id
     and cv.run_id = l_run_id
     and cv.change_event_id = l_change_event_id
     and cv.target_entity_name = 'MD_TARGET_CONS_SMOKE_TGT'
     and cv.target_column_name = 'SMOKE_VALUE';

  select count(*)
    into l_loser_value_count
    from md_run_target_consolidated_value cv
   where cv.tenant_id = l_tenant_id
     and cv.context_id = l_context_id
     and cv.run_id = l_run_id
     and cv.change_event_id = l_change_event_id
     and cv.target_entity_name = 'MD_TARGET_CONS_SMOKE_TGT'
     and cv.target_column_name = 'SMOKE_VALUE'
     and cv.computed_value_txt in ('LOW_LOSES', 'EQ_OLD_LOSES');

  -- Count consolidated execution rows.
  select count(*)
    into l_consolidated_exec_count
    from md_run_target_action a
   where a.tenant_id = l_tenant_id
     and a.context_id = l_context_id
     and a.run_id = l_run_id
     and nvl(a.execution_phase, 'PER_RULE_DIAGNOSTIC') = 'CONSOLIDATED_EXECUTION'
     and a.execution_status = 'EXECUTED';

  select count(*)
    into l_per_rule_exec_count
    from md_run_target_action a
   where a.tenant_id = l_tenant_id
     and a.context_id = l_context_id
     and a.run_id = l_run_id
     and nvl(a.execution_phase, 'PER_RULE_DIAGNOSTIC') = 'PER_RULE_DIAGNOSTIC'
     and a.execution_status = 'EXECUTED';

  dbms_output.put_line('target_consolidation_smoke consolidated_exec_count=' || l_consolidated_exec_count);
  dbms_output.put_line('target_consolidation_smoke per_rule_exec_count=' || l_per_rule_exec_count);

  -- Per-rule output must remain auditable.
  select count(*)
    into l_per_rule_output_count
    from md_run_target_value v
   where v.tenant_id = l_tenant_id
     and v.context_id = l_context_id
     and v.run_id = l_run_id;

  select count(*)
    into l_failed_output_count
    from md_run_target_value v
   where v.tenant_id = l_tenant_id
     and v.context_id = l_context_id
     and v.run_id = l_run_id
     and v.value_status = 'FAILED';

  dbms_output.put_line('target_consolidation_smoke per_rule_output_count=' || l_per_rule_output_count);
  dbms_output.put_line('target_consolidation_smoke failed_output_count=' || l_failed_output_count);

  dbms_output.put_line('target_consolidation_smoke consolidated_value_count=' || l_consolidated_value_count);
  dbms_output.put_line('target_consolidation_smoke loser_value_count=' || l_loser_value_count);

  -- Partial status evidence if one contributor failed.
  select count(*)
    into l_partial_status_count
    from md_run_target_consolidation c
   where c.tenant_id = l_tenant_id
     and c.context_id = l_context_id
     and c.run_id = l_run_id
     and c.change_event_id = l_change_event_id
     and c.consolidation_status = 'PARTIAL';

  dbms_output.put_line('target_consolidation_smoke partial_status_count=' || l_partial_status_count);

  select max(case when smoke_id = 1 then smoke_value end),
         max(case when smoke_id = 2 then smoke_value end),
         max(case when smoke_id = 3 then smoke_value end)
    into l_row_1_value,
         l_row_2_value,
         l_row_3_value
    from md_target_cons_smoke_tgt;

  dbms_output.put_line('target_consolidation_smoke row1=' || nvl(l_row_1_value, '<null>'));
  dbms_output.put_line('target_consolidation_smoke row2=' || nvl(l_row_2_value, '<null>'));
  dbms_output.put_line('target_consolidation_smoke row3=' || nvl(l_row_3_value, '<null>'));

  if l_result.run_status <> 'PARTIAL' then
    raise_application_error(-20901, 'Expected PARTIAL run_status due one failing contributor; found ' || nvl(l_result.run_status, '<null>'));
  end if;

  if l_winner_hi_rule_id <> l_rule_hi_pri_id then
    raise_application_error(-20902, 'Priority winner mismatch for key=1; expected rule_id=' || l_rule_hi_pri_id || ', found=' || nvl(to_char(l_winner_hi_rule_id), '<null>'));
  end if;

  if l_winner_eq_rule_id <> l_rule_eq_pri_high_id then
    raise_application_error(-20903, 'Equal-priority winner mismatch for key=2; expected higher rule_id=' || l_rule_eq_pri_high_id || ', found=' || nvl(to_char(l_winner_eq_rule_id), '<null>'));
  end if;

  if l_consolidated_value_count <> 2 then
    raise_application_error(-20904, 'Expected exactly 2 consolidated winners for SMOKE_VALUE; found=' || l_consolidated_value_count);
  end if;

  if l_loser_value_count <> 0 then
    raise_application_error(-20905, 'Losing values should not appear in winners-only artifact; found=' || l_loser_value_count);
  end if;

  if l_per_rule_output_count <> 5 then
    raise_application_error(-20906, 'Expected 5 per-rule output audit rows; found=' || l_per_rule_output_count);
  end if;

  if l_failed_output_count < 1 then
    raise_application_error(-20907, 'Expected at least one FAILED per-rule output row for failing contributor');
  end if;

  if l_consolidated_exec_count <> 2 then
    raise_application_error(-20908, 'Expected exactly 2 consolidated EXECUTED actions (keys 1 and 2); found=' || l_consolidated_exec_count);
  end if;

  if l_per_rule_exec_count <> 0 then
    raise_application_error(-20909, 'Expected no PER_RULE_DIAGNOSTIC EXECUTED actions in consolidated-only execution mode; found=' || l_per_rule_exec_count);
  end if;

  if l_partial_status_count < 1 then
    raise_application_error(-20910, 'Expected PARTIAL consolidation status evidence for failing contributor scenario');
  end if;

  if l_row_1_value <> 'HIGH_WINS' then
    raise_application_error(-20911, 'Target row 1 mismatch; expected HIGH_WINS, found=' || nvl(l_row_1_value, '<null>'));
  end if;

  if l_row_2_value <> 'EQ_NEW_WINS' then
    raise_application_error(-20912, 'Target row 2 mismatch; expected EQ_NEW_WINS, found=' || nvl(l_row_2_value, '<null>'));
  end if;

  if l_row_3_value <> 'BEFORE_3' then
    raise_application_error(-20913, 'Target row 3 should remain unchanged due failing contributor; found=' || nvl(l_row_3_value, '<null>'));
  end if;

  dbms_output.put_line('target_consolidation_smoke PASSED');

  delete from md_run_target_action where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_run_target_consolidated_value where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_run_target_consolidation where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_run_target_value where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_impact_trace where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_run_selected_rule where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_run_source_snapshot where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_run_context_snapshot where tenant_id = l_tenant_id and context_id = l_context_id;
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
    dbms_output.put_line('target_consolidation_smoke FAILED: ' || sqlerrm);
    rollback;
    raise;
end;
/

begin
  execute immediate 'drop table md_target_cons_smoke_tgt purge';
exception
  when others then
    if sqlcode != -942 then
      raise;
    end if;
end;
/

prompt Target consolidation smoke test complete.
