# Metadata Population Quick Guide

Purpose: populate the minimum metadata rows needed to run one rule that updates or inserts into a target table such as CRIMS_SECURITY.

## 1) Minimal data model path

Populate in this order:

1. md_release
2. md_object (SOURCE and TARGET)
3. md_column (source key/value columns and target key/value columns)
4. md_key_definition and md_key_component (target key)
5. md_rule
6. md_rule_input and md_rule_output
7. md_rule_target_action
8. md_rule_target_key_map and md_rule_target_column_map

Notes:

- target table identity comes from md_rule_target_action.target_object_id.
- key matching comes from md_rule_target_key_map.
- values to write come from md_rule_target_column_map.

## 2) Example values (CRIMS_SECURITY)

Use this sample shape:

- tenant_id: TENANT_DEMO
- context_id: CTX_DEMO
- source object: SRC_SECURITY
- target object: CRIMS_SECURITY
- rule: R_SECURITY_DERIVE
- target key: SECURITY_ID
- target write column: DERIVED_VALUE

## 3) Copy-paste starter SQL

```sql
-- Release
insert into md_release (
  release_id, tenant_id, context_id, release_name, semantic_version, status, created_by, published_at
) values (
  md_release_seq.nextval, 'TENANT_DEMO', 'CTX_DEMO', 'REL_QUICK', '1.0.0', 'PUBLISHED', 'quick_guide', systimestamp
);

-- Objects
insert into md_object (
  object_id, tenant_id, context_id, release_id, system_name, schema_name, object_name, object_type
)
select md_object_seq.nextval, 'TENANT_DEMO', 'CTX_DEMO', r.release_id, 'SOURCE', 'SRC', 'SRC_SECURITY', 'TABLE'
from md_release r
where r.tenant_id='TENANT_DEMO' and r.context_id='CTX_DEMO' and r.release_name='REL_QUICK' and r.semantic_version='1.0.0';

insert into md_object (
  object_id, tenant_id, context_id, release_id, system_name, schema_name, object_name, object_type
)
select md_object_seq.nextval, 'TENANT_DEMO', 'CTX_DEMO', r.release_id, 'TARGET', 'CRIMS', 'CRIMS_SECURITY', 'TABLE'
from md_release r
where r.tenant_id='TENANT_DEMO' and r.context_id='CTX_DEMO' and r.release_name='REL_QUICK' and r.semantic_version='1.0.0';

-- Columns
insert into md_column (column_id, tenant_id, context_id, object_id, column_name, data_type, nullable_flag, ordinal_position)
select md_column_seq.nextval, 'TENANT_DEMO', 'CTX_DEMO', o.object_id, 'SECURITY_ID', 'NUMBER', 'N', 1
from md_object o
where o.tenant_id='TENANT_DEMO' and o.context_id='CTX_DEMO' and o.system_name='SOURCE' and o.object_name='SRC_SECURITY';

insert into md_column (column_id, tenant_id, context_id, object_id, column_name, data_type, nullable_flag, ordinal_position)
select md_column_seq.nextval, 'TENANT_DEMO', 'CTX_DEMO', o.object_id, 'SECURITY_ID', 'NUMBER', 'N', 1
from md_object o
where o.tenant_id='TENANT_DEMO' and o.context_id='CTX_DEMO' and o.system_name='TARGET' and o.object_name='CRIMS_SECURITY';

insert into md_column (column_id, tenant_id, context_id, object_id, column_name, data_type, nullable_flag, ordinal_position)
select md_column_seq.nextval, 'TENANT_DEMO', 'CTX_DEMO', o.object_id, 'DERIVED_VALUE', 'VARCHAR2', 'Y', 2
from md_object o
where o.tenant_id='TENANT_DEMO' and o.context_id='CTX_DEMO' and o.system_name='TARGET' and o.object_name='CRIMS_SECURITY';

-- Target key definition
insert into md_key_definition (
  key_id, tenant_id, context_id, release_id, key_scope, system_name, entity_name, key_name, key_type, active_flag
)
select md_key_definition_seq.nextval, 'TENANT_DEMO', 'CTX_DEMO', r.release_id, 'TARGET', 'CRIMS', 'CRIMS_SECURITY', 'CRIMS_SECURITY_PK', 'SURROGATE', 'Y'
from md_release r
where r.tenant_id='TENANT_DEMO' and r.context_id='CTX_DEMO' and r.release_name='REL_QUICK' and r.semantic_version='1.0.0';

insert into md_key_component (
  key_component_id, tenant_id, context_id, key_id, column_id, ordinal_position
)
select md_key_component_seq.nextval, 'TENANT_DEMO', 'CTX_DEMO', kd.key_id, c.column_id, 1
from md_key_definition kd
join md_release r on r.release_id = kd.release_id
join md_object o on o.release_id = r.release_id and o.tenant_id=r.tenant_id and o.context_id=r.context_id
join md_column c on c.object_id = o.object_id and c.tenant_id=o.tenant_id and c.context_id=o.context_id
where kd.tenant_id='TENANT_DEMO' and kd.context_id='CTX_DEMO' and kd.key_name='CRIMS_SECURITY_PK'
  and o.system_name='TARGET' and o.object_name='CRIMS_SECURITY' and c.column_name='SECURITY_ID';

-- Rule
insert into md_rule (
  rule_id, tenant_id, context_id, release_id, rule_name, rule_type, status, rule_payload, active_flag, created_by
)
select md_rule_seq.nextval, 'TENANT_DEMO', 'CTX_DEMO', r.release_id,
       'R_SECURITY_DERIVE', 'EXPRESSION', 'PUBLISHED', '{"expr":"SRC.SECURITY_ID"}', 'Y', 'quick_guide'
from md_release r
where r.tenant_id='TENANT_DEMO' and r.context_id='CTX_DEMO' and r.release_name='REL_QUICK' and r.semantic_version='1.0.0';

insert into md_rule_input (rule_input_id, tenant_id, context_id, rule_id, source_column_id, required_flag)
select md_rule_input_seq.nextval, 'TENANT_DEMO', 'CTX_DEMO', rl.rule_id, c.column_id, 'Y'
from md_rule rl
join md_object o on o.release_id=rl.release_id and o.tenant_id=rl.tenant_id and o.context_id=rl.context_id
join md_column c on c.object_id=o.object_id and c.tenant_id=o.tenant_id and c.context_id=o.context_id
where rl.tenant_id='TENANT_DEMO' and rl.context_id='CTX_DEMO' and rl.rule_name='R_SECURITY_DERIVE'
  and o.system_name='SOURCE' and o.object_name='SRC_SECURITY' and c.column_name='SECURITY_ID';

insert into md_rule_output (rule_output_id, tenant_id, context_id, rule_id, target_column_id, output_expr)
select md_rule_output_seq.nextval, 'TENANT_DEMO', 'CTX_DEMO', rl.rule_id, c.column_id, 'SRC.SECURITY_ID'
from md_rule rl
join md_object o on o.release_id=rl.release_id and o.tenant_id=rl.tenant_id and o.context_id=rl.context_id
join md_column c on c.object_id=o.object_id and c.tenant_id=o.tenant_id and c.context_id=o.context_id
where rl.tenant_id='TENANT_DEMO' and rl.context_id='CTX_DEMO' and rl.rule_name='R_SECURITY_DERIVE'
  and o.system_name='TARGET' and o.object_name='CRIMS_SECURITY' and c.column_name='DERIVED_VALUE';

-- Target action (UPDATE with INSERT fallback)
insert into md_rule_target_action (
  rule_target_action_id, tenant_id, context_id, release_id, rule_id,
  target_object_id, target_key_id, target_column_id,
  action_type, execution_mode, missing_row_policy, delete_policy, created_at
)
select md_rule_target_action_seq.nextval, 'TENANT_DEMO', 'CTX_DEMO', r.release_id, rl.rule_id,
       o.object_id, kd.key_id, c.column_id,
       'UPDATE', 'APPLY', 'INSERT', 'RULE_DEFINED', systimestamp
from md_release r
join md_rule rl on rl.release_id=r.release_id and rl.tenant_id=r.tenant_id and rl.context_id=r.context_id
join md_object o on o.release_id=r.release_id and o.tenant_id=r.tenant_id and o.context_id=r.context_id
join md_column c on c.object_id=o.object_id and c.tenant_id=o.tenant_id and c.context_id=o.context_id
join md_key_definition kd on kd.release_id=r.release_id and kd.tenant_id=r.tenant_id and kd.context_id=r.context_id
where r.tenant_id='TENANT_DEMO' and r.context_id='CTX_DEMO' and r.release_name='REL_QUICK' and r.semantic_version='1.0.0'
  and rl.rule_name='R_SECURITY_DERIVE'
  and o.system_name='TARGET' and o.object_name='CRIMS_SECURITY' and c.column_name='DERIVED_VALUE'
  and kd.key_name='CRIMS_SECURITY_PK';

-- Key map: target SECURITY_ID = literal 1001 (replace with SOURCE_ALIAS/PARAM as needed)
insert into md_rule_target_key_map (
  rule_target_key_map_id, tenant_id, context_id, release_id,
  rule_target_action_id, target_key_component_id, source_kind, source_expr, required_flag, created_at
)
select md_rule_target_key_map_seq.nextval, 'TENANT_DEMO', 'CTX_DEMO', r.release_id,
       rta.rule_target_action_id, kc.key_component_id, 'LITERAL', '1001', 'Y', systimestamp
from md_release r
join md_rule rl on rl.release_id=r.release_id and rl.tenant_id=r.tenant_id and rl.context_id=r.context_id
join md_rule_target_action rta on rta.rule_id=rl.rule_id and rta.tenant_id=rl.tenant_id and rta.context_id=rl.context_id
join md_key_definition kd on kd.key_id=rta.target_key_id and kd.tenant_id=rta.tenant_id and kd.context_id=rta.context_id
join md_key_component kc on kc.key_id=kd.key_id and kc.tenant_id=kd.tenant_id and kc.context_id=kd.context_id
where r.tenant_id='TENANT_DEMO' and r.context_id='CTX_DEMO' and r.release_name='REL_QUICK' and r.semantic_version='1.0.0'
  and rl.rule_name='R_SECURITY_DERIVE';

-- Tiny variant: use SOURCE_ALIAS instead of LITERAL for key mapping
update md_rule_target_key_map km
   set km.source_kind = 'SOURCE_ALIAS',
       km.source_expr = 'SRC.SECURITY_ID'
 where km.tenant_id = 'TENANT_DEMO'
   and km.context_id = 'CTX_DEMO'
   and km.rule_target_action_id = (
     select rta.rule_target_action_id
       from md_rule_target_action rta
       join md_rule rl
         on rl.rule_id = rta.rule_id
        and rl.tenant_id = rta.tenant_id
        and rl.context_id = rta.context_id
      where rl.tenant_id = 'TENANT_DEMO'
        and rl.context_id = 'CTX_DEMO'
        and rl.rule_name = 'R_SECURITY_DERIVE'
        fetch first 1 row only
   );

-- Tiny variant: use PARAM instead of LITERAL for key mapping
update md_rule_target_key_map km
   set km.source_kind = 'PARAM',
       km.source_expr = 'SECURITY_ID_PARAM'
 where km.tenant_id = 'TENANT_DEMO'
   and km.context_id = 'CTX_DEMO'
   and km.rule_target_action_id = (
     select rta.rule_target_action_id
       from md_rule_target_action rta
       join md_rule rl
         on rl.rule_id = rta.rule_id
        and rl.tenant_id = rta.tenant_id
        and rl.context_id = rta.context_id
      where rl.tenant_id = 'TENANT_DEMO'
        and rl.context_id = 'CTX_DEMO'
        and rl.rule_name = 'R_SECURITY_DERIVE'
        fetch first 1 row only
   );

-- Column map: target DERIVED_VALUE = PARAM.UPDATE_VALUE
insert into md_rule_target_column_map (
  rule_target_column_map_id, tenant_id, context_id, release_id,
  rule_target_action_id, target_column_id, value_source_kind, value_expr,
  required_flag, write_on_insert_flag, write_on_update_flag, created_at
)
select md_rule_target_column_map_seq.nextval, 'TENANT_DEMO', 'CTX_DEMO', r.release_id,
       rta.rule_target_action_id, c.column_id, 'PARAM', 'UPDATE_VALUE',
       'Y', 'Y', 'Y', systimestamp
from md_release r
join md_rule rl on rl.release_id=r.release_id and rl.tenant_id=r.tenant_id and rl.context_id=r.context_id
join md_rule_target_action rta on rta.rule_id=rl.rule_id and rta.tenant_id=rl.tenant_id and rta.context_id=rl.context_id
join md_object o on o.object_id=rta.target_object_id and o.tenant_id=rta.tenant_id and o.context_id=rta.context_id
join md_column c on c.object_id=o.object_id and c.tenant_id=o.tenant_id and c.context_id=o.context_id
where r.tenant_id='TENANT_DEMO' and r.context_id='CTX_DEMO' and r.release_name='REL_QUICK' and r.semantic_version='1.0.0'
  and rl.rule_name='R_SECURITY_DERIVE'
  and c.column_name='DERIVED_VALUE';

commit;
```

