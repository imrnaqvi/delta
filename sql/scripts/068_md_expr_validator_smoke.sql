-- 068_md_expr_validator_smoke.sql
-- Smoke test for EXPRESSION validator guardrails.
-- Verifies blocked keyword rejection and allowed function enforcement.

set serveroutput on

prompt Running expression validator smoke test...

declare
  l_ok_result        md_expr_executor_pkg.computed_value_rec;
  l_blocked_result   md_expr_executor_pkg.computed_value_rec;
  l_disallowed_result md_expr_executor_pkg.computed_value_rec;
begin
  delete from md_expr_allowed_function
   where tenant_id = 'TENANT_EXPR_VALID_SMOKE'
     and context_id = 'CTX_EXPR_VALID_SMOKE';

  insert into md_expr_allowed_function (
    expr_allowed_function_id,
    tenant_id,
    context_id,
    function_name,
    active_flag,
    created_by
  ) values (
    md_expr_allowed_function_seq.nextval,
    'TENANT_EXPR_VALID_SMOKE',
    'CTX_EXPR_VALID_SMOKE',
    'ROUND',
    'Y',
    'smoke_068'
  );

  l_ok_result := md_expr_executor_pkg.execute_expression(
    p_rule_payload  => '{"expr":"round(PARAM.X + 1)","disallow_subqueries":true}',
    p_source_values => '{}',
    p_params_json   => '{"X":2}',
    p_tenant_id     => 'TENANT_EXPR_VALID_SMOKE',
    p_context_id    => 'CTX_EXPR_VALID_SMOKE'
  );

  dbms_output.put_line('ok_status=' || l_ok_result.value_status);
  dbms_output.put_line('ok_value=' || nvl(l_ok_result.computed_value_txt, '<null>'));

  if l_ok_result.value_status <> 'COMPUTED' or nvl(l_ok_result.computed_value_txt, 'NULL') <> '3' then
    raise_application_error(-20801, 'Expected COMPUTED=3 for allowlisted ROUND expression');
  end if;

  l_blocked_result := md_expr_executor_pkg.execute_expression(
    p_rule_payload  => '{"expr":"(select 1 from dual)","disallow_subqueries":true}',
    p_source_values => '{}',
    p_params_json   => '{}',
    p_tenant_id     => 'TENANT_EXPR_VALID_SMOKE',
    p_context_id    => 'CTX_EXPR_VALID_SMOKE'
  );

  dbms_output.put_line('blocked_status=' || l_blocked_result.value_status);
  dbms_output.put_line('blocked_reason=' || nvl(l_blocked_result.failure_reason, '<null>'));

  if l_blocked_result.value_status <> 'FAILED'
     or instr(nvl(l_blocked_result.failure_reason, ' '), 'Expression validation failed:') = 0 then
    raise_application_error(-20802, 'Expected FAILED validation for blocked keyword expression');
  end if;

  l_disallowed_result := md_expr_executor_pkg.execute_expression(
    p_rule_payload  => '{"expr":"abs(PARAM.X)","allowed_functions":["ROUND"],"disallow_subqueries":true}',
    p_source_values => '{}',
    p_params_json   => '{"X":2}',
    p_tenant_id     => 'TENANT_EXPR_VALID_SMOKE',
    p_context_id    => 'CTX_EXPR_VALID_SMOKE'
  );

  dbms_output.put_line('disallowed_status=' || l_disallowed_result.value_status);
  dbms_output.put_line('disallowed_reason=' || nvl(l_disallowed_result.failure_reason, '<null>'));

  if l_disallowed_result.value_status <> 'FAILED'
     or instr(nvl(l_disallowed_result.failure_reason, ' '), 'Function not allowed: ABS') = 0 then
    raise_application_error(-20803, 'Expected FAILED validation for disallowed function ABS');
  end if;

  delete from md_expr_allowed_function
   where tenant_id = 'TENANT_EXPR_VALID_SMOKE'
     and context_id = 'CTX_EXPR_VALID_SMOKE';

  dbms_output.put_line('expr_validator_smoke PASSED');
exception
  when others then
    delete from md_expr_allowed_function
     where tenant_id = 'TENANT_EXPR_VALID_SMOKE'
       and context_id = 'CTX_EXPR_VALID_SMOKE';
    dbms_output.put_line('expr_validator_smoke FAILED: ' || sqlerrm);
    raise;
end;
/

prompt Expression validator smoke test complete.
