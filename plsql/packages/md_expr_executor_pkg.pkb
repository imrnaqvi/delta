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

  function validate_expression_guardrails(
    p_expr                 in varchar2,
    p_allowed_functions    in json_array_t,
    p_disallow_subqueries  in boolean default true
  ) return varchar2 is
    type function_set_t is table of pls_integer index by varchar2(4000);
    l_allowed_set        function_set_t;
    l_has_allowlist      boolean := false;
    l_upper_expr         varchar2(4000) := upper(nvl(p_expr, ''));
    l_func_name          varchar2(4000);
    l_allowed_name       varchar2(4000);
    l_occurrence         pls_integer := 1;
  begin
    if instr(l_upper_expr, ';') > 0 then
      return 'Blocked token detected: ;';
    end if;

    if instr(l_upper_expr, '--') > 0 then
      return 'Blocked token detected: --';
    end if;

    if instr(l_upper_expr, '/*') > 0 or instr(l_upper_expr, '*/') > 0 then
      return 'Blocked token detected: SQL comment marker';
    end if;

    if p_disallow_subqueries then
      if regexp_like(l_upper_expr, '(^|[^A-Z0-9_])(SELECT|FROM|UNION|JOIN|WITH)([^A-Z0-9_]|$)') then
        return 'Blocked keyword detected for expression guardrails';
      end if;
    end if;

    if p_allowed_functions is not null and p_allowed_functions.get_size > 0 then
      l_has_allowlist := true;

      for i in 0 .. p_allowed_functions.get_size - 1 loop
        l_allowed_name := upper(trim(p_allowed_functions.get_string(i)));
        if l_allowed_name is not null then
          l_allowed_set(l_allowed_name) := 1;
        end if;
      end loop;
    end if;

    if l_has_allowlist then
      loop
        l_func_name := regexp_substr(
          l_upper_expr,
          '([A-Z][A-Z0-9_$#\.]*)\(',
          1,
          l_occurrence,
          null,
          1
        );

        exit when l_func_name is null;

        if not l_allowed_set.exists(l_func_name) then
          return 'Function not allowed: ' || l_func_name;
        end if;

        l_occurrence := l_occurrence + 1;
      end loop;
    end if;

    return null;
  exception
    when others then
      return 'Expression validator failed: ' || sqlerrm;
  end validate_expression_guardrails;

  function load_registry_allowed_functions(
    p_tenant_id  in varchar2,
    p_context_id in varchar2
  ) return json_array_t is
    l_allowed_json clob;
  begin
    if p_tenant_id is null or p_context_id is null then
      return null;
    end if;

    select json_arrayagg(upper(function_name) returning clob)
      into l_allowed_json
      from md_expr_allowed_function
     where tenant_id = p_tenant_id
       and context_id = p_context_id
       and nvl(active_flag, 'Y') = 'Y';

    if l_allowed_json is null then
      return null;
    end if;

    return json_array_t.parse(l_allowed_json);
  exception
    when no_data_found then
      return null;
    when others then
      return null;
  end load_registry_allowed_functions;

  function execute_expression(
    p_rule_payload  in clob,
    p_source_values in clob,
    p_params_json   in clob default null,
    p_tenant_id     in varchar2 default null,
    p_context_id    in varchar2 default null
  ) return computed_value_rec is
    l_result            computed_value_rec;
    l_payload_obj       json_object_t;
    l_expr              varchar2(4000);
  begin
    l_payload_obj := json_object_t.parse(p_rule_payload);

    -- Extract "expr" from payload
    l_expr := l_payload_obj.get_string('expr');

    if l_expr is null then
      l_result.value_status := 'FAILED';
      l_result.failure_reason := 'Payload missing "expr" field';
      return l_result;
    end if;

    return evaluate_expr(
      p_expr          => l_expr,
      p_source_values => p_source_values,
      p_params_json   => p_params_json,
      p_tenant_id     => p_tenant_id,
      p_context_id    => p_context_id
    );
  exception
    when others then
      l_result.value_status := 'FAILED';
      l_result.failure_reason := sqlerrm;
      return l_result;
  end execute_expression;

  function evaluate_expr(
    p_expr          in varchar2,
    p_source_values in clob,
    p_params_json   in clob default null,
    p_tenant_id     in varchar2 default null,
    p_context_id    in varchar2 default null
  ) return computed_value_rec is
    l_result            computed_value_rec;
    l_allowed_functions json_array_t;
    l_validation_error  varchar2(4000);
    l_evaluable_expr    varchar2(4000);
    l_computed_value    varchar2(4000);
  begin
    if p_expr is null then
      l_result.value_status := 'FAILED';
      l_result.failure_reason := 'Expression is null';
      return l_result;
    end if;

    l_allowed_functions := load_registry_allowed_functions(
      p_tenant_id  => p_tenant_id,
      p_context_id => p_context_id
    );

    l_validation_error := validate_expression_guardrails(
      p_expr                => p_expr,
      p_allowed_functions   => l_allowed_functions,
      p_disallow_subqueries => true
    );

    if l_validation_error is not null then
      l_result.value_status := 'FAILED';
      l_result.failure_reason := 'Expression validation failed: ' || l_validation_error;
      return l_result;
    end if;

    l_evaluable_expr := substitute_source_references(p_expr, p_source_values);
    l_evaluable_expr := substitute_param_references(l_evaluable_expr, p_params_json);

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
  end evaluate_expr;

end md_expr_executor_pkg;
/

show errors package body md_expr_executor_pkg;
