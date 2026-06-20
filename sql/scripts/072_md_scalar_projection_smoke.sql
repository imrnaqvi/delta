-- 072_md_scalar_projection_smoke.sql
-- Smoke test for rule-scoped scalar source projections (md_rule_input_expr).
-- Validates:
--   1) multi-expression scalar_expr with inline AS aliases
--   2) projected aliases are merged into rule source snapshot JSON
--   3) output_expr can consume projected alias (SRC.MV)
--   4) blocked scalar expression is skipped with diagnostic trace

whenever sqlerror continue
set serveroutput on

prompt Running scalar projection smoke test...

begin
  execute immediate 'drop table md_scalar_expr_smoke_src purge';
exception
  when others then
    if sqlcode != -942 then
      raise;
    end if;
end;
/

create table md_scalar_expr_smoke_src (
  id     number primary key,
  units  number not null,
  prc    number not null,
  delta  number not null
);

insert into md_scalar_expr_smoke_src (id, units, prc, delta)
values (1, 2, 50, 0.25);
commit;

declare
  l_tenant_id            varchar2(64) := 'TENANT_SCALAR_SMOKE';
  l_context_id           varchar2(64) := 'CTX_SCALAR_SMOKE';
  l_schema_name          varchar2(128) := sys_context('USERENV', 'CURRENT_SCHEMA');

  l_release_id           number;
  l_src_object_id        number;
  l_tgt_object_id        number;
  l_src_id_col_id        number;
  l_src_units_col_id     number;
  l_src_prc_col_id       number;
  l_src_delta_col_id     number;
  l_tgt_mv_col_id        number;
  l_rule_id              number;
  l_source_context_id    number;
  l_run_id               number;
  l_change_event_id      number;

  l_result               md_rule_executor_pkg.run_result_rec;

  l_mv_actual            number;
  l_dav_actual           number;
  l_target_mv_txt        varchar2(4000);
  l_skip_diag_count      number;

  l_mv_expected          number := 100;
  l_dav_expected         number := 25;
