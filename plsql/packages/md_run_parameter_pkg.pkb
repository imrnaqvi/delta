create or replace package body md_run_parameter_pkg as

  function load_run_parameters(
    p_run_id      in number,
    p_tenant_id   in varchar2,
    p_context_id  in varchar2
  ) return clob is
    l_params_json clob;
  begin
    select json_objectagg(
             param_name value param_value_txt
             returning clob
           )
      into l_params_json
      from md_run_parameter
     where run_id = p_run_id
       and tenant_id = p_tenant_id
       and context_id = p_context_id;

    return nvl(l_params_json, '{}');
  exception
    when no_data_found then
      return '{}';
  end load_run_parameters;

  procedure persist_run_parameters(
    p_run_id      in number,
    p_tenant_id   in varchar2,
    p_context_id  in varchar2,
    p_params_json in clob
  ) is
    l_obj       json_object_t;
    l_keys      json_key_list;
    l_key       varchar2(4000);
    l_elem      json_element_t;
    l_value     varchar2(4000);
    l_type      varchar2(128);
    l_snapshot  clob;
    l_hash      varchar2(200);
  begin
    delete from md_run_parameter
     where run_id = p_run_id
       and tenant_id = p_tenant_id
       and context_id = p_context_id;

    if p_params_json is null then
      l_snapshot := '{}';
      l_hash := to_char(dbms_utility.get_hash_value(l_snapshot, 0, 2147483647));
    else
      l_obj := json_object_t.parse(p_params_json);
      l_keys := l_obj.get_keys;

      for i in 1 .. l_keys.count loop
        l_key := l_keys(i);
        l_elem := l_obj.get(l_key);

        if l_elem is null or l_elem.is_null then
          l_value := null;
          l_type := 'NULL';
        elsif l_elem.is_string then
          l_value := l_obj.get_string(l_key);
          l_type := 'VARCHAR2';
        elsif l_elem.is_number then
          l_value := to_char(l_obj.get_number(l_key));
          l_type := 'NUMBER';
        elsif l_elem.is_boolean then
          if l_obj.get_boolean(l_key) then
            l_value := 'Y';
          else
            l_value := 'N';
          end if;
          l_type := 'BOOLEAN';
        else
          l_value := l_elem.to_clob;
          l_type := 'JSON';
        end if;

        insert into md_run_parameter (
          run_parameter_id,
          tenant_id,
          context_id,
          run_id,
          param_name,
          param_value_txt,
          param_data_type,
          created_at
        ) values (
          md_run_parameter_seq.nextval,
          p_tenant_id,
          p_context_id,
          p_run_id,
          l_key,
          l_value,
          l_type,
          systimestamp
        );
      end loop;

      l_snapshot := p_params_json;
      l_hash := to_char(dbms_utility.get_hash_value(l_snapshot, 0, 2147483647));
    end if;

    merge into md_run_parameter_snapshot tgt
    using (
      select p_tenant_id as tenant_id,
             p_context_id as context_id,
             p_run_id as run_id,
             l_snapshot as parameter_json,
             l_hash as parameter_hash
        from dual
    ) src
       on (
          tgt.tenant_id = src.tenant_id
      and tgt.context_id = src.context_id
      and tgt.run_id = src.run_id
       )
     when matched then
       update set
         tgt.parameter_json = src.parameter_json,
         tgt.parameter_hash = src.parameter_hash,
         tgt.captured_at = systimestamp
     when not matched then
       insert (
         run_parameter_snapshot_id,
         tenant_id,
         context_id,
         run_id,
         parameter_json,
         parameter_hash,
         captured_at
       ) values (
         md_run_parameter_snapshot_seq.nextval,
         src.tenant_id,
         src.context_id,
         src.run_id,
         src.parameter_json,
         src.parameter_hash,
         systimestamp
       );
  end persist_run_parameters;

  function get_parameter_value(
    p_params_json in clob,
    p_param_name  in varchar2
  ) return varchar2 is
    l_obj json_object_t;
    l_elem json_element_t;
  begin
    if p_params_json is null then
      return null;
    end if;

    l_obj := json_object_t.parse(p_params_json);
    l_elem := l_obj.get(p_param_name);

    if l_elem is null or l_elem.is_null then
      return null;
    elsif l_elem.is_string then
      return l_obj.get_string(p_param_name);
    elsif l_elem.is_number then
      return to_char(l_obj.get_number(p_param_name));
    elsif l_elem.is_boolean then
      if l_obj.get_boolean(p_param_name) then
        return 'Y';
      else
        return 'N';
      end if;
    else
      return l_elem.to_clob;
    end if;
  exception
    when others then
      return null;
  end get_parameter_value;

  procedure validate_required_parameters(
    p_run_id      in number,
    p_rule_id     in number,
    p_tenant_id   in varchar2,
    p_context_id  in varchar2,
    p_params_json in clob
  ) is
    l_params_json clob;
    l_obj         json_object_t;
    l_dummy       json_element_t;
    l_missing     varchar2(4000);
  begin
    l_params_json := nvl(p_params_json, load_run_parameters(p_run_id, p_tenant_id, p_context_id));
    l_obj := json_object_t.parse(nvl(l_params_json, '{}'));

    for req in (
      select param_name, default_value_txt
        from md_rule_parameter_requirement
       where rule_id = p_rule_id
         and tenant_id = p_tenant_id
         and context_id = p_context_id
         and required_flag = 'Y'
       order by param_name
    ) loop
      begin
        l_dummy := l_obj.get(req.param_name);
      exception
        when others then
          l_dummy := null;
      end;

      if l_dummy is null or l_dummy.is_null then
        if l_missing is null then
          l_missing := req.param_name;
        else
          l_missing := l_missing || ', ' || req.param_name;
        end if;
      end if;
    end loop;

    if l_missing is not null then
      raise_application_error(-20111, 'Missing required runtime parameter(s) for rule_id=' || p_rule_id || ': ' || l_missing);
    end if;
  end validate_required_parameters;

end md_run_parameter_pkg;
/

show errors package body md_run_parameter_pkg;
