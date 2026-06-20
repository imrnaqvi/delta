-- 069_md_expr_function_registry_smoke.sql
-- Smoke test for optional metadata registry-based function governance.

set serveroutput on

prompt Running expression function registry smoke test...

declare
  l_ok_registry      md_expr_executor_pkg.computed_value_rec;
  l_fail_registry    md_expr_executor_pkg.computed_value_rec;
  l_fail_override    md_expr_executor_pkg.computed_value_rec;
  l_ok_optional      md_expr_executor_pkg.computed_value_rec;
begin
  delete from md_expr_allowed_function
   where tenant_id in ('TENANT_EXPR_GOV_SMOKE', 'TENANT_EXPR_GOV_NONE')
     and context_id in ('CTX_EXPR_GOV_SMOKE', 'CTX_EXPR_GOV_NONE');

  insert into md_expr_allowed_function (
    tenant_id,
    context_id,
    function_name,
    active_flag,
    created_by
  ) values (
    'TENANT_EXPR_GOV_SMOKE',
    'CTX_EXPR_GOV_SMOKE',
    'ROUND',
    'Y',
    'smoke_069'
  );

  l_ok_registry := md_expr_executor_pkg.execute_expression(
    p_rule_payload  => '{"expr":"round(PARAM.X + 1)","disallow_subqueries":true}',
    p_source_values => '{}',
    p_params_json   => '{"X":2}',
    p_tenant_id     => 'TENANT_EXPR_GOV_SMOKE',
    p_context_id    => 'CTX_EXPR_GOV_SMOKE'
  );

  dbms_output.put_line('ok_registry_status=' || l_ok_registry.value_status);
  dbms_output.put_line('ok_registry_value=' || nvl(l_ok_registry.computed_value_txt, '<null>'));

  if l_ok_registry.value_status <> 'COMPUTED' or nvl(l_ok_registry.computed_value_txt, 'NULL') <> '3' then
    raise_application_error(-20901, 'Expected COMPUTED=3 for registry-allowed ROUND expression');
  end if;

  l_fail_registry := md_expr_executor_pkg.execute_expression(
    p_rule_payload  => '{"expr":"abs(PARAM.X)","disallow_subqueries":true}',
    p_source_values => '{}',
    p_params_json   => '{"X":2}',
    p_tenant_id     => 'TENANT_EXPR_GOV_SMOKE',
    p_context_id    => 'CTX_EXPR_GOV_SMOKE'
  );

  dbms_output.put_line('fail_registry_status=' || l_fail_registry.value_status);
  dbms_output.put_line('fail_registry_reason=' || nvl(l_fail_registry.failure_reason, '<null>'));

  if l_fail_registry.value_status <> 'FAILED'
     or instr(nvl(l_fail_registry.failure_reason, ' '), 'Function not allowed: ABS') = 0 then
    raise_application_error(-20902, 'Expected ABS to be blocked by metadata registry');
  end if;

  l_fail_override := md_expr_executor_pkg.execute_expression(
    p_rule_payload  => '{"expr":"abs(PARAM.X)","allowed_functions":["ABS"],"disallow_subqueries":true}',
    p_source_values => '{}',
    p_params_json   => '{"X":2}',
    p_tenant_id     => 'TENANT_EXPR_GOV_SMOKE',
    p_context_id    => 'CTX_EXPR_GOV_SMOKE'
  );

  dbms_output.put_line('fail_override_status=' || l_fail_override.value_status);
  dbms_output.put_line('fail_override_reason=' || nvl(l_fail_override.failure_reason, '<null>'));

  if l_fail_override.value_status <> 'FAILED'
     or instr(nvl(l_fail_override.failure_reason, ' '), 'Function not allowed: ABS') = 0 then
    raise_application_error(-20903, 'Expected metadata registry to block ABS even when payload allowlist is provided');
  end if;

  l_ok_optional := md_expr_executor_pkg.execute_expression(
    p_rule_payload  => '{"expr":"abs(PARAM.X)","disallow_subqueries":true}',
    p_source_values => '{}',
    p_params_json   => '{"X":2}',
    p_tenant_id     => 'TENANT_EXPR_GOV_NONE',
    p_context_id    => 'CTX_EXPR_GOV_NONE'
  );

  dbms_output.put_line('ok_optional_status=' || l_ok_optional.value_status);
  dbms_output.put_line('ok_optional_value=' || nvl(l_ok_optional.computed_value_txt, '<null>'));

  if l_ok_optional.value_status <> 'COMPUTED' or nvl(l_ok_optional.computed_value_txt, 'NULL') <> '2' then
    raise_application_error(-20904, 'Expected governance to remain optional with no registry rows');
  end if;

  dbms_output.put_line('expr_function_registry_smoke PASSED');
exception
  when others then
    dbms_output.put_line('expr_function_registry_smoke FAILED: ' || sqlerrm);
    raise;
end;
/

prompt Expression function registry smoke test complete.
