create or replace package body md_rule_selector_pkg as

  procedure populate_selected_rules(
    p_run_id          in number,
    p_change_event_id in number,
    p_tenant_id       in varchar2,
    p_context_id      in varchar2,
    p_purge_existing  in varchar2 default 'Y'
  ) is
    l_release_id number;
  begin
    -- Resolve release for this run so dependency traversal is release-scoped.
    select r.release_id
      into l_release_id
      from md_run r
     where r.run_id = p_run_id
       and r.tenant_id = p_tenant_id
       and r.context_id = p_context_id;

    if upper(nvl(p_purge_existing, 'Y')) = 'Y' then
      delete from md_run_selected_rule s
       where s.run_id = p_run_id
         and s.change_event_id = p_change_event_id
         and s.tenant_id = p_tenant_id
         and s.context_id = p_context_id;
    end if;

    -- 1) Directly impacted rules from changed source columns.
    merge into md_run_selected_rule tgt
    using (
      with direct_rules as (
        select distinct ri.rule_id
          from md_change_event evt
          join md_change_event_column_delta d
            on d.change_event_id = evt.change_event_id
           and d.tenant_id = evt.tenant_id
           and d.context_id = evt.context_id
          join md_column c
            on c.tenant_id = d.tenant_id
           and c.context_id = d.context_id
           and upper(c.column_name) = upper(d.source_column_name)
          join md_object o
            on o.object_id = c.object_id
           and o.tenant_id = c.tenant_id
           and o.context_id = c.context_id
           and o.release_id = l_release_id
           and upper(o.object_name) = upper(evt.source_entity_name)
          join md_rule_input ri
            on ri.source_column_id = c.column_id
           and ri.tenant_id = c.tenant_id
           and ri.context_id = c.context_id
          join md_rule r
            on r.rule_id = ri.rule_id
           and r.tenant_id = ri.tenant_id
           and r.context_id = ri.context_id
           and r.release_id = l_release_id
           and r.active_flag = 'Y'
           and r.status in ('APPROVED','PUBLISHED')
         where evt.change_event_id = p_change_event_id
           and evt.tenant_id = p_tenant_id
           and evt.context_id = p_context_id
           and d.value_changed_flag = 'Y'
      )
      select p_tenant_id as tenant_id,
             p_context_id as context_id,
             p_run_id as run_id,
             p_change_event_id as change_event_id,
             dr.rule_id,
             'DIRECT_COLUMN_LINK' as selection_reason,
             'N' as transitive_flag
        from direct_rules dr
    ) src
       on (
          tgt.tenant_id = src.tenant_id
      and tgt.context_id = src.context_id
      and tgt.run_id = src.run_id
      and tgt.change_event_id = src.change_event_id
      and tgt.rule_id = src.rule_id
       )
     when not matched then
       insert (
         run_selected_rule_id,
         tenant_id,
         context_id,
         run_id,
         change_event_id,
         rule_id,
         selection_reason,
         transitive_flag,
         selected_at
       ) values (
         md_run_selected_rule_seq.nextval,
         src.tenant_id,
         src.context_id,
         src.run_id,
         src.change_event_id,
         src.rule_id,
         src.selection_reason,
         src.transitive_flag,
         systimestamp
       );

    -- 2) Transitive dependencies (downstream rules).
    merge into md_run_selected_rule tgt
    using (
      with direct_rules as (
        select distinct s.rule_id
          from md_run_selected_rule s
         where s.run_id = p_run_id
           and s.change_event_id = p_change_event_id
           and s.tenant_id = p_tenant_id
           and s.context_id = p_context_id
           and s.selection_reason = 'DIRECT_COLUMN_LINK'
      ),
      dep_tree (rule_id) as (
        select dr.rule_id
          from direct_rules dr
        union all
        select d.downstream_rule_id
          from md_rule_dependency d
          join dep_tree t
            on d.upstream_rule_id = t.rule_id
         where d.tenant_id = p_tenant_id
           and d.context_id = p_context_id
           and d.release_id = l_release_id
           and d.active_flag = 'Y'
      ),
      transitive_rules as (
        select distinct dt.rule_id
          from dep_tree dt
         minus
        select rule_id from direct_rules
      )
      select p_tenant_id as tenant_id,
             p_context_id as context_id,
             p_run_id as run_id,
             p_change_event_id as change_event_id,
             tr.rule_id,
             'TRANSITIVE_DEPENDENCY' as selection_reason,
             'Y' as transitive_flag
        from transitive_rules tr
    ) src
       on (
          tgt.tenant_id = src.tenant_id
      and tgt.context_id = src.context_id
      and tgt.run_id = src.run_id
      and tgt.change_event_id = src.change_event_id
      and tgt.rule_id = src.rule_id
       )
     when not matched then
       insert (
         run_selected_rule_id,
         tenant_id,
         context_id,
         run_id,
         change_event_id,
         rule_id,
         selection_reason,
         transitive_flag,
         selected_at
       ) values (
         md_run_selected_rule_seq.nextval,
         src.tenant_id,
         src.context_id,
         src.run_id,
         src.change_event_id,
         src.rule_id,
         src.selection_reason,
         src.transitive_flag,
         systimestamp
       );

  exception
    when no_data_found then
      raise_application_error(-20021, 'Run not found for selector: run_id=' || p_run_id);
  end populate_selected_rules;

end md_rule_selector_pkg;
/

show errors package body md_rule_selector_pkg;
