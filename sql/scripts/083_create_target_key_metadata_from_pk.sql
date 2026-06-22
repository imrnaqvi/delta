-- 083_create_target_key_metadata_from_pk.sql
-- Create MD_KEY_DEFINITION and MD_KEY_COMPONENT rows for a target object
-- based on the primary key of the physical table behind md_object.object_id.
--
-- Usage:
--   begin
--     create_target_key_metadata_from_pk(
--       p_target_object_id => 65,
--       p_tenant_id        => 'TENANT_DEMO',
--       p_context_id       => 'CTX_DEMO',
--       p_release_id       => 1,
--       p_dry_run          => 'Y'
--     );
--   end;
--   /

create or replace procedure create_target_key_metadata_from_pk(
  p_target_object_id in number,
  p_tenant_id        in varchar2,
  p_context_id       in varchar2,
  p_release_id       in number,
  p_dry_run          in varchar2 default 'Y'
) is
  l_system_name          varchar2(100);
  l_schema_name          varchar2(128);
  l_object_name          varchar2(128);
  l_object_type          varchar2(20);
  l_pk_constraint_name   varchar2(128);
  l_key_name             varchar2(128);
  l_key_type             varchar2(20);
  l_key_id               number;
  l_key_exists           number := 0;
  l_component_exists     number;
  l_pk_column_count      number := 0;
  l_created_key_def      boolean := false;
  l_created_components   number := 0;
  l_skipped_components   number := 0;

  cursor c_pk_columns is
    select acc.column_name,
           acc.position,
           mc.column_id
      from all_constraints ac
      join all_cons_columns acc
        on acc.owner = ac.owner
       and acc.constraint_name = ac.constraint_name
      join md_column mc
        on mc.object_id = p_target_object_id
       and mc.tenant_id = p_tenant_id
       and mc.context_id = p_context_id
       and mc.column_name = acc.column_name
     where ac.owner = l_schema_name
       and ac.table_name = l_object_name
       and ac.constraint_type = 'P'
       and ac.status = 'ENABLED'
     order by acc.position;

