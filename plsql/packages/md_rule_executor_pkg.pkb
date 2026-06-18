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

  /**
   * Fetch md_rule metadata including rule_payload JSON.
   */
  procedure fetch_rule(
    p_rule_id      in number,
    p_tenant_id    in varchar2,
    p_context_id   in varchar2,
    o_rule_name    out varchar2,
    o_rule_type    out varchar2,
    o_rule_payload out clob
  ) is
  begin
    select rule_name, rule_type, rule_payload
      into o_rule_name, o_rule_type, o_rule_payload
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
    p_source_values in clob
  ) return computed_value_rec is
    l_result computed_value_rec;
  begin
    log_debug('Dispatching rule: rule_id=' || p_rule_id || ', type=' || p_rule_type);

    case p_rule_type
      when 'EXPRESSION' then
        declare
          l_expr_result md_expr_executor_pkg.computed_value_rec;
        begin
          l_expr_result := md_expr_executor_pkg.execute_expression(p_rule_payload, p_source_values);
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
    l_source_values     clob;
    l_computed_value    computed_value_rec;
    l_change_event_id   number;
    l_rule_inputs       clob;
    l_rule_outputs      clob;
    l_output_columns    sys.odcivarchar2list;
    l_row_count         pls_integer;
    l_params_json       clob;

    cursor c_selected_rules is
      select rule_id, transitive_flag
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
        l_source_values := md_source_context_resolver_pkg.resolve_rule_source_values(
          p_run_id          => p_run_id,
          p_change_event_id => l_change_event_id,
          p_rule_id         => l_rule_id,
          p_tenant_id       => p_tenant_id,
          p_context_id      => p_context_id,
          p_params_json     => l_params_json
        );

        -- Fetch rule metadata
        fetch_rule(l_rule_id, p_tenant_id, p_context_id, l_rule_name, l_rule_type, l_rule_payload);
        fetch_rule_inputs(l_rule_id, p_tenant_id, p_context_id, l_rule_inputs);
        fetch_rule_outputs(l_rule_id, p_tenant_id, p_context_id, l_rule_outputs);

        -- Dispatch execution
        l_computed_value := dispatch_rule_execution(
          l_rule_id,
          l_rule_type,
          l_rule_name,
          l_rule_payload,
          l_source_values
        );

        l_result.metrics.rules_executed := l_result.metrics.rules_executed + 1;

        -- Persist results per output column
        if l_rule_outputs is not null then
          for out_rec in (
            select jt.target_column_name
              from json_table(
                     l_rule_outputs,
                     '$[*]'
                     columns (
                       target_column_name varchar2(128) path '$.target_column_name'
                     )
                   ) jt
          ) loop
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
            elsif l_computed_value.value_status = 'SKIPPED' then
              l_result.metrics.values_skipped := l_result.metrics.values_skipped + 1;
            else
              l_result.metrics.values_failed := l_result.metrics.values_failed + 1;
            end if;
          end loop;
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
    l_result       computed_value_rec;
  begin
    fetch_rule(p_rule_id, p_tenant_id, p_context_id, l_rule_name, l_rule_type, l_rule_payload);
    l_result := dispatch_rule_execution(p_rule_id, l_rule_type, l_rule_name, l_rule_payload, p_source_values);
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
