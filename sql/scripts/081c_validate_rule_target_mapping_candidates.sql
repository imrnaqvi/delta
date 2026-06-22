-- 081c_validate_rule_target_mapping_candidates.sql
-- Validates whether a rule/target pair is safe for auto-derivation
-- Reports conflicts, gaps, and edge cases
--
-- Usage:
--   @081c_validate_rule_target_mapping_candidates.sql [rule_id] [target_object_id]

set pagesize 50
set linesize 200
col rule_id format 9999
col target_object_id format 9999
col rule_name format a50
col object_name format a30
col validation_type format a25
col message format a80

prompt
prompt ===== VALIDATION: MAPPING CANDIDATES =====
prompt

declare
  l_rule_id number := &1;
  l_target_object_id number := &2;

  cursor c_validation is
    with rule_info as (
      select r.rule_id,
             r.rule_name,
             mo.object_id as target_object_id,
             mo.object_name
        from md_rule r
        join md_rule_target_action rta on rta.rule_id = r.rule_id
        join md_object mo on mo.object_id = rta.target_object_id
       where (l_rule_id is null or r.rule_id = l_rule_id)
         and (l_target_object_id is null or mo.object_id = l_target_object_id)
    ),
    output_coverage as (
      select ri.rule_id,
             ri.target_object_id,
             ri.rule_name,
             ri.object_name,
             count(distinct ro.rule_output_id) as output_count,
             count(distinct ro.target_column_id) as mapped_col_count
        from rule_info ri
        left join md_rule_output ro on ro.rule_id = ri.rule_id
                                    and ro.target_column_id in (
                                      select column_id from md_column
                                       where object_id = ri.target_object_id
                                    )
       group by ri.rule_id, ri.target_object_id, ri.rule_name, ri.object_name
    ),
    key_coverage as (
      select rta.rule_id,
             rta.target_object_id,
             count(distinct kc.key_component_id) as key_component_count,
             sum(case when ro.rule_output_id is not null then 1 else 0 end) as key_outputs_found
        from md_rule_target_action rta
        join md_key_definition kd on kd.key_id = rta.target_key_id
        join md_key_component kc on kc.key_id = kd.key_id
        left join md_rule_output ro on ro.rule_id = rta.rule_id
                                    and ro.target_column_id = kc.column_id
       where kd.key_scope = 'TARGET'
         and (l_rule_id is null or rta.rule_id = l_rule_id)
         and (l_target_object_id is null or rta.target_object_id = l_target_object_id)
       group by rta.rule_id, rta.target_object_id
    ),
    all_validations as (
      select oc.rule_id,
             oc.target_object_id,
             oc.rule_name,
             oc.object_name,
             case when oc.output_count = 0 then 'ERROR'
                  when oc.output_count > 0 and kc.key_outputs_found < kc.key_component_count then 'WARNING'
                  when oc.output_count > 0 and kc.key_outputs_found = kc.key_component_count then 'OK'
                  else 'INFO' end as validation_status,
             case when oc.output_count = 0 then 'No rule outputs defined for target table'
                  when kc.key_outputs_found is null then 'No target key defined'
                  when kc.key_outputs_found < kc.key_component_count then
                    'Key gap: ' || kc.key_component_count || ' components, ' ||
                    kc.key_outputs_found || ' outputs found'
                  else 'All key components have rule outputs' end as validation_message,
             oc.output_count as rule_output_count,
             kc.key_component_count,
             kc.key_outputs_found
        from output_coverage oc
        left join key_coverage kc on kc.rule_id = oc.rule_id
                                  and kc.target_object_id = oc.target_object_id
    )
    select rule_id,
           target_object_id,
           rule_name,
           object_name,
           validation_status,
           validation_message,
           rule_output_count,
           key_component_count,
           key_outputs_found
      from all_validations
     order by validation_status desc, rule_name, object_name;

begin
  dbms_output.put_line('');
  dbms_output.put_line('Validation Results:');
  dbms_output.put_line('');

  for rec in c_validation loop
    dbms_output.put_line('[' || rec.validation_status || '] ' ||
                         rec.rule_name || ' -> ' || rec.object_name);
    dbms_output.put_line('    ' || rec.validation_message);
    if rec.key_component_count is not null then
      dbms_output.put_line('    Key: ' || rec.key_outputs_found || '/' ||
                           rec.key_component_count || ' outputs found');
    end if;
    dbms_output.put_line('');
  end loop;

end;
/

prompt
prompt ===== AMBIGUOUS MAPPINGS (multiple outputs → same column) =====
prompt

select r.rule_id,
       r.rule_name,
       mc.column_id,
       mc.column_name,
       count(distinct ro.rule_output_id) as output_count,
       listagg(ro.rule_output_id, ', ') within group (order by ro.rule_output_id) as rule_output_ids
  from md_rule r
  join md_rule_output ro on ro.rule_id = r.rule_id
  join md_column mc on mc.column_id = ro.target_column_id
 group by r.rule_id, r.rule_name, mc.column_id, mc.column_name
 having count(distinct ro.rule_output_id) > 1
 order by r.rule_name, mc.column_name;

prompt
prompt ===== ORPHANED RULE OUTPUTS (no target table) =====
prompt

select r.rule_id,
       r.rule_name,
       ro.rule_output_id,
       mc.column_name,
       mo.object_name
  from md_rule_output ro
  join md_rule r on r.rule_id = ro.rule_id
  join md_column mc on mc.column_id = ro.target_column_id
  join md_object mo on mo.object_id = mc.object_id
 where not exists (
   select 1 from md_rule_target_action rta
    where rta.rule_id = r.rule_id
      and rta.target_object_id = mo.object_id
 )
 order by r.rule_name, mo.object_name;

prompt
