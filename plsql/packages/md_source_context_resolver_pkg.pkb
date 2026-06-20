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

  function get_rule_source_context_id(
    p_rule_id     in number,
    p_tenant_id   in varchar2,
    p_context_id  in varchar2
  ) return number is
    l_source_context_id number;
  begin
    select rsc.source_context_id
      into l_source_context_id
      from md_rule_source_context rsc
     where rsc.rule_id = p_rule_id
       and rsc.tenant_id = p_tenant_id
       and rsc.context_id = p_context_id
       and rsc.active_flag = 'Y';

    return l_source_context_id;
  exception
    when no_data_found then
      return null;
  end get_rule_source_context_id;

  procedure upsert_run_context_snapshot(
    p_run_id            in number,
    p_change_event_id   in number,
    p_source_context_id in number,
    p_tenant_id         in varchar2,
    p_context_id        in varchar2,
    p_source_values_json in clob
  ) is
  begin
    merge into md_run_context_snapshot tgt
    using (
      select p_tenant_id as tenant_id,
             p_context_id as context_id,
             p_run_id as run_id,
             p_change_event_id as change_event_id,
             p_source_context_id as source_context_id,
             p_source_values_json as source_values_json
        from dual
    ) src
       on (
          tgt.tenant_id = src.tenant_id
      and tgt.context_id = src.context_id
      and tgt.run_id = src.run_id
      and tgt.change_event_id = src.change_event_id
      and tgt.source_context_id = src.source_context_id
       )
     when matched then
       update set
         tgt.source_values_json = src.source_values_json,
         tgt.created_at = systimestamp
     when not matched then
       insert (
         run_context_snapshot_id,
         tenant_id,
         context_id,
         run_id,
         change_event_id,
         source_context_id,
         source_values_json,
         created_at
       ) values (
         md_run_context_snapshot_seq.nextval,
         src.tenant_id,
         src.context_id,
         src.run_id,
         src.change_event_id,
         src.source_context_id,
         src.source_values_json,
         systimestamp
       );
  end upsert_run_context_snapshot;

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

    if l_source_context_id is null then
      l_result_obj := json_object_t();
      l_result_obj.put('SRC', json_object_t.parse(l_source_key_json));
      if p_params_json is not null then
        l_result_obj.put('PARAM', l_params_obj);
      end if;

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
        select evt.source_key_json
          into l_alias_json
          from md_change_event evt
         where evt.change_event_id = p_change_event_id
           and evt.tenant_id = p_tenant_id
           and evt.context_id = p_context_id
           and upper(evt.source_entity_name) = upper(rec.object_name);
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

  function clean_identifier(
    p_value in varchar2
  ) return varchar2 is
  begin
    if p_value is null or not regexp_like(p_value, '^[A-Za-z][A-Za-z0-9_$#]*$') then
      raise_application_error(-20041, 'Invalid identifier: ' || nvl(p_value, '<null>'));
    end if;
    return p_value;
  end clean_identifier;

  function to_sql_literal(
    p_value in varchar2
  ) return varchar2 is
  begin
    if p_value is null then
      return 'null';
    elsif regexp_like(p_value, '^[-+]?[0-9]+(\.[0-9]+)?$') then
      return p_value;
    else
      return '''' || replace(p_value, '''', '''''') || '''';
    end if;
  end to_sql_literal;

  function get_json_value_by_path(
    p_json in clob,
    p_path in varchar2
  ) return varchar2 is
    l_obj    json_object_t;
    l_curr_o json_object_t;
    l_elem   json_element_t;
    l_token  varchar2(4000);
    l_pos    pls_integer := 1;
    l_dot    pls_integer;
    l_path   varchar2(4000) := nvl(trim(p_path), '');
  begin
    if p_json is null or l_path is null then
      return null;
    end if;

    l_obj := json_object_t.parse(p_json);
    l_curr_o := l_obj;

    loop
      l_dot := instr(l_path, '.', l_pos);
      if l_dot = 0 then
        l_token := substr(l_path, l_pos);
      else
        l_token := substr(l_path, l_pos, l_dot - l_pos);
      end if;

      if l_token is null then
        return null;
      end if;

      l_elem := l_curr_o.get(l_token);
      if l_elem is null then
        return null;
      end if;

      if l_dot = 0 then
        if l_elem.is_null then
          return null;
        elsif l_elem.is_string then
          return l_curr_o.get_string(l_token);
        elsif l_elem.is_number then
          return to_char(l_curr_o.get_number(l_token));
        elsif l_elem.is_boolean then
          if l_curr_o.get_boolean(l_token) then
            return 'Y';
          else
            return 'N';
          end if;
        else
          return l_elem.to_string;
        end if;
      end if;

      if l_elem.is_object then
        l_curr_o := json_object_t.parse(l_elem.to_string);
      else
        return null;
      end if;

      l_pos := l_dot + 1;
    end loop;
  exception
    when others then
      return null;
  end get_json_value_by_path;

  function resolve_predicate_value(
    p_value_source_kind in varchar2,
    p_value_expr        in clob,
    p_source_key_json   in clob,
    p_old_key_json      in clob,
    p_new_key_json      in clob,
    p_params_json       in clob
  ) return varchar2 is
    l_expr varchar2(4000) := trim(dbms_lob.substr(p_value_expr, 4000, 1));
  begin
    case upper(nvl(p_value_source_kind, 'LITERAL'))
      when 'EVENT_KEY' then
        return get_json_value_by_path(p_source_key_json, l_expr);
      when 'EVENT_OLD' then
        return get_json_value_by_path(p_old_key_json, l_expr);
      when 'EVENT_NEW' then
        return get_json_value_by_path(p_new_key_json, l_expr);
      when 'PARAM' then
        return md_run_parameter_pkg.get_parameter_value(p_params_json, l_expr);
      when 'LITERAL' then
        return l_expr;
      else
        return null;
    end case;
  end resolve_predicate_value;

  function merge_json_objects(
    p_base_json    in clob,
    p_overlay_json in clob
  ) return clob is
    l_base_obj    json_object_t;
    l_overlay_obj json_object_t;
    l_keys        json_key_list;
    l_elem        json_element_t;
    l_key         varchar2(4000);
  begin
    if p_base_json is null then
      l_base_obj := json_object_t();
    else
      l_base_obj := json_object_t.parse(p_base_json);
    end if;

    if p_overlay_json is null then
      return l_base_obj.to_clob;
    end if;

    l_overlay_obj := json_object_t.parse(p_overlay_json);
    l_keys := l_overlay_obj.get_keys;

    for i in 1 .. l_keys.count loop
      l_key := l_keys(i);
      l_elem := l_overlay_obj.get(l_key);
      l_base_obj.put(l_key, l_elem);
    end loop;

    return l_base_obj.to_clob;
  exception
    when others then
      return nvl(p_base_json, p_overlay_json);
  end merge_json_objects;

  function build_context_projection_json(
    p_run_id            in number,
    p_change_event_id   in number,
    p_source_context_id in number,
    p_rule_id           in number,
    p_tenant_id         in varchar2,
    p_context_id        in varchar2,
    p_source_key_json   in clob,
    p_old_key_json      in clob,
    p_new_key_json      in clob,
    p_params_json       in clob
  ) return clob is
    type key_set_t is table of pls_integer index by varchar2(4000);
    l_used_keys key_set_t;
    l_select_list   clob;
    l_from_clause   clob;
    l_where_clause  clob;
    l_group_clause  clob;
    l_predicate_sql varchar2(4000);
    l_curr_group    number := null;
    l_output_key    varchar2(4000);
    l_alias         varchar2(128);
    l_col_name      varchar2(128);
    l_val1          varchar2(4000);
    l_val2          varchar2(4000);
    l_sql           clob;
    l_json_out      clob;
    l_joined_count  number;
    l_anchor_alias  varchar2(64);
    l_anchor_owner  varchar2(128);
    l_anchor_object varchar2(128);
    l_loop_guard    number := 0;

    function split_expr_count(
      p_expr in varchar2
    ) return number is
      l_count number := 0;
      l_level number := 0;
      l_ch    varchar2(1);
    begin
      if p_expr is null then
        return 0;
      end if;

      l_count := 1;
      for i in 1 .. length(p_expr) loop
        l_ch := substr(p_expr, i, 1);
        if l_ch = '(' then
          l_level := l_level + 1;
        elsif l_ch = ')' and l_level > 0 then
          l_level := l_level - 1;
        elsif l_ch = ',' and l_level = 0 then
          l_count := l_count + 1;
        end if;
      end loop;

      return l_count;
    end split_expr_count;

    function split_expr_part(
      p_expr in varchar2,
      p_idx  in number
    ) return varchar2 is
      l_level number := 0;
      l_start number := 1;
      l_curr  number := 1;
      l_ch    varchar2(1);
    begin
      if p_expr is null then
        return null;
      end if;

      for i in 1 .. length(p_expr) loop
        l_ch := substr(p_expr, i, 1);
        if l_ch = '(' then
          l_level := l_level + 1;
        elsif l_ch = ')' and l_level > 0 then
          l_level := l_level - 1;
        elsif l_ch = ',' and l_level = 0 then
          if l_curr = p_idx then
            return trim(substr(p_expr, l_start, i - l_start));
          end if;
          l_curr := l_curr + 1;
          l_start := i + 1;
        end if;
      end loop;

      if l_curr = p_idx then
        return trim(substr(p_expr, l_start));
      end if;

      return null;
    end split_expr_part;

    procedure split_expr_and_alias(
      p_expr_item    in varchar2,
      p_default_alias in varchar2,
      o_expr_only    out varchar2,
      o_alias        out varchar2
    ) is
      l_expr_item varchar2(4000) := trim(p_expr_item);
    begin
      o_expr_only := null;
      o_alias := null;

      if l_expr_item is null then
        return;
      end if;

      if p_default_alias is not null then
        o_expr_only := l_expr_item;
        o_alias := trim(p_default_alias);
        return;
      end if;

      o_alias := regexp_substr(
        l_expr_item,
        '[[:space:]]+AS[[:space:]]+([A-Za-z][A-Za-z0-9_$#]*)[[:space:]]*$',
        1,
        1,
        'i',
        1
      );

      if o_alias is null then
        return;
      end if;

      o_expr_only := trim(regexp_replace(
        l_expr_item,
        '[[:space:]]+AS[[:space:]]+[A-Za-z][A-Za-z0-9_$#]*[[:space:]]*$',
        '',
        1,
        1,
        'i'
      ));
    end split_expr_and_alias;

    function validate_scalar_expr(
      p_expr in varchar2
    ) return varchar2 is
      l_upper_expr varchar2(4000) := upper(nvl(p_expr, ''));
    begin
      if p_expr is null then
        return 'Expression is null';
      end if;

      if instr(l_upper_expr, ';') > 0 then
        return 'Blocked token detected: ;';
      end if;

      if instr(l_upper_expr, '--') > 0 then
        return 'Blocked token detected: --';
      end if;

      if instr(l_upper_expr, '/*') > 0 or instr(l_upper_expr, '*/') > 0 then
        return 'Blocked token detected: SQL comment marker';
      end if;

      if regexp_like(l_upper_expr, '(^|[^A-Z0-9_])(SELECT|FROM|UNION|JOIN|WITH)([^A-Z0-9_]|$)') then
        return 'Blocked keyword detected for scalar expression';
      end if;

      return null;
    end validate_scalar_expr;
  begin
    select sco.object_alias, o.schema_name, o.object_name
      into l_anchor_alias, l_anchor_owner, l_anchor_object
      from md_source_context_object sco
      join md_object o
        on o.object_id = sco.object_id
       and o.tenant_id = sco.tenant_id
       and o.context_id = sco.context_id
     where sco.source_context_id = p_source_context_id
       and sco.tenant_id = p_tenant_id
       and sco.context_id = p_context_id
       and sco.role_type = 'ANCHOR';

    l_from_clause := clean_identifier(l_anchor_owner) || '.' || clean_identifier(l_anchor_object) || ' ' || clean_identifier(l_anchor_alias);

    -- Build join chain from source-context graph.
    l_joined_count := 1;
    while l_loop_guard < 20 loop
      l_loop_guard := l_loop_guard + 1;
      declare
        l_added number := 0;
      begin
        for j in (
          select scj.left_alias,
                 scj.right_alias,
                 scj.join_type,
                 scj.join_expr,
                 o.schema_name,
                 o.object_name
            from md_source_context_join scj
            join md_source_context_object sco_r
              on sco_r.source_context_id = scj.source_context_id
             and sco_r.tenant_id = scj.tenant_id
             and sco_r.context_id = scj.context_id
             and sco_r.object_alias = scj.right_alias
            join md_object o
              on o.object_id = sco_r.object_id
             and o.tenant_id = sco_r.tenant_id
             and o.context_id = sco_r.context_id
           where scj.source_context_id = p_source_context_id
             and scj.tenant_id = p_tenant_id
             and scj.context_id = p_context_id
             and scj.active_flag = 'Y'
             and instr(' ' || upper(l_from_clause) || ' ', ' ' || upper(scj.left_alias) || ' ') > 0
             and instr(' ' || upper(l_from_clause) || ' ', ' ' || upper(scj.right_alias) || ' ') = 0
        ) loop
          l_from_clause := l_from_clause
            || ' ' || case upper(j.join_type) when 'LEFT' then 'LEFT JOIN' else 'JOIN' end
            || ' ' || clean_identifier(j.schema_name) || '.' || clean_identifier(j.object_name)
            || ' ' || clean_identifier(j.right_alias)
            || ' ON ' || dbms_lob.substr(j.join_expr, 4000, 1);
          l_added := l_added + 1;
        end loop;

        exit when l_added = 0;
      end;
    end loop;

    -- Projection list from selected rules + md_rule_input.
    for p in (
      select distinct
             sco.object_alias,
             c.column_name,
             ri.output_alias
        from md_run_selected_rule s
        join md_rule_source_context rsc
          on rsc.rule_id = s.rule_id
         and rsc.tenant_id = s.tenant_id
         and rsc.context_id = s.context_id
         and rsc.active_flag = 'Y'
        join md_rule_input ri
          on ri.rule_id = s.rule_id
         and ri.tenant_id = s.tenant_id
         and ri.context_id = s.context_id
        join md_column c
          on c.column_id = ri.source_column_id
         and c.tenant_id = ri.tenant_id
         and c.context_id = ri.context_id
        join md_source_context_object sco
          on sco.source_context_id = rsc.source_context_id
         and sco.object_id = c.object_id
         and sco.tenant_id = c.tenant_id
         and sco.context_id = c.context_id
       where s.run_id = p_run_id
         and s.change_event_id = p_change_event_id
         and s.tenant_id = p_tenant_id
         and s.context_id = p_context_id
           and s.rule_id = p_rule_id
         and rsc.source_context_id = p_source_context_id
    ) loop
      l_alias := clean_identifier(p.object_alias);
      l_col_name := clean_identifier(p.column_name);
      l_output_key := nvl(trim(p.output_alias), p.column_name);

      if l_used_keys.exists(upper(l_output_key)) then
        l_output_key := p.object_alias || '_' || p.column_name;
      end if;

      if l_used_keys.exists(upper(l_output_key)) then
        l_output_key := l_output_key || '_' || to_char(dbms_utility.get_hash_value(l_alias || '.' || l_col_name, 0, 9999));
      end if;

      l_used_keys(upper(l_output_key)) := 1;

      if l_select_list is not null then
        l_select_list := l_select_list || ', ';
      end if;

      l_select_list := l_select_list
        || '''' || replace(l_output_key, '''', '''''') || ''' value '
        || l_alias || '.' || l_col_name;
    end loop;

    -- Rule-scoped scalar expressions that project additional JSON keys.
    for expr_rec in (
      select rule_input_expr_id,
             output_alias,
             scalar_expr,
             nvl(required_flag, 'N') as required_flag
        from md_rule_input_expr
       where tenant_id = p_tenant_id
         and context_id = p_context_id
         and rule_id = p_rule_id
         and nvl(active_flag, 'Y') = 'Y'
       order by nvl(expression_order_no, 999999), rule_input_expr_id
    ) loop
      declare
        l_expr_text      varchar2(4000) := trim(dbms_lob.substr(expr_rec.scalar_expr, 4000, 1));
        l_part_count     number;
        l_part           varchar2(4000);
        l_expr_only      varchar2(4000);
        l_expr_alias     varchar2(128);
        l_validation_err varchar2(4000);
      begin
        l_part_count := split_expr_count(l_expr_text);

        for i in 1 .. l_part_count loop
          l_part := split_expr_part(l_expr_text, i);

          split_expr_and_alias(
            p_expr_item     => l_part,
            p_default_alias => case when l_part_count = 1 then expr_rec.output_alias else null end,
            o_expr_only     => l_expr_only,
            o_alias         => l_expr_alias
          );

          if l_expr_alias is null or l_expr_only is null then
            begin
              insert into md_impact_trace (
                impact_trace_id,
                tenant_id,
                context_id,
                run_id,
                change_event_id,
                source_ref_json,
                rule_ref_json,
                target_ref_json
              ) values (
                md_impact_trace_seq.nextval,
                p_tenant_id,
                p_context_id,
                p_run_id,
                p_change_event_id,
                json_object(
                  'diagnostic_type' value 'RULE_SCALAR_EXPR_SKIPPED',
                  'rule_input_expr_id' value expr_rec.rule_input_expr_id,
                  'reason' value 'Missing output alias (use OUTPUT_ALIAS or inline AS alias)'
                  returning clob
                ),
                json_object(
                  'stage' value 'BUILD_CONTEXT_PROJECTION_JSON',
                  'rule_id' value p_rule_id
                  returning clob
                ),
                json_object(
                  'expr_item' value nvl(l_part, '<null>')
                  returning clob
                )
              );
            exception
              when others then
                null;
            end;

            if expr_rec.required_flag = 'Y' then
              raise_application_error(-20043, 'Required scalar expression alias missing for rule_id=' || p_rule_id);
            end if;

            continue;
          end if;

          l_validation_err := validate_scalar_expr(l_expr_only);
          if l_validation_err is not null then
            begin
              insert into md_impact_trace (
                impact_trace_id,
                tenant_id,
                context_id,
                run_id,
                change_event_id,
                source_ref_json,
                rule_ref_json,
                target_ref_json
              ) values (
                md_impact_trace_seq.nextval,
                p_tenant_id,
                p_context_id,
                p_run_id,
                p_change_event_id,
                json_object(
                  'diagnostic_type' value 'RULE_SCALAR_EXPR_SKIPPED',
                  'rule_input_expr_id' value expr_rec.rule_input_expr_id,
                  'reason' value l_validation_err
                  returning clob
                ),
                json_object(
                  'stage' value 'BUILD_CONTEXT_PROJECTION_JSON',
                  'rule_id' value p_rule_id
                  returning clob
                ),
                json_object(
                  'expr_item' value nvl(l_part, '<null>')
                  returning clob
                )
              );
            exception
              when others then
                null;
            end;

            if expr_rec.required_flag = 'Y' then
              raise_application_error(-20044, 'Required scalar expression blocked for rule_id=' || p_rule_id || ': ' || l_validation_err);
            end if;

            continue;
          end if;

          if l_used_keys.exists(upper(l_expr_alias)) then
            begin
              insert into md_impact_trace (
                impact_trace_id,
                tenant_id,
                context_id,
                run_id,
                change_event_id,
                source_ref_json,
                rule_ref_json,
                target_ref_json
              ) values (
                md_impact_trace_seq.nextval,
                p_tenant_id,
                p_context_id,
                p_run_id,
                p_change_event_id,
                json_object(
                  'diagnostic_type' value 'RULE_SCALAR_EXPR_SKIPPED',
                  'rule_input_expr_id' value expr_rec.rule_input_expr_id,
                  'reason' value 'Duplicate output alias: ' || l_expr_alias
                  returning clob
                ),
                json_object(
                  'stage' value 'BUILD_CONTEXT_PROJECTION_JSON',
                  'rule_id' value p_rule_id
                  returning clob
                ),
                json_object(
                  'expr_item' value nvl(l_part, '<null>')
                  returning clob
                )
              );
            exception
              when others then
                null;
            end;

            if expr_rec.required_flag = 'Y' then
              raise_application_error(-20045, 'Required scalar expression alias conflicts with existing key for rule_id=' || p_rule_id || ': ' || l_expr_alias);
            end if;

            continue;
          end if;

          l_used_keys(upper(l_expr_alias)) := 1;

          if l_select_list is not null then
            l_select_list := l_select_list || ', ';
          end if;

          l_select_list := l_select_list
            || '''' || replace(l_expr_alias, '''', '''''') || ''' value (' || l_expr_only || ')';
        end loop;
      end;
    end loop;

    if l_select_list is null then
      return '{}';
    end if;

    -- Predicate list from md_source_context_predicate.
    for pred in (
      select p.predicate_group_no,
             p.predicate_order_no,
             sco.object_alias,
             c.column_name,
             p.operator_code,
             p.value_source_kind,
             p.value_expr,
             p.value_expr_to,
             p.required_flag,
             p.null_behavior
        from md_source_context_predicate p
        join md_source_context_object sco
          on sco.source_context_object_id = p.source_context_object_id
         and sco.tenant_id = p.tenant_id
         and sco.context_id = p.context_id
        join md_column c
          on c.column_id = p.column_id
         and c.tenant_id = p.tenant_id
         and c.context_id = p.context_id
       where p.source_context_id = p_source_context_id
         and p.tenant_id = p_tenant_id
         and p.context_id = p_context_id
         and p.active_flag = 'Y'
         and (
              p.rule_id is null
              or p.rule_id = p_rule_id
         )
       order by p.predicate_group_no, p.predicate_order_no
    ) loop
      if l_curr_group is null or l_curr_group <> pred.predicate_group_no then
        if l_group_clause is not null then
          if l_where_clause is null then
            l_where_clause := '(' || l_group_clause || ')';
          else
            l_where_clause := l_where_clause || ' OR (' || l_group_clause || ')';
          end if;
        end if;
        l_group_clause := null;
        l_curr_group := pred.predicate_group_no;
      end if;

      l_predicate_sql := null;

      if upper(pred.operator_code) in ('IS_NULL', 'IS_NOT_NULL') then
        l_predicate_sql := clean_identifier(pred.object_alias) || '.' || clean_identifier(pred.column_name)
          || case upper(pred.operator_code) when 'IS_NULL' then ' is null' else ' is not null' end;
      else
        l_val1 := resolve_predicate_value(
          p_value_source_kind => pred.value_source_kind,
          p_value_expr        => pred.value_expr,
          p_source_key_json   => p_source_key_json,
          p_old_key_json      => p_old_key_json,
          p_new_key_json      => p_new_key_json,
          p_params_json       => p_params_json
        );

        if l_val1 is null then
          case upper(nvl(pred.null_behavior, 'SKIP_IF_NULL'))
            when 'FAIL_IF_NULL' then
              raise_application_error(-20042, 'Required predicate value missing for ' || pred.object_alias || '.' || pred.column_name);
            when 'IS_NULL_IF_NULL' then
              l_predicate_sql := clean_identifier(pred.object_alias) || '.' || clean_identifier(pred.column_name) || ' is null';
            else
              l_predicate_sql := null;
          end case;
        else
          case upper(pred.operator_code)
            when 'EQ' then
              l_predicate_sql := clean_identifier(pred.object_alias) || '.' || clean_identifier(pred.column_name) || ' = ' || to_sql_literal(l_val1);
            when 'NE' then
              l_predicate_sql := clean_identifier(pred.object_alias) || '.' || clean_identifier(pred.column_name) || ' <> ' || to_sql_literal(l_val1);
            when 'GT' then
              l_predicate_sql := clean_identifier(pred.object_alias) || '.' || clean_identifier(pred.column_name) || ' > ' || to_sql_literal(l_val1);
            when 'GE' then
              l_predicate_sql := clean_identifier(pred.object_alias) || '.' || clean_identifier(pred.column_name) || ' >= ' || to_sql_literal(l_val1);
            when 'LT' then
              l_predicate_sql := clean_identifier(pred.object_alias) || '.' || clean_identifier(pred.column_name) || ' < ' || to_sql_literal(l_val1);
            when 'LE' then
              l_predicate_sql := clean_identifier(pred.object_alias) || '.' || clean_identifier(pred.column_name) || ' <= ' || to_sql_literal(l_val1);
            when 'LIKE' then
              l_predicate_sql := clean_identifier(pred.object_alias) || '.' || clean_identifier(pred.column_name) || ' like ' || to_sql_literal(l_val1);
            when 'BETWEEN' then
              l_val2 := resolve_predicate_value(
                p_value_source_kind => pred.value_source_kind,
                p_value_expr        => pred.value_expr_to,
                p_source_key_json   => p_source_key_json,
                p_old_key_json      => p_old_key_json,
                p_new_key_json      => p_new_key_json,
                p_params_json       => p_params_json
              );
              if l_val2 is null then
                l_predicate_sql := null;
              else
                l_predicate_sql := clean_identifier(pred.object_alias) || '.' || clean_identifier(pred.column_name)
                  || ' between ' || to_sql_literal(l_val1) || ' and ' || to_sql_literal(l_val2);
              end if;
            when 'IN' then
              declare
                l_item varchar2(4000);
                l_list varchar2(32767);
                l_idx  number := 1;
              begin
                loop
                  l_item := trim(regexp_substr(l_val1, '[^,]+', 1, l_idx));
                  exit when l_item is null;
                  if l_list is not null then
                    l_list := l_list || ',';
                  end if;
                  l_list := l_list || to_sql_literal(l_item);
                  l_idx := l_idx + 1;
                end loop;

                if l_list is not null then
                  l_predicate_sql := clean_identifier(pred.object_alias) || '.' || clean_identifier(pred.column_name) || ' in (' || l_list || ')';
                end if;
              end;
            else
              null;
          end case;
        end if;
      end if;

      if l_predicate_sql is not null then
        if l_group_clause is null then
          l_group_clause := l_predicate_sql;
        else
          l_group_clause := l_group_clause || ' AND ' || l_predicate_sql;
        end if;
      end if;
    end loop;

    if l_group_clause is not null then
      if l_where_clause is null then
        l_where_clause := '(' || l_group_clause || ')';
      else
        l_where_clause := l_where_clause || ' OR (' || l_group_clause || ')';
      end if;
    end if;

    l_sql := 'select json_object(' || l_select_list || ' returning clob) from ' || l_from_clause;
    if l_where_clause is not null then
      l_sql := l_sql || ' where ' || l_where_clause;
    end if;
    l_sql := l_sql || ' fetch first 1 row only';

    begin
      insert into md_impact_trace (
        impact_trace_id,
        tenant_id,
        context_id,
        run_id,
        change_event_id,
        source_ref_json,
        rule_ref_json,
        target_ref_json
      ) values (
        md_impact_trace_seq.nextval,
        p_tenant_id,
        p_context_id,
        p_run_id,
        p_change_event_id,
        json_object(
          'diagnostic_type' value 'SOURCE_CONTEXT_SQL',
          'source_context_id' value p_source_context_id
          returning clob
        ),
        json_object(
          'stage' value 'BUILD_CONTEXT_PROJECTION_JSON',
          'rule_id' value null
          returning clob
        ),
        json_object(
          'sql_text' value l_sql
          returning clob
        )
      );
    exception
      when others then
        null;
    end;

    begin
      execute immediate l_sql into l_json_out;
    exception
      when no_data_found then
        l_json_out := '{}';
    end;

    return nvl(l_json_out, '{}');
  end build_context_projection_json;

  procedure prefetch_selected_contexts(
    p_run_id          in number,
    p_change_event_id in number,
    p_tenant_id       in varchar2,
    p_context_id      in varchar2,
    p_params_json     in clob default null
  ) is
    l_source_values_json clob;
    l_augmented_json     clob;
    l_source_key_json    clob;
    l_old_key_json       clob;
    l_new_key_json       clob;
    l_source_key_hash    varchar2(128);
  begin
    select evt.source_key_json,
           evt.source_key_hash,
           evt.old_key_json,
           evt.new_key_json
      into l_source_key_json,
           l_source_key_hash,
           l_old_key_json,
           l_new_key_json
      from md_change_event evt
     where evt.change_event_id = p_change_event_id
       and evt.tenant_id = p_tenant_id
       and evt.context_id = p_context_id;

    for rec in (
      select s.rule_id,
             rsc.source_context_id
        from md_run_selected_rule s
        join md_rule_source_context rsc
          on rsc.rule_id = s.rule_id
         and rsc.tenant_id = s.tenant_id
         and rsc.context_id = s.context_id
         and rsc.active_flag = 'Y'
       where s.run_id = p_run_id
         and s.change_event_id = p_change_event_id
         and s.tenant_id = p_tenant_id
         and s.context_id = p_context_id
       group by s.rule_id, rsc.source_context_id
    ) loop
      l_source_values_json := resolve_rule_source_values(
        p_run_id          => p_run_id,
        p_change_event_id => p_change_event_id,
        p_rule_id         => rec.rule_id,
        p_tenant_id       => p_tenant_id,
        p_context_id      => p_context_id,
        p_params_json     => p_params_json
      );

      begin
        l_augmented_json := build_context_projection_json(
          p_run_id            => p_run_id,
          p_change_event_id   => p_change_event_id,
          p_source_context_id => rec.source_context_id,
          p_rule_id           => rec.rule_id,
          p_tenant_id         => p_tenant_id,
          p_context_id        => p_context_id,
          p_source_key_json   => l_source_key_json,
          p_old_key_json      => l_old_key_json,
          p_new_key_json      => l_new_key_json,
          p_params_json       => p_params_json
        );

        l_source_values_json := merge_json_objects(l_source_values_json, l_augmented_json);
      exception
        when others then
          null;
      end;

      upsert_source_snapshot(
        p_run_id             => p_run_id,
        p_change_event_id    => p_change_event_id,
        p_rule_id            => rec.rule_id,
        p_source_context_id  => rec.source_context_id,
        p_tenant_id          => p_tenant_id,
        p_context_id         => p_context_id,
        p_correlation_key    => l_source_key_hash,
        p_source_values_json => l_source_values_json
      );

      upsert_run_context_snapshot(
        p_run_id             => p_run_id,
        p_change_event_id    => p_change_event_id,
        p_source_context_id  => rec.source_context_id,
        p_tenant_id          => p_tenant_id,
        p_context_id         => p_context_id,
        p_source_values_json => l_source_values_json
      );
    end loop;
  end prefetch_selected_contexts;

  function get_prefetched_rule_source_values(
    p_run_id          in number,
    p_change_event_id in number,
    p_rule_id         in number,
    p_tenant_id       in varchar2,
    p_context_id      in varchar2,
    p_params_json     in clob default null
  ) return clob is
    l_source_context_id number;
    l_source_values_json clob;
    l_source_key_json    clob;
    l_old_key_json       clob;
    l_new_key_json       clob;
    l_augmented_json     clob;
  begin
    begin
      select source_values_json
        into l_source_values_json
        from md_run_source_snapshot
       where tenant_id = p_tenant_id
         and context_id = p_context_id
         and run_id = p_run_id
         and nvl(change_event_id, -1) = nvl(p_change_event_id, -1)
         and rule_id = p_rule_id;

      return l_source_values_json;
    exception
      when no_data_found then
        null;
    end;

    l_source_context_id := get_rule_source_context_id(
      p_rule_id    => p_rule_id,
      p_tenant_id  => p_tenant_id,
      p_context_id => p_context_id
    );

    if l_source_context_id is null then
      return resolve_rule_source_values(
        p_run_id          => p_run_id,
        p_change_event_id => p_change_event_id,
        p_rule_id         => p_rule_id,
        p_tenant_id       => p_tenant_id,
        p_context_id      => p_context_id,
        p_params_json     => p_params_json
      );
    end if;

    begin
      select source_values_json
        into l_source_values_json
        from md_run_context_snapshot
       where tenant_id = p_tenant_id
         and context_id = p_context_id
         and run_id = p_run_id
         and change_event_id = p_change_event_id
         and source_context_id = l_source_context_id;

      begin
        select evt.source_key_json,
               evt.old_key_json,
               evt.new_key_json
          into l_source_key_json,
               l_old_key_json,
               l_new_key_json
          from md_change_event evt
         where evt.change_event_id = p_change_event_id
           and evt.tenant_id = p_tenant_id
           and evt.context_id = p_context_id;

        l_augmented_json := build_context_projection_json(
          p_run_id            => p_run_id,
          p_change_event_id   => p_change_event_id,
          p_source_context_id => l_source_context_id,
          p_rule_id           => p_rule_id,
          p_tenant_id         => p_tenant_id,
          p_context_id        => p_context_id,
          p_source_key_json   => l_source_key_json,
          p_old_key_json      => l_old_key_json,
          p_new_key_json      => l_new_key_json,
          p_params_json       => p_params_json
        );

        l_source_values_json := merge_json_objects(l_source_values_json, l_augmented_json);
      exception
        when others then
          null;
      end;

      upsert_source_snapshot(
        p_run_id             => p_run_id,
        p_change_event_id    => p_change_event_id,
        p_rule_id            => p_rule_id,
        p_source_context_id  => l_source_context_id,
        p_tenant_id          => p_tenant_id,
        p_context_id         => p_context_id,
        p_correlation_key    => null,
        p_source_values_json => l_source_values_json
      );

      return l_source_values_json;
    exception
      when no_data_found then
        l_source_values_json := resolve_rule_source_values(
          p_run_id          => p_run_id,
          p_change_event_id => p_change_event_id,
          p_rule_id         => p_rule_id,
          p_tenant_id       => p_tenant_id,
          p_context_id      => p_context_id,
          p_params_json     => p_params_json
        );

        upsert_run_context_snapshot(
          p_run_id             => p_run_id,
          p_change_event_id    => p_change_event_id,
          p_source_context_id  => l_source_context_id,
          p_tenant_id          => p_tenant_id,
          p_context_id         => p_context_id,
          p_source_values_json => l_source_values_json
        );

        begin
          select evt.source_key_json,
                 evt.old_key_json,
                 evt.new_key_json
            into l_source_key_json,
                 l_old_key_json,
                 l_new_key_json
            from md_change_event evt
           where evt.change_event_id = p_change_event_id
             and evt.tenant_id = p_tenant_id
             and evt.context_id = p_context_id;

          l_augmented_json := build_context_projection_json(
            p_run_id            => p_run_id,
            p_change_event_id   => p_change_event_id,
            p_source_context_id => l_source_context_id,
            p_rule_id           => p_rule_id,
            p_tenant_id         => p_tenant_id,
            p_context_id        => p_context_id,
            p_source_key_json   => l_source_key_json,
            p_old_key_json      => l_old_key_json,
            p_new_key_json      => l_new_key_json,
            p_params_json       => p_params_json
          );

          l_source_values_json := merge_json_objects(l_source_values_json, l_augmented_json);
        exception
          when others then
            null;
        end;

        upsert_source_snapshot(
          p_run_id             => p_run_id,
          p_change_event_id    => p_change_event_id,
          p_rule_id            => p_rule_id,
          p_source_context_id  => l_source_context_id,
          p_tenant_id          => p_tenant_id,
          p_context_id         => p_context_id,
          p_correlation_key    => null,
          p_source_values_json => l_source_values_json
        );

        return l_source_values_json;
    end;
  end get_prefetched_rule_source_values;

end md_source_context_resolver_pkg;
/

show errors package body md_source_context_resolver_pkg;
