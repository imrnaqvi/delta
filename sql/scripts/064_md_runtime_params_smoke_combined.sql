-- 064_md_runtime_params_smoke_combined.sql
-- Combined smoke driver for runtime parameters.
-- Runs early and late back-to-back and prints the derived value difference explicitly.

set serveroutput on

prompt Running combined runtime parameter smoke test...

begin
  execute immediate 'drop table src_security purge';
exception
  when others then
    if sqlcode != -942 then
      raise;
    end if;
end;
/

begin
  execute immediate 'drop table src_issuer purge';
exception
  when others then
    if sqlcode != -942 then
      raise;
    end if;
end;
/

begin
  execute immediate 'drop table src_pricing purge';
exception
  when others then
    if sqlcode != -942 then
      raise;
    end if;
end;
/

create table src_security (
  security_id number primary key
);

create table src_issuer (
  security_id number not null,
  issuer_id   number not null
);

create table src_pricing (
  security_id number not null,
  price       number not null
);

insert into src_security (security_id) values (2001);
insert into src_issuer (security_id, issuer_id) values (2001, 501);
insert into src_pricing (security_id, price) values (2001, 99);
commit;

declare
  l_tenant_id            varchar2(64) := 'TENANT_PARAM_SMOKE_COMBINED';
  l_context_id           varchar2(64) := 'CTX_PARAM_SMOKE_COMBINED';
  l_schema_name          varchar2(128) := sys_context('USERENV', 'CURRENT_SCHEMA');

  l_release_id           number;
  l_src_security_obj_id  number;
  l_src_issuer_obj_id    number;
  l_src_pricing_obj_id   number;
  l_tgt_security_obj_id  number;

  l_sec_security_col_id  number;
  l_iss_issuer_col_id    number;
  l_prc_price_col_id     number;
  l_tgt_derived_col_id   number;

  l_rule_id              number;
  l_source_context_id    number;

  l_run_id_early         number;
  l_run_id_late          number;
  l_evt_sec_id           number;
  l_evt_iss_id           number;
  l_evt_prc_early_id     number;
  l_evt_prc_late_id      number;

  l_result_early         md_rule_executor_pkg.run_result_rec;
  l_result_late          md_rule_executor_pkg.run_result_rec;

  l_nav_date_early       varchar2(30);
  l_asof_date_early      varchar2(30);
  l_nav_date_late        varchar2(30);
  l_asof_date_late       varchar2(30);

  l_params_early         clob;
  l_params_late          clob;
  l_expected_early       varchar2(4000);
  l_expected_late        varchar2(4000);
  l_actual_early         varchar2(4000);
  l_actual_late          varchar2(4000);
  l_value_delta          varchar2(4000);

  l_param_hash_early     varchar2(200);
  l_param_hash_late      varchar2(200);
  l_snapshot_count_early number;
  l_snapshot_count_late  number;
