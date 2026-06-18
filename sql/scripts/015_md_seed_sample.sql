-- 015_md_seed_sample.sql
-- Minimal seed data for smoke testing core metadata.
-- If runtime tables already exist, this script also seeds one selective-run sample.

prompt Seeding MD sample data...

insert into md_release (
  release_id,
  tenant_id,
  context_id,
  release_name,
  semantic_version,
  status,
  created_by
)
values (
  md_release_seq.nextval,
  'TENANT_DEMO',
  'CTX_DEMO',
  'PHASE1_WAVE1',
  '1.0.0',
  'DRAFT',
  'seed_script'
);

insert into md_object (
  object_id, tenant_id, context_id, release_id, system_name, schema_name, object_name, object_type
)
select md_object_seq.nextval, 'TENANT_DEMO', 'CTX_DEMO', r.release_id, 'SOURCE', 'SRC', 'SRC_SECURITY', 'TABLE'
from md_release r
where r.tenant_id = 'TENANT_DEMO' and r.context_id = 'CTX_DEMO' and r.release_name = 'PHASE1_WAVE1' and r.semantic_version = '1.0.0';

insert into md_object (
  object_id, tenant_id, context_id, release_id, system_name, schema_name, object_name, object_type
)
select md_object_seq.nextval, 'TENANT_DEMO', 'CTX_DEMO', r.release_id, 'TARGET', 'CRIMS', 'CRIMS_SECURITY', 'TABLE'
from md_release r
where r.tenant_id = 'TENANT_DEMO' and r.context_id = 'CTX_DEMO' and r.release_name = 'PHASE1_WAVE1' and r.semantic_version = '1.0.0';

insert into md_column (
  column_id, tenant_id, context_id, object_id, column_name, data_type, nullable_flag, ordinal_position
)
select md_column_seq.nextval, 'TENANT_DEMO', 'CTX_DEMO', o.object_id, 'SECURITY_ID', 'NUMBER', 'N', 1
from md_object o
where o.tenant_id='TENANT_DEMO' and o.context_id='CTX_DEMO' and o.system_name='SOURCE' and o.object_name='SRC_SECURITY';

insert into md_column (
  column_id, tenant_id, context_id, object_id, column_name, data_type, nullable_flag, ordinal_position
)
select md_column_seq.nextval, 'TENANT_DEMO', 'CTX_DEMO', o.object_id, 'ISSUER_ID', 'NUMBER', 'Y', 2
from md_object o
where o.tenant_id='TENANT_DEMO' and o.context_id='CTX_DEMO' and o.system_name='SOURCE' and o.object_name='SRC_SECURITY';

insert into md_column (
  column_id, tenant_id, context_id, object_id, column_name, data_type, nullable_flag, ordinal_position
)
select md_column_seq.nextval, 'TENANT_DEMO', 'CTX_DEMO', o.object_id, 'SECURITY_ID', 'NUMBER', 'N', 1
from md_object o
where o.tenant_id='TENANT_DEMO' and o.context_id='CTX_DEMO' and o.system_name='TARGET' and o.object_name='CRIMS_SECURITY';

insert into md_key_definition (
  key_id, tenant_id, context_id, release_id, key_scope, system_name, entity_name, key_name, key_type, active_flag
)
select md_key_definition_seq.nextval, 'TENANT_DEMO', 'CTX_DEMO', r.release_id,
       'SOURCE', 'SOURCE', 'SRC_SECURITY', 'SRC_SECURITY_PK', 'NATURAL_COMPOSITE', 'Y'
from md_release r
where r.tenant_id='TENANT_DEMO' and r.context_id='CTX_DEMO' and r.release_name='PHASE1_WAVE1' and r.semantic_version='1.0.0';

insert into md_key_definition (
  key_id, tenant_id, context_id, release_id, key_scope, system_name, entity_name, key_name, key_type, active_flag
)
select md_key_definition_seq.nextval, 'TENANT_DEMO', 'CTX_DEMO', r.release_id,
       'TARGET', 'TARGET', 'CRIMS_SECURITY', 'CRIMS_SECURITY_PK', 'NATURAL_COMPOSITE', 'Y'