## 4) Optional gate metadata example

Use gate metadata on md_rule to run only when condition is true:

```sql
update md_rule
   set selection_gate_enabled_flag = 'Y',
       selection_gate_expr = 'OLD.SECURITY_ID is not null and NEW.SECURITY_ID is not null and PARAM.RUN_MODE = ''GO'''
 where tenant_id = 'TENANT_DEMO'
   and context_id = 'CTX_DEMO'
   and rule_name = 'R_SECURITY_DERIVE';

commit;
```

## 5) Quick verification queries

```sql
-- Rule to target action linkage
select r.rule_name, o.schema_name, o.object_name, rta.action_type, rta.missing_row_policy
from md_rule r
join md_rule_target_action rta on rta.rule_id = r.rule_id and rta.tenant_id = r.tenant_id and rta.context_id = r.context_id
join md_object o on o.object_id = rta.target_object_id and o.tenant_id = rta.tenant_id and o.context_id = rta.context_id
where r.tenant_id = 'TENANT_DEMO' and r.context_id = 'CTX_DEMO';

-- Target key and value maps
select r.rule_name, km.source_kind as key_source_kind, km.source_expr as key_source_expr,
       cm.value_source_kind, cm.value_expr
from md_rule r
join md_rule_target_action rta on rta.rule_id=r.rule_id and rta.tenant_id=r.tenant_id and rta.context_id=r.context_id
left join md_rule_target_key_map km on km.rule_target_action_id=rta.rule_target_action_id and km.tenant_id=rta.tenant_id and km.context_id=rta.context_id
left join md_rule_target_column_map cm on cm.rule_target_action_id=rta.rule_target_action_id and cm.tenant_id=rta.tenant_id and cm.context_id=rta.context_id
where r.tenant_id='TENANT_DEMO' and r.context_id='CTX_DEMO' and r.rule_name='R_SECURITY_DERIVE';
```

## 6) Existing full examples in this repo

- sql/scripts/015_md_seed_sample.sql
- sql/scripts/061_md_cross_entity_context_smoke.sql
- sql/scripts/064_md_runtime_params_smoke_combined.sql
- sql/scripts/066_md_target_dml_smoke.sql
- sql/scripts/067_md_rule_selection_gate_smoke.sql
