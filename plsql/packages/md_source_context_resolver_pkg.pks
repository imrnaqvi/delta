create or replace package md_source_context_resolver_pkg as
  /**
   * MD_SOURCE_CONTEXT_RESOLVER_PKG
   *
   * Resolves joined source context for a rule/run/change-event and persists
   * a snapshot in md_run_source_snapshot for deterministic execution.
   */

  function resolve_rule_source_values(
    p_run_id          in number,
    p_change_event_id in number,
    p_rule_id         in number,
    p_tenant_id       in varchar2,
    p_context_id      in varchar2,
    p_params_json     in clob default null
  ) return clob;

end md_source_context_resolver_pkg;
/

show errors package md_source_context_resolver_pkg;