from md_release r
where r.tenant_id='TENANT_DEMO' and r.context_id='CTX_DEMO' and r.release_name='PHASE1_WAVE1' and r.semantic_version='1.0.0';

insert into md_key_component (
  key_component_id, tenant_id, context_id, key_id, column_id, ordinal_position
)
select md_key_component_seq.nextval, 'TENANT_DEMO', 'CTX_DEMO', k.key_id, c.column_id, 1
from md_key_definition k
join md_object o on o.release_id = k.release_id and o.tenant_id = k.tenant_id and o.context_id = k.context_id
join md_column c on c.object_id = o.object_id and c.tenant_id = o.tenant_id and c.context_id = o.context_id
where k.tenant_id='TENANT_DEMO' and k.context_id='CTX_DEMO'
  and k.key_name='SRC_SECURITY_PK'
  and o.system_name='SOURCE' and o.object_name='SRC_SECURITY'
  and c.column_name='SECURITY_ID';

insert into md_key_component (
  key_component_id, tenant_id, context_id, key_id, column_id, ordinal_position
)
select md_key_component_seq.nextval, 'TENANT_DEMO', 'CTX_DEMO', k.key_id, c.column_id, 1
from md_key_definition k
join md_object o on o.release_id = k.release_id and o.tenant_id = k.tenant_id and o.context_id = k.context_id
join md_column c on c.object_id = o.object_id and c.tenant_id = o.tenant_id and c.context_id = o.context_id
where k.tenant_id='TENANT_DEMO' and k.context_id='CTX_DEMO'
  and k.key_name='CRIMS_SECURITY_PK'
  and o.system_name='TARGET' and o.object_name='CRIMS_SECURITY'
  and c.column_name='SECURITY_ID';

insert into md_key_mapping (
  key_mapping_id, tenant_id, context_id, release_id, source_key_id, target_key_id, mapping_expr, active_flag
)
select md_key_mapping_seq.nextval, 'TENANT_DEMO', 'CTX_DEMO', r.release_id,
       src.key_id, tgt.key_id,
       'SRC.SECURITY_ID = TGT.SECURITY_ID', 'Y'
from md_release r
join md_key_definition src on src.release_id = r.release_id and src.tenant_id=r.tenant_id and src.context_id=r.context_id
join md_key_definition tgt on tgt.release_id = r.release_id and tgt.tenant_id=r.tenant_id and tgt.context_id=r.context_id
where r.tenant_id='TENANT_DEMO' and r.context_id='CTX_DEMO' and r.release_name='PHASE1_WAVE1' and r.semantic_version='1.0.0'
  and src.key_name='SRC_SECURITY_PK'
  and tgt.key_name='CRIMS_SECURITY_PK';

insert into md_rule (
  rule_id, tenant_id, context_id, release_id, rule_name, rule_type, status, rule_payload, active_flag, created_by
)
select md_rule_seq.nextval, 'TENANT_DEMO', 'CTX_DEMO', r.release_id,
       'R_SECURITY_ID_PASS_THROUGH', 'EXPRESSION', 'PUBLISHED',
       '{"expr":"SRC.SECURITY_ID"}', 'Y', 'seed_script'
from md_release r
where r.tenant_id='TENANT_DEMO' and r.context_id='CTX_DEMO' and r.release_name='PHASE1_WAVE1' and r.semantic_version='1.0.0';

insert into md_rule_input (
  rule_input_id, tenant_id, context_id, rule_id, source_column_id, required_flag
)
select md_rule_input_seq.nextval, 'TENANT_DEMO', 'CTX_DEMO', rl.rule_id, c.column_id, 'Y'
from md_rule rl
join md_release r on r.release_id = rl.release_id
join md_object o on o.release_id = r.release_id and o.tenant_id = r.tenant_id and o.context_id = r.context_id
join md_column c on c.object_id = o.object_id and c.tenant_id = o.tenant_id and c.context_id = o.context_id
where rl.tenant_id='TENANT_DEMO' and rl.context_id='CTX_DEMO' and rl.rule_name='R_SECURITY_ID_PASS_THROUGH'
  and o.system_name='SOURCE' and o.object_name='SRC_SECURITY' and c.column_name='SECURITY_ID';

