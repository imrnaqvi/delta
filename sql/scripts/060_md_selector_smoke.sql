-- 060_md_selector_smoke.sql
-- Smoke test for selector persistence.
-- Calls md_rule_selector_pkg.populate_selected_rules directly and prints counts.

set serveroutput on

prompt Running selector smoke test...

declare
  l_tenant_id         varchar2(64) := 'TENANT_DEMO';
  l_context_id        varchar2(64) := 'CTX_DEMO';
  l_change_event_id   number;
  l_run_id            number;
  l_direct_count      number;
  l_transitive_count  number;
  l_total_count       number;
  l_gate_not_eval_count number;
  l_gate_other_count    number;
  l_gate_msg_count      number;
  l_gate_ts_count       number;
begin
  select evt.change_event_id
    into l_change_event_id
    from md_change_event evt
   where evt.tenant_id = l_tenant_id
     and evt.context_id = l_context_id
     and evt.event_fingerprint = 'EVT_FP_001';

  select rn.run_id
    into l_run_id
    from md_run rn
   where rn.tenant_id = l_tenant_id
     and rn.context_id = l_context_id
     and rn.initiated_by = 'seed_script'
     and rn.run_mode = 'SELECTIVE'
   order by rn.run_id desc
   fetch first 1 row only;

  md_rule_selector_pkg.populate_selected_rules(
    p_run_id          => l_run_id,
    p_change_event_id => l_change_event_id,
    p_tenant_id       => l_tenant_id,
    p_context_id      => l_context_id,
    p_purge_existing  => 'Y'
  );

  select count(*)
    into l_direct_count
    from md_run_selected_rule s
   where s.run_id = l_run_id
     and s.change_event_id = l_change_event_id
     and s.tenant_id = l_tenant_id
     and s.context_id = l_context_id
     and s.selection_reason = 'DIRECT_COLUMN_LINK';

  select count(*)
    into l_transitive_count
    from md_run_selected_rule s
   where s.run_id = l_run_id
     and s.change_event_id = l_change_event_id
     and s.tenant_id = l_tenant_id
     and s.context_id = l_context_id
     and s.selection_reason = 'TRANSITIVE_DEPENDENCY';

  l_total_count := l_direct_count + l_transitive_count;

  select count(*)
    into l_gate_not_eval_count
    from md_run_selected_rule s
   where s.run_id = l_run_id
     and s.change_event_id = l_change_event_id
     and s.tenant_id = l_tenant_id
     and s.context_id = l_context_id
     and s.gate_eval_status = 'NOT_EVALUATED';

  select count(*)
    into l_gate_other_count
    from md_run_selected_rule s
   where s.run_id = l_run_id
     and s.change_event_id = l_change_event_id
     and s.tenant_id = l_tenant_id
     and s.context_id = l_context_id
     and s.gate_eval_status <> 'NOT_EVALUATED';

  select count(*)
    into l_gate_msg_count
    from md_run_selected_rule s
   where s.run_id = l_run_id
     and s.change_event_id = l_change_event_id
     and s.tenant_id = l_tenant_id
     and s.context_id = l_context_id
     and s.gate_eval_message is not null;

  select count(*)
    into l_gate_ts_count
    from md_run_selected_rule s
   where s.run_id = l_run_id
     and s.change_event_id = l_change_event_id
     and s.tenant_id = l_tenant_id
     and s.context_id = l_context_id
     and s.gate_evaluated_at is not null;

  dbms_output.put_line('selector_smoke run_id=' || l_run_id || ' change_event_id=' || l_change_event_id);
  dbms_output.put_line('direct_count=' || l_direct_count);
  dbms_output.put_line('transitive_count=' || l_transitive_count);
  dbms_output.put_line('total_count=' || l_total_count);
  dbms_output.put_line('gate_not_evaluated_count=' || l_gate_not_eval_count);
  dbms_output.put_line('gate_other_status_count=' || l_gate_other_count);

  if l_gate_not_eval_count <> l_total_count
     or l_gate_other_count <> 0
     or l_gate_msg_count <> 0
     or l_gate_ts_count <> 0 then
    raise_application_error(-20620, 'Selector smoke failed: gate columns were mutated before execution.');
  end if;

  rollback;
exception
  when no_data_found then
    dbms_output.put_line('selector_smoke skipped: demo run/event not found; execute 015_md_seed_sample.sql first.');
    rollback;
end;
/

prompt Selector smoke test complete.
