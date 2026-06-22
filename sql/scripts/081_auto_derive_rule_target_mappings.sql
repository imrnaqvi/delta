-- 081_auto_derive_rule_target_mappings.sql
-- Auto-derive MD_RULE_TARGET_COLUMN_MAP and MD_RULE_TARGET_KEY_MAP
-- Matches rule outputs to target table columns/keys by column name
--
-- Usage:
--   exec derive_rule_target_mappings(
--     p_rule_id => 123,
--     p_target_object_id => 456,
--     p_tenant_id => 'TENANT1',
--     p_context_id => 'PROD',
--     p_release_id => 1
--   );

create or replace procedure derive_rule_target_mappings(
  p_rule_id          in number,
  p_target_object_id in number,
  p_tenant_id        in varchar2,
  p_context_id       in varchar2,
  p_release_id       in number,
  p_dry_run          in varchar2 default 'N'
) is

  l_target_key_id           number;
  l_rule_target_action_id   number;
  l_mapped_col_count        number := 0;
  l_mapped_key_count        number := 0;
  l_skipped_col_count       number := 0;
  l_unmapped_col_count      number := 0;
  l_existing_map_count      number;

  cursor c_rule_outputs is
    select ro.rule_output_id,
           ro.target_column_id,
           ro.output_expr,
           mc.column_name,
           mc.object_id
      from md_rule_output ro
      join md_column mc on mc.column_id = ro.target_column_id
     where ro.rule_id = p_rule_id
       and ro.tenant_id = p_tenant_id
       and ro.context_id = p_context_id
       and mc.object_id = p_target_object_id
     order by ro.rule_output_id;

  cursor c_target_columns is
    select column_id,
           column_name,
           data_type
      from md_column
     where object_id = p_target_object_id
       and tenant_id = p_tenant_id
       and context_id = p_context_id
     order by column_name;

  cursor c_key_components(p_key_id number) is
    select kc.key_component_id,
           kc.ordinal_position,
           mc.column_id,
           mc.column_name
      from md_key_component kc
      join md_column mc on mc.column_id = kc.column_id
     where kc.key_id = p_key_id
       and kc.tenant_id = p_tenant_id
       and kc.context_id = p_context_id
     order by kc.ordinal_position;

