-- 029_md_output_expr_eval_upgrade.sql
-- Add md_rule output-level evaluation policy for expression outputs.

set serveroutput on

prompt Applying output expression evaluation policy upgrade...

declare
  l_count number;
begin
  select count(*)
    into l_count
    from user_tab_columns
   where table_name = 'MD_RULE'
     and column_name = 'OUTPUT_EVAL_FAILURE_POLICY';

  if l_count = 0 then
    execute immediate q'[alter table md_rule add (output_eval_failure_policy varchar2(20) default 'CONTINUE' not null)]';
  end if;

  select count(*)
    into l_count
    from user_constraints
   where constraint_name = 'MD_RULE_OUTPUT_FAIL_POLICY_CK';

  if l_count = 0 then
    execute immediate q'[alter table md_rule add constraint md_rule_output_fail_policy_ck check (output_eval_failure_policy in ('CONTINUE','FAIL_RULE'))]';
  end if;
end;
/

prompt Output expression evaluation policy upgrade complete.
