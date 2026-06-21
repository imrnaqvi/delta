create or replace package body md_rule_executor_pkg as

  g_debug boolean := false;

  -- ===== PRIVATE PROCEDURES =====

  procedure log_debug(p_message in varchar2) is
  begin
    if g_debug then
      dbms_output.put_line('[DEBUG] ' || p_message);
    end if;
  end log_debug;

  procedure log_error(p_message in varchar2) is
  begin
    dbms_output.put_line('[ERROR] ' || p_message);
  end log_error;

  function enquote_value(p_value in varchar2) return varchar2 is
  begin
    if p_value is null then
      return 'null';
    end if;

    return '''' || replace(p_value, '''', '''''') || '''';
  end enquote_value;

  function substitute_tokens(
    p_expr          in varchar2,
    p_source_values in clob,
    p_params_json   in clob default null
  ) return varchar2 is
    l_result varchar2(4000) := p_expr;

    procedure replace_object(
      p_obj      in json_object_t,
      p_prefix   in varchar2,
      p_is_param in boolean
    ) is
      l_keys  json_key_list;
      l_key   varchar2(4000);
      l_elem  json_element_t;
      l_child json_object_t;
      l_token varchar2(4000);
      l_value varchar2(4000);
    begin
      l_keys := p_obj.get_keys;

      for i in 1 .. l_keys.count loop
        l_key := l_keys(i);
        l_elem := p_obj.get(l_key);

        if p_prefix is null then
          l_token := l_key;
        else
          l_token := p_prefix || '.' || l_key;
        end if;

        if l_elem is not null and l_elem.is_object then
          l_child := json_object_t.parse(l_elem.to_string);
          replace_object(l_child, l_token, p_is_param);
        else
          if l_elem is null or l_elem.is_null then
            l_value := 'null';
          elsif l_elem.is_string then
            l_value := enquote_value(p_obj.get_string(l_key));
          elsif l_elem.is_number then
            l_value := to_char(p_obj.get_number(l_key));
          elsif l_elem.is_boolean then
            if p_obj.get_boolean(l_key) then
              l_value := '''Y''';
            else
              l_value := '''N''';
            end if;
          else
            l_value := enquote_value(l_elem.to_string);
          end if;

          if p_is_param then
            l_result := replace(l_result, 'PARAM.' || l_token, l_value);
          else
            if p_prefix is null then
              l_result := replace(l_result, 'SRC.' || l_key, l_value);
            end if;

            l_result := replace(l_result, l_token, l_value);
          end if;
        end if;
      end loop;
    end replace_object;
  begin
    if p_source_values is not null then
      replace_object(json_object_t.parse(p_source_values), null, false);
    end if;

    if p_params_json is not null then
      replace_object(json_object_t.parse(p_params_json), null, true);
    end if;

    return l_result;
  exception
    when others then
      return p_expr;
  end substitute_tokens;

  function substitute_change_delta_tokens(
    p_expr            in varchar2,
    p_change_event_id in number,
    p_tenant_id       in varchar2,
    p_context_id      in varchar2
  ) return varchar2 is
    l_result varchar2(4000) := p_expr;
    l_old_value varchar2(4000);
    l_new_value varchar2(4000);
  begin
    for rec in (
      select source_column_name, old_value_txt, new_value_txt
        from md_change_event_column_delta
       where change_event_id = p_change_event_id
         and tenant_id = p_tenant_id
         and context_id = p_context_id
    ) loop
      l_old_value := case when rec.old_value_txt is null then 'null' else enquote_value(rec.old_value_txt) end;
      l_new_value := case when rec.new_value_txt is null then 'null' else enquote_value(rec.new_value_txt) end;

      l_result := replace(l_result, 'OLD.' || rec.source_column_name, l_old_value);
      l_result := replace(l_result, 'NEW.' || rec.source_column_name, l_new_value);
      l_result := replace(l_result, 'old.' || rec.source_column_name, l_old_value);
      l_result := replace(l_result, 'new.' || rec.source_column_name, l_new_value);
    end loop;

    return l_result;
  exception
    when others then
      return p_expr;
  end substitute_change_delta_tokens;

  procedure evaluate_selection_gate(
    p_rule_id          in number,
    p_change_event_id  in number,
    p_tenant_id        in varchar2,
    p_context_id       in varchar2,
    p_source_values    in clob,
    p_params_json      in clob,
    o_gate_status      out varchar2,
    o_gate_message     out varchar2
  ) is
    l_gate_expr         clob;
    l_gate_enabled_flag varchar2(1);
    l_eval_expr         varchar2(4000);
    l_gate_result       number;
  begin
    select selection_gate_expr, nvl(selection_gate_enabled_flag, 'Y')
      into l_gate_expr, l_gate_enabled_flag
      from md_rule
     where rule_id = p_rule_id
       and tenant_id = p_tenant_id
       and context_id = p_context_id;

    if l_gate_enabled_flag = 'N' or l_gate_expr is null then
      o_gate_status := 'PASSED';
      o_gate_message := null;
      return;
    end if;

    l_eval_expr := substr(l_gate_expr, 1, 4000);
    l_eval_expr := substitute_change_delta_tokens(l_eval_expr, p_change_event_id, p_tenant_id, p_context_id);
    l_eval_expr := substitute_tokens(l_eval_expr, p_source_values, p_params_json);

    execute immediate 'select case when (' || l_eval_expr || ') then 1 else 0 end from dual'
      into l_gate_result;

    if l_gate_result = 1 then
      o_gate_status := 'PASSED';
      o_gate_message := null;
    else
      o_gate_status := 'FILTERED';
      o_gate_message := 'Gate expression evaluated FALSE';
    end if;
  exception
    when others then
      o_gate_status := 'ERROR';
      o_gate_message := substr('Gate evaluation failed: ' || sqlerrm, 1, 4000);
  end evaluate_selection_gate;

  function get_rule_output_value(
    p_rule_output_values_json in clob,
    p_output_key              in varchar2
  ) return varchar2 is
    l_obj  json_object_t;
    l_elem json_element_t;
  begin
    if p_rule_output_values_json is null or p_output_key is null then
      return null;
    end if;

    l_obj := json_object_t.parse(p_rule_output_values_json);
    l_elem := l_obj.get(p_output_key);

    if l_elem is null or l_elem.is_null then
      return null;
    elsif l_elem.is_string then
      return l_obj.get_string(p_output_key);
    elsif l_elem.is_number then
      return to_char(l_obj.get_number(p_output_key));
    elsif l_elem.is_boolean then
      if l_obj.get_boolean(p_output_key) then
        return 'Y';
      else
        return 'N';
      end if;
    else
      return l_elem.to_string;
    end if;
  exception
    when others then
      return null;
  end get_rule_output_value;

  function get_effective_rule_priority(
    p_rule_id     in number,
    p_tenant_id   in varchar2,
    p_context_id  in varchar2
  ) return number is
    l_priority number;
  begin
    select nvl(rule_priority_no, 0)
      into l_priority
      from md_rule
     where rule_id = p_rule_id
       and tenant_id = p_tenant_id
       and context_id = p_context_id;

    return nvl(l_priority, 0);
  exception
    when others then
      return 0;
  end get_effective_rule_priority;

  function get_json_key_value(
    p_json in clob,
    p_key  in varchar2
  ) return varchar2 is
    l_obj  json_object_t;
    l_elem json_element_t;
  begin
    if p_json is null or p_key is null then
      return null;
    end if;

    l_obj := json_object_t.parse(p_json);
    l_elem := l_obj.get(p_key);

    if l_elem is null or l_elem.is_null then
      return null;
    elsif l_elem.is_string then
      return l_obj.get_string(p_key);
    elsif l_elem.is_number then
      return to_char(l_obj.get_number(p_key));
    elsif l_elem.is_boolean then
      if l_obj.get_boolean(p_key) then
        return 'Y';
      else
        return 'N';
      end if;
    else
      return l_elem.to_string;
    end if;
  exception
    when others then
      return null;
  end get_json_key_value;

  function resolve_mapped_value(
    p_source_kind    in varchar2,
    p_source_expr    in clob,
    p_computed_value in computed_value_rec,
    p_source_values  in clob,
    p_params_json    in clob,
    p_rule_output_values_json in clob default null,
    p_default_output_column   in varchar2 default null
  ) return varchar2 is
    l_expr varchar2(4000);
    l_sql  varchar2(4000);
    l_txt  varchar2(4000);
    l_output_key varchar2(4000);
  begin
    case upper(p_source_kind)
      when 'COMPUTED_VALUE_JSON' then
        if p_computed_value.computed_value_json is not null then
          return dbms_lob.substr(p_computed_value.computed_value_json, 4000, 1);
        end if;
        l_txt := get_rule_output_value(p_rule_output_values_json, p_default_output_column);
        if l_txt is not null then
          return l_txt;
        end if;
        return p_computed_value.computed_value_txt;
      when 'COMPUTED_VALUE_TXT' then
        l_txt := get_rule_output_value(p_rule_output_values_json, p_default_output_column);
        if l_txt is not null then
          return l_txt;
        end if;
        return p_computed_value.computed_value_txt;
      when 'SOURCE_ALIAS' then
        return substitute_tokens(substr(p_source_expr, 1, 4000), p_source_values, null);
      when 'PARAM' then
        l_expr := substr(p_source_expr, 1, 4000);
        if instr(upper(l_expr), 'PARAM.') <> 1 then
          l_expr := 'PARAM.' || l_expr;
        end if;
        return substitute_tokens(l_expr, null, p_params_json);
      when 'EXPR' then
        l_sql := substitute_tokens(substr(p_source_expr, 1, 4000), p_source_values, p_params_json);
        execute immediate 'select ' || l_sql || ' from dual' into l_txt;
        return l_txt;
      when 'LITERAL' then
        return substr(p_source_expr, 1, 4000);
      when 'RULE_OUTPUT' then
        l_output_key := trim(substr(p_source_expr, 1, 4000));
        if l_output_key is null then
          l_output_key := p_default_output_column;
        end if;
        l_txt := get_rule_output_value(p_rule_output_values_json, l_output_key);
        if l_txt is not null then
          return l_txt;
        end if;
        return p_computed_value.computed_value_txt;
      else
        return p_computed_value.computed_value_txt;
    end case;
  exception
    when others then
      return null;
  end resolve_mapped_value;

  function normalize_target_value(p_value in varchar2) return varchar2 is
  begin
    if p_value is null then
      return null;
    end if;

    if length(p_value) >= 2 and substr(p_value, 1, 1) = '''' and substr(p_value, -1, 1) = '''' then
      return replace(substr(p_value, 2, length(p_value) - 2), '''''', '''');
    end if;

    return p_value;
  end normalize_target_value;

  function json_quote(p_value in varchar2) return varchar2 is
  begin
    return '"' || replace(replace(nvl(p_value, ''), '\', '\\'), '"', '\"') || '"';
  end json_quote;

  function generate_target_action_fingerprint(
    p_run_id            in number,
    p_rule_id           in number,
    p_action_type       in varchar2,
    p_target_column_name in varchar2,
    p_target_key_hash   in varchar2,
    p_value             in varchar2
  ) return varchar2 is
    l_hash_value number;
  begin
    l_hash_value := dbms_utility.get_hash_value(
      to_char(p_run_id) || '|' ||
      to_char(p_rule_id) || '|' ||
      p_action_type || '|' ||
      nvl(p_target_column_name, '') || '|' ||
      nvl(p_target_key_hash, '') || '|' ||
      nvl(p_value, ''),
      0,
      2147483647
    );

    return to_char(l_hash_value);
  end generate_target_action_fingerprint;

  procedure log_output_eval_failure_trace(
    p_run_id             in number,
    p_change_event_id    in number,
    p_rule_id            in number,
    p_target_column_name in varchar2,
    p_output_expr        in varchar2,
    p_failure_reason     in varchar2,
    p_tenant_id          in varchar2,
    p_context_id         in varchar2
  ) is
    l_key_json      clob;
    l_action_json   clob;
    l_bind_json     clob;
    l_key_hash      varchar2(128);
    l_fingerprint   varchar2(200);
    l_token         varchar2(4000);
  begin
    l_key_json := '{'
      || json_quote('ruleId') || ':' || json_quote(to_char(p_rule_id)) || ','
      || json_quote('targetColumn') || ':' || json_quote(nvl(p_target_column_name, 'UNKNOWN'))
      || '}';

    l_action_json := '{'
      || json_quote('traceType') || ':' || json_quote('OUTPUT_EVAL_FAILURE') || ','
      || json_quote('outputExpr') || ':' || json_quote(substr(nvl(p_output_expr, ''), 1, 3900)) || ','
      || json_quote('failureReason') || ':' || json_quote(substr(nvl(p_failure_reason, ''), 1, 3900))
      || '}';

    l_bind_json := '{'
      || json_quote('tenantId') || ':' || json_quote(p_tenant_id) || ','
      || json_quote('contextId') || ':' || json_quote(p_context_id)
      || '}';

    l_token := to_char(systimestamp, 'YYYYMMDDHH24MISSFF6');
    l_key_hash := to_char(dbms_utility.get_hash_value(
      to_char(p_run_id) || '|' || to_char(p_rule_id) || '|' || nvl(p_target_column_name, '') || '|' || l_token,
      0,
      2147483647
    ));

    l_fingerprint := generate_target_action_fingerprint(
      p_run_id,
      p_rule_id,
      'UPDATE',
      nvl(p_target_column_name, 'UNKNOWN'),
      l_key_hash,
      substr(nvl(p_failure_reason, ''), 1, 4000)
    ) || ':' || l_token;

    insert into md_run_target_action (
      run_target_action_id, tenant_id, context_id, run_id, change_event_id, rule_id, target_object_id,
      target_system_name, target_entity_name, target_key_json, target_key_hash, target_column_name,
      action_type, action_payload_json, generated_sql_text, bind_payload_json, execution_status,
      rows_affected, error_code, error_message, applied_flag, applied_at, action_fingerprint
    ) values (
      md_run_target_action_seq.nextval, p_tenant_id, p_context_id, p_run_id, p_change_event_id, p_rule_id,
      null, 'TRACE', 'RULE_OUTPUT_EVAL', l_key_json, l_key_hash, p_target_column_name,
      'UPDATE', l_action_json, p_output_expr, l_bind_json, 'FAILED',
      0, -20090, substr(nvl(p_failure_reason, 'Unknown output evaluation failure'), 1, 4000),
      'N', null, l_fingerprint
    );
  exception
    when others then
      log_error('Failed to write output-eval trace: ' || sqlerrm);
  end log_output_eval_failure_trace;

  procedure apply_target_actions(
    p_run_id          in number,
    p_rule_id         in number,
    p_tenant_id       in varchar2,
    p_context_id      in varchar2,
    p_change_event_id in number,
    p_source_values   in clob,
    p_params_json     in clob,
    p_computed_value  in computed_value_rec,
    p_rule_output_values_json in clob,
    o_executed_count  out number,
    o_failed_count    out number,
    o_skipped_count   out number
  ) is
    l_key_json        clob;
    l_action_json     clob;
    l_bind_json       clob;
    l_key_hash        varchar2(128);
    l_sql             clob;
    l_target_value    varchar2(4000);
    l_rows_affected   number;
    l_status          varchar2(20);
    l_error_message   varchar2(4000);
    l_error_code      number;
    l_fingerprint     varchar2(200);
    l_insert_columns  clob;
    l_insert_values   clob;
    l_where_clause    clob;
    l_key_value       varchar2(4000);
    l_action_id       number;
    l_action_type     varchar2(20);
    l_target_object_id number;
    l_target_column_id number;
    l_missing_row_policy varchar2(20);
    l_schema_name     varchar2(128);
    l_object_name     varchar2(128);
    l_column_name     varchar2(128);

    cursor c_actions is
      select rta.rule_target_action_id,
             rta.action_type,
             rta.target_object_id,
             rta.target_column_id,
             rta.missing_row_policy,
             o.system_name,
             o.schema_name,
             o.object_name,
             c.column_name
        from md_rule_target_action rta
        join md_object o
          on o.object_id = rta.target_object_id
         and o.tenant_id = rta.tenant_id
         and o.context_id = rta.context_id
        left join md_column c
          on c.column_id = rta.target_column_id
         and c.tenant_id = rta.tenant_id
         and c.context_id = rta.context_id
       where rta.rule_id = p_rule_id
         and rta.tenant_id = p_tenant_id
           and rta.context_id = p_context_id
       order by rta.rule_target_action_id;

    cursor c_key_maps(p_rule_target_action_id number) is
      select kcm.source_kind,
             kcm.source_expr,
             kc.ordinal_position,
             c.column_name
        from md_rule_target_key_map kcm
        join md_key_component kc
          on kc.key_component_id = kcm.target_key_component_id
        join md_column c
          on c.column_id = kc.column_id
         and c.tenant_id = kcm.tenant_id
         and c.context_id = kcm.context_id
       where kcm.rule_target_action_id = p_rule_target_action_id
         and kcm.tenant_id = p_tenant_id
         and kcm.context_id = p_context_id
       order by kc.ordinal_position;

    cursor c_column_maps(p_rule_target_action_id number) is
      select value_source_kind, value_expr, target_column_id, c.column_name
        from md_rule_target_column_map tcm
        join md_column c
          on c.column_id = tcm.target_column_id
         and c.tenant_id = tcm.tenant_id
         and c.context_id = tcm.context_id
       where tcm.rule_target_action_id = p_rule_target_action_id
         and tcm.tenant_id = p_tenant_id
         and tcm.context_id = p_context_id;
  begin
    o_executed_count := 0;
    o_failed_count := 0;
    o_skipped_count := 0;

    for act_rec in c_actions loop
      begin
        l_action_id := act_rec.rule_target_action_id;
        l_action_type := act_rec.action_type;
        l_target_object_id := act_rec.target_object_id;
        l_target_column_id := act_rec.target_column_id;
        l_missing_row_policy := act_rec.missing_row_policy;
        l_schema_name := act_rec.schema_name;
        l_object_name := act_rec.object_name;
        l_column_name := act_rec.column_name;

        l_key_json := '{';
        l_action_json := null;
        l_bind_json := null;
        l_key_hash := null;
        l_sql := null;
        l_insert_columns := null;
        l_insert_values := null;
        l_where_clause := null;
        l_status := null;
        l_error_message := null;
        l_error_code := null;
        l_rows_affected := null;

        for key_rec in c_key_maps(l_action_id) loop
          l_key_value := resolve_mapped_value(
            key_rec.source_kind,
            key_rec.source_expr,
            p_computed_value,
            p_source_values,
            p_params_json,
            p_rule_output_values_json,
            null
          );
          l_key_value := normalize_target_value(l_key_value);

          if l_key_json <> '{' then
            l_key_json := l_key_json || ',';
          end if;

          l_key_json := l_key_json || json_quote(key_rec.column_name) || ':' || json_quote(l_key_value);
          l_key_hash := case when l_key_hash is null then l_key_value else l_key_hash || ':' || l_key_value end;
        end loop;

        if l_key_json = '{' then
          raise_application_error(-20010, 'No target key mapping for rule_target_action_id=' || l_action_id);
        end if;

        l_key_json := l_key_json || '}';

        for col_rec in c_column_maps(l_action_id) loop
          l_target_value := resolve_mapped_value(
            col_rec.value_source_kind,
            col_rec.value_expr,
            p_computed_value,
            p_source_values,
            p_params_json,
            p_rule_output_values_json,
            col_rec.column_name
          );
          l_target_value := normalize_target_value(l_target_value);

          l_fingerprint := generate_target_action_fingerprint(
            p_run_id,
            p_rule_id,
            l_action_type,
            col_rec.column_name,
            l_key_hash,
            l_target_value
          );

          l_action_json := '{'
            || json_quote('targetColumn') || ':' || json_quote(col_rec.column_name) || ','
            || json_quote('targetValue') || ':' || json_quote(l_target_value) || ','
            || json_quote('actionType') || ':' || json_quote(l_action_type)
            || '}';

          l_bind_json := '{'
            || json_quote('targetKey') || ':' || l_key_json || ','
            || json_quote('targetValue') || ':' || json_quote(l_target_value) || ','
            || json_quote('actionType') || ':' || json_quote(l_action_type)
            || '}';

          l_insert_columns := null;
          l_insert_values := null;

          for key_rec in c_key_maps(l_action_id) loop
            if l_insert_columns is null then
              l_insert_columns := key_rec.column_name;
              l_insert_values := enquote_value(normalize_target_value(resolve_mapped_value(
                key_rec.source_kind,
                key_rec.source_expr,
                p_computed_value,
                p_source_values,
                p_params_json,
                p_rule_output_values_json,
                null
              )));
            else
              l_insert_columns := l_insert_columns || ', ' || key_rec.column_name;
              l_insert_values := l_insert_values || ', ' || enquote_value(normalize_target_value(resolve_mapped_value(
                key_rec.source_kind,
                key_rec.source_expr,
                p_computed_value,
                p_source_values,
                p_params_json,
                p_rule_output_values_json,
                null
              )));
            end if;
          end loop;

          if l_insert_columns is null then
            raise_application_error(-20012, 'Unable to build insert column list for rule_target_action_id=' || l_action_id);
          end if;

          l_insert_columns := l_insert_columns || ', ' || col_rec.column_name;
          l_insert_values := l_insert_values || ', ' || enquote_value(l_target_value);

          if upper(l_action_type) in ('UPDATE','INSERT') then
            if upper(l_action_type) = 'UPDATE' then
              l_sql := 'update ' || l_schema_name || '.' || l_object_name || ' set ' || col_rec.column_name || ' = ' || enquote_value(l_target_value) || ' where ';

              declare
                l_first boolean := true;
              begin
                for key_rec in c_key_maps(l_action_id) loop
                  if not l_first then
                    l_sql := l_sql || ' and ';
                  end if;
                  l_key_value := resolve_mapped_value(
                    key_rec.source_kind,
                    key_rec.source_expr,
                    p_computed_value,
                    p_source_values,
                    p_params_json,
                    p_rule_output_values_json,
                    null
                  );
                  l_key_value := normalize_target_value(l_key_value);
                  l_sql := l_sql || key_rec.column_name || ' = ' || enquote_value(l_key_value);
                  l_where_clause := case when l_where_clause is null then key_rec.column_name || '=' || nvl(l_key_value, 'null') else l_where_clause || ';' || key_rec.column_name || '=' || nvl(l_key_value, 'null') end;
                  l_first := false;
                end loop;
              end;

              execute immediate l_sql;
              l_rows_affected := sql%rowcount;

              if l_rows_affected = 0 and upper(l_missing_row_policy) = 'INSERT' then
                l_sql := 'insert into ' || l_schema_name || '.' || l_object_name || ' (' || l_insert_columns || ') values (' || l_insert_values || ')';
                execute immediate l_sql;
                l_rows_affected := sql%rowcount;
              elsif l_rows_affected = 0 and upper(l_missing_row_policy) = 'SKIP' then
                o_skipped_count := o_skipped_count + 1;
                l_status := 'SKIPPED';
              elsif l_rows_affected = 0 then
                raise_application_error(-20011, 'Target row not found for update: ' || l_schema_name || '.' || l_object_name);
              end if;
            else
              l_sql := 'insert into ' || l_schema_name || '.' || l_object_name || ' (' || l_insert_columns || ') values (' || l_insert_values || ')';
              execute immediate l_sql;
              l_rows_affected := sql%rowcount;
            end if;

            if l_status is null then
              l_status := 'EXECUTED';
              o_executed_count := o_executed_count + 1;
            end if;
          else
            l_status := 'SKIPPED';
            l_rows_affected := 0;
            l_error_message := 'Target action type not executed by this path: ' || l_action_type;
            o_skipped_count := o_skipped_count + 1;
          end if;

          insert into md_run_target_action (
            run_target_action_id, tenant_id, context_id, run_id, change_event_id, rule_id, target_object_id,
            target_system_name, target_entity_name, target_key_json, target_key_hash, target_column_name,
            action_type, action_payload_json, generated_sql_text, bind_payload_json, execution_status,
            rows_affected, error_code, error_message, applied_flag, applied_at, action_fingerprint
          ) values (
            md_run_target_action_seq.nextval, p_tenant_id, p_context_id, p_run_id, p_change_event_id, p_rule_id,
            l_target_object_id, act_rec.system_name, l_object_name, l_key_json, l_key_hash,
            col_rec.column_name, l_action_type, l_action_json, l_sql, l_bind_json, l_status,
            l_rows_affected, l_error_code, l_error_message,
            case when l_status = 'EXECUTED' then 'Y' else 'N' end,
            case when l_status = 'EXECUTED' then systimestamp else null end,
            l_fingerprint
          );
        end loop;
      exception
        when others then
          o_failed_count := o_failed_count + 1;
          log_error('Target action failed: rule_id=' || p_rule_id || ', error=' || sqlerrm);
      end;
    end loop;
  end apply_target_actions;

  procedure upsert_target_consolidation(
    p_run_id                   in number,
    p_change_event_id          in number,
    p_tenant_id                in varchar2,
    p_context_id               in varchar2,
    p_target_entity_name       in varchar2,
    p_target_key_json          in clob,
    p_target_key_hash          in varchar2,
    p_mark_partial             in varchar2 default 'N',
    o_run_target_cons_id       out number
  ) is
  begin
    begin
      select run_target_consolidation_id
        into o_run_target_cons_id
        from md_run_target_consolidation
       where tenant_id = p_tenant_id
         and context_id = p_context_id
         and run_id = p_run_id
         and change_event_id = p_change_event_id
         and target_entity_name = p_target_entity_name
         and target_key_hash = p_target_key_hash;
    exception
      when no_data_found then
        insert into md_run_target_consolidation (
          run_target_consolidation_id,
          tenant_id,
          context_id,
          run_id,
          change_event_id,
          target_entity_name,
          target_key_json,
          target_key_hash,
          consolidation_status,
          winning_value_count,
          source_rule_count,
          created_at,
          updated_at
        ) values (
          md_run_target_cons_seq.nextval,
          p_tenant_id,
          p_context_id,
          p_run_id,
          p_change_event_id,
          p_target_entity_name,
          p_target_key_json,
          p_target_key_hash,
          case when p_mark_partial = 'Y' then 'PARTIAL' else 'READY' end,
          0,
          0,
          systimestamp,
          systimestamp
        ) returning run_target_consolidation_id into o_run_target_cons_id;
    end;

    if p_mark_partial = 'Y' then
      update md_run_target_consolidation
         set consolidation_status = 'PARTIAL',
             updated_at = systimestamp
       where run_target_consolidation_id = o_run_target_cons_id;
    end if;
  end upsert_target_consolidation;

  procedure upsert_consolidated_winner(
    p_run_target_cons_id       in number,
    p_run_id                   in number,
    p_change_event_id          in number,
    p_tenant_id                in varchar2,
    p_context_id               in varchar2,
    p_target_entity_name       in varchar2,
    p_target_key_hash          in varchar2,
    p_target_column_name       in varchar2,
    p_computed_value_txt       in varchar2,
    p_computed_value_json      in clob,
    p_value_data_type          in varchar2,
    p_winner_rule_id           in number,
    p_winner_priority_no       in number
  ) is
    l_existing_id              number;
    l_existing_rule_id         number;
    l_existing_priority_no     number;
    l_replace                  boolean := false;
    l_value_fingerprint        varchar2(128);
    l_win_count                number;
  begin
    l_value_fingerprint := generate_target_action_fingerprint(
      p_run_id,
      p_winner_rule_id,
      'CONSOLIDATED',
      p_target_column_name,
      p_target_key_hash,
      p_computed_value_txt
    );

    begin
      select run_target_consolidated_value_id,
             winner_rule_id,
             winner_priority_no
        into l_existing_id,
             l_existing_rule_id,
             l_existing_priority_no
        from md_run_target_consolidated_value
       where tenant_id = p_tenant_id
         and context_id = p_context_id
         and run_id = p_run_id
         and change_event_id = p_change_event_id
         and target_entity_name = p_target_entity_name
         and target_key_hash = p_target_key_hash
         and target_column_name = p_target_column_name;

      if p_winner_priority_no > nvl(l_existing_priority_no, 0)
         or (p_winner_priority_no = nvl(l_existing_priority_no, 0) and p_winner_rule_id > nvl(l_existing_rule_id, 0)) then
        l_replace := true;
      end if;

      if l_replace then
        update md_run_target_consolidated_value
           set run_target_consolidation_id = p_run_target_cons_id,
               computed_value_txt = p_computed_value_txt,
               computed_value_json = p_computed_value_json,
               value_data_type = p_value_data_type,
               winner_rule_id = p_winner_rule_id,
               winner_priority_no = p_winner_priority_no,
               value_fingerprint = l_value_fingerprint,
               updated_at = systimestamp
         where run_target_consolidated_value_id = l_existing_id;
      end if;
    exception
      when no_data_found then
        insert into md_run_target_consolidated_value (
          run_target_consolidated_value_id,
          run_target_consolidation_id,
          tenant_id,
          context_id,
          run_id,
          change_event_id,
          target_entity_name,
          target_key_hash,
          target_column_name,
          computed_value_txt,
          computed_value_json,
          value_data_type,
          winner_rule_id,
          winner_priority_no,
          value_fingerprint,
          created_at,
          updated_at
        ) values (
          md_run_target_cons_val_seq.nextval,
          p_run_target_cons_id,
          p_tenant_id,
          p_context_id,
          p_run_id,
          p_change_event_id,
          p_target_entity_name,
          p_target_key_hash,
          p_target_column_name,
          p_computed_value_txt,
          p_computed_value_json,
          p_value_data_type,
          p_winner_rule_id,
          p_winner_priority_no,
          l_value_fingerprint,
          systimestamp,
          systimestamp
        );
    end;

    select count(*)
      into l_win_count
      from md_run_target_consolidated_value
     where run_target_consolidation_id = p_run_target_cons_id;

    update md_run_target_consolidation
       set winning_value_count = l_win_count,
           source_rule_count = nvl(source_rule_count, 0) + 1,
           updated_at = systimestamp
     where run_target_consolidation_id = p_run_target_cons_id;
  end upsert_consolidated_winner;

  procedure consolidate_rule_actions(
    p_run_id                  in number,
    p_rule_id                 in number,
    p_tenant_id               in varchar2,
    p_context_id              in varchar2,
    p_change_event_id         in number,
    p_source_values           in clob,
    p_params_json             in clob,
    p_computed_value          in computed_value_rec,
    p_rule_output_values_json in clob,
    o_consolidated_count      out number,
    o_failed_count            out number,
    o_skipped_count           out number
  ) is
    l_key_json              clob;
    l_key_hash              varchar2(128);
    l_key_value             varchar2(4000);
    l_target_value          varchar2(4000);
    l_cons_id               number;
    l_rule_priority         number;

    cursor c_actions is
      select rta.rule_target_action_id,
             rta.action_type,
             rta.target_object_id,
             rta.missing_row_policy,
             o.object_name
        from md_rule_target_action rta
        join md_object o
          on o.object_id = rta.target_object_id
         and o.tenant_id = rta.tenant_id
         and o.context_id = rta.context_id
       where rta.rule_id = p_rule_id
         and rta.tenant_id = p_tenant_id
         and rta.context_id = p_context_id
       order by rta.rule_target_action_id;

    cursor c_key_maps(p_rule_target_action_id number) is
      select kcm.source_kind,
             kcm.source_expr,
             kc.ordinal_position,
             c.column_name
        from md_rule_target_key_map kcm
        join md_key_component kc
          on kc.key_component_id = kcm.target_key_component_id
        join md_column c
          on c.column_id = kc.column_id
         and c.tenant_id = kcm.tenant_id
         and c.context_id = kcm.context_id
       where kcm.rule_target_action_id = p_rule_target_action_id
         and kcm.tenant_id = p_tenant_id
         and kcm.context_id = p_context_id
       order by kc.ordinal_position;

    cursor c_column_maps(p_rule_target_action_id number) is
      select value_source_kind, value_expr, c.column_name
        from md_rule_target_column_map tcm
        join md_column c
          on c.column_id = tcm.target_column_id
         and c.tenant_id = tcm.tenant_id
         and c.context_id = tcm.context_id
       where tcm.rule_target_action_id = p_rule_target_action_id
         and tcm.tenant_id = p_tenant_id
         and tcm.context_id = p_context_id;
  begin
    o_consolidated_count := 0;
    o_failed_count := 0;
    o_skipped_count := 0;
    l_rule_priority := get_effective_rule_priority(p_rule_id, p_tenant_id, p_context_id);

    for act_rec in c_actions loop
      begin
        l_key_json := '{';
        l_key_hash := null;

        for key_rec in c_key_maps(act_rec.rule_target_action_id) loop
          l_key_value := resolve_mapped_value(
            key_rec.source_kind,
            key_rec.source_expr,
            p_computed_value,
            p_source_values,
            p_params_json,
            p_rule_output_values_json,
            null
          );
          l_key_value := normalize_target_value(l_key_value);

          if l_key_json <> '{' then
            l_key_json := l_key_json || ',';
          end if;

          l_key_json := l_key_json || json_quote(key_rec.column_name) || ':' || json_quote(l_key_value);
          l_key_hash := case when l_key_hash is null then l_key_value else l_key_hash || ':' || l_key_value end;
        end loop;

        if l_key_json = '{' then
          o_failed_count := o_failed_count + 1;
          continue;
        end if;

        l_key_json := l_key_json || '}';

        upsert_target_consolidation(
          p_run_id             => p_run_id,
          p_change_event_id    => p_change_event_id,
          p_tenant_id          => p_tenant_id,
          p_context_id         => p_context_id,
          p_target_entity_name => act_rec.object_name,
          p_target_key_json    => l_key_json,
          p_target_key_hash    => l_key_hash,
          p_mark_partial       => 'N',
          o_run_target_cons_id => l_cons_id
        );

        for col_rec in c_column_maps(act_rec.rule_target_action_id) loop
          l_target_value := resolve_mapped_value(
            col_rec.value_source_kind,
            col_rec.value_expr,
            p_computed_value,
            p_source_values,
            p_params_json,
            p_rule_output_values_json,
            col_rec.column_name
          );
          l_target_value := normalize_target_value(l_target_value);

          if l_target_value is null then
            o_failed_count := o_failed_count + 1;

            update md_run_target_consolidation
               set consolidation_status = 'PARTIAL',
                   source_rule_count = nvl(source_rule_count, 0) + 1,
                   updated_at = systimestamp
             where run_target_consolidation_id = l_cons_id;
          else
            upsert_consolidated_winner(
              p_run_target_cons_id   => l_cons_id,
              p_run_id               => p_run_id,
              p_change_event_id      => p_change_event_id,
              p_tenant_id            => p_tenant_id,
              p_context_id           => p_context_id,
              p_target_entity_name   => act_rec.object_name,
              p_target_key_hash      => l_key_hash,
              p_target_column_name   => col_rec.column_name,
              p_computed_value_txt   => l_target_value,
              p_computed_value_json  => p_computed_value.computed_value_json,
              p_value_data_type      => p_computed_value.value_data_type,
              p_winner_rule_id       => p_rule_id,
              p_winner_priority_no   => l_rule_priority
            );
            o_consolidated_count := o_consolidated_count + 1;
          end if;
        end loop;
      exception
        when others then
          o_failed_count := o_failed_count + 1;
          log_error('Consolidation failed: rule_id=' || p_rule_id || ', error=' || sqlerrm);
      end;
    end loop;
  end consolidate_rule_actions;

  procedure execute_consolidated_actions_for_run(
    p_run_id          in number,
    p_change_event_id in number,
    p_tenant_id       in varchar2,
    p_context_id      in varchar2,
    o_executed_count  out number,
    o_failed_count    out number,
    o_skipped_count   out number
  ) is
    l_action_id            number;
    l_action_type          varchar2(20);
    l_missing_row_policy   varchar2(20);
    l_system_name          varchar2(100);
    l_schema_name          varchar2(128);
    l_object_name          varchar2(128);
    l_sql                  clob;
    l_rows_affected        number;
    l_status               varchar2(20);
    l_error_code           number;
    l_error_message        varchar2(4000);
    l_key_value            varchar2(4000);
    l_where_clause         clob;
    l_insert_columns       clob;
    l_insert_values        clob;
    l_fingerprint          varchar2(200);
    l_bind_json            clob;
    l_action_json          clob;
    l_fail_fingerprint     varchar2(200);

    cursor c_values is
      select cv.run_target_consolidated_value_id,
             cv.run_target_consolidation_id,
             cv.target_entity_name,
             cv.target_key_hash,
             cv.target_column_name,
             cv.computed_value_txt,
             cv.winner_rule_id,
             c.target_key_json
        from md_run_target_consolidated_value cv
        join md_run_target_consolidation c
          on c.run_target_consolidation_id = cv.run_target_consolidation_id
       where cv.tenant_id = p_tenant_id
         and cv.context_id = p_context_id
         and cv.run_id = p_run_id
         and cv.change_event_id = p_change_event_id;

    cursor c_key_maps(p_rule_target_action_id number) is
      select kc.ordinal_position,
             col.column_name
        from md_rule_target_key_map km
        join md_key_component kc
          on kc.key_component_id = km.target_key_component_id
        join md_column col
          on col.column_id = kc.column_id
       where km.rule_target_action_id = p_rule_target_action_id
       order by kc.ordinal_position;
  begin
    o_executed_count := 0;
    o_failed_count := 0;
    o_skipped_count := 0;

    for rec in c_values loop
      begin
        begin
          select rta.rule_target_action_id,
                 rta.action_type,
                 rta.missing_row_policy,
                 o.system_name,
                 o.schema_name,
                 o.object_name
            into l_action_id,
                 l_action_type,
                 l_missing_row_policy,
                 l_system_name,
                 l_schema_name,
                 l_object_name
            from md_rule_target_action rta
            join md_object o
              on o.object_id = rta.target_object_id
             and o.tenant_id = rta.tenant_id
             and o.context_id = rta.context_id
           where rta.rule_id = rec.winner_rule_id
             and rta.tenant_id = p_tenant_id
             and rta.context_id = p_context_id
             and exists (
               select 1
                 from md_rule_target_column_map cm
                 join md_column c
                   on c.column_id = cm.target_column_id
                where cm.rule_target_action_id = rta.rule_target_action_id
                  and cm.tenant_id = p_tenant_id
                  and cm.context_id = p_context_id
                  and c.column_name = rec.target_column_name
             )
           order by rta.rule_target_action_id desc
           fetch first 1 row only;
        exception
          when no_data_found then
            o_skipped_count := o_skipped_count + 1;
            continue;
        end;

        l_where_clause := null;
        l_insert_columns := null;
        l_insert_values := null;

        for key_rec in c_key_maps(l_action_id) loop
          l_key_value := get_json_key_value(rec.target_key_json, key_rec.column_name);

          if l_where_clause is null then
            l_where_clause := key_rec.column_name || ' = ' || enquote_value(l_key_value);
            l_insert_columns := key_rec.column_name;
            l_insert_values := enquote_value(l_key_value);
          else
            l_where_clause := l_where_clause || ' and ' || key_rec.column_name || ' = ' || enquote_value(l_key_value);
            l_insert_columns := l_insert_columns || ', ' || key_rec.column_name;
            l_insert_values := l_insert_values || ', ' || enquote_value(l_key_value);
          end if;
        end loop;

        l_sql := 'update ' || l_schema_name || '.' || l_object_name
              || ' set ' || rec.target_column_name || ' = ' || enquote_value(rec.computed_value_txt)
              || ' where ' || l_where_clause;

        execute immediate l_sql;
        l_rows_affected := sql%rowcount;

        if l_rows_affected = 0 and upper(nvl(l_missing_row_policy, 'ERROR')) = 'INSERT' then
          l_sql := 'insert into ' || l_schema_name || '.' || l_object_name
              || ' (' || l_insert_columns || ', ' || rec.target_column_name || ') values ('
              || l_insert_values || ', ' || enquote_value(rec.computed_value_txt) || ')';
          execute immediate l_sql;
          l_rows_affected := sql%rowcount;
        elsif l_rows_affected = 0 and upper(nvl(l_missing_row_policy, 'ERROR')) = 'SKIP' then
          o_skipped_count := o_skipped_count + 1;
          l_status := 'SKIPPED';
        elsif l_rows_affected = 0 then
          raise_application_error(-20071, 'Target row not found for consolidated action: ' || l_object_name);
        end if;

        if l_status is null then
          l_status := 'EXECUTED';
          o_executed_count := o_executed_count + 1;
        end if;

        l_action_json := '{'
          || json_quote('winnerRuleId') || ':' || json_quote(to_char(rec.winner_rule_id)) || ','
          || json_quote('targetColumn') || ':' || json_quote(rec.target_column_name)
          || '}';

        l_bind_json := '{'
          || json_quote('targetKey') || ':' || rec.target_key_json || ','
          || json_quote('targetValue') || ':' || json_quote(rec.computed_value_txt)
          || '}';

        l_fingerprint := generate_target_action_fingerprint(
          p_run_id,
          rec.winner_rule_id,
          nvl(l_action_type, 'UPDATE'),
          rec.target_column_name,
          rec.target_key_hash,
          rec.computed_value_txt
        ) || ':CONS:' || to_char(rec.run_target_consolidation_id);

        insert into md_run_target_action (
          run_target_action_id,
          tenant_id,
          context_id,
          run_id,
          change_event_id,
          rule_id,
          target_object_id,
          target_system_name,
          target_entity_name,
          target_key_json,
          target_key_hash,
          target_column_name,
          action_type,
          action_payload_json,
          generated_sql_text,
          bind_payload_json,
          execution_status,
          rows_affected,
          error_code,
          error_message,
          applied_flag,
          applied_at,
          action_fingerprint,
          execution_phase,
          run_target_consolidation_id
        ) values (
          md_run_target_action_seq.nextval,
          p_tenant_id,
          p_context_id,
          p_run_id,
          p_change_event_id,
          rec.winner_rule_id,
          null,
          l_system_name,
          rec.target_entity_name,
          rec.target_key_json,
          rec.target_key_hash,
          rec.target_column_name,
          nvl(l_action_type, 'UPDATE'),
          l_action_json,
          l_sql,
          l_bind_json,
          l_status,
          l_rows_affected,
          null,
          null,
          case when l_status = 'EXECUTED' then 'Y' else 'N' end,
          case when l_status = 'EXECUTED' then systimestamp else null end,
          l_fingerprint,
          'CONSOLIDATED_EXECUTION',
          rec.run_target_consolidation_id
        );

        update md_run_target_consolidation
           set consolidation_status = case when consolidation_status = 'PARTIAL' then 'PARTIAL' else 'EXECUTED' end,
               updated_at = systimestamp
         where run_target_consolidation_id = rec.run_target_consolidation_id;
      exception
        when others then
          o_failed_count := o_failed_count + 1;
          l_error_code := sqlcode;
          l_error_message := substr(sqlerrm, 1, 4000);
          l_fail_fingerprint := generate_target_action_fingerprint(
            p_run_id,
            rec.winner_rule_id,
            'UPDATE',
            rec.target_column_name,
            rec.target_key_hash,
            nvl(rec.computed_value_txt, '')
          ) || ':CONS_FAIL';

          update md_run_target_consolidation
             set consolidation_status = 'PARTIAL',
                 updated_at = systimestamp
           where run_target_consolidation_id = rec.run_target_consolidation_id;

          insert into md_run_target_action (
            run_target_action_id,
            tenant_id,
            context_id,
            run_id,
            change_event_id,
            rule_id,
            target_object_id,
            target_system_name,
            target_entity_name,
            target_key_json,
            target_key_hash,
            target_column_name,
            action_type,
            action_payload_json,
            generated_sql_text,
            bind_payload_json,
            execution_status,
            rows_affected,
            error_code,
            error_message,
            applied_flag,
            applied_at,
            action_fingerprint,
            execution_phase,
            run_target_consolidation_id
          ) values (
            md_run_target_action_seq.nextval,
            p_tenant_id,
            p_context_id,
            p_run_id,
            p_change_event_id,
            rec.winner_rule_id,
            null,
            'TARGET',
            rec.target_entity_name,
            rec.target_key_json,
            rec.target_key_hash,
            rec.target_column_name,
            'UPDATE',
            null,
            null,
            null,
            'FAILED',
            0,
            l_error_code,
            l_error_message,
            'N',
            null,
            l_fail_fingerprint,
            'CONSOLIDATED_EXECUTION',
            rec.run_target_consolidation_id
          );
      end;
    end loop;
  end execute_consolidated_actions_for_run;

  /**
   * Fetch md_rule metadata including rule_payload JSON.
   */
  procedure fetch_rule(
    p_rule_id      in number,
    p_tenant_id    in varchar2,
    p_context_id   in varchar2,
    o_rule_name    out varchar2,
    o_rule_type    out varchar2,
    o_rule_payload out clob,
    o_output_eval_failure_policy out varchar2
  ) is
  begin
    select rule_name,
           rule_type,
           rule_payload,
           nvl(output_eval_failure_policy, 'CONTINUE')
      into o_rule_name,
           o_rule_type,
           o_rule_payload,
           o_output_eval_failure_policy
      from md_rule
     where rule_id = p_rule_id
       and tenant_id = p_tenant_id
       and context_id = p_context_id;
  exception
    when no_data_found then
      raise_application_error(-20001, 'Rule not found: rule_id=' || p_rule_id);
  end fetch_rule;

  /**
   * Fetch rule inputs (md_rule_input joined to md_column).
   */
  procedure fetch_rule_inputs(
    p_rule_id      in number,
    p_tenant_id    in varchar2,
    p_context_id   in varchar2,
    o_input_json   out clob
  ) is
  begin
    select json_arrayagg(
             json_object(
               'rule_input_id' value ri.rule_input_id,
               'source_column_name' value c.column_name,
               'required_flag' value ri.required_flag
             )
           ) into o_input_json
      from md_rule_input ri
      join md_column c on ri.source_column_id = c.column_id
                      and ri.tenant_id = c.tenant_id
                      and ri.context_id = c.context_id
     where ri.rule_id = p_rule_id
       and ri.tenant_id = p_tenant_id
       and ri.context_id = p_context_id;
  exception
    when no_data_found then
      o_input_json := null;
  end fetch_rule_inputs;

  /**
   * Fetch rule outputs (md_rule_output joined to md_column).
   */
  procedure fetch_rule_outputs(
    p_rule_id      in number,
    p_tenant_id    in varchar2,
    p_context_id   in varchar2,
    o_output_json  out clob
  ) is
  begin
    select json_arrayagg(
             json_object(
               'rule_output_id' value ro.rule_output_id,
               'target_column_id' value ro.target_column_id,
               'target_column_name' value c.column_name,
               'output_expr' value ro.output_expr
             )
           ) into o_output_json
      from md_rule_output ro
      join md_column c on ro.target_column_id = c.column_id
                      and ro.tenant_id = c.tenant_id
                      and ro.context_id = c.context_id
     where ro.rule_id = p_rule_id
       and ro.tenant_id = p_tenant_id
       and ro.context_id = p_context_id;
  exception
    when no_data_found then
      o_output_json := null;
  end fetch_rule_outputs;

  /**
   * Fetch source values from md_change_event.
   */
  procedure fetch_source_values(
    p_change_event_id in number,
    p_tenant_id       in varchar2,
    p_context_id      in varchar2,
    o_source_values   out clob
  ) is
  begin
    select source_key_json
      into o_source_values
      from md_change_event
     where change_event_id = p_change_event_id
       and tenant_id = p_tenant_id
       and context_id = p_context_id;
  exception
    when no_data_found then
      raise_application_error(-20002, 'Change event not found: change_event_id=' || p_change_event_id);
  end fetch_source_values;

  /**
   * Dispatch rule execution based on rule_type.
   * Calls type-specific executor package.
   */
  function dispatch_rule_execution(
    p_rule_id       in number,
    p_rule_type     in varchar2,
    p_rule_name     in varchar2,
    p_rule_payload  in clob,
    p_source_values in clob,
    p_params_json   in clob default null,
    p_tenant_id     in varchar2 default null,
    p_context_id    in varchar2 default null
  ) return computed_value_rec is
    l_result computed_value_rec;
  begin
    log_debug('Dispatching rule: rule_id=' || p_rule_id || ', type=' || p_rule_type);

    case p_rule_type
      when 'EXPRESSION' then
        declare
          l_expr_result md_expr_executor_pkg.computed_value_rec;
        begin
          l_expr_result := md_expr_executor_pkg.execute_expression(
            p_rule_payload  => p_rule_payload,
            p_source_values => p_source_values,
            p_params_json   => p_params_json,
            p_tenant_id     => p_tenant_id,
            p_context_id    => p_context_id
          );
          l_result.computed_value_txt := l_expr_result.computed_value_txt;
          l_result.computed_value_json := l_expr_result.computed_value_json;
          l_result.value_data_type := l_expr_result.value_data_type;
          l_result.value_status := l_expr_result.value_status;
          l_result.failure_reason := l_expr_result.failure_reason;
        end;

      when 'LOOKUP' then
        declare
          l_lookup_result md_lookup_executor_pkg.computed_value_rec;
        begin
          l_lookup_result := md_lookup_executor_pkg.execute_lookup(p_rule_payload, p_source_values);
          l_result.computed_value_txt := l_lookup_result.computed_value_txt;
          l_result.computed_value_json := l_lookup_result.computed_value_json;
          l_result.value_data_type := l_lookup_result.value_data_type;
          l_result.value_status := l_lookup_result.value_status;
          l_result.failure_reason := l_lookup_result.failure_reason;
        end;

      when 'COLUMN_TO_ROW' then
        declare
          l_ctr_result md_column_to_row_executor_pkg.computed_value_rec;
        begin
          l_ctr_result := md_column_to_row_executor_pkg.execute_column_to_row(p_rule_payload, p_source_values);
          l_result.computed_value_txt := l_ctr_result.computed_value_txt;
          l_result.computed_value_json := l_ctr_result.computed_value_json;
          l_result.value_data_type := l_ctr_result.value_data_type;
          l_result.value_status := l_ctr_result.value_status;
          l_result.failure_reason := l_ctr_result.failure_reason;
        end;

      when 'PLSQL_FUNC' then
        declare
          l_func_result md_plsql_func_executor_pkg.computed_value_rec;
        begin
          l_func_result := md_plsql_func_executor_pkg.execute_plsql_func(p_rule_payload, p_source_values);
          l_result.computed_value_txt := l_func_result.computed_value_txt;
          l_result.computed_value_json := l_func_result.computed_value_json;
          l_result.value_data_type := l_func_result.value_data_type;
          l_result.value_status := l_func_result.value_status;
          l_result.failure_reason := l_func_result.failure_reason;
        end;

      else
        raise_application_error(-20003, 'Unknown rule type: ' || p_rule_type);
    end case;

    return l_result;
  exception
    when others then
      l_result.value_status := 'FAILED';
      l_result.failure_reason := 'Rule execution failed: ' || sqlerrm;
      return l_result;
  end dispatch_rule_execution;

  -- ===== PUBLIC PROCEDURES & FUNCTIONS =====

  function execute_run(
    p_run_id          in number,
    p_change_event_id in number,
    p_tenant_id       in varchar2,
    p_context_id      in varchar2,
    p_params_json     in clob default null
  ) return run_result_rec is
    l_result            run_result_rec;
    l_rule_id           number;
    l_rule_name         varchar2(200);
    l_rule_type         varchar2(40);
    l_rule_payload      clob;
    l_output_eval_failure_policy varchar2(20);
    l_source_values     clob;
    l_computed_value    computed_value_rec;
    l_change_event_id   number;
    l_rule_inputs       clob;
    l_rule_outputs      clob;
    l_rule_output_values_json clob;
    l_output_columns    sys.odcivarchar2list;
    l_row_count         pls_integer;
    l_params_json       clob;
    l_target_executed   number;
    l_target_failed     number;
    l_target_skipped    number;
    l_cons_built        number;
    l_cons_build_failed number;
    l_cons_build_skipped number;
    l_cons_exec_count   number;
    l_cons_exec_failed  number;
    l_cons_exec_skipped number;
    l_gate_status       varchar2(20);
    l_gate_message      varchar2(4000);
    l_output_values_obj json_object_t;
    l_any_output_failed boolean;

    cursor c_selected_rules is
      select run_selected_rule_id, rule_id, transitive_flag
        from md_run_selected_rule
       where run_id = p_run_id
         and change_event_id = p_change_event_id
         and tenant_id = p_tenant_id
         and context_id = p_context_id;
  begin
    log_debug('Starting rule execution for run_id=' || p_run_id);

    l_result.run_id := p_run_id;
    l_result.run_status := 'RUNNING';
    l_result.metrics.rules_selected := 0;
    l_result.metrics.rules_executed := 0;
    l_result.metrics.values_computed := 0;
    l_result.metrics.values_failed := 0;
    l_result.metrics.values_skipped := 0;
    l_result.error_messages := sys.odcivarchar2list();

    l_change_event_id := p_change_event_id;

    if p_params_json is not null then
      md_run_parameter_pkg.persist_run_parameters(
        p_run_id      => p_run_id,
        p_tenant_id   => p_tenant_id,
        p_context_id  => p_context_id,
        p_params_json => p_params_json
      );
      l_params_json := p_params_json;
    else
      l_params_json := md_run_parameter_pkg.load_run_parameters(
        p_run_id     => p_run_id,
        p_tenant_id  => p_tenant_id,
        p_context_id => p_context_id
      );
    end if;

    if l_params_json is null then
      l_params_json := '{}';
    end if;

    -- Compute selected rules dynamically and persist once for this run/event.
    md_rule_selector_pkg.populate_selected_rules(
      p_run_id          => p_run_id,
      p_change_event_id => l_change_event_id,
      p_tenant_id       => p_tenant_id,
      p_context_id      => p_context_id,
      p_purge_existing  => 'Y'
    );

    md_source_context_resolver_pkg.prefetch_selected_contexts(
      p_run_id          => p_run_id,
      p_change_event_id => l_change_event_id,
      p_tenant_id       => p_tenant_id,
      p_context_id      => p_context_id,
      p_params_json     => l_params_json
    );

    -- Iterate selected rules
    for rec in c_selected_rules loop
      l_result.metrics.rules_selected := l_result.metrics.rules_selected + 1;
      l_rule_id := rec.rule_id;

      begin
        md_run_parameter_pkg.validate_required_parameters(
          p_run_id      => p_run_id,
          p_rule_id     => l_rule_id,
          p_tenant_id   => p_tenant_id,
          p_context_id  => p_context_id,
          p_params_json => l_params_json
        );

        -- Resolve source context per rule (supports multi-entity context graphs).
        l_source_values := md_source_context_resolver_pkg.get_prefetched_rule_source_values(
          p_run_id          => p_run_id,
          p_change_event_id => l_change_event_id,
          p_rule_id         => l_rule_id,
          p_tenant_id       => p_tenant_id,
          p_context_id      => p_context_id,
          p_params_json     => l_params_json
        );

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
            l_change_event_id,
            json_object(
              'diagnostic_type' value 'RULE_SOURCE_VALUES',
              'rule_id' value l_rule_id
              returning clob
            ),
            json_object(
              'stage' value 'EXECUTE_RUN',
              'step' value 'RESOLVED_SOURCE_VALUES'
              returning clob
            ),
            json_object(
              'source_values' value l_source_values
              returning clob
            )
          );
        exception
          when others then
            null;
        end;

        -- Fetch rule metadata
        fetch_rule(
          l_rule_id,
          p_tenant_id,
          p_context_id,
          l_rule_name,
          l_rule_type,
          l_rule_payload,
          l_output_eval_failure_policy
        );
        fetch_rule_inputs(l_rule_id, p_tenant_id, p_context_id, l_rule_inputs);
        fetch_rule_outputs(l_rule_id, p_tenant_id, p_context_id, l_rule_outputs);

        evaluate_selection_gate(
          p_rule_id         => l_rule_id,
          p_change_event_id => l_change_event_id,
          p_tenant_id       => p_tenant_id,
          p_context_id      => p_context_id,
          p_source_values   => l_source_values,
          p_params_json     => l_params_json,
          o_gate_status     => l_gate_status,
          o_gate_message    => l_gate_message
        );

        update md_run_selected_rule
           set gate_eval_status = l_gate_status,
               gate_eval_message = l_gate_message,
               gate_evaluated_at = systimestamp
         where run_selected_rule_id = rec.run_selected_rule_id
           and tenant_id = p_tenant_id
           and context_id = p_context_id;

        if l_gate_status = 'FILTERED' then
          l_result.metrics.values_skipped := l_result.metrics.values_skipped + 1;
          continue;
        elsif l_gate_status = 'ERROR' then
          l_result.error_messages.extend;
          l_result.error_messages(l_result.error_messages.last) :=
            'Rule gate failed: rule_id=' || l_rule_id || ', error=' || nvl(l_gate_message, 'UNKNOWN');
          continue;
        end if;

        l_result.metrics.rules_executed := l_result.metrics.rules_executed + 1;

        if l_rule_type <> 'EXPRESSION' then
          l_result.error_messages.extend;
          l_result.error_messages(l_result.error_messages.last) :=
            'Rule type not supported for output_expr evaluation: rule_id=' || l_rule_id || ', rule_type=' || l_rule_type;
          continue;
        end if;

        l_output_values_obj := json_object_t();
        l_any_output_failed := false;
        l_rule_output_values_json := null;

        -- Persist results per output column
        if l_rule_outputs is not null then
          for out_rec in (
            select jt.target_column_name,
                   jt.output_expr
              from json_table(
                     l_rule_outputs,
                     '$[*]'
                     columns (
                       target_column_name varchar2(128) path '$.target_column_name',
                       output_expr varchar2(4000) path '$.output_expr'
                     )
                   ) jt
          ) loop
            if out_rec.output_expr is null then
              l_computed_value.computed_value_txt := null;
              l_computed_value.computed_value_json := null;
              l_computed_value.value_data_type := null;
              l_computed_value.value_status := 'FAILED';
              l_computed_value.failure_reason :=
                'Output expression missing for target column: ' || out_rec.target_column_name;
            else
              declare
                l_expr_result md_expr_executor_pkg.computed_value_rec;
              begin
                l_expr_result := md_expr_executor_pkg.evaluate_expr(
                  p_expr          => out_rec.output_expr,
                  p_source_values => l_source_values,
                  p_params_json   => l_params_json,
                  p_tenant_id     => p_tenant_id,
                  p_context_id    => p_context_id
                );

                l_computed_value.computed_value_txt := l_expr_result.computed_value_txt;
                l_computed_value.computed_value_json := l_expr_result.computed_value_json;
                l_computed_value.value_data_type := l_expr_result.value_data_type;
                l_computed_value.value_status := l_expr_result.value_status;
                l_computed_value.failure_reason := l_expr_result.failure_reason;
              end;
            end if;

            persist_target_value(
              p_run_id,
              l_rule_id,
              out_rec.target_column_name,
              l_computed_value,
              p_tenant_id,
              p_context_id
            );

            if l_computed_value.value_status = 'COMPUTED' then
              l_result.metrics.values_computed := l_result.metrics.values_computed + 1;
              l_output_values_obj.put(out_rec.target_column_name, l_computed_value.computed_value_txt);
            elsif l_computed_value.value_status = 'SKIPPED' then
              l_result.metrics.values_skipped := l_result.metrics.values_skipped + 1;
            else
              l_any_output_failed := true;
              l_result.metrics.values_failed := l_result.metrics.values_failed + 1;

              log_output_eval_failure_trace(
                p_run_id             => p_run_id,
                p_change_event_id    => l_change_event_id,
                p_rule_id            => l_rule_id,
                p_target_column_name => out_rec.target_column_name,
                p_output_expr        => out_rec.output_expr,
                p_failure_reason     => l_computed_value.failure_reason,
                p_tenant_id          => p_tenant_id,
                p_context_id         => p_context_id
              );

              if upper(nvl(l_output_eval_failure_policy, 'CONTINUE')) = 'FAIL_RULE' then
                l_result.error_messages.extend;
                l_result.error_messages(l_result.error_messages.last) :=
                  'Output evaluation failed: rule_id=' || l_rule_id ||
                  ', target_column=' || out_rec.target_column_name ||
                  ', error=' || nvl(l_computed_value.failure_reason, 'UNKNOWN');
                exit;
              end if;
            end if;
          end loop;

          l_rule_output_values_json := l_output_values_obj.to_clob;
        end if;

        if l_any_output_failed and upper(nvl(l_output_eval_failure_policy, 'CONTINUE')) = 'FAIL_RULE' then
          continue;
        end if;

        consolidate_rule_actions(
          p_run_id          => p_run_id,
          p_rule_id         => l_rule_id,
          p_tenant_id       => p_tenant_id,
          p_context_id      => p_context_id,
          p_change_event_id => l_change_event_id,
          p_source_values   => l_source_values,
          p_params_json     => l_params_json,
          p_computed_value  => l_computed_value,
          p_rule_output_values_json => l_rule_output_values_json,
          o_consolidated_count => l_cons_built,
          o_failed_count    => l_cons_build_failed,
          o_skipped_count   => l_cons_build_skipped
        );

        if nvl(l_cons_build_failed, 0) > 0 then
          l_result.metrics.values_failed := l_result.metrics.values_failed + l_cons_build_failed;
        end if;

        if nvl(l_cons_build_skipped, 0) > 0 then
          l_result.metrics.values_skipped := l_result.metrics.values_skipped + l_cons_build_skipped;
        end if;

        -- Log impact trace
        log_impact_trace(p_run_id, l_rule_id, l_source_values, p_tenant_id, p_context_id);

      exception
        when others then
          l_result.error_messages.extend;
          l_result.error_messages(l_result.error_messages.last) :=
            'Rule execution failed: rule_id=' || l_rule_id || ', error=' || sqlerrm;
          log_error(l_result.error_messages(l_result.error_messages.last));
      end;
    end loop;

    execute_consolidated_actions_for_run(
      p_run_id          => p_run_id,
      p_change_event_id => l_change_event_id,
      p_tenant_id       => p_tenant_id,
      p_context_id      => p_context_id,
      o_executed_count  => l_cons_exec_count,
      o_failed_count    => l_cons_exec_failed,
      o_skipped_count   => l_cons_exec_skipped
    );

    if nvl(l_cons_exec_failed, 0) > 0 then
      l_result.metrics.values_failed := l_result.metrics.values_failed + l_cons_exec_failed;
    end if;

    if nvl(l_cons_exec_skipped, 0) > 0 then
      l_result.metrics.values_skipped := l_result.metrics.values_skipped + l_cons_exec_skipped;
    end if;

    -- Determine final run status
    if l_result.error_messages.count > 0 then
      l_result.run_status := 'FAILED';
    elsif l_result.metrics.values_failed > 0 then
      l_result.run_status := 'PARTIAL';
    else
      l_result.run_status := 'SUCCEEDED';
    end if;

    -- Update md_run with final status
    update_run_status(p_run_id, l_result.run_status, p_tenant_id, p_context_id);

    log_debug('Rule execution completed: run_id=' || p_run_id || ', status=' || l_result.run_status);

    return l_result;
  exception
    when others then
      l_result.run_status := 'FAILED';
      l_result.error_messages.extend;
      l_result.error_messages(l_result.error_messages.last) := 'Orchestration failed: ' || sqlerrm;
      return l_result;
  end execute_run;

  function execute_rule(
    p_rule_id       in number,
    p_tenant_id     in varchar2,
    p_context_id    in varchar2,
    p_source_values in clob
  ) return computed_value_rec is
    l_rule_name    varchar2(200);
    l_rule_type    varchar2(40);
    l_rule_payload clob;
    l_output_eval_failure_policy varchar2(20);
    l_result       computed_value_rec;
  begin
    fetch_rule(
      p_rule_id,
      p_tenant_id,
      p_context_id,
      l_rule_name,
      l_rule_type,
      l_rule_payload,
      l_output_eval_failure_policy
    );
    l_result := dispatch_rule_execution(
      p_rule_id       => p_rule_id,
      p_rule_type     => l_rule_type,
      p_rule_name     => l_rule_name,
      p_rule_payload  => l_rule_payload,
      p_source_values => p_source_values,
      p_params_json   => null,
      p_tenant_id     => p_tenant_id,
      p_context_id    => p_context_id
    );
    return l_result;
  exception
    when others then
      l_result.value_status := 'FAILED';
      l_result.failure_reason := sqlerrm;
      return l_result;
  end execute_rule;

  procedure persist_target_value(
    p_run_id             in number,
    p_rule_id            in number,
    p_target_column_name in varchar2,
    p_computed_value     in computed_value_rec,
    p_tenant_id          in varchar2,
    p_context_id         in varchar2
  ) is
    l_value_fingerprint varchar2(128);
    l_existing_count    number;
  begin
    -- Generate fingerprint for idempotency
    l_value_fingerprint := generate_fingerprint(p_run_id, p_rule_id, p_target_column_name, p_computed_value.computed_value_txt);

    -- Check if already persisted (idempotency)
    select count(*)
      into l_existing_count
      from md_run_target_value
     where run_id = p_run_id
       and rule_id = p_rule_id
       and tenant_id = p_tenant_id
       and context_id = p_context_id
       and value_fingerprint = l_value_fingerprint;

    if l_existing_count > 0 then
      log_debug('Value already persisted (idempotent): value_fingerprint=' || l_value_fingerprint);
      return;
    end if;

    -- Insert md_run_target_value
    insert into md_run_target_value (
      run_target_value_id,
      tenant_id,
      context_id,
      run_id,
      change_event_id,
      rule_id,
      target_system_name,
      target_entity_name,
      target_key_json,
      target_key_hash,
      target_column_name,
      computed_value_txt,
      computed_value_json,
      value_data_type,
      value_status,
      value_fingerprint,
      computed_at
    ) values (
      md_run_target_value_seq.nextval,
      p_tenant_id,
      p_context_id,
      p_run_id,
      null,
      p_rule_id,
      'TARGET',
      'UNKNOWN_ENTITY',
      '{}',
      'UNKNOWN_KEY',
      p_target_column_name,
      p_computed_value.computed_value_txt,
      p_computed_value.computed_value_json,
      p_computed_value.value_data_type,
      p_computed_value.value_status,
      l_value_fingerprint,
      systimestamp
    );

    log_debug('Persisted target value: run_id=' || p_run_id || ', rule_id=' || p_rule_id ||
              ', column=' || p_target_column_name || ', status=' || p_computed_value.value_status);
  exception
    when others then
      log_error('Failed to persist target value: ' || sqlerrm);
      raise;
  end persist_target_value;

  procedure log_impact_trace(
    p_run_id      in number,
    p_rule_id     in number,
    p_source_json in clob,
    p_tenant_id   in varchar2,
    p_context_id  in varchar2
  ) is
    l_rule_json   clob;
    l_target_json clob;
  begin
    -- Build rule and target references
    select json_object(
             'rule_id' value p_rule_id,
             'rule_type' value r.rule_type,
             'rule_name' value r.rule_name
           )
      into l_rule_json
      from md_rule r
     where r.rule_id = p_rule_id
       and r.tenant_id = p_tenant_id
       and r.context_id = p_context_id;

    select json_arrayagg(
             json_object('column' value c.column_name)
           )
      into l_target_json
      from md_rule_output ro
      join md_column c on ro.target_column_id = c.column_id
                      and ro.tenant_id = c.tenant_id
                      and ro.context_id = c.context_id
     where ro.rule_id = p_rule_id
       and ro.tenant_id = p_tenant_id
       and ro.context_id = p_context_id;

    -- Insert impact trace
    insert into md_impact_trace (
      impact_trace_id,
      tenant_id,
      context_id,
      run_id,
      change_event_id,
      source_ref_json,
      rule_ref_json,
      target_ref_json,
      created_at
    ) values (
      md_impact_trace_seq.nextval,
      p_tenant_id,
      p_context_id,
      p_run_id,
      null,
      p_source_json,
      l_rule_json,
      nvl(l_target_json, '[]'),
      systimestamp
    );
  exception
    when others then
      log_error('Failed to log impact trace: ' || sqlerrm);
      -- Don't re-raise; impact trace is informational
  end log_impact_trace;

  procedure update_run_status(
    p_run_id      in number,
    p_status      in varchar2,
    p_tenant_id   in varchar2,
    p_context_id  in varchar2
  ) is
  begin
    update md_run
       set run_status = p_status,
           ended_at = systimestamp
     where run_id = p_run_id
       and tenant_id = p_tenant_id
       and context_id = p_context_id;
  exception
    when others then
      log_error('Failed to update run status: ' || sqlerrm);
      raise;
  end update_run_status;

  function generate_fingerprint(
    p_run_id             in number,
    p_rule_id            in number,
    p_target_column_name in varchar2,
    p_value              in varchar2
  ) return varchar2 is
    l_input varchar2(4000);
    l_hash  varchar2(128);
  begin
    l_input := p_run_id || '|' || p_rule_id || '|' || p_target_column_name || '|' ||
               nvl(p_value, 'NULL');
    select lower(standard_hash(l_input, 'SHA1'))
      into l_hash
      from dual;
    return l_hash;
  exception
    when others then
      log_error('Fingerprint generation failed: ' || sqlerrm);
      raise;
  end generate_fingerprint;

end md_rule_executor_pkg;
/

show errors package body md_rule_executor_pkg;
