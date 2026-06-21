-- 036_md_sql_select_rule_upgrade.sql
-- Incremental/idempotent upgrade to enable SQL_SELECT rule type.

prompt Applying SQL_SELECT rule metadata upgrade...

declare
  l_has_sql_select number;
  l_col_comment    varchar2(4000);
begin
  select case
           when search_condition_vc like '%''SQL_SELECT''%' then 1
           else 0
         end
    into l_has_sql_select
    from user_constraints
   where table_name = 'MD_RULE'
     and constraint_name = 'MD_RULE_TYPE_CK';

  if l_has_sql_select = 0 then
    execute immediate 'alter table md_rule drop constraint md_rule_type_ck';

    execute immediate q'[
      alter table md_rule add constraint md_rule_type_ck
      check (rule_type in ('EXPRESSION','COLUMN_TO_ROW','LOOKUP','PLSQL_FUNC','SQL_SELECT'))
    ]';
  end if;

  select comments
    into l_col_comment
    from user_col_comments
   where table_name = 'MD_RULE'
     and column_name = 'RULE_PAYLOAD';

  if l_col_comment is null or instr(upper(l_col_comment), 'SQL_SELECT') = 0 then
    execute immediate q'[
      comment on column md_rule.rule_payload is
      'JSON payload by rule type. SQL_SELECT payload uses keys: sql_query, enable_token_substitution.'
    ]';
  end if;
exception
  when no_data_found then
    raise_application_error(-20801, 'Expected MD_RULE or MD_RULE_TYPE_CK metadata was not found.');
end;
/

prompt SQL_SELECT rule metadata upgrade complete.