begin
  insert into md_release (
    release_id, tenant_id, context_id, release_name, semantic_version, status, created_by, published_at
  ) values (
    md_release_seq.nextval, l_tenant_id, l_context_id, 'SCALAR_SMOKE_RELEASE', '1.0.0', 'PUBLISHED', 'scalar_smoke', systimestamp
  ) returning release_id into l_release_id;

  insert into md_object (
    object_id, tenant_id, context_id, release_id, system_name, schema_name, object_name, object_type
  ) values (
    md_object_seq.nextval, l_tenant_id, l_context_id, l_release_id, 'SOURCE', l_schema_name, 'MD_SCALAR_EXPR_SMOKE_SRC', 'TABLE'
  ) returning object_id into l_src_object_id;

  insert into md_object (
    object_id, tenant_id, context_id, release_id, system_name, schema_name, object_name, object_type
  ) values (
    md_object_seq.nextval, l_tenant_id, l_context_id, l_release_id, 'TARGET', l_schema_name, 'MD_SCALAR_EXPR_SMOKE_TGT', 'TABLE'
  ) returning object_id into l_tgt_object_id;

  insert into md_column (
    column_id, tenant_id, context_id, object_id, column_name, data_type, nullable_flag, ordinal_position
  ) values (
    md_column_seq.nextval, l_tenant_id, l_context_id, l_src_object_id, 'ID', 'NUMBER', 'N', 1
  ) returning column_id into l_src_id_col_id;

  insert into md_column (
    column_id, tenant_id, context_id, object_id, column_name, data_type, nullable_flag, ordinal_position
  ) values (
    md_column_seq.nextval, l_tenant_id, l_context_id, l_src_object_id, 'UNITS', 'NUMBER', 'N', 2
  ) returning column_id into l_src_units_col_id;

  insert into md_column (
    column_id, tenant_id, context_id, object_id, column_name, data_type, nullable_flag, ordinal_position
  ) values (
    md_column_seq.nextval, l_tenant_id, l_context_id, l_src_object_id, 'PRC', 'NUMBER', 'N', 3
  ) returning column_id into l_src_prc_col_id;

  insert into md_column (
    column_id, tenant_id, context_id, object_id, column_name, data_type, nullable_flag, ordinal_position
  ) values (
    md_column_seq.nextval, l_tenant_id, l_context_id, l_src_object_id, 'DELTA', 'NUMBER', 'N', 4
  ) returning column_id into l_src_delta_col_id;

  insert into md_column (
    column_id, tenant_id, context_id, object_id, column_name, data_type, nullable_flag, ordinal_position
  ) values (
    md_column_seq.nextval, l_tenant_id, l_context_id, l_tgt_object_id, 'DERIVED_MV', 'NUMBER', 'Y', 1
  ) returning column_id into l_tgt_mv_col_id;

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
    'R_SCALAR_PROJECTION',
    'EXPRESSION',
    'PUBLISHED',
    '{}',
    'Y',
    'scalar_smoke'
  ) returning rule_id into l_rule_id;

  insert into md_rule_input (
    rule_input_id, tenant_id, context_id, rule_id, source_column_id, output_alias, required_flag
  ) values (
    md_rule_input_seq.nextval, l_tenant_id, l_context_id, l_rule_id, l_src_units_col_id, 'UNITS', 'Y'
  );

  insert into md_rule_input (
    rule_input_id, tenant_id, context_id, rule_id, source_column_id, output_alias, required_flag
  ) values (
    md_rule_input_seq.nextval, l_tenant_id, l_context_id, l_rule_id, l_src_prc_col_id, 'PRC', 'Y'
  );

  insert into md_rule_input (
    rule_input_id, tenant_id, context_id, rule_id, source_column_id, output_alias, required_flag
  ) values (
    md_rule_input_seq.nextval, l_tenant_id, l_context_id, l_rule_id, l_src_delta_col_id, 'DELTA', 'Y'
  );

  insert into md_rule_output (
    rule_output_id, tenant_id, context_id, rule_id, target_column_id, output_expr
  ) values (
    md_rule_output_seq.nextval, l_tenant_id, l_context_id, l_rule_id, l_tgt_mv_col_id, 'SRC.MV'
  );

  insert into md_source_context (
    source_context_id, tenant_id, context_id, release_id, context_name, anchor_object_id, active_flag
  ) values (
    md_source_context_seq.nextval, l_tenant_id, l_context_id, l_release_id, 'SCALAR_CTX', l_src_object_id, 'Y'
  ) returning source_context_id into l_source_context_id;

  insert into md_source_context_object (
    source_context_object_id, tenant_id, context_id, source_context_id, object_id, object_alias, role_type, required_flag
  ) values (
    md_source_context_object_seq.nextval, l_tenant_id, l_context_id, l_source_context_id, l_src_object_id, 'SEC', 'ANCHOR', 'Y'
  );

  insert into md_rule_source_context (
    rule_source_context_id, tenant_id, context_id, release_id, rule_id, source_context_id, active_flag
  ) values (
    md_rule_source_context_seq.nextval, l_tenant_id, l_context_id, l_release_id, l_rule_id, l_source_context_id, 'Y'
  );

  -- Multi-expression row with inline aliases.
  insert into md_rule_input_expr (
    rule_input_expr_id,
    tenant_id,
    context_id,
    release_id,
    rule_id,
    output_alias,
    scalar_expr,
    expression_order_no,
    required_flag,
    active_flag
  ) values (
    md_rule_input_expr_seq.nextval,
    l_tenant_id,
    l_context_id,
    l_release_id,
    l_rule_id,
    null,
    'SEC.UNITS * SEC.PRC AS MV, SEC.PRC * SEC.UNITS * SEC.DELTA AS DAV',
    1,
    'N',
    'Y'
  );

  -- Intentionally blocked expression; should be skipped and traced.
  insert into md_rule_input_expr (
    rule_input_expr_id,
    tenant_id,
    context_id,
    release_id,
    rule_id,
    output_alias,
    scalar_expr,
    expression_order_no,
    required_flag,
    active_flag
  ) values (
    md_rule_input_expr_seq.nextval,
    l_tenant_id,
    l_context_id,
    l_release_id,
    l_rule_id,
    'BAD_EXPR',
    'SELECT 1',
    2,
    'N',
    'Y'
  );

  insert into md_run (
    run_id, tenant_id, context_id, release_id, run_mode, run_status, initiated_by, input_summary_json
  ) values (
    md_run_seq.nextval, l_tenant_id, l_context_id, l_release_id, 'SELECTIVE', 'RUNNING', 'scalar_smoke', '{"scenario":"scalar_projection_smoke"}'
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
    'MD_SCALAR_EXPR_SMOKE_SRC',
    '{"ID":1,"UNITS":2,"PRC":50,"DELTA":0.25}',
    'SCALAR_SMOKE_HASH_1',
    systimestamp,
    'SCALAR_SMOKE_EVT_1',
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
    'UNITS',
    '1',
    '2',
    'Y'
  );

  l_result := md_rule_executor_pkg.execute_run(
    p_run_id          => l_run_id,
    p_change_event_id => l_change_event_id,
    p_tenant_id       => l_tenant_id,
    p_context_id      => l_context_id,
    p_params_json     => '{}'
  );

  select json_value(source_values_json, '$.MV' returning number),
         json_value(source_values_json, '$.DAV' returning number)
    into l_mv_actual, l_dav_actual
    from md_run_source_snapshot
   where tenant_id = l_tenant_id
     and context_id = l_context_id
     and run_id = l_run_id
     and change_event_id = l_change_event_id
     and rule_id = l_rule_id;

  select computed_value_txt
    into l_target_mv_txt
    from md_run_target_value
   where tenant_id = l_tenant_id
     and context_id = l_context_id
     and run_id = l_run_id
     and rule_id = l_rule_id
     and target_column_name = 'DERIVED_MV';

  select count(*)
    into l_skip_diag_count
    from md_impact_trace t
   where t.tenant_id = l_tenant_id
     and t.context_id = l_context_id
     and t.run_id = l_run_id
     and json_value(t.source_ref_json, '$.diagnostic_type') = 'RULE_SCALAR_EXPR_SKIPPED';

  dbms_output.put_line('scalar_projection_smoke run_status=' || l_result.run_status);
  dbms_output.put_line('scalar_projection_smoke MV_expected=' || l_mv_expected || ', MV_actual=' || nvl(to_char(l_mv_actual), '<null>'));
  dbms_output.put_line('scalar_projection_smoke DAV_expected=' || l_dav_expected || ', DAV_actual=' || nvl(to_char(l_dav_actual), '<null>'));
  dbms_output.put_line('scalar_projection_smoke target_MV=' || nvl(l_target_mv_txt, '<null>'));
  dbms_output.put_line('scalar_projection_smoke skipped_expr_diag_count=' || l_skip_diag_count);

  if l_result.run_status not in ('SUCCEEDED', 'PARTIAL') then
    raise_application_error(-20701, 'Scalar projection smoke failed: run_status=' || l_result.run_status);
  end if;

  if l_mv_actual != l_mv_expected then
    raise_application_error(-20702, 'Scalar projection smoke failed: MV expected=' || l_mv_expected || ', actual=' || nvl(to_char(l_mv_actual), '<null>'));
  end if;

  if l_dav_actual != l_dav_expected then
    raise_application_error(-20703, 'Scalar projection smoke failed: DAV expected=' || l_dav_expected || ', actual=' || nvl(to_char(l_dav_actual), '<null>'));
  end if;

  if nvl(l_target_mv_txt, '?') <> to_char(l_mv_expected) then
    raise_application_error(-20704, 'Scalar projection smoke failed: persisted DERIVED_MV expected=' || to_char(l_mv_expected) || ', actual=' || nvl(l_target_mv_txt, '<null>'));
  end if;

  if l_skip_diag_count < 1 then
    raise_application_error(-20705, 'Scalar projection smoke failed: expected RULE_SCALAR_EXPR_SKIPPED diagnostics');
  end if;

  delete from md_run_target_action where tenant_id = l_tenant_id and context_id = l_context_id;
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
  delete from md_rule_input_expr where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_rule_output where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_rule_input where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_rule_source_context where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_source_context_join where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_source_context_object where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_source_context where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_rule where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_column where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_object where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_run where tenant_id = l_tenant_id and context_id = l_context_id;
  delete from md_release where tenant_id = l_tenant_id and context_id = l_context_id;

  commit;
exception
  when others then
    dbms_output.put_line('scalar_projection_smoke FAILED: ' || sqlerrm);
    rollback;
    raise;
end;
/

begin
  execute immediate 'drop table md_scalar_expr_smoke_src purge';
exception
  when others then
    if sqlcode != -942 then
      raise;
    end if;
end;
/

prompt Scalar projection smoke test complete.