begin
  -- Ensure rerunnable behavior when script is executed repeatedly.
  dbms_output.put_line('[SMOKE_064] Starting cleanup phase...');
  delete from md_run_target_action
   where tenant_id = l_tenant_id
     and context_id = l_context_id;

  delete from md_run_target_value
   where tenant_id = l_tenant_id
     and context_id = l_context_id;

  delete from md_impact_trace
   where tenant_id = l_tenant_id
     and context_id = l_context_id;

  delete from md_run_selected_rule
   where tenant_id = l_tenant_id
     and context_id = l_context_id;

  delete from md_run_source_snapshot
   where tenant_id = l_tenant_id
     and context_id = l_context_id;

  delete from md_run_context_snapshot
   where tenant_id = l_tenant_id
     and context_id = l_context_id;

  delete from md_run_target_consolidated_value
   where tenant_id = l_tenant_id
     and context_id = l_context_id;

  delete from md_run_target_consolidation
   where tenant_id = l_tenant_id
     and context_id = l_context_id;

  delete from md_run_correlation_group
   where tenant_id = l_tenant_id
     and context_id = l_context_id;

  delete from md_change_event_column_delta
   where tenant_id = l_tenant_id
     and context_id = l_context_id;

  delete from md_change_event
   where tenant_id = l_tenant_id
     and context_id = l_context_id;

  delete from md_run_parameter
   where tenant_id = l_tenant_id
     and context_id = l_context_id;

  delete from md_run_parameter_snapshot
   where tenant_id = l_tenant_id
     and context_id = l_context_id;

  delete from md_rule_target_column_map
   where tenant_id = l_tenant_id
     and context_id = l_context_id;

  delete from md_rule_target_key_map
   where tenant_id = l_tenant_id
     and context_id = l_context_id;

  delete from md_rule_target_action
   where tenant_id = l_tenant_id
     and context_id = l_context_id;

  delete from md_rule_source_join
   where tenant_id = l_tenant_id
     and context_id = l_context_id;

  delete from md_rule_source_object
   where tenant_id = l_tenant_id
     and context_id = l_context_id;

  delete from md_rule_source_context
   where tenant_id = l_tenant_id
     and context_id = l_context_id;

  delete from md_rule_parameter_requirement
   where tenant_id = l_tenant_id
     and context_id = l_context_id;

  delete from md_rule_output
   where tenant_id = l_tenant_id
     and context_id = l_context_id;

  delete from md_rule_input
   where tenant_id = l_tenant_id
     and context_id = l_context_id;

  delete from md_rule
   where tenant_id = l_tenant_id
     and context_id = l_context_id;

  delete from md_source_context_join
   where tenant_id = l_tenant_id
     and context_id = l_context_id;

  delete from md_source_context_object
   where tenant_id = l_tenant_id
     and context_id = l_context_id;

  delete from md_source_context
   where tenant_id = l_tenant_id
     and context_id = l_context_id;

  delete from md_correlation_policy
   where tenant_id = l_tenant_id
     and context_id = l_context_id;

  delete from md_key_component
   where tenant_id = l_tenant_id
     and context_id = l_context_id;

  delete from md_key_definition
   where tenant_id = l_tenant_id
     and context_id = l_context_id;

  delete from md_column
   where tenant_id = l_tenant_id
     and context_id = l_context_id;

  delete from md_object
   where tenant_id = l_tenant_id
     and context_id = l_context_id;

  delete from md_run
   where tenant_id = l_tenant_id
     and context_id = l_context_id;

  delete from md_release
   where tenant_id = l_tenant_id
     and context_id = l_context_id;

  commit;
  dbms_output.put_line('[SMOKE_064] Cleanup complete. Starting metadata inserts...');

  insert into md_release (
    release_id, tenant_id, context_id, release_name, semantic_version, status, created_by, published_at
  ) values (
    md_release_seq.nextval, l_tenant_id, l_context_id, 'PARAM_SMOKE_RELEASE_COMBINED', '1.0.0', 'PUBLISHED', 'param_smoke_combined', systimestamp
  ) returning release_id into l_release_id;

  dbms_output.put_line('[SMOKE_064] Created release. Inserting metadata objects...');

  insert into md_object (object_id, tenant_id, context_id, release_id, system_name, schema_name, object_name, object_type)
  values (md_object_seq.nextval, l_tenant_id, l_context_id, l_release_id, 'SOURCE', l_schema_name, 'SRC_SECURITY', 'TABLE')
  returning object_id into l_src_security_obj_id;

  insert into md_object (object_id, tenant_id, context_id, release_id, system_name, schema_name, object_name, object_type)
  values (md_object_seq.nextval, l_tenant_id, l_context_id, l_release_id, 'SOURCE', l_schema_name, 'SRC_ISSUER', 'TABLE')
  returning object_id into l_src_issuer_obj_id;

  insert into md_object (object_id, tenant_id, context_id, release_id, system_name, schema_name, object_name, object_type)
  values (md_object_seq.nextval, l_tenant_id, l_context_id, l_release_id, 'SOURCE', l_schema_name, 'SRC_PRICING', 'TABLE')
  returning object_id into l_src_pricing_obj_id;

  insert into md_object (object_id, tenant_id, context_id, release_id, system_name, schema_name, object_name, object_type)
  values (md_object_seq.nextval, l_tenant_id, l_context_id, l_release_id, 'TARGET', 'CRIMS', 'CRIMS_SECURITY', 'TABLE')
  returning object_id into l_tgt_security_obj_id;

  insert into md_column (column_id, tenant_id, context_id, object_id, column_name, data_type, nullable_flag, ordinal_position)
  values (md_column_seq.nextval, l_tenant_id, l_context_id, l_src_security_obj_id, 'SECURITY_ID', 'NUMBER', 'N', 1)
  returning column_id into l_sec_security_col_id;

  insert into md_column (column_id, tenant_id, context_id, object_id, column_name, data_type, nullable_flag, ordinal_position)
  values (md_column_seq.nextval, l_tenant_id, l_context_id, l_src_issuer_obj_id, 'ISSUER_ID', 'NUMBER', 'N', 2)
  returning column_id into l_iss_issuer_col_id;

  insert into md_column (column_id, tenant_id, context_id, object_id, column_name, data_type, nullable_flag, ordinal_position)
  values (md_column_seq.nextval, l_tenant_id, l_context_id, l_src_pricing_obj_id, 'PRICE', 'NUMBER', 'N', 2)
  returning column_id into l_prc_price_col_id;

  insert into md_column (column_id, tenant_id, context_id, object_id, column_name, data_type, nullable_flag, ordinal_position)
  values (md_column_seq.nextval, l_tenant_id, l_context_id, l_tgt_security_obj_id, 'DERIVED_PARAM', 'VARCHAR2', 'Y', 1)
  returning column_id into l_tgt_derived_col_id;

  insert into md_rule (
    rule_id, tenant_id, context_id, release_id, rule_name, rule_type, status, rule_payload, active_flag, created_by
  ) values (
    md_rule_seq.nextval,
    l_tenant_id,
    l_context_id,
    l_release_id,
    'R_PARAM_SECURITY_ISSUER_PRICING_EXPR_COMBINED',
    'EXPRESSION',
    'PUBLISHED',
    '{"expr":"SRC.SECURITY_ID || ''-'' || SRC.ISSUER_ID || ''-'' || SRC.PRICE || ''-'' || PARAM.NAV_DATE || ''-'' || PARAM.ASOF_DATE"}',
    'Y',
    'param_smoke_combined'
  ) returning rule_id into l_rule_id;

  insert into md_rule_input (rule_input_id, tenant_id, context_id, rule_id, source_column_id, required_flag)
  values (md_rule_input_seq.nextval, l_tenant_id, l_context_id, l_rule_id, l_sec_security_col_id, 'Y');
  insert into md_rule_input (rule_input_id, tenant_id, context_id, rule_id, source_column_id, required_flag)
  values (md_rule_input_seq.nextval, l_tenant_id, l_context_id, l_rule_id, l_iss_issuer_col_id, 'Y');
  insert into md_rule_input (rule_input_id, tenant_id, context_id, rule_id, source_column_id, required_flag)
  values (md_rule_input_seq.nextval, l_tenant_id, l_context_id, l_rule_id, l_prc_price_col_id, 'Y');

  insert into md_rule_output (
    rule_output_id, tenant_id, context_id, rule_id, target_column_id, output_expr
  ) values (
    md_rule_output_seq.nextval, l_tenant_id, l_context_id, l_rule_id, l_tgt_derived_col_id,
    'SRC.SECURITY_ID || ''-'' || SRC.ISSUER_ID || ''-'' || SRC.PRICE || ''-'' || PARAM.NAV_DATE || ''-'' || PARAM.ASOF_DATE'
  );

  insert into md_rule_parameter_requirement (
    rule_parameter_requirement_id, tenant_id, context_id, release_id, rule_id, param_name, param_data_type, required_flag
  ) values (
    md_rule_parameter_requirement_seq.nextval, l_tenant_id, l_context_id, l_release_id, l_rule_id, 'NAV_DATE', 'VARCHAR2', 'Y'
  );
  insert into md_rule_parameter_requirement (
    rule_parameter_requirement_id, tenant_id, context_id, release_id, rule_id, param_name, param_data_type, required_flag
  ) values (
    md_rule_parameter_requirement_seq.nextval, l_tenant_id, l_context_id, l_release_id, l_rule_id, 'ASOF_DATE', 'VARCHAR2', 'Y'
  );

  insert into md_run (
    run_id, tenant_id, context_id, release_id, run_mode, run_status, initiated_by, input_summary_json
  ) values (
    md_run_seq.nextval, l_tenant_id, l_context_id, l_release_id, 'SELECTIVE', 'RUNNING', 'param_smoke_combined', '{"scenario":"runtime_parameters_combined_early"}'
  ) returning run_id into l_run_id_early;

  insert into md_run (
    run_id, tenant_id, context_id, release_id, run_mode, run_status, initiated_by, input_summary_json
  ) values (
    md_run_seq.nextval, l_tenant_id, l_context_id, l_release_id, 'SELECTIVE', 'RUNNING', 'param_smoke_combined', '{"scenario":"runtime_parameters_combined_late"}'
  ) returning run_id into l_run_id_late;

  insert into md_change_event (
    change_event_id, tenant_id, context_id, release_id, event_type, source_system_name, source_entity_name,
    source_key_json, source_key_hash, event_ts, event_fingerprint, processing_status
  ) values (
    md_change_event_seq.nextval, l_tenant_id, l_context_id, l_release_id, 'UPDATE', 'SOURCE', 'SRC_SECURITY',
    '{"SECURITY_ID":2001,"ISSUER_ID":501,"PRICE":99}', 'PARAM_COMBINED_HASH_2001', systimestamp, 'PARAM_COMBINED_EVT_SEC_001', 'NEW'
  ) returning change_event_id into l_evt_sec_id;

  insert into md_change_event (
    change_event_id, tenant_id, context_id, release_id, event_type, source_system_name, source_entity_name,
    source_key_json, source_key_hash, event_ts, event_fingerprint, processing_status
  ) values (
    md_change_event_seq.nextval, l_tenant_id, l_context_id, l_release_id, 'UPDATE', 'SOURCE', 'SRC_ISSUER',
    '{"SECURITY_ID":2001,"ISSUER_ID":501}', 'PARAM_COMBINED_HASH_2001', systimestamp, 'PARAM_COMBINED_EVT_ISS_001', 'NEW'
  ) returning change_event_id into l_evt_iss_id;

  insert into md_change_event (
    change_event_id, tenant_id, context_id, release_id, event_type, source_system_name, source_entity_name,
    source_key_json, source_key_hash, event_ts, event_fingerprint, processing_status
  ) values (
    md_change_event_seq.nextval, l_tenant_id, l_context_id, l_release_id, 'UPDATE', 'SOURCE', 'SRC_PRICING',
    '{"SECURITY_ID":2001,"PRICE":99}', 'PARAM_COMBINED_HASH_2001', systimestamp, 'PARAM_COMBINED_EVT_PRC_001', 'NEW'
  ) returning change_event_id into l_evt_prc_early_id;

  insert into md_change_event (
    change_event_id, tenant_id, context_id, release_id, event_type, source_system_name, source_entity_name,
    source_key_json, source_key_hash, event_ts, event_fingerprint, processing_status
  ) values (
    md_change_event_seq.nextval, l_tenant_id, l_context_id, l_release_id, 'UPDATE', 'SOURCE', 'SRC_PRICING',
    '{"SECURITY_ID":2001,"PRICE":105}', 'PARAM_COMBINED_HASH_2001', systimestamp + numtodsinterval(5, 'minute'), 'PARAM_COMBINED_EVT_PRC_002', 'NEW'
  ) returning change_event_id into l_evt_prc_late_id;

  insert into md_change_event_column_delta (
    change_event_column_delta_id, tenant_id, context_id, change_event_id, source_column_name, old_value_txt, new_value_txt, value_changed_flag
  ) values (
    md_change_event_col_delta_seq.nextval, l_tenant_id, l_context_id, l_evt_sec_id, 'SECURITY_ID', '2000', '2001', 'Y'
  );

  l_nav_date_early := to_char(systimestamp + numtodsinterval(2, 'minute'), 'YYYY-MM-DD HH24:MI:SS');
  l_asof_date_early := l_nav_date_early;
  l_params_early := '{"NAV_DATE":"' || l_nav_date_early || '","ASOF_DATE":"' || l_asof_date_early || '"}';
  l_expected_early := '2001-501-99-' || l_nav_date_early || '-' || l_asof_date_early;

  l_nav_date_late := to_char(systimestamp + numtodsinterval(10, 'minute'), 'YYYY-MM-DD HH24:MI:SS');
  l_asof_date_late := l_nav_date_late;
  l_params_late := '{"NAV_DATE":"' || l_nav_date_late || '","ASOF_DATE":"' || l_asof_date_late || '"}';
  l_expected_late := '2001-501-99-' || l_nav_date_late || '-' || l_asof_date_late;

  md_run_parameter_pkg.persist_run_parameters(
    p_run_id      => l_run_id_early,
    p_tenant_id   => l_tenant_id,
    p_context_id  => l_context_id,
    p_params_json => l_params_early
  );

  dbms_output.put_line('[SMOKE_064] Setup complete. Executing early rule run...');
  l_result_early := md_rule_executor_pkg.execute_run(
    p_run_id          => l_run_id_early,
    p_change_event_id => l_evt_sec_id,
    p_tenant_id       => l_tenant_id,
    p_context_id      => l_context_id,
    p_params_json     => l_params_early
  );

  dbms_output.put_line('[SMOKE_064] Early run complete with status=' || l_result_early.run_status);
  dbms_output.put_line('[SMOKE_064] Executing late rule run...');
  md_run_parameter_pkg.persist_run_parameters(
    p_run_id      => l_run_id_late,
    p_tenant_id   => l_tenant_id,
    p_context_id  => l_context_id,
    p_params_json => l_params_late
  );
  l_result_late := md_rule_executor_pkg.execute_run(
    p_run_id          => l_run_id_late,
    p_change_event_id => l_evt_sec_id,
    p_tenant_id       => l_tenant_id,
    p_context_id      => l_context_id,
    p_params_json     => l_params_late
  );

  dbms_output.put_line('[SMOKE_064] Late run complete with status=' || l_result_late.run_status);
  dbms_output.put_line('[SMOKE_064] Running validation queries...');

  select max(v.computed_value_txt)
    into l_actual_early
    from md_run_target_value v
   where v.run_id = l_run_id_early
     and v.rule_id = l_rule_id
     and v.tenant_id = l_tenant_id
     and v.context_id = l_context_id
     and v.target_column_name = 'DERIVED_PARAM';

  select max(v.computed_value_txt)
    into l_actual_late
    from md_run_target_value v
   where v.run_id = l_run_id_late
     and v.rule_id = l_rule_id
     and v.tenant_id = l_tenant_id
     and v.context_id = l_context_id
     and v.target_column_name = 'DERIVED_PARAM';

  select parameter_hash
    into l_param_hash_early
    from md_run_parameter_snapshot
   where run_id = l_run_id_early
     and tenant_id = l_tenant_id
     and context_id = l_context_id;

  select parameter_hash
    into l_param_hash_late
    from md_run_parameter_snapshot
   where run_id = l_run_id_late
     and tenant_id = l_tenant_id
     and context_id = l_context_id;

  select count(*)
    into l_snapshot_count_early
    from md_run_source_snapshot
   where run_id = l_run_id_early
     and tenant_id = l_tenant_id
     and context_id = l_context_id
     and rule_id = l_rule_id;

  select count(*)
    into l_snapshot_count_late
    from md_run_source_snapshot
   where run_id = l_run_id_late
     and tenant_id = l_tenant_id
     and context_id = l_context_id
     and rule_id = l_rule_id;

  l_value_delta := case
    when l_actual_early is null or l_actual_late is null then null
    else l_actual_early || ' -> ' || l_actual_late
  end;

  dbms_output.put_line('runtime_param_smoke_combined early_run_status=' || l_result_early.run_status);
  dbms_output.put_line('runtime_param_smoke_combined early_expected=' || l_expected_early);
  dbms_output.put_line('runtime_param_smoke_combined early_actual=' || nvl(l_actual_early, '<null>'));
  dbms_output.put_line('runtime_param_smoke_combined early_param_hash=' || l_param_hash_early);
  dbms_output.put_line('runtime_param_smoke_combined early_snapshot_count=' || l_snapshot_count_early);
  dbms_output.put_line('runtime_param_smoke_combined late_run_status=' || l_result_late.run_status);
  dbms_output.put_line('runtime_param_smoke_combined late_expected=' || l_expected_late);
  dbms_output.put_line('runtime_param_smoke_combined late_actual=' || nvl(l_actual_late, '<null>'));
  dbms_output.put_line('runtime_param_smoke_combined late_param_hash=' || l_param_hash_late);
  dbms_output.put_line('runtime_param_smoke_combined late_snapshot_count=' || l_snapshot_count_late);
  dbms_output.put_line('runtime_param_smoke_combined value_delta=' || nvl(l_value_delta, '<null>'));

  if l_result_early.run_status <> 'SUCCEEDED' then
    raise_application_error(-20401, 'Combined smoke failed: early run status=' || l_result_early.run_status);
  end if;

  if l_result_late.run_status <> 'SUCCEEDED' then
    raise_application_error(-20402, 'Combined smoke failed: late run status=' || l_result_late.run_status);
  end if;

  if nvl(l_actual_early, 'NULL') <> l_expected_early then
    raise_application_error(-20403, 'Combined smoke failed: early expected=' || l_expected_early || ', actual=' || nvl(l_actual_early, '<null>'));
  end if;

  if nvl(l_actual_late, 'NULL') <> l_expected_late then
    raise_application_error(-20404, 'Combined smoke failed: late expected=' || l_expected_late || ', actual=' || nvl(l_actual_late, '<null>'));
  end if;

  if l_actual_early = l_actual_late then
    raise_application_error(-20405, 'Combined smoke failed: early and late values are identical');
  end if;

  if l_snapshot_count_early = 0 or l_snapshot_count_late = 0 then
    raise_application_error(-20406, 'Combined smoke failed: missing source snapshot');
  end if;
   dbms_output.put_line('[SMOKE_064] All validations passed. Test complete.');
   dbms_output.put_line('runtime_param_smoke_combined PASSED');
exception
  when others then
    dbms_output.put_line('runtime_param_smoke_combined FAILED: ' || sqlerrm);
    raise;
end;
/

begin
  execute immediate 'drop table src_security purge';
exception
  when others then
    if sqlcode != -942 then
      raise;
    end if;
end;
/

begin
  execute immediate 'drop table src_issuer purge';
exception
  when others then
    if sqlcode != -942 then
      raise;
    end if;
end;
/

begin
  execute immediate 'drop table src_pricing purge';
exception
  when others then
    if sqlcode != -942 then
      raise;
    end if;
end;
/

-- @c:\Users\imrna\delta\sql\scripts\065_md_runtime_params_smoke_cleanup.sql

prompt Combined runtime parameter smoke test complete.
