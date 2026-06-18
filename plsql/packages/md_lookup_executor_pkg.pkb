create or replace package body md_lookup_executor_pkg as

  function execute_lookup(
    p_rule_payload  in clob,
    p_source_values in clob
  ) return computed_value_rec is
    l_result          computed_value_rec;
    l_payload_obj     json_object_t;
    l_source_obj      json_object_t;
    l_lookup_table    varchar2(128);
    l_return_format   varchar2(30);
    l_join_obj        json_object_t;
    l_join_keys       json_key_list;
    l_ret_cols_arr    json_array_t;
    l_sql             varchar2(32767);
    l_col_list        varchar2(32767) := '';
    l_where_list      varchar2(32767) := '';
    l_col_count       pls_integer;
    l_cur             integer;
    l_rc              integer;
    l_bind_value      varchar2(4000);
    l_src_ref         varchar2(4000);
    l_tgt_col         varchar2(4000);
    l_col_value       varchar2(4000);
    l_json_result     json_object_t;
    l_delimited       varchar2(4000) := '';
    l_cur_open        boolean := false;

    function clean_identifier(p_value in varchar2) return varchar2 is
    begin
      if p_value is null or not regexp_like(p_value, '^[A-Za-z][A-Za-z0-9_$#\.]*$') then
        raise_application_error(-20031, 'Invalid identifier: ' || nvl(p_value, '<null>'));
      end if;
      return p_value;
    end clean_identifier;

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
  begin
    l_payload_obj := json_object_t.parse(p_rule_payload);
    l_source_obj := json_object_t.parse(p_source_values);

    l_lookup_table := clean_identifier(l_payload_obj.get_string('lookup_table'));
    l_return_format := lower(nvl(l_payload_obj.get_string('return_format'), 'single_row'));
    l_join_obj := l_payload_obj.get_object('join_key');
    l_ret_cols_arr := l_payload_obj.get_array('return_columns');

    if l_join_obj is null or l_ret_cols_arr is null or l_ret_cols_arr.get_size = 0 then
      l_result.value_status := 'FAILED';
      l_result.failure_reason := 'Payload missing required fields: join_key/return_columns';
      return l_result;
    end if;

    l_join_keys := l_join_obj.get_keys;
    l_col_count := l_ret_cols_arr.get_size;

    for i in 0 .. l_col_count - 1 loop
      if i > 0 then
        l_col_list := l_col_list || ', ';
      end if;
      l_col_list := l_col_list || clean_identifier(l_ret_cols_arr.get_string(i));
    end loop;

    for i in 1 .. l_join_keys.count loop
      l_src_ref := l_join_keys(i);
      l_tgt_col := clean_identifier(l_join_obj.get_string(l_src_ref));

      if i > 1 then
        l_where_list := l_where_list || ' and ';
      end if;

      l_where_list := l_where_list || l_tgt_col || ' = :b' || i;
    end loop;

    l_sql := 'select ' || l_col_list || ' from ' || l_lookup_table || ' where ' || l_where_list;

    l_cur := dbms_sql.open_cursor;
    l_cur_open := true;
    dbms_sql.parse(l_cur, l_sql, dbms_sql.native);

    for i in 1 .. l_join_keys.count loop
      l_src_ref := l_join_keys(i);
          l_bind_value := resolve_source_value(l_src_ref);
      dbms_sql.bind_variable(l_cur, ':b' || i, l_bind_value);
    end loop;

    for i in 1 .. l_col_count loop
      dbms_sql.define_column(l_cur, i, l_col_value, 4000);
    end loop;

    l_rc := dbms_sql.execute(l_cur);

    if dbms_sql.fetch_rows(l_cur) = 0 then
      dbms_sql.close_cursor(l_cur);
      l_result.value_status := 'SKIPPED';
      return l_result;
    end if;

    if l_return_format = 'json_object' then
      l_json_result := json_object_t();
      for i in 1 .. l_col_count loop
        dbms_sql.column_value(l_cur, i, l_col_value);
        l_json_result.put(l_ret_cols_arr.get_string(i - 1), l_col_value);
      end loop;
      l_result.computed_value_json := l_json_result.to_clob;
      l_result.computed_value_txt := l_json_result.to_string;
      l_result.value_data_type := 'JSON';
    elsif l_return_format = 'semicolon_delimited' then
      for i in 1 .. l_col_count loop
        dbms_sql.column_value(l_cur, i, l_col_value);
        if i > 1 then
          l_delimited := l_delimited || ';';
        end if;
        l_delimited := l_delimited || nvl(l_col_value, '');
      end loop;
      l_result.computed_value_txt := l_delimited;
      l_result.value_data_type := 'VARCHAR2';
    else
      dbms_sql.column_value(l_cur, 1, l_col_value);
      l_result.computed_value_txt := l_col_value;
      l_result.value_data_type := 'VARCHAR2';
    end if;

    dbms_sql.close_cursor(l_cur);
    l_cur_open := false;
    l_result.value_status := 'COMPUTED';

    return l_result;

  exception
    when others then
      if l_cur_open then
        dbms_sql.close_cursor(l_cur);
      end if;
      l_result.value_status := 'FAILED';
      l_result.failure_reason := 'Lookup execution failed: ' || sqlerrm;
      return l_result;
  end execute_lookup;

end md_lookup_executor_pkg;
/

show errors package body md_lookup_executor_pkg;
