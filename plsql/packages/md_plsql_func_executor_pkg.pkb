create or replace package body md_plsql_func_executor_pkg as

  function execute_plsql_func(
    p_rule_payload  in clob,
    p_source_values in clob
  ) return computed_value_rec is
    l_result           computed_value_rec;
    l_payload_obj      json_object_t;
    l_source_obj       json_object_t;
    l_function_owner   varchar2(128);
    l_function_name    varchar2(128);
    l_params           json_array_t;
    l_return_type      varchar2(128);
    l_sql              varchar2(32767);
    l_arg_list         varchar2(32767) := '';
    l_arg_ref          varchar2(4000);
    l_arg_col          varchar2(4000);
    l_arg_val          varchar2(4000);
    l_out_val          varchar2(4000);

    function resolve_source_value(p_ref in varchar2) return varchar2 is
      l_alias varchar2(4000);
      l_col   varchar2(4000);
      l_elem  json_element_t;
      l_obj   json_object_t;
    begin
      if instr(p_ref, '.') > 0 then
        l_alias := substr(p_ref, 1, instr(p_ref, '.') - 1);
        l_col := substr(p_ref, instr(p_ref, '.') + 1);

        l_elem := l_source_obj.get(l_alias);
        if l_elem is not null and l_elem.is_object then
          l_obj := json_object_t.parse(l_elem.to_string);
          begin
            return l_obj.get_string(l_col);
          exception
            when others then
              null;
          end;
        end if;

        begin
          return l_source_obj.get_string(l_col);
        exception
          when others then
            return null;
        end;
      else
        begin
          return l_source_obj.get_string(p_ref);
        exception
          when others then
            return null;
        end;
      end if;
    end resolve_source_value;

    function clean_identifier(p_value in varchar2) return varchar2 is
    begin
      if p_value is null or not regexp_like(p_value, '^[A-Za-z][A-Za-z0-9_$#\.]*$') then
        raise_application_error(-20051, 'Invalid identifier: ' || nvl(p_value, '<null>'));
      end if;
      return p_value;
    end clean_identifier;
  begin
    -- Extract payload fields
    l_payload_obj := json_object_t.parse(p_rule_payload);
    l_source_obj := json_object_t.parse(p_source_values);

    l_function_owner := clean_identifier(l_payload_obj.get_string('function_owner'));
    l_function_name := clean_identifier(l_payload_obj.get_string('function_name'));
    l_return_type := nvl(l_payload_obj.get_string('return_type'), 'VARCHAR2');
    l_params := l_payload_obj.get_array('params');

    if l_function_owner is null or l_function_name is null or
       l_return_type is null or l_params is null then
      l_result.value_status := 'FAILED';
      l_result.failure_reason := 'Payload missing required fields: function_owner, function_name, params, return_type';
      return l_result;
    end if;

    for i in 0 .. l_params.get_size - 1 loop
      if i > 0 then
        l_arg_list := l_arg_list || ', ';
      end if;

      l_arg_ref := l_params.get_string(i);

      if upper(substr(l_arg_ref, 1, 4)) = 'SRC.' then
        l_arg_val := resolve_source_value(l_arg_ref);
        l_arg_list := l_arg_list || '''' || replace(nvl(l_arg_val, ''), '''', '''''') || '''';
      elsif instr(l_arg_ref, '.') > 0 then
        l_arg_val := resolve_source_value(l_arg_ref);
        l_arg_list := l_arg_list || '''' || replace(nvl(l_arg_val, ''), '''', '''''') || '''';
      else
        l_arg_list := l_arg_list || '''' || replace(l_arg_ref, '''', '''''') || '''';
      end if;
    end loop;

    l_sql := 'select ' || l_function_owner || '.' || l_function_name || '(' || l_arg_list || ') from dual';
    execute immediate l_sql into l_out_val;

    l_result.computed_value_txt := l_out_val;
    l_result.value_data_type := l_return_type;
    l_result.value_status := 'COMPUTED';

    return l_result;
  exception
    when others then
      l_result.value_status := 'FAILED';
      l_result.failure_reason := 'Function execution failed: ' || sqlerrm;
      return l_result;
  end execute_plsql_func;

end md_plsql_func_executor_pkg;
/

show errors package body md_plsql_func_executor_pkg;
