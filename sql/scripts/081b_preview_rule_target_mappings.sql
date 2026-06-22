-- 081b_preview_rule_target_mappings.sql
-- Preview auto-derived mappings without applying them
-- Shows which columns/keys would be mapped for a given rule/target combination
--
-- Usage:
--   @081b_preview_rule_target_mappings.sql

set pagesize 100
set linesize 200
col rule_id format 9999
col target_object_id format 9999
col rule_name format a50
col object_name format a30
col column_name format a30
col rule_output_id format 9999
col existing_map format a10

prompt
prompt ===== COLUMN MAPPING PREVIEW =====
prompt

with rule_outputs as (
  select ro.rule_output_id,
         ro.rule_id,
         r.rule_name,
         ro.target_column_id,
         ro.output_expr,
         mc.column_name,
         mc.object_id,
         mo.object_name,
         case when rtcm.rule_target_column_map_id is not null then 'EXISTING'
              else 'NEW' end as mapping_status
    from md_rule_output ro
    join md_rule r on r.rule_id = ro.rule_id
    join md_column mc on mc.column_id = ro.target_column_id
    join md_object mo on mo.object_id = mc.object_id
    left join md_rule_target_action rta on rta.rule_id = ro.rule_id
                                        and rta.target_object_id = mo.object_id
    left join md_rule_target_column_map rtcm on rtcm.rule_target_action_id = rta.rule_target_action_id
                                             and rtcm.target_column_id = ro.target_column_id
   order by r.rule_name, mo.object_name, mc.column_name
)
select rule_id,
       target_object_id,
       rule_name,
       object_name,
       rule_output_id,
       column_name,
       substr(output_expr, 1, 60) as output_expr,
       mapping_status
  from rule_outputs;

prompt
prompt ===== UNMAPPED COLUMNS (in target tables linked to rules) =====
prompt

select mo.object_id,
       mo.object_name,
       mc.column_id,
       mc.column_name,
       mc.data_type,
       'No rule output found' as reason
  from md_column mc
  join md_object mo on mo.object_id = mc.object_id
  where not exists (
    select 1 from md_rule_output ro
     where ro.target_column_id = mc.column_id
  )
  order by mo.object_name, mc.column_name;

prompt
prompt ===== KEY COMPONENT MAPPING PREVIEW =====
prompt

with key_info as (
  select rta.rule_target_action_id,
         rta.rule_id,
         rta.target_object_id,
         rta.target_key_id,
         r.rule_name,
         mo.object_name,
         kc.key_component_id,
         kc.ordinal_position,
         mc.column_name,
         case when rtcm.rule_target_column_map_id is not null then 'EXISTING'
              else 'NEW' end as mapping_status,
         rtkm.rule_target_key_map_id
    from md_rule_target_action rta
    join md_rule r on r.rule_id = rta.rule_id
    join md_object mo on mo.object_id = rta.target_object_id
    join md_key_definition kd on kd.key_id = rta.target_key_id
    join md_key_component kc on kc.key_id = kd.key_id
    join md_column mc on mc.column_id = kc.column_id
    left join md_rule_target_column_map rtcm on rtcm.rule_target_action_id = rta.rule_target_action_id
                                             and rtcm.target_column_id = kc.column_id
    left join md_rule_target_key_map rtkm on rtkm.rule_target_action_id = rta.rule_target_action_id
                                          and rtkm.target_key_component_id = kc.key_component_id
   where kd.key_scope = 'TARGET'
)
select rule_id,
       target_object_id,
       rule_name,
       object_name,
       key_component_id,
       ordinal_position,
       column_name,
       case when rule_target_key_map_id is not null then 'EXISTING'
            when mapping_status = 'NEW' then 'NEW (col output exists)'
            else 'MISSING (no col output)' end as key_map_status
  from key_info
 order by rule_name, object_name, ordinal_position;

prompt
prompt ===== CANDIDATE RULES FOR AUTO-DERIVATION =====
prompt

select r.rule_id,
       r.rule_name,
       count(distinct rta.target_object_id) as target_object_count,
       count(distinct ro.rule_output_id) as rule_output_count,
       count(distinct rta.rule_target_action_id) as target_actions
  from md_rule r
  left join md_rule_output ro on ro.rule_id = r.rule_id
  left join md_rule_target_action rta on rta.rule_id = r.rule_id
 where r.active_flag = 'Y'
   and r.status = 'PUBLISHED'
 group by r.rule_id, r.rule_name
 having count(distinct ro.rule_output_id) > 0
    and count(distinct rta.rule_target_action_id) > 0
 order by r.rule_name;

prompt
