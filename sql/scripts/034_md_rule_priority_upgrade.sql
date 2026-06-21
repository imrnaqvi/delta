-- 034_md_rule_priority_upgrade.sql
-- Incremental/idempotent upgrade for optional rule consolidation priority.

prompt Applying md_rule priority upgrade...

declare
  l_count number;
begin
  select count(*)
    into l_count
    from user_tab_cols
   where table_name = 'MD_RULE'
     and column_name = 'RULE_PRIORITY_NO';

  if l_count = 0 then
    execute immediate 'alter table md_rule add (rule_priority_no number)';
  end if;

  -- Optional helper index for runtime ordering and lookup.
  select count(*)
    into l_count
    from user_indexes
   where index_name = 'MD_RULE_PRIORITY_IX';

  if l_count = 0 then
    execute immediate 'create index md_rule_priority_ix on md_rule (tenant_id, context_id, release_id, nvl(rule_priority_no, 0), rule_id)';
  end if;
end;
/

prompt md_rule priority upgrade complete.
