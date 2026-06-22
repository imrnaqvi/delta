-- 079_md_rule_executor_debug_timeline.sql
-- Diagnostic timeline for md_rule_executor_pkg.execute_run
-- Usage example:
--   @sql/scripts/079_md_rule_executor_debug_timeline.sql 9001 12001

set serveroutput on
set verify off
set feedback on
set pagesize 200
set linesize 240
set long 200000
set longchunksize 200000
set trimspool on

column c_run_id new_value v_run_id noprint
column c_change_event_id new_value v_change_event_id noprint

select nvl('&&1','') c_run_id,
       nvl('&&2','') c_change_event_id
  from dual;

prompt =====================================================================
prompt Rule Executor Debug Timeline
prompt =====================================================================
prompt Input run_id=&v_run_id  change_event_id=&v_change_event_id
prompt

prompt [1] RUN SUMMARY
column run_status format a14
column tenant_id format a20
column context_id format a20
select run_id,
       tenant_id,
       context_id,
       run_status,
       started_at,
       ended_at
  from md_run
 where run_id = to_number('&v_run_id');

prompt
prompt [2] RULE SELECTION + GATE EVALUATION
column gate_eval_status format a10
column gate_eval_message format a90 word_wrapped
select rsr.run_selected_rule_id,
       rsr.rule_id,
       r.rule_name,
       r.rule_type,
       rsr.transitive_flag,
       rsr.gate_eval_status,
       rsr.gate_eval_message,
       rsr.gate_evaluated_at
  from md_run_selected_rule rsr
  join md_rule r
    on r.rule_id = rsr.rule_id
   and r.tenant_id = rsr.tenant_id
   and r.context_id = rsr.context_id
 where rsr.run_id = to_number('&v_run_id')
   and rsr.change_event_id = to_number('&v_change_event_id')
 order by rsr.run_selected_rule_id;

prompt
prompt [3] RULE OUTPUT FAILURE POLICY SNAPSHOT
column output_eval_failure_policy format a24
select rsr.rule_id,
       r.rule_name,
       nvl(r.output_eval_failure_policy, 'CONTINUE') as output_eval_failure_policy
  from md_run_selected_rule rsr
  join md_rule r
    on r.rule_id = rsr.rule_id
   and r.tenant_id = rsr.tenant_id
   and r.context_id = rsr.context_id
 where rsr.run_id = to_number('&v_run_id')
   and rsr.change_event_id = to_number('&v_change_event_id')
 order by rsr.run_selected_rule_id;

prompt
prompt [4] PERSISTED TARGET VALUES
column value_status format a10
column target_column_name format a40
column computed_value_txt format a80 word_wrapped
select run_target_value_id,
       rule_id,
       target_column_name,
       value_status,
       computed_value_txt,
       computed_at
  from md_run_target_value
 where run_id = to_number('&v_run_id')
 order by run_target_value_id;

prompt
prompt [5] TARGET ACTION EXECUTION LOG
column execution_phase format a24
column execution_status format a10
column target_entity_name format a32
column target_column_name format a32
column action_type format a10
column error_message format a90 word_wrapped
select run_target_action_id,
       rule_id,
       nvl(execution_phase, 'DIRECT_EXECUTION') as execution_phase,
       execution_status,
       action_type,
       target_entity_name,
       target_column_name,
       rows_affected,
       error_code,
       error_message,
       applied_flag,
       applied_at
  from md_run_target_action
 where run_id = to_number('&v_run_id')
   and change_event_id = to_number('&v_change_event_id')
 order by run_target_action_id;

prompt
prompt [6] FAILED ACTION SQL / PAYLOAD DETAILS
column generated_sql_text format a120 word_wrapped
column action_payload_json format a120 word_wrapped
column bind_payload_json format a120 word_wrapped
select run_target_action_id,
       rule_id,
       execution_status,
       error_code,
       generated_sql_text,
       action_payload_json,
       bind_payload_json
  from md_run_target_action
 where run_id = to_number('&v_run_id')
   and change_event_id = to_number('&v_change_event_id')
   and execution_status = 'FAILED'
 order by run_target_action_id;