insert into md_rule_output (
  rule_output_id, tenant_id, context_id, rule_id, target_column_id, output_expr
)
select md_rule_output_seq.nextval, 'TENANT_DEMO', 'CTX_DEMO', rl.rule_id, c.column_id, 'SRC.SECURITY_ID'
from md_rule rl
join md_release r on r.release_id = rl.release_id
join md_object o on o.release_id = r.release_id and o.tenant_id = r.tenant_id and o.context_id = r.context_id
join md_column c on c.object_id = o.object_id and c.tenant_id = o.tenant_id and c.context_id = o.context_id
where rl.tenant_id='TENANT_DEMO' and rl.context_id='CTX_DEMO' and rl.rule_name='R_SECURITY_ID_PASS_THROUGH'
  and o.system_name='TARGET' and o.object_name='CRIMS_SECURITY' and c.column_name='SECURITY_ID';

insert into md_rule_target_action (
  rule_target_action_id, tenant_id, context_id, release_id, rule_id, target_object_id, target_column_id, action_type
)
select md_rule_target_action_seq.nextval, 'TENANT_DEMO', 'CTX_DEMO', r.release_id, rl.rule_id, o.object_id, c.column_id, 'UPDATE'
from md_release r
join md_rule rl on rl.release_id = r.release_id and rl.tenant_id = r.tenant_id and rl.context_id = r.context_id
join md_object o on o.release_id = r.release_id and o.tenant_id = r.tenant_id and o.context_id = r.context_id
join md_column c on c.object_id = o.object_id and c.tenant_id = o.tenant_id and c.context_id = o.context_id
where r.tenant_id='TENANT_DEMO' and r.context_id='CTX_DEMO' and r.release_name='PHASE1_WAVE1' and r.semantic_version='1.0.0'
  and rl.rule_name='R_SECURITY_ID_PASS_THROUGH'
  and o.system_name='TARGET' and o.object_name='CRIMS_SECURITY' and c.column_name='SECURITY_ID';

insert into md_delete_policy (
  delete_policy_id, tenant_id, context_id, release_id, scope_type, scope_id, policy_code, active_flag
)
select md_delete_policy_seq.nextval, 'TENANT_DEMO', 'CTX_DEMO', r.release_id, 'GLOBAL', null, 'HARD_DELETE', 'Y'
from md_release r
where r.tenant_id='TENANT_DEMO' and r.context_id='CTX_DEMO' and r.release_name='PHASE1_WAVE1' and r.semantic_version='1.0.0';

insert into md_execution_policy (
  execution_policy_id, tenant_id, context_id, release_id, policy_name, ordering_key, tie_breaker, idempotency_days, default_delete_policy, active_flag
)
select md_execution_policy_seq.nextval, 'TENANT_DEMO', 'CTX_DEMO', r.release_id,
       'DEFAULT_SELECTIVE', 'EVENT_TS', 'EVENT_FINGERPRINT', 30, 'HARD_DELETE', 'Y'
from md_release r
where r.tenant_id='TENANT_DEMO' and r.context_id='CTX_DEMO' and r.release_name='PHASE1_WAVE1' and r.semantic_version='1.0.0';

