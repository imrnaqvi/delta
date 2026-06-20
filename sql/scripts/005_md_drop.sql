-- 005_md_drop.sql
-- Drops MD_* objects created by phased metadata scripts.
-- Safe re-run: ignores "object does not exist" errors.

prompt Dropping MD objects (if present)...

begin
  for t in (
    select trigger_name
    from user_triggers
    where trigger_name in (
      'MD_RELEASE_BI_TRG',
      'MD_OBJECT_BI_TRG',
      'MD_COLUMN_BI_TRG',
      'MD_KEY_DEFINITION_BI_TRG',
      'MD_KEY_COMPONENT_BI_TRG',
      'MD_KEY_MAPPING_BI_TRG',
      'MD_RULE_BI_TRG',
      'MD_RULE_PARAM_REQ_BI_TRG',
      'MD_SOURCE_CONTEXT_BI_TRG',
      'MD_SOURCE_CONTEXT_OBJECT_BI_TRG',
      'MD_SOURCE_CONTEXT_JOIN_BI_TRG',
      'MD_SOURCE_CONTEXT_PRED_BI_TRG',
      'MD_RULE_SOURCE_CONTEXT_BI_TRG',
      'MD_RULE_SOURCE_OBJECT_BI_TRG',
      'MD_RULE_SOURCE_JOIN_BI_TRG',
      'MD_RULE_INPUT_BI_TRG',
      'MD_RULE_OUTPUT_BI_TRG',
      'MD_RULE_DEPENDENCY_BI_TRG',
      'MD_RULE_DEP_CONDITION_BI_TRG',
      'MD_RULE_TARGET_ACTION_BI_TRG',
      'MD_RULE_TARGET_KEY_MAP_BI_TRG',
      'MD_RULE_TARGET_COL_MAP_BI_TRG',
      'MD_DELETE_POLICY_BI_TRG',
      'MD_PUBLISH_VALIDATION_BI_TRG',
      'MD_OVERRIDE_REQUEST_BI_TRG',
      'MD_CORRELATION_POLICY_BI_TRG',
      'MD_CHANGE_EVENT_RAW_BI_TRG',
      'MD_CHANGE_EVENT_BI_TRG',
      'MD_CHANGE_EVENT_DELTA_BI_TRG',
      'MD_EXECUTION_POLICY_BI_TRG',
      'MD_RUN_BI_TRG',
      'MD_RUN_PARAM_BI_TRG',
      'MD_RUN_PARAM_SNAP_BI_TRG',
      'MD_RUN_CORR_GROUP_BI_TRG',
      'MD_RUN_SOURCE_SNAPSHOT_BI_TRG',
      'MD_RUN_CONTEXT_SNAPSHOT_BI_TRG',
      'MD_PROCESSED_EVENT_BI_TRG',
      'MD_RUN_SELECTED_RULE_BI_TRG',
      'MD_RUN_TARGET_ACTION_BI_TRG',
      'MD_RUN_TARGET_VALUE_BI_TRG',
      'MD_IMPACT_TRACE_BI_TRG',
      'MD_OVERRIDE_APPROVAL_BI_TRG',
      'MD_AUDIT_EVENT_BI_TRG',
      'MD_AUDIT_EVENT_DETAIL_BI_TRG',
      'MD_AUDIT_EVENT_NO_UPDATE_DELETE_TRG',
      'MD_AUDIT_EVENT_DETAIL_NO_UPDATE_DELETE_TRG'
    )
  ) loop
    execute immediate 'drop trigger ' || t.trigger_name;
  end loop;
end;
/

