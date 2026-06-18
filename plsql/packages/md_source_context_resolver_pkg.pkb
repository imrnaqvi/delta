create or replace package body md_source_context_resolver_pkg as

  function parse_params_object(
    p_params_json in clob
  ) return json_object_t is
  begin
    if p_params_json is null then
      return json_object_t();
    end if;

    return json_object_t.parse(p_params_json);
  exception
    when others then
      return json_object_t();
  end parse_params_object;

  function parse_timestamp_param(
    p_param_value in varchar2,
    p_fallback    in timestamp
  ) return timestamp is
  begin
    if p_param_value is null then
      return p_fallback;
    end if;

    begin
      return to_timestamp(p_param_value, 'YYYY-MM-DD HH24:MI:SS');
    exception
      when others then
        null;
    end;

    begin
      return to_timestamp(p_param_value, 'YYYY-MM-DD');
    exception
      when others then
        return p_fallback;
    end;
  end parse_timestamp_param;

  function get_anchor_alias(
    p_source_context_id in number,
    p_tenant_id         in varchar2,
    p_context_id        in varchar2
  ) return varchar2 is
    l_alias varchar2(64);
  begin
    select sco.object_alias
      into l_alias
      from md_source_context_object sco
     where sco.source_context_id = p_source_context_id
       and sco.tenant_id = p_tenant_id
       and sco.context_id = p_context_id
       and sco.role_type = 'ANCHOR';

    return l_alias;
  exception
    when no_data_found then
      return 'SRC';
  end get_anchor_alias;

  function get_correlation_window_minutes(
    p_run_id      in number,
    p_tenant_id   in varchar2,
    p_context_id  in varchar2
  ) return number is
    l_window number;
  begin
    select nvl(max(cp.window_minutes), 15)
      into l_window
      from md_run r
      left join md_correlation_policy cp
        on cp.release_id = r.release_id
       and cp.tenant_id = r.tenant_id
       and cp.context_id = r.context_id
       and cp.active_flag = 'Y'
     where r.run_id = p_run_id
       and r.tenant_id = p_tenant_id
       and r.context_id = p_context_id;

    return nvl(l_window, 15);
  exception
    when no_data_found then
      return 15;
  end get_correlation_window_minutes;

  procedure upsert_correlation_group(
    p_run_id            in number,
    p_change_event_id   in number,
    p_tenant_id         in varchar2,
    p_context_id        in varchar2,
    p_correlation_key   in varchar2
  ) is
  begin
    merge into md_run_correlation_group tgt
    using (
      select p_tenant_id as tenant_id,
             p_context_id as context_id,
             p_run_id as run_id,
             p_change_event_id as anchor_change_event_id,
             p_correlation_key as correlation_key
        from dual
    ) src
       on (
          tgt.tenant_id = src.tenant_id
      and tgt.context_id = src.context_id
      and tgt.run_id = src.run_id
      and tgt.correlation_key = src.correlation_key
       )
     when not matched then
       insert (
         run_correlation_group_id,
         tenant_id,
         context_id,
         run_id,
         anchor_change_event_id,
         correlation_key,
         grouped_at
       ) values (
         md_run_correlation_group_seq.nextval,
         src.tenant_id,
         src.context_id,
         src.run_id,
         src.anchor_change_event_id,
         src.correlation_key,
         systimestamp
       );
  end upsert_correlation_group;

  procedure upsert_source_snapshot(
    p_run_id             in number,
    p_change_event_id    in number,
    p_rule_id            in number,
    p_source_context_id  in number,
    p_tenant_id          in varchar2,
    p_context_id         in varchar2,
    p_correlation_key    in varchar2,
    p_source_values_json in clob
  ) is
  begin
    merge into md_run_source_snapshot tgt
    using (
      select p_tenant_id as tenant_id,
             p_context_id as context_id,
             p_run_id as run_id,
             p_change_event_id as change_event_id,
             p_rule_id as rule_id,
             p_source_context_id as source_context_id,
             p_correlation_key as correlation_key,
             p_source_values_json as source_values_json
        from dual
    ) src
       on (
          tgt.tenant_id = src.tenant_id
      and tgt.context_id = src.context_id
      and tgt.run_id = src.run_id
      and nvl(tgt.change_event_id, -1) = nvl(src.change_event_id, -1)
      and tgt.rule_id = src.rule_id
       )
     when matched then
       update set
         tgt.source_context_id = src.source_context_id,
         tgt.correlation_key = src.correlation_key,
         tgt.source_values_json = src.source_values_json,
         tgt.created_at = systimestamp
     when not matched then
       insert (
         run_source_snapshot_id,
         tenant_id,
         context_id,
         run_id,
         change_event_id,
         rule_id,
         source_context_id,
         correlation_key,
         source_values_json,
         created_at
       ) values (
         md_run_source_snapshot_seq.nextval,
         src.tenant_id,
         src.context_id,
         src.run_id,
         src.change_event_id,
         src.rule_id,
         src.source_context_id,
         src.correlation_key,
         src.source_values_json,
         systimestamp
       );
  end upsert_source_snapshot;

  function resolve_rule_source_values(
    p_run_id          in number,
    p_change_event_id in number,
    p_rule_id         in number,
    p_tenant_id       in varchar2,
    p_context_id      in varchar2,
    p_params_json     in clob default null
  ) return clob is
    l_source_context_id   number;
    l_source_key_json     clob;
    l_source_key_hash     varchar2(128);
    l_anchor_alias        varchar2(64);
    l_anchor_event_ts     timestamp;
    l_window_minutes      number;
    l_effective_asof_ts   timestamp;
    l_params_obj          json_object_t;
    l_result_json         clob;
    l_result_obj          json_object_t;
    l_alias_json          clob;

    cursor c_context_objects is
      select sco.object_alias,
             sco.required_flag,
             o.object_name
        from md_source_context_object sco
        join md_object o
          on o.object_id = sco.object_id
         and o.tenant_id = sco.tenant_id
         and o.context_id = sco.context_id
       where sco.source_context_id = l_source_context_id
         and sco.tenant_id = p_tenant_id
         and sco.context_id = p_context_id
       order by case sco.role_type when 'ANCHOR' then 0 else 1 end,
                sco.object_alias;
  begin
    begin
      select rsc.source_context_id
        into l_source_context_id
        from md_rule_source_context rsc
       where rsc.rule_id = p_rule_id
         and rsc.tenant_id = p_tenant_id
         and rsc.context_id = p_context_id
         and rsc.active_flag = 'Y';
    exception
      when no_data_found then
        l_source_context_id := null;
    end;

    select evt.source_key_json, evt.source_key_hash, evt.event_ts
      into l_source_key_json, l_source_key_hash, l_anchor_event_ts
      from md_change_event evt
     where evt.change_event_id = p_change_event_id
       and evt.tenant_id = p_tenant_id
       and evt.context_id = p_context_id;

    l_params_obj := parse_params_object(p_params_json);
    l_effective_asof_ts := parse_timestamp_param(
      p_param_value => md_run_parameter_pkg.get_parameter_value(p_params_json, 'ASOF_DATE'),
      p_fallback    => parse_timestamp_param(md_run_parameter_pkg.get_parameter_value(p_params_json, 'NAV_DATE'), l_anchor_event_ts)
    );
    l_effective_asof_ts := nvl(l_effective_asof_ts, l_anchor_event_ts);

    l_window_minutes := get_correlation_window_minutes(
      p_run_id => p_run_id,
      p_tenant_id => p_tenant_id,
      p_context_id => p_context_id
    );

    if l_source_context_id is null then
      l_result_obj := json_object_t();
      l_result_obj.put('SRC', json_object_t.parse(l_source_key_json));
      if p_params_json is not null then
        l_result_obj.put('PARAM', l_params_obj);
      end if;

      upsert_correlation_group(
        p_run_id          => p_run_id,
        p_change_event_id => p_change_event_id,
        p_tenant_id       => p_tenant_id,
        p_context_id      => p_context_id,
        p_correlation_key => l_source_key_hash
      );

      upsert_source_snapshot(
        p_run_id             => p_run_id,
        p_change_event_id    => p_change_event_id,
        p_rule_id            => p_rule_id,
        p_source_context_id  => null,
        p_tenant_id          => p_tenant_id,
        p_context_id         => p_context_id,
        p_correlation_key    => l_source_key_hash,
        p_source_values_json => l_source_key_json
      );

      return l_result_obj.to_clob;
    end if;

    l_anchor_alias := get_anchor_alias(
      p_source_context_id => l_source_context_id,
      p_tenant_id         => p_tenant_id,
      p_context_id        => p_context_id
    );

    l_result_obj := json_object_t();

    -- Ensure anchor payload is always available in resolved context.
    l_result_obj.put(l_anchor_alias, json_object_t.parse(l_source_key_json));
    if p_params_json is not null then
      l_result_obj.put('PARAM', l_params_obj);
    end if;

    for rec in c_context_objects loop
      begin
        select q.source_key_json
          into l_alias_json
          from (
            select evt.source_key_json,
                   evt.event_ts
              from md_change_event evt
             where evt.tenant_id = p_tenant_id
               and evt.context_id = p_context_id
               and evt.source_key_hash = l_source_key_hash
               and upper(evt.source_entity_name) = upper(rec.object_name)
               and evt.event_ts between l_effective_asof_ts - numtodsinterval(l_window_minutes, 'MINUTE')
                                   and l_effective_asof_ts + numtodsinterval(l_window_minutes, 'MINUTE')
               and evt.event_ts <= l_effective_asof_ts
             order by evt.event_ts desc
          ) q
         where rownum = 1;
      exception
        when no_data_found then
          l_alias_json := null;
      end;

      if l_alias_json is not null then
        l_result_obj.put(rec.object_alias, json_object_t.parse(l_alias_json));
      elsif rec.required_flag = 'Y' and upper(rec.object_alias) <> upper(l_anchor_alias) then
        raise_application_error(
          -20032,
          'Missing required correlated source object for alias=' || rec.object_alias ||
          ', rule_id=' || p_rule_id || ', change_event_id=' || p_change_event_id
        );
      elsif upper(rec.object_alias) <> upper(l_anchor_alias) then
        l_result_obj.put_null(rec.object_alias);
      end if;
    end loop;

    l_result_json := l_result_obj.to_clob;

    upsert_correlation_group(
      p_run_id          => p_run_id,
      p_change_event_id => p_change_event_id,
      p_tenant_id       => p_tenant_id,
      p_context_id      => p_context_id,
      p_correlation_key => l_source_key_hash
    );

    upsert_source_snapshot(
      p_run_id             => p_run_id,
      p_change_event_id    => p_change_event_id,
      p_rule_id            => p_rule_id,
      p_source_context_id  => l_source_context_id,
      p_tenant_id          => p_tenant_id,
      p_context_id         => p_context_id,
      p_correlation_key    => l_source_key_hash,
      p_source_values_json => l_result_json
    );

    return l_result_json;
  exception
    when no_data_found then
      raise_application_error(-20031, 'Change event not found for source context resolver: change_event_id=' || p_change_event_id);
  end resolve_rule_source_values;

end md_source_context_resolver_pkg;
/

show errors package body md_source_context_resolver_pkg;