begin
  if exists (
    select 1
    from user_tables
    where table_name = 'MD_RUN_TARGET_VALUE'
  ) then
    execute immediate q'[
      insert into md_change_event_raw (
        change_event_raw_id, tenant_id, context_id, source_system_name, source_entity_name, source_event_ts, source_event_id, payload_json
      )
      values (
        md_change_event_raw_seq.nextval,
        'TENANT_DEMO',
        'CTX_DEMO',
        'SOURCE',
        'SRC_SECURITY',
        systimestamp,
        'SRC_EVT_001',
        '{"eventType":"UPDATE","entity":"SRC_SECURITY","keys":{"SECURITY_ID":1001},"changedColumns":{"SECURITY_ID":{"old":1000,"new":1001}}}'
      )
    ]';

    execute immediate q'[
      insert into md_change_event (
        change_event_id, tenant_id, context_id, release_id, change_event_raw_id, event_type, source_system_name, source_entity_name,
        source_key_json, source_key_hash, event_ts, event_fingerprint, processing_status
      )
      select
        md_change_event_seq.nextval,
        'TENANT_DEMO',
        'CTX_DEMO',
        r.release_id,
        raw.change_event_raw_id,
        'UPDATE',
        'SOURCE',
        'SRC_SECURITY',
        '{"SECURITY_ID":1001}',
        'SRC_SECURITY:1001',
        systimestamp,
        'EVT_FP_001',
        'APPLIED'
      from md_release r
      join md_change_event_raw raw
        on raw.tenant_id = 'TENANT_DEMO'
       and raw.context_id = 'CTX_DEMO'
       and raw.source_event_id = 'SRC_EVT_001'
      where r.tenant_id='TENANT_DEMO'
        and r.context_id='CTX_DEMO'
        and r.release_name='PHASE1_WAVE1'
        and r.semantic_version='1.0.0'
    ]';

    execute immediate q'[
      insert into md_change_event_column_delta (
        change_event_column_delta_id, tenant_id, context_id, change_event_id, source_column_name, old_value_txt, new_value_txt, value_changed_flag
      )
      select
        md_change_event_col_delta_seq.nextval,
        'TENANT_DEMO',
        'CTX_DEMO',
        evt.change_event_id,
        'SECURITY_ID',
        '1000',
        '1001',
        'Y'
      from md_change_event evt
      where evt.tenant_id='TENANT_DEMO'
        and evt.context_id='CTX_DEMO'
        and evt.event_fingerprint='EVT_FP_001'
    ]';

    execute immediate q'[
      insert into md_run (
        run_id, tenant_id, context_id, release_id, run_mode, run_status, initiated_by, input_summary_json
      )
      select
        md_run_seq.nextval,
        'TENANT_DEMO',
        'CTX_DEMO',
        r.release_id,
        'SELECTIVE',
        'SUCCEEDED',
        'seed_script',
        '{"batchId":"BATCH_001","eventCount":1}'
      from md_release r
      where r.tenant_id='TENANT_DEMO'
        and r.context_id='CTX_DEMO'
        and r.release_name='PHASE1_WAVE1'
        and r.semantic_version='1.0.0'
    ]';

    execute immediate q'[
      insert into md_run_selected_rule (
        run_selected_rule_id, tenant_id, context_id, run_id, change_event_id, rule_id, selection_reason, transitive_flag
      )
      select
        md_run_selected_rule_seq.nextval,
        'TENANT_DEMO',
        'CTX_DEMO',
        rn.run_id,
        evt.change_event_id,
        rl.rule_id,
        'DIRECT_COLUMN_LINK',
        'N'
      from md_run rn
      join md_change_event evt
        on evt.tenant_id = rn.tenant_id
       and evt.context_id = rn.context_id
       and evt.event_fingerprint = 'EVT_FP_001'
      join md_rule rl
        on rl.release_id = rn.release_id
       and rl.tenant_id = rn.tenant_id
       and rl.context_id = rn.context_id
       and rl.rule_name = 'R_SECURITY_ID_PASS_THROUGH'
      where rn.tenant_id='TENANT_DEMO'
        and rn.context_id='CTX_DEMO'
        and rn.initiated_by='seed_script'
        and rn.run_mode='SELECTIVE'
    ]';

    execute immediate q'[
      insert into md_run_target_action (
        run_target_action_id, tenant_id, context_id, run_id, change_event_id, rule_id, target_system_name, target_entity_name,
        target_key_json, target_key_hash, target_column_name, action_type, action_payload_json, applied_flag, applied_at, action_fingerprint
      )
      select
        md_run_target_action_seq.nextval,
        'TENANT_DEMO',
        'CTX_DEMO',
        rn.run_id,
        evt.change_event_id,
        rl.rule_id,
        'TARGET',
        'CRIMS_SECURITY',
        '{"SECURITY_ID":1001}',
        'CRIMS_SECURITY:1001',
        'SECURITY_ID',
        'UPDATE',
        '{"targetColumns":{"SECURITY_ID":1001}}',
        'Y',
        systimestamp,
        'ACT_FP_001'
      from md_run rn
      join md_change_event evt
        on evt.tenant_id = rn.tenant_id
       and evt.context_id = rn.context_id
       and evt.event_fingerprint = 'EVT_FP_001'
      join md_rule rl
        on rl.release_id = rn.release_id
       and rl.tenant_id = rn.tenant_id
       and rl.context_id = rn.context_id
       and rl.rule_name = 'R_SECURITY_ID_PASS_THROUGH'
      where rn.tenant_id='TENANT_DEMO'
        and rn.context_id='CTX_DEMO'
        and rn.initiated_by='seed_script'
        and rn.run_mode='SELECTIVE'
    ]';

    execute immediate q'[
      insert into md_run_target_value (
        run_target_value_id, tenant_id, context_id, run_id, run_target_action_id, change_event_id, rule_id, target_system_name,
        target_entity_name, target_key_json, target_key_hash, target_column_name, computed_value_txt, computed_value_json,
        value_data_type, value_status, applied_flag, computed_at, applied_at, value_fingerprint
      )
      select
        md_run_target_value_seq.nextval,
        'TENANT_DEMO',
        'CTX_DEMO',
        act.run_id,
        act.run_target_action_id,
        act.change_event_id,
        act.rule_id,
        act.target_system_name,
        act.target_entity_name,
        act.target_key_json,
        act.target_key_hash,
        'SECURITY_ID',
        '1001',
        '{"value":1001}',
        'NUMBER',
        'APPLIED',
        'Y',
        systimestamp,
        systimestamp,
        'VAL_FP_001'
      from md_run_target_action act
      where act.tenant_id='TENANT_DEMO'
        and act.context_id='CTX_DEMO'
        and act.action_fingerprint='ACT_FP_001'
    ]';

    execute immediate q'[
      insert into md_impact_trace (
        impact_trace_id, tenant_id, context_id, run_id, change_event_id, source_ref_json, rule_ref_json, target_ref_json
      )
      select
        md_impact_trace_seq.nextval,
        'TENANT_DEMO',
        'CTX_DEMO',
        act.run_id,
        act.change_event_id,
        '{"sourceSystem":"SOURCE","entity":"SRC_SECURITY","key":{"SECURITY_ID":1001},"column":"SECURITY_ID"}',
        '{"ruleName":"R_SECURITY_ID_PASS_THROUGH"}',
        '{"targetSystem":"TARGET","entity":"CRIMS_SECURITY","key":{"SECURITY_ID":1001},"column":"SECURITY_ID"}'
      from md_run_target_action act
      where act.tenant_id='TENANT_DEMO'
        and act.context_id='CTX_DEMO'
        and act.action_fingerprint='ACT_FP_001'
    ]';

    execute immediate q'[
      insert into md_processed_event (
        processed_event_id, tenant_id, context_id, event_fingerprint, change_event_id, run_id, processed_at, expires_at, processing_result
      )
      select
        md_processed_event_seq.nextval,
        'TENANT_DEMO',
        'CTX_DEMO',
        evt.event_fingerprint,
        evt.change_event_id,
        rn.run_id,
        systimestamp,
        systimestamp + interval '30' day,
        'APPLIED'
      from md_change_event evt
      join md_run rn
        on rn.tenant_id = evt.tenant_id
       and rn.context_id = evt.context_id
       and rn.initiated_by = 'seed_script'
       and rn.run_mode = 'SELECTIVE'
      where evt.tenant_id='TENANT_DEMO'
        and evt.context_id='CTX_DEMO'
        and evt.event_fingerprint='EVT_FP_001'
    ]';
  end if;
end;
/

commit;

prompt MD sample seed complete.
