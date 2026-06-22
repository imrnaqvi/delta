-- 080_md_rule_executor_debug_latest_event.sql
-- Wrapper for 079: resolves latest change_event_id for a run_id, then runs full timeline.
-- Usage example:
--   @sql/scripts/080_md_rule_executor_debug_latest_event.sql 9001

set verify off
set feedback on
set pagesize 200
set linesize 240

column c_run_id new_value v_run_id noprint
column c_change_event_id new_value v_change_event_id noprint

select nvl('&&1','') c_run_id
  from dual;

select nvl((
  select max(change_event_id)
    from (
      select change_event_id
        from md_run_selected_rule
       where run_id = to_number('&v_run_id')
         and change_event_id is not null
      union all
      select change_event_id
        from md_run_target_action
       where run_id = to_number('&v_run_id')
         and change_event_id is not null
      union all
      select change_event_id
        from md_run_target_consolidation
       where run_id = to_number('&v_run_id')
         and change_event_id is not null
      union all
      select change_event_id
        from md_impact_trace
       where run_id = to_number('&v_run_id')
         and change_event_id is not null
    )
), -1) as c_change_event_id
from dual;

prompt =====================================================================
prompt Auto-resolved latest change_event_id for run_id=&v_run_id is &v_change_event_id
prompt =====================================================================

@@079_md_rule_executor_debug_timeline.sql &v_run_id &v_change_event_id