begin
  dbms_output.put_line('========================================');
  dbms_output.put_line('Create Target Key Metadata From PK');
  dbms_output.put_line('========================================');
  dbms_output.put_line('Target Object ID: ' || p_target_object_id);
  dbms_output.put_line('Tenant ID: ' || p_tenant_id);
  dbms_output.put_line('Context ID: ' || p_context_id);
  dbms_output.put_line('Release ID: ' || p_release_id);
  dbms_output.put_line('Dry Run: ' || p_dry_run);
  dbms_output.put_line('');

  select o.system_name,
         o.schema_name,
         o.object_name,
         o.object_type
    into l_system_name,
         l_schema_name,
         l_object_name,
         l_object_type
    from md_object o
   where o.object_id = p_target_object_id
     and o.tenant_id = p_tenant_id
     and o.context_id = p_context_id
     and o.release_id = p_release_id;

  if l_object_type <> 'TABLE' then
    raise_application_error(-20001, 'Object must be of type TABLE: object_id=' || p_target_object_id);
  end if;

  l_key_name := 'PK_' || l_object_name;

  begin
    select constraint_name
      into l_pk_constraint_name
      from all_constraints
     where owner = l_schema_name
       and table_name = l_object_name
       and constraint_type = 'P'
       and status = 'ENABLED';
  exception
    when no_data_found then
      raise_application_error(-20002, 'No enabled primary key found for ' || l_schema_name || '.' || l_object_name);
  end;

  select count(*)
    into l_pk_column_count
    from all_cons_columns acc
    join all_constraints ac
      on ac.owner = acc.owner
     and ac.constraint_name = acc.constraint_name
   where ac.owner = l_schema_name
     and ac.table_name = l_object_name
     and ac.constraint_type = 'P'
     and ac.status = 'ENABLED';

  l_key_type := case when l_pk_column_count > 1 then 'NATURAL_COMPOSITE' else 'SURROGATE' end;

  begin
    select key_id
      into l_key_id
      from md_key_definition
     where tenant_id = p_tenant_id
       and context_id = p_context_id
       and release_id = p_release_id
       and key_scope = 'TARGET'
       and system_name = l_system_name
       and entity_name = l_object_name;
       --and key_name = l_key_name;

    l_key_exists := 1;
  exception
    when no_data_found then
      l_key_exists := 0;
  end;

  dbms_output.put_line('Resolved object: ' || l_schema_name || '.' || l_object_name);
  dbms_output.put_line('Primary key constraint: ' || l_pk_constraint_name);
  dbms_output.put_line('Key name: ' || l_key_name);
  dbms_output.put_line('Key type: ' || l_key_type);
  dbms_output.put_line('');

  if l_key_exists = 0 then
    dbms_output.put_line('KEY_DEFINITION: will create new row');
    if p_dry_run = 'N' then
      insert into md_key_definition (
        key_id,
        tenant_id,
        context_id,
        release_id,
        key_scope,
        system_name,
        entity_name,
        key_name,
        key_type,
        active_flag
      ) values (
        md_key_definition_seq.nextval,
        p_tenant_id,
        p_context_id,
        p_release_id,
        'TARGET',
        l_system_name,
        l_object_name,
        l_key_name,
        l_key_type,
        'Y'
      ) returning key_id into l_key_id;

      l_created_key_def := true;
    end if;
  else
    dbms_output.put_line('KEY_DEFINITION: existing key_id=' || l_key_id);
  end if;

  dbms_output.put_line('');
  dbms_output.put_line('--- Primary Key Components ---');

  for pk_rec in c_pk_columns loop
    select count(*)
      into l_component_exists
      from md_key_component
     where tenant_id = p_tenant_id
       and context_id = p_context_id
       and key_id = l_key_id
       and column_id = pk_rec.column_id;

    if l_component_exists > 0 then
      dbms_output.put_line('SKIP: ' || pk_rec.position || '. ' || pk_rec.column_name || ' (component already exists)');
      l_skipped_components := l_skipped_components + 1;
    else
      dbms_output.put_line('DERIVE: ' || pk_rec.position || '. ' || pk_rec.column_name);
      if p_dry_run = 'N' and l_key_id is not null then
        insert into md_key_component (
          key_component_id,
          tenant_id,
          context_id,
          key_id,
          column_id,
          ordinal_position
        ) values (
          md_key_component_seq.nextval,
          p_tenant_id,
          p_context_id,
          l_key_id,
          pk_rec.column_id,
          pk_rec.position
        );
      end if;

      l_created_components := l_created_components + 1;
    end if;
  end loop;

  dbms_output.put_line('');
  dbms_output.put_line('Summary:');
  dbms_output.put_line('  Key definition ' || case when l_created_key_def then 'created' else 'reused or previewed' end);
  dbms_output.put_line('  Components derived: ' || l_created_components);
  dbms_output.put_line('  Components skipped : ' || l_skipped_components);

  if p_dry_run = 'N' then
    commit;
    dbms_output.put_line('');
    dbms_output.put_line('Changes committed successfully.');
  else
    rollback;
    dbms_output.put_line('');
    dbms_output.put_line('DRY RUN: no changes committed.');
  end if;

exception
  when others then
    rollback;
    dbms_output.put_line('ERROR: ' || sqlerrm);
    raise;
end create_target_key_metadata_from_pk;
/

show errors;

-- Example:
-- begin
--   create_target_key_metadata_from_pk(
--     p_target_object_id => 65,
--     p_tenant_id        => 'TENANT_DEMO',
--     p_context_id       => 'CTX_DEMO',
--     p_release_id       => 1,
--     p_dry_run          => 'Y'
--   );
-- end;
-- /