begin

  dbms_output.put_line('========================================');
  dbms_output.put_line('Auto-Derive Rule Target Mappings');
  dbms_output.put_line('========================================');
  dbms_output.put_line('Rule ID: ' || p_rule_id);
  dbms_output.put_line('Target Object ID: ' || p_target_object_id);
  dbms_output.put_line('Dry Run: ' || p_dry_run);
  dbms_output.put_line('');

  -- ===== Step 1: Validate inputs =====
  declare
    l_rule_exists number;
    l_object_exists number;
  begin
    select count(*) into l_rule_exists from md_rule where rule_id = p_rule_id;
    select count(*) into l_object_exists from md_object where object_id = p_target_object_id;

    if l_rule_exists = 0 then
      raise_application_error(-20001, 'Rule ID ' || p_rule_id || ' not found');
    end if;

    if l_object_exists = 0 then
      raise_application_error(-20002, 'Target Object ID ' || p_target_object_id || ' not found');
    end if;
  end;

  -- ===== Step 2: Get or create MD_RULE_TARGET_ACTION =====
  begin
    select rule_target_action_id into l_rule_target_action_id
      from md_rule_target_action
     where rule_id = p_rule_id
       and target_object_id = p_target_object_id
       and tenant_id = p_tenant_id
       and context_id = p_context_id
       and release_id = p_release_id
       and rownum = 1;
  exception
    when no_data_found then
      dbms_output.put_line('ERROR: No MD_RULE_TARGET_ACTION found for rule_id=' || p_rule_id ||
                           ', target_object_id=' || p_target_object_id);
      dbms_output.put_line('       Create MD_RULE_TARGET_ACTION first, then retry.');
      raise_application_error(-20003, 'MD_RULE_TARGET_ACTION not found');
  end;

  dbms_output.put_line('Found rule_target_action_id: ' || l_rule_target_action_id);
  dbms_output.put_line('');

  -- ===== Step 3: Derive column mappings =====
  dbms_output.put_line('--- Column Mappings ---');

  for out_rec in c_rule_outputs loop
    begin
      select count(*) into l_existing_map_count
        from md_rule_target_column_map
       where rule_target_action_id = l_rule_target_action_id
         and target_column_id = out_rec.target_column_id;

      if l_existing_map_count > 0 then
        dbms_output.put_line('SKIP: Column ' || out_rec.column_name ||
                             ' (mapping already exists)');
        l_skipped_col_count := l_skipped_col_count + 1;
      else
        dbms_output.put_line('DERIVE: Column ' || out_rec.column_name ||
                             ' from rule_output_id=' || out_rec.rule_output_id);

        if p_dry_run = 'N' then
          insert into md_rule_target_column_map (
            rule_target_column_map_id,
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
          ) values (
            md_rule_target_column_map_seq.nextval,
            p_tenant_id,
            p_context_id,
            p_release_id,
            l_rule_target_action_id,
            out_rec.target_column_id,
            'RULE_OUTPUT',
            'RULE_OUTPUT:' || out_rec.column_name,
            'Y',
            'Y',
            'Y'
          );
        end if;

        l_mapped_col_count := l_mapped_col_count + 1;
      end if;
    end;
  end loop;

  -- Report unmapped columns
  for col_rec in c_target_columns loop
    declare
      l_has_map number;
    begin
      select count(*) into l_has_map
        from md_rule_target_column_map
       where rule_target_action_id = l_rule_target_action_id
         and target_column_id = col_rec.column_id;

      if l_has_map = 0 then
        dbms_output.put_line('UNMAPPED: Column ' || col_rec.column_name || ' (' || col_rec.data_type || ')');
        l_unmapped_col_count := l_unmapped_col_count + 1;
      end if;
    end;
  end loop;

  dbms_output.put_line('');
  dbms_output.put_line('Column Summary: ' || l_mapped_col_count || ' derived, ' ||
                       l_skipped_col_count || ' existing, ' || l_unmapped_col_count || ' unmapped');
  dbms_output.put_line('');

  -- ===== Step 4: Derive key mappings =====
  dbms_output.put_line('--- Key Mappings ---');

  begin
    select target_key_id into l_target_key_id
      from md_rule_target_action
     where rule_target_action_id = l_rule_target_action_id;

    if l_target_key_id is not null then
      for key_rec in c_key_components(l_target_key_id) loop
        declare
          l_key_has_output number;
          l_key_existing_map number;
        begin
          select count(*) into l_key_has_output
            from md_rule_output ro
           where ro.rule_id = p_rule_id
             and ro.target_column_id = key_rec.column_id
             and ro.tenant_id = p_tenant_id
             and ro.context_id = p_context_id;

          select count(*) into l_key_existing_map
            from md_rule_target_key_map
           where rule_target_action_id = l_rule_target_action_id
             and target_key_component_id = key_rec.key_component_id;

          if l_key_existing_map > 0 then
            dbms_output.put_line('SKIP: Key component ' || key_rec.column_name ||
                                 ' (mapping already exists)');
          elsif l_key_has_output = 0 then
            dbms_output.put_line('MISSING: Key component ' || key_rec.column_name ||
                                 ' - no rule output defined');
          else
            dbms_output.put_line('DERIVE: Key component ' || key_rec.column_name ||
                                 ' (ordinal=' || key_rec.ordinal_position || ')');

            if p_dry_run = 'N' then
              insert into md_rule_target_key_map (
                rule_target_key_map_id,
                tenant_id,
                context_id,
                release_id,
                rule_target_action_id,
                target_key_component_id,
                source_kind,
                source_expr,
                required_flag
              ) values (
                md_rule_target_key_map_seq.nextval,
                p_tenant_id,
                p_context_id,
                p_release_id,
                l_rule_target_action_id,
                key_rec.key_component_id,
                'RULE_OUTPUT',
                'RULE_OUTPUT:' || key_rec.column_name,
                'Y'
              );
            end if;

            l_mapped_key_count := l_mapped_key_count + 1;
          end if;
        end;
      end loop;
    else
      dbms_output.put_line('INFO: No target_key_id defined in MD_RULE_TARGET_ACTION');
    end if;
  end;

  dbms_output.put_line('');
  dbms_output.put_line('Key Summary: ' || l_mapped_key_count || ' derived');
  dbms_output.put_line('');

  -- ===== Step 5: Commit and summary =====
  if p_dry_run = 'N' then
    commit;
    dbms_output.put_line('========================================');
    dbms_output.put_line('Mappings committed successfully');
    dbms_output.put_line('========================================');
  else
    dbms_output.put_line('========================================');
    dbms_output.put_line('DRY RUN: No changes committed');
    dbms_output.put_line('========================================');
  end if;

exception
  when others then
    rollback;
    dbms_output.put_line('ERROR: ' || sqlerrm);
    raise;
end derive_rule_target_mappings;
/

show errors;

-- ===== Example usage =====
-- exec derive_rule_target_mappings(p_rule_id => 1, p_target_object_id => 10, p_tenant_id => 'TENANT1', p_context_id => 'PROD', p_release_id => 1, p_dry_run => 'Y');
-- exec derive_rule_target_mappings(p_rule_id => 1, p_target_object_id => 10, p_tenant_id => 'TENANT1', p_context_id => 'PROD', p_release_id => 1);
