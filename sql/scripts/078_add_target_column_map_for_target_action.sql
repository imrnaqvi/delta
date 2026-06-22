-- ============================================================
-- Seed MD_RULE_TARGET_COLUMN_MAP for all columns of the
-- target object tied to a given rule_target_action_id.
--
-- Usage: set l_action_id to the desired rule_target_action_id.
--        Review / update value_source_kind and value_expr
--        for each row after insertion.
-- ============================================================

declare
  l_action_id  md_rule_target_action.rule_target_action_id%type := 125; -- << change me
begin
  insert into md_rule_target_column_map (
    tenant_id,
    context_id,
    release_id,
    rule_target_action_id,
    target_column_id,
    value_source_kind,
    value_expr,
    required_flag,
    write_on_insert_flag,
    write_on_update_flag
  )
  select
    rta.tenant_id,
    rta.context_id,
    rta.release_id,
    rta.rule_target_action_id,
    c.column_id,
    'LITERAL'   as value_source_kind,  -- << update per column
    null        as value_expr,          -- << fill in expression
    'Y'         as required_flag,
    'Y'         as write_on_insert_flag,
    'Y'         as write_on_update_flag
  from md_rule_target_action rta
  join md_column c
    on  c.object_id  = rta.target_object_id
    and c.tenant_id  = rta.tenant_id
    and c.context_id = rta.context_id
  -- skip any columns already mapped
  where rta.rule_target_action_id = l_action_id
    and not exists (
      select 1
        from md_rule_target_column_map m
       where m.rule_target_action_id = rta.rule_target_action_id
         and m.target_column_id      = c.column_id
    )
  order by c.ordinal_position;

  dbms_output.put_line(sql%rowcount || ' row(s) inserted for action_id=' || l_action_id);
end;
/