prompt
prompt [7] CONSOLIDATION HEADER
column consolidation_status format a14
column target_entity_name format a32
select run_target_consolidation_id,
       target_entity_name,
       consolidation_status,
       winning_value_count,
       source_rule_count,
       updated_at
  from md_run_target_consolidation
 where run_id = to_number('&v_run_id')
   and change_event_id = to_number('&v_change_event_id')
 order by run_target_consolidation_id;

prompt
prompt [8] CONSOLIDATION WINNERS
column target_entity_name format a32
column target_column_name format a32
column computed_value_txt format a80 word_wrapped
select run_target_consolidated_value_id,
       run_target_consolidation_id,
       winner_rule_id,
       winner_priority_no,
       target_entity_name,
       target_column_name,
       computed_value_txt,
       updated_at
  from md_run_target_consolidated_value
 where run_id = to_number('&v_run_id')
   and change_event_id = to_number('&v_change_event_id')
 order by run_target_consolidation_id, target_column_name;

prompt
prompt [9] IMPACT TRACE (RULE SOURCE + SQL_SELECT TEXT)
column diagnostic_type format a24
column trace_step format a26
column target_excerpt format a120 word_wrapped
with trace_rows as (
  select it.impact_trace_id,
         json_value(it.source_ref_json, '$.diagnostic_type' returning varchar2(100)) as diagnostic_type,
         json_value(it.rule_ref_json, '$.step' returning varchar2(100)) as trace_step,
         dbms_lob.substr(it.target_ref_json, 4000, 1) as target_excerpt
    from md_impact_trace it
   where it.run_id = to_number('&v_run_id')
     and it.change_event_id = to_number('&v_change_event_id')
)
select impact_trace_id,
       diagnostic_type,
       trace_step,
       target_excerpt
  from trace_rows
 order by impact_trace_id;

prompt
prompt [10] CHRONOLOGICAL EVENT FEED
column source_name format a24
column event_status format a14
column event_detail format a120 word_wrapped
with events as (
  select mra.applied_at as event_ts,
         'MD_RUN_TARGET_ACTION' as source_name,
         mra.execution_status as event_status,
         'rule_id=' || mra.rule_id ||
         ', phase=' || nvl(mra.execution_phase, 'DIRECT_EXECUTION') ||
         ', col=' || nvl(mra.target_column_name, 'n/a') ||
         ', err=' || nvl(to_char(mra.error_code), 'n/a') as event_detail
    from md_run_target_action mra
   where mra.run_id = to_number('&v_run_id')
     and mra.change_event_id = to_number('&v_change_event_id')
  union all
  select rtc.updated_at as event_ts,
         'MD_RUN_TARGET_CONS' as source_name,
         rtc.consolidation_status as event_status,
         'cons_id=' || rtc.run_target_consolidation_id ||
         ', entity=' || rtc.target_entity_name ||
         ', win=' || rtc.winning_value_count as event_detail
    from md_run_target_consolidation rtc
   where rtc.run_id = to_number('&v_run_id')
     and rtc.change_event_id = to_number('&v_change_event_id')
  union all
  select cast(null as timestamp) as event_ts,
         'MD_IMPACT_TRACE' as source_name,
         nvl(json_value(it.source_ref_json, '$.diagnostic_type' returning varchar2(100)), 'TRACE') as event_status,
         'impact_trace_id=' || it.impact_trace_id as event_detail
    from md_impact_trace it
   where it.run_id = to_number('&v_run_id')
     and it.change_event_id = to_number('&v_change_event_id')
)
select event_ts,
       source_name,
       event_status,
       event_detail
  from events
 order by event_ts nulls last, source_name;

prompt
prompt Done.
