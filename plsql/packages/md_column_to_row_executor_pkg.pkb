create or replace package body md_column_to_row_executor_pkg as

  function execute_column_to_row(
    p_rule_payload  in clob,
    p_source_values in clob
  ) return computed_value_rec is
    l_result           computed_value_rec;
    l_payload_obj      json_object_t;
    l_source_obj       json_object_t;
    l_source_table     varchar2(128);
    l_pk_columns       json_array_t;
    l_row_filters      json_array_t;
    l_pivot_column     varchar2(128);
    l_value_column     varchar2(128);
    l_sql              varchar2(32767);
    l_where_clause     varchar2(32767) := '';
    l_cur              integer;
    l_rc               integer;
    l_attr_name        varchar2(4000);
    l_attr_value       varchar2(4000);
    l_result_json      json_object_t;
    l_filter_obj       json_object_t;
    l_filter_attr      varchar2(4000);
    l_filter_target    varchar2(4000);
    l_target_name      varchar2(4000);
    l_filter_count     pls_integer := 0;
    l_idx              pls_integer := 0;
    type map_t is table of varchar2(4000) index by varchar2(4000);
    l_attr_to_target   map_t;

    function clean_identifier(p_value in varchar2) return varchar2 is
    begin
      if p_value is null or not regexp_like(p_value, '^[A-Za-z][A-Za-z0-9_$#\.]*$') then
        raise_application_error(-20041, 'Invalid identifier: ' || nvl(p_value, '<null>'));
      end if;
      return p_value;
    end clean_identifier;
  begin
    l_payload_obj := json_object_t.parse(p_rule_payload);
    l_source_obj := json_object_t.parse(p_source_values);

    l_source_table := clean_identifier(l_payload_obj.get_string('source_table'));
    l_pivot_column := clean_identifier(l_payload_obj.get_string('pivot_column'));
    l_value_column := clean_identifier(l_payload_obj.get_string('value_column'));
    l_pk_columns := l_payload_obj.get_array('pk_columns');
    l_row_filters := l_payload_obj.get_array('row_filters');

    if l_pk_columns is null or l_pk_columns.get_size = 0 then
      l_result.value_status := 'FAILED';
      l_result.failure_reason := 'Payload missing required field: pk_columns';
      return l_result;
    end if;

    for i in 0 .. l_pk_columns.get_size - 1 loop
      if i > 0 then
        l_where_clause := l_where_clause || ' and ';
      end if;
      l_where_clause := l_where_clause || clean_identifier(l_pk_columns.get_string(i)) || ' = :b' || (i + 1);
    end loop;

    if l_row_filters is not null and l_row_filters.get_size > 0 then
      l_filter_count := l_row_filters.get_size;
      l_where_clause := l_where_clause || ' and ' || l_pivot_column || ' in (';
      for i in 1 .. l_filter_count loop
        if i > 1 then
          l_where_clause := l_where_clause || ', ';
        end if;
        l_where_clause := l_where_clause || ':b' || (l_pk_columns.get_size + i);

        l_filter_obj := treat(l_row_filters.get(i - 1) as json_object_t);
        l_filter_attr := l_filter_obj.get_string('attr_name');
        l_filter_target := nvl(l_filter_obj.get_string('target_column'), l_filter_attr);
        l_attr_to_target(l_filter_attr) := l_filter_target;
      end loop;
      l_where_clause := l_where_clause || ')';
    end if;

    l_sql := 'select ' || l_pivot_column || ', ' || l_value_column ||
             ' from ' || l_source_table || ' where ' || l_where_clause;

    l_cur := dbms_sql.open_cursor;
    dbms_sql.parse(l_cur, l_sql, dbms_sql.native);

    for i in 0 .. l_pk_columns.get_size - 1 loop
      dbms_sql.bind_variable(
        l_cur,
        ':b' || (i + 1),
        l_source_obj.get_string(l_pk_columns.get_string(i))
      );
    end loop;

    if l_filter_count > 0 then
      for i in 1 .. l_filter_count loop
        l_filter_obj := treat(l_row_filters.get(i - 1) as json_object_t);
        dbms_sql.bind_variable(l_cur, ':b' || (l_pk_columns.get_size + i), l_filter_obj.get_string('attr_name'));
      end loop;
    end if;

    dbms_sql.define_column(l_cur, 1, l_attr_name, 4000);
    dbms_sql.define_column(l_cur, 2, l_attr_value, 4000);

    l_rc := dbms_sql.execute(l_cur);
    l_result_json := json_object_t();

    while dbms_sql.fetch_rows(l_cur) > 0 loop
      dbms_sql.column_value(l_cur, 1, l_attr_name);
      dbms_sql.column_value(l_cur, 2, l_attr_value);

      if l_attr_to_target.exists(l_attr_name) then
        l_target_name := l_attr_to_target(l_attr_name);
      else
        l_target_name := l_attr_name;
      end if;

      l_result_json.put(l_target_name, l_attr_value);
    end loop;

    dbms_sql.close_cursor(l_cur);

    l_result.computed_value_json := l_result_json.to_clob;
    l_result.computed_value_txt := l_result_json.to_string;
    l_result.value_data_type := 'JSON';
    l_result.value_status := 'COMPUTED';

    return l_result;
  exception
    when others then
      if dbms_sql.is_open(l_cur) then
        dbms_sql.close_cursor(l_cur);
      end if;
      l_result.value_status := 'FAILED';
      l_result.failure_reason := 'Column-to-row execution failed: ' || sqlerrm;
      return l_result;
  end execute_column_to_row;

end md_column_to_row_executor_pkg;
/

show errors package body md_column_to_row_executor_pkg;
