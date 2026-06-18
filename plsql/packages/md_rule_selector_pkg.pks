create or replace package md_rule_selector_pkg as
  /**
   * MD_RULE_SELECTOR_PKG
   *
   * Computes selected rules dynamically for a run/change_event and persists them
   * into MD_RUN_SELECTED_RULE as the execution contract.
   */

  procedure populate_selected_rules(
    p_run_id          in number,
    p_change_event_id in number,
    p_tenant_id       in varchar2,
    p_context_id      in varchar2,
    p_purge_existing  in varchar2 default 'Y'
  );

end md_rule_selector_pkg;
/

show errors package md_rule_selector_pkg;
