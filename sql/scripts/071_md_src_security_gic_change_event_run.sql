-- 071_md_src_security_gic_change_event_run.sql
-- Create a SRC_SECURITY GIC_CD change event and execute it through md_rule_executor_pkg.execute_run.
-- Assumes metadata for rule_id = 2 already exists.

set serveroutput on

prompt Running SRC_SECURITY GIC_CD change event through execute_run...

declare
  l_rule_id            number := 2;
  l_tenant_id          varchar2(64);
  l_context_id         varchar2(64);
  l_release_id         number;

  l_run_id             number;
  l_change_event_id    number;
  l_evt_suffix         varchar2(32);

  l_asset_id           varchar2(100) := 'ASSET_1001';
  l_old_gic_cd         varchar2(100) := '45102010';
  l_new_gic_cd         varchar2(100) := '45201020';

  l_result             md_rule_executor_pkg.run_result_rec;
  l_target_value_count number;
begin
  -- Resolve tenant/context/release from the target rule.
  select r.tenant_id,
         r.context_id,
         r.release_id
    into l_tenant_id,
         l_context_id,
         l_release_id
    from md_rule r
   where r.rule_id = l_rule_id;

  l_evt_suffix := to_char(systimestamp, 'YYYYMMDDHH24MISSFF3');

  insert into md_run (
    run_id,
    tenant_id,
    context_id,
    release_id,
    run_mode,
    run_status,
    initiated_by,
    input_summary_json
  ) values (
    md_run_seq.nextval,
    l_tenant_id,
    l_context_id,
    l_release_id,
    'SELECTIVE',
    'RUNNING',
    'gic_cd_change_event_script',
    '{"scenario":"src_security_gic_cd_change"}'
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
    'SOURCE',
    'SRC_SECURITY',
    '{"ASSET_ID":"' || l_asset_id || '"}',
    'SRC_SECURITY_' || l_asset_id,
    systimestamp,
    'SRC_SECURITY_GIC_CD_EVT_' || l_evt_suffix,
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
    'GIC_CD',
    l_old_gic_cd,
    l_new_gic_cd,
    'Y'
  );

  l_result := md_rule_executor_pkg.execute_run(
    p_run_id          => l_run_id,
    p_change_event_id => l_change_event_id,
    p_tenant_id       => l_tenant_id,
    p_context_id      => l_context_id,
    p_params_json     => null
  );

  select count(*)
    into l_target_value_count
    from md_run_target_value v
   where v.tenant_id = l_tenant_id
     and v.context_id = l_context_id
     and v.run_id = l_run_id;

  dbms_output.put_line('run_id=' || l_run_id);
  dbms_output.put_line('change_event_id=' || l_change_event_id);
  dbms_output.put_line('run_status=' || l_result.run_status);
  dbms_output.put_line('rules_selected=' || l_result.metrics.rules_selected);
  dbms_output.put_line('rules_executed=' || l_result.metrics.rules_executed);
  dbms_output.put_line('values_computed=' || l_result.metrics.values_computed);
  dbms_output.put_line('values_failed=' || l_result.metrics.values_failed);
  dbms_output.put_line('run_target_value_rows=' || l_target_value_count);

  if l_result.error_messages is not null and l_result.error_messages.count > 0 then
    for i in 1 .. l_result.error_messages.count loop
      dbms_output.put_line('run_error=' || l_result.error_messages(i));
    end loop;
  end if;

  dbms_output.put_line('src_security_gic_cd_change_event_script COMPLETED');
exception
  when others then
    dbms_output.put_line('src_security_gic_cd_change_event_script FAILED: ' || sqlerrm);
    raise;
end;
/

prompt SRC_SECURITY GIC_CD change event script complete.
