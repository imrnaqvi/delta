create or replace package md_rule_executor_pkg as
  /**
   * MD_RULE_EXECUTOR_PKG
   *
   * High-level PL/SQL package for rule execution and target value persistence.
   * Handles selective rule execution, computed value storage, and audit logging.
   *
   * Core Responsibilities:
   *   1. Dispatch rule execution by rule_type (EXPRESSION, LOOKUP, COLUMN_TO_ROW, PLSQL_FUNC)
   *   2. Execute selected rules for a specific md_run
   *   3. Persist computed values to md_run_target_value with idempotency
   *   4. Log impact traces (source → rule → target lineage)
   *   5. Rollup run status (SUCCEEDED, FAILED, PARTIAL)
   *
   * Dependencies:
  *   - md_rule_selector_pkg: dynamic rule selection + persistence into md_run_selected_rule
  *   - md_source_context_resolver_pkg: resolves cross-entity source context snapshots
   *   - md_expr_executor_pkg: EXPRESSION rule execution
   *   - md_lookup_executor_pkg: LOOKUP rule execution
   *   - md_column_to_row_executor_pkg: COLUMN_TO_ROW rule execution
   *   - md_plsql_func_executor_pkg: PLSQL_FUNC rule execution
   */

  -- ===== TYPE DEFINITIONS =====

  type computed_value_rec is record (
    computed_value_txt   varchar2(4000),
    computed_value_json  clob,
    value_data_type      varchar2(128),
    value_status         varchar2(20),  -- COMPUTED, APPLIED, SKIPPED, FAILED
    failure_reason       varchar2(4000)
  );

  type run_metrics_rec is record (
    rules_selected       number,
    rules_executed       number,
    values_computed      number,
    values_failed        number,
    values_skipped       number
  );

  type run_result_rec is record (
    run_id               number,
    run_status           varchar2(20),   -- RUNNING, SUCCEEDED, FAILED, PARTIAL
    metrics              run_metrics_rec,
    error_messages       sys.odcivarchar2list
  );

  -- ===== PUBLIC PROCEDURES =====

  /**
   * Execute all selected rules for a specific md_run.
   *
   * @param p_run_id         md_run.run_id
   * @param p_change_event_id md_change_event.change_event_id
   * @param p_tenant_id      md_run.tenant_id
   * @param p_context_id     md_run.context_id
   * @return run_result_rec  Execution results and metrics
   */
  function execute_run(
    p_run_id          in number,
    p_change_event_id in number,
    p_tenant_id       in varchar2,
    p_context_id      in varchar2,
    p_params_json     in clob default null
  ) return run_result_rec;

  /**
   * Execute a single rule (for testing or manual invocation).
   *
   * @param p_rule_id        md_rule.rule_id
   * @param p_tenant_id      md_rule.tenant_id
   * @param p_context_id     md_rule.context_id
   * @param p_source_values  Source column values as JSON object
   * @return computed_value_rec  Computed value result
   */
  function execute_rule(
    p_rule_id       in number,
    p_tenant_id     in varchar2,
    p_context_id    in varchar2,
    p_source_values in clob
  ) return computed_value_rec;

  /**
   * Persist computed value to md_run_target_value with idempotency check.
   *
   * @param p_run_id             md_run_target_value.run_id
   * @param p_rule_id            md_run_target_value.rule_id
   * @param p_target_column_name md_run_target_value.target_column_name
   * @param p_computed_value     ComputedValue result
   * @param p_tenant_id          md_run_target_value.tenant_id
   * @param p_context_id         md_run_target_value.context_id
   */
  procedure persist_target_value(
    p_run_id             in number,
    p_rule_id            in number,
    p_target_column_name in varchar2,
    p_computed_value     in computed_value_rec,
    p_tenant_id          in varchar2,
    p_context_id         in varchar2
  );

  /**
   * Log impact trace (source → rule → target lineage).
   *
   * @param p_run_id        md_impact_trace.run_id
   * @param p_rule_id       md_impact_trace.rule_id
   * @param p_source_json   Source values as JSON
   * @param p_tenant_id     md_impact_trace.tenant_id
   * @param p_context_id    md_impact_trace.context_id
   */
  procedure log_impact_trace(
    p_run_id      in number,
    p_rule_id     in number,
    p_source_json in clob,
    p_tenant_id   in varchar2,
    p_context_id  in varchar2
  );

  /**
   * Update md_run status based on execution results.
   *
   * @param p_run_id      md_run.run_id
   * @param p_status      New status (SUCCEEDED, FAILED, PARTIAL)
   * @param p_tenant_id   md_run.tenant_id
   * @param p_context_id  md_run.context_id
   */
  procedure update_run_status(
    p_run_id      in number,
    p_status      in varchar2,
    p_tenant_id   in varchar2,
    p_context_id  in varchar2
  );

  /**
   * Generate fingerprint for idempotency.
   *
   * @param p_run_id             md_run_target_value.run_id
   * @param p_rule_id            md_rule.rule_id
   * @param p_target_column_name Column name
   * @param p_value              Computed value
   * @return Fingerprint string (e.g., SHA-1 hex)
   */
  function generate_fingerprint(
    p_run_id             in number,
    p_rule_id            in number,
    p_target_column_name in varchar2,
    p_value              in varchar2
  ) return varchar2;

end md_rule_executor_pkg;
/

show errors package md_rule_executor_pkg;
