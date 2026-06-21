-- 061_md_cross_entity_context_smoke.sql
-- Focused smoke test for cross-entity source context resolution.
-- Seeds SECURITY + ISSUER + PRICING context graph, runs one selective execution,
-- validates alias-based derived expression output, then rolls back.

set serveroutput on

prompt Running cross-entity context smoke test...

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
  l_tenant_id            varchar2(64) := 'TENANT_XE_SMOKE';
  l_context_id           varchar2(64) := 'CTX_XE_SMOKE';
  l_schema_name          varchar2(128) := sys_context('USERENV', 'CURRENT_SCHEMA');

  l_release_id           number;

  l_src_security_obj_id  number;
  l_src_issuer_obj_id    number;
  l_src_pricing_obj_id   number;
  l_tgt_security_obj_id  number;

  l_sec_security_col_id  number;
  l_iss_security_col_id  number;
  l_iss_issuer_col_id    number;
  l_prc_security_col_id  number;
  l_prc_price_col_id     number;
  l_tgt_derived_col_id   number;

  l_rule_id              number;
  l_source_context_id    number;

  l_rso_sec_id           number;
  l_rso_iss_id           number;
  l_rso_prc_id           number;

  l_run_id               number;
  l_evt_sec_id           number;
  l_evt_iss_id           number;
  l_evt_prc_id           number;

  l_expected_value       varchar2(4000) := '2001-501-99';
  l_actual_value         varchar2(4000);

  l_result               md_rule_executor_pkg.run_result_rec;