begin
  for s in (
    select table_name
    from user_tables
    where table_name in (
      'MD_AUDIT_EVENT_DETAIL',
      'MD_AUDIT_EVENT',
      'MD_OVERRIDE_APPROVAL',
      'MD_IMPACT_TRACE',
      'MD_RUN_TARGET_VALUE',
      'MD_RUN_TARGET_ACTION',
      'MD_RUN_SELECTED_RULE',
      'MD_PROCESSED_EVENT',
      'MD_RUN',
      'MD_RUN_PARAMETER',
      'MD_RUN_PARAMETER_SNAPSHOT',
      'MD_EXECUTION_POLICY',
      'MD_CHANGE_EVENT_COLUMN_DELTA',
      'MD_CHANGE_EVENT',
      'MD_CHANGE_EVENT_RAW',
      'MD_OVERRIDE_REQUEST',
      'MD_CORRELATION_POLICY',
      'MD_RULE_SOURCE_JOIN',
      'MD_RULE_SOURCE_OBJECT',
      'MD_RULE_SOURCE_CONTEXT',
      'MD_SOURCE_CONTEXT_JOIN',
      'MD_SOURCE_CONTEXT_OBJECT',
      'MD_SOURCE_CONTEXT',
      'MD_SOURCE_CONTEXT_PREDICATE',
      'MD_RUN_SOURCE_SNAPSHOT',
      'MD_RUN_CONTEXT_SNAPSHOT',
      'MD_RUN_CORRELATION_GROUP',
      'MD_PUBLISH_VALIDATION_RESULT',
      'MD_DELETE_POLICY',
      'MD_RULE_TARGET_ACTION',
      'MD_RULE_TARGET_COLUMN_MAP',
      'MD_RULE_TARGET_KEY_MAP',
      'MD_RULE_DEPENDENCY_CONDITION',
      'MD_RULE_DEPENDENCY',
      'MD_RULE_OUTPUT',
      'MD_RULE_INPUT',
      'MD_RULE_PARAMETER_REQUIREMENT',
      'MD_RULE',
      'MD_KEY_MAPPING',
      'MD_KEY_COMPONENT',
      'MD_KEY_DEFINITION',
      'MD_COLUMN',
      'MD_OBJECT',
      'MD_RELEASE'
    )
  ) loop
    execute immediate 'drop table ' || s.table_name || ' cascade constraints purge';
  end loop;
end;
/

begin
  for q in (
    select sequence_name
    from user_sequences
    where sequence_name in (
      'MD_AUDIT_EVENT_DETAIL_SEQ',
      'MD_AUDIT_EVENT_SEQ',
      'MD_OVERRIDE_APPROVAL_SEQ',
      'MD_IMPACT_TRACE_SEQ',
      'MD_RUN_TARGET_VALUE_SEQ',
      'MD_RUN_TARGET_ACTION_SEQ',
      'MD_RUN_SELECTED_RULE_SEQ',
      'MD_PROCESSED_EVENT_SEQ',
      'MD_RUN_SEQ',
      'MD_RUN_PARAMETER_SEQ',
      'MD_RUN_PARAMETER_SNAPSHOT_SEQ',
      'MD_RUN_SOURCE_SNAPSHOT_SEQ',
      'MD_RUN_CONTEXT_SNAPSHOT_SEQ',
      'MD_RUN_CORRELATION_GROUP_SEQ',
      'MD_EXECUTION_POLICY_SEQ',
      'MD_CHANGE_EVENT_COL_DELTA_SEQ',
      'MD_CHANGE_EVENT_SEQ',
      'MD_CHANGE_EVENT_RAW_SEQ',
      'MD_OVERRIDE_REQUEST_SEQ',
      'MD_PUBLISH_VALIDATION_RESULT_SEQ',
      'MD_DELETE_POLICY_SEQ',
      'MD_RULE_TARGET_ACTION_SEQ',
      'MD_RULE_TARGET_COLUMN_MAP_SEQ',
      'MD_RULE_TARGET_KEY_MAP_SEQ',
      'MD_RULE_DEP_CONDITION_SEQ',
      'MD_RULE_DEPENDENCY_SEQ',
      'MD_RULE_OUTPUT_SEQ',
      'MD_RULE_INPUT_SEQ',
      'MD_RULE_PARAMETER_REQUIREMENT_SEQ',
      'MD_RULE_SOURCE_JOIN_SEQ',
      'MD_RULE_SOURCE_OBJECT_SEQ',
      'MD_RULE_SOURCE_CONTEXT_SEQ',
      'MD_SOURCE_CONTEXT_JOIN_SEQ',
      'MD_SOURCE_CONTEXT_OBJECT_SEQ',
      'MD_SOURCE_CONTEXT_SEQ',
      'MD_SOURCE_CONTEXT_PREDICATE_SEQ',
      'MD_RULE_SEQ',
      'MD_CORRELATION_POLICY_SEQ',
      'MD_KEY_MAPPING_SEQ',
      'MD_KEY_COMPONENT_SEQ',
      'MD_KEY_DEFINITION_SEQ',
      'MD_COLUMN_SEQ',
      'MD_OBJECT_SEQ',
      'MD_RELEASE_SEQ'
    )
  ) loop
    execute immediate 'drop sequence ' || q.sequence_name;
  end loop;
end;
/

prompt MD drop script complete.
