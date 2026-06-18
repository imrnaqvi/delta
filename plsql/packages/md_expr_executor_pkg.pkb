create or replace package body md_expr_executor_pkg as

  /**
   * Substitute SRC.COL references with actual source values.
   * E.g., "SRC.SECURITY_ID * 1.1" with {"SECURITY_ID": 1000} → "1000 * 1.1"
   */
  function substitute_source_references(
    p_expr          in varchar2,
    p_source_values in clob
  ) return varchar2 is
    l_result varchar2(4000) := p_expr;
    l_root   json_object_t;

    function elem_to_sql_literal(
      p_obj  in json_object_t,
      p_key  in varchar2,
      p_elem in json_element_t
    ) return varchar2 is
    begin
      if p_elem is null or p_elem.is_null then
        return 'null';
      elsif p_elem.is_string then
        return '''' || replace(p_obj.get_string(p_key), '''', '''''') || '''';
      elsif p_elem.is_number then
        return to_char(p_obj.get_number(p_key));
      elsif p_elem.is_boolean then
        if p_obj.get_boolean(p_key) then
          return '''Y''';
        else
          return '''N''';
        end if;
      else
        return '''' || replace(p_elem.to_string, '''', '''''') || '''';
      end if;
    end elem_to_sql_literal;

    procedure walk_object(
      p_obj    in json_object_t,
      p_prefix in varchar2
    ) is
      l_keys   json_key_list;
      l_key    varchar2(4000);
      l_elem   json_element_t;
      l_token  varchar2(4000);
      l_child  json_object_t;
      l_value  varchar2(4000);
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
          walk_object(l_child, l_token);
        else
          l_value := elem_to_sql_literal(p_obj, l_key, l_elem);

          -- Backward compatibility for legacy expressions like SRC.COL where
          -- source JSON is still flat: {"COL": ...}
          if p_prefix is null then
            l_result := replace(l_result, 'SRC.' || l_key, l_value);
          end if;

          -- Alias-aware replacement for nested contexts: ALIAS.COL
          l_result := replace(l_result, l_token, l_value);
        end if;
      end loop;
    end walk_object;
  begin
    if p_source_values is null then
      return l_result;
    end if;

    l_root := json_object_t.parse(p_source_values);
    walk_object(l_root, null);

    return l_result;
  exception
    when others then
      return p_expr;
  end substitute_source_references;

  function substitute_param_references(
    p_expr        in varchar2,
    p_params_json in clob
  ) return varchar2 is
    l_result varchar2(4000) := p_expr;
    l_root   json_object_t;

    function elem_to_sql_literal(
      p_obj  in json_object_t,
      p_key  in varchar2,
      p_elem in json_element_t
    ) return varchar2 is
    begin
      if p_elem is null or p_elem.is_null then
        return 'null';
      elsif p_elem.is_string then
        return '''' || replace(p_obj.get_string(p_key), '''', '''''') || '''';
      elsif p_elem.is_number then
        return to_char(p_obj.get_number(p_key));
      elsif p_elem.is_boolean then
        if p_obj.get_boolean(p_key) then
          return '''Y''';
        else
          return '''N''';
        end if;
      else
        return '''' || replace(p_elem.to_string, '''', '''''') || '''';
      end if;
    end elem_to_sql_literal;

    procedure walk_object(
      p_obj    in json_object_t,
      p_prefix in varchar2
    ) is
      l_keys   json_key_list;
      l_key    varchar2(4000);
      l_elem   json_element_t;
      l_token  varchar2(4000);
      l_child  json_object_t;
      l_value  varchar2(4000);
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
          walk_object(l_child, l_token);
        else
          l_value := elem_to_sql_literal(p_obj, l_key, l_elem);
          l_result := replace(l_result, 'PARAM.' || l_token, l_value);
        end if;
      end loop;
    end walk_object;
  begin
    if p_params_json is null then
      return l_result;
    end if;

    l_root := json_object_t.parse(p_params_json);
    walk_object(l_root, null);

    return l_result;
  exception
    when others then
      return p_expr;
  end substitute_param_references;

  function execute_expression(
    p_rule_payload  in clob,
    p_source_values in clob,
    p_params_json   in clob default null
  ) return computed_value_rec is
    l_result            computed_value_rec;
    l_expr              varchar2(4000);
    l_evaluable_expr    varchar2(4000);
    l_computed_value    varchar2(4000);
  begin
    -- Extract "expr" from payload
    l_expr := json_value(p_rule_payload, '$.expr');

    if l_expr is null then
      l_result.value_status := 'FAILED';
      l_result.failure_reason := 'Payload missing "expr" field';
      return l_result;
    end if;

    -- Substitute source and runtime parameter references.
    l_evaluable_expr := substitute_source_references(l_expr, p_source_values);
    l_evaluable_expr := substitute_param_references(l_evaluable_expr, p_params_json);

    -- Evaluate expression in SQL context after SRC substitution.
    begin
      execute immediate 'select ' || l_evaluable_expr || ' from dual' into l_computed_value;

      l_result.computed_value_txt := l_computed_value;
      l_result.value_data_type := 'VARCHAR2';
      l_result.value_status := 'COMPUTED';

      return l_result;
    exception
      when others then
        l_result.value_status := 'FAILED';
        l_result.failure_reason := 'Expression evaluation failed: ' || sqlerrm;
        return l_result;
    end;
  exception
    when others then
      l_result.value_status := 'FAILED';
      l_result.failure_reason := sqlerrm;
      return l_result;
  end execute_expression;

end md_expr_executor_pkg;
/

show errors package body md_expr_executor_pkg;
