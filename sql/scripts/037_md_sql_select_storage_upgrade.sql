-- 037_md_sql_select_storage_upgrade.sql
-- Incremental/idempotent upgrade for SQL_SELECT-specific query storage.
-- Adds md_rule.sql_select_query and backfills from legacy rule_payload.sql_query.

prompt Applying SQL_SELECT-specific storage upgrade...

declare
  l_col_exists number;
begin
  select count(*)
    into l_col_exists
    from user_tab_cols
   where table_name = 'MD_RULE'
     and column_name = 'SQL_SELECT_QUERY';

  if l_col_exists = 0 then
    execute immediate 'alter table md_rule add (sql_select_query clob)';
  end if;

  execute immediate q'[
    comment on column md_rule.sql_select_query is
    'Preferred SQL text for SQL_SELECT rules. Orchestrator resolves this first, then falls back to legacy rule_payload.sql_query during transition.'
  ]';

  execute immediate q'[
    update md_rule
       set sql_select_query = json_value(rule_payload, '$.sql_query' returning varchar2(4000))
     where rule_type = 'SQL_SELECT'
       and sql_select_query is null
       and rule_payload is not null
       and json_exists(rule_payload, '$.sql_query')
  ]';

  execute immediate q'[
    comment on column md_rule.rule_payload is
    'JSON payload by rule type. For SQL_SELECT, rule_payload.sql_query is legacy fallback; prefer md_rule.sql_select_query.'
  ]';
end;
/

prompt SQL_SELECT-specific storage upgrade complete.