begin
  -- 1) Release
  insert into md_release (
    release_id,
    tenant_id,
    context_id,
    release_name,
    semantic_version,
    status,
    created_by,
    published_at
  ) values (
    md_release_seq.nextval,
    l_tenant_id,
    l_context_id,
    'XE_SMOKE_RELEASE',
    '1.0.0',
    'PUBLISHED',
    'xe_smoke',
    systimestamp
  ) returning release_id into l_release_id;

  -- 2) Source/target objects
  insert into md_object (
    object_id, tenant_id, context_id, release_id,
    system_name, schema_name, object_name, object_type
  ) values (
    md_object_seq.nextval, l_tenant_id, l_context_id, l_release_id,
    'SOURCE', l_schema_name, 'SRC_SECURITY', 'TABLE'
  ) returning object_id into l_src_security_obj_id;

  insert into md_object (
    object_id, tenant_id, context_id, release_id,
    system_name, schema_name, object_name, object_type
  ) values (
    md_object_seq.nextval, l_tenant_id, l_context_id, l_release_id,
    'SOURCE', l_schema_name, 'SRC_ISSUER', 'TABLE'
  ) returning object_id into l_src_issuer_obj_id;

  insert into md_object (
    object_id, tenant_id, context_id, release_id,
    system_name, schema_name, object_name, object_type
  ) values (
    md_object_seq.nextval, l_tenant_id, l_context_id, l_release_id,
    'SOURCE', l_schema_name, 'SRC_PRICING', 'TABLE'
  ) returning object_id into l_src_pricing_obj_id;

  insert into md_object (
    object_id, tenant_id, context_id, release_id,
    system_name, schema_name, object_name, object_type
  ) values (
    md_object_seq.nextval, l_tenant_id, l_context_id, l_release_id,
    'TARGET', 'CRIMS', 'CRIMS_SECURITY', 'TABLE'
  ) returning object_id into l_tgt_security_obj_id;

  -- 3) Columns
  insert into md_column (
    column_id, tenant_id, context_id, object_id, column_name, data_type, nullable_flag, ordinal_position
  ) values (
    md_column_seq.nextval, l_tenant_id, l_context_id, l_src_security_obj_id, 'SECURITY_ID', 'NUMBER', 'N', 1
  ) returning column_id into l_sec_security_col_id;

  insert into md_column (
    column_id, tenant_id, context_id, object_id, column_name, data_type, nullable_flag, ordinal_position
  ) values (
    md_column_seq.nextval, l_tenant_id, l_context_id, l_src_issuer_obj_id, 'SECURITY_ID', 'NUMBER', 'N', 1
  ) returning column_id into l_iss_security_col_id;

  insert into md_column (
    column_id, tenant_id, context_id, object_id, column_name, data_type, nullable_flag, ordinal_position
  ) values (
    md_column_seq.nextval, l_tenant_id, l_context_id, l_src_issuer_obj_id, 'ISSUER_ID', 'NUMBER', 'N', 2
  ) returning column_id into l_iss_issuer_col_id;

  insert into md_column (
    column_id, tenant_id, context_id, object_id, column_name, data_type, nullable_flag, ordinal_position
  ) values (
    md_column_seq.nextval, l_tenant_id, l_context_id, l_src_pricing_obj_id, 'SECURITY_ID', 'NUMBER', 'N', 1
  ) returning column_id into l_prc_security_col_id;

  insert into md_column (
    column_id, tenant_id, context_id, object_id, column_name, data_type, nullable_flag, ordinal_position
  ) values (
    md_column_seq.nextval, l_tenant_id, l_context_id, l_src_pricing_obj_id, 'PRICE', 'NUMBER', 'N', 2
  ) returning column_id into l_prc_price_col_id;

  insert into md_column (
    column_id, tenant_id, context_id, object_id, column_name, data_type, nullable_flag, ordinal_position
  ) values (
    md_column_seq.nextval, l_tenant_id, l_context_id, l_tgt_security_obj_id, 'DERIVED_XE', 'VARCHAR2', 'Y', 1
  ) returning column_id into l_tgt_derived_col_id;

  -- 4) Rule with alias-based cross-entity expression
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
    'R_XE_SECURITY_ISSUER_PRICING_EXPR',
    'EXPRESSION',
    'PUBLISHED',
    '{}',
    'Y',
    'xe_smoke'
  ) returning rule_id into l_rule_id;

  -- Inputs include anchor + joined source fields
  insert into md_rule_input (
    rule_input_id, tenant_id, context_id, rule_id, source_column_id, output_alias, required_flag
  ) values (
    md_rule_input_seq.nextval, l_tenant_id, l_context_id, l_rule_id, l_sec_security_col_id, 'SECURITY_ID', 'Y'
  );

  insert into md_rule_input (
    rule_input_id, tenant_id, context_id, rule_id, source_column_id, output_alias, required_flag
  ) values (
    md_rule_input_seq.nextval, l_tenant_id, l_context_id, l_rule_id, l_iss_issuer_col_id, 'ISSUER_ID', 'Y'
  );

  insert into md_rule_input (
    rule_input_id, tenant_id, context_id, rule_id, source_column_id, output_alias, required_flag
  ) values (
    md_rule_input_seq.nextval, l_tenant_id, l_context_id, l_rule_id, l_prc_price_col_id, 'PRICE', 'Y'
  );

  insert into md_rule_output (
    rule_output_id, tenant_id, context_id, rule_id, target_column_id, output_expr
  ) values (
    md_rule_output_seq.nextval, l_tenant_id, l_context_id, l_rule_id, l_tgt_derived_col_id,
    'SRC.SECURITY_ID || ''-'' || SRC.ISSUER_ID || ''-'' || SRC.PRICE'
  );

  -- 5) Runtime seed
  insert into md_run (
    run_id, tenant_id, context_id, release_id, run_mode, run_status, initiated_by, input_summary_json
  ) values (
    md_run_seq.nextval,
    l_tenant_id,
    l_context_id,
    l_release_id,
    'SELECTIVE',
    'RUNNING',
    'xe_smoke',
    '{"scenario":"cross_entity_context"}'
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
    '{"SECURITY_ID":2001,"ISSUER_ID":501,"PRICE":99}',
    'XE_HASH_SECURITY_2001',
    systimestamp,
    'XE_EVT_SEC_001',
    'NEW'
  ) returning change_event_id into l_evt_sec_id;

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
    'SRC_ISSUER',
    '{"SECURITY_ID":2001,"ISSUER_ID":501}',
    'XE_HASH_SECURITY_2001',
    systimestamp - numtodsinterval(2, 'SECOND'),
    'XE_EVT_ISS_001',
    'NEW'
  ) returning change_event_id into l_evt_iss_id;

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
    'SRC_PRICING',
    '{"SECURITY_ID":2001,"PRICE":99}',
    'XE_HASH_SECURITY_2001',
    systimestamp - numtodsinterval(1, 'SECOND'),
    'XE_EVT_PRC_001',
    'NEW'
  ) returning change_event_id into l_evt_prc_id;

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
    l_evt_sec_id,
    'SECURITY_ID',
    '2000',
    '2001',
    'Y'
  );

  -- 8) Execute run (selector + resolver + expression)
  l_result := md_rule_executor_pkg.execute_run(
    p_run_id          => l_run_id,
    p_change_event_id => l_evt_sec_id,
    p_tenant_id       => l_tenant_id,
    p_context_id      => l_context_id
  );

  select max(v.computed_value_txt)
    into l_actual_value
    from md_run_target_value v
   where v.run_id = l_run_id
     and v.rule_id = l_rule_id
     and v.tenant_id = l_tenant_id
     and v.context_id = l_context_id
     and v.target_column_name = 'DERIVED_XE';

  dbms_output.put_line('cross_entity_smoke run_status=' || l_result.run_status);
  dbms_output.put_line('cross_entity_smoke expected=' || l_expected_value);
  dbms_output.put_line('cross_entity_smoke actual=' || nvl(l_actual_value, '<null>'));

  if l_result.error_messages is not null and l_result.error_messages.count > 0 then
    for i in 1 .. l_result.error_messages.count loop
      dbms_output.put_line('cross_entity_smoke run_error=' || l_result.error_messages(i));
    end loop;
  end if;

  if l_result.run_status <> 'SUCCEEDED' then
    raise_application_error(-20101, 'Cross-entity smoke failed: run_status=' || l_result.run_status);
  end if;

  if nvl(l_actual_value, 'NULL') <> l_expected_value then
    raise_application_error(-20102, 'Cross-entity smoke failed: expected=' || l_expected_value || ', actual=' || nvl(l_actual_value, '<null>'));
  end if;

  dbms_output.put_line('cross_entity_smoke PASSED');

  rollback;
exception
  when others then
    dbms_output.put_line('cross_entity_smoke FAILED: ' || sqlerrm);
    rollback;
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

prompt Cross-entity context smoke test complete.
