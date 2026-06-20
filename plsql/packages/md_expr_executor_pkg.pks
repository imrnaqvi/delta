create or replace package md_expr_executor_pkg as
  /**
   * MD_EXPR_EXECUTOR_PKG
   *
   * Executes EXPRESSION rules: simple value transformations.
   *
   * Payload example:
   *   {"expr":"SRC.SECURITY_ID"}
   *   {"expr":"SRC.QUANTITY * SRC.UNIT_PRICE"}
   *   {"expr":"SRC.FIRST_NAME || ' ' || SRC.LAST_NAME"}
    *   {"expr":"round(PARAM.X + 1)","allowed_functions":["ROUND"],"disallow_subqueries":true}
   *
   * Execution:
   *   1. Extract "expr" from rule_payload JSON
   *   2. Substitute SRC.COL references with actual source values
    *   3. Validate blocked keywords/tokens and optional allowed function list
    *   4. If payload allowlist is missing, optionally load allowed functions from metadata registry
    *   5. Evaluate expression via SQL or PL/SQL
    *   6. Return computed value
   */

  type computed_value_rec is record (
    computed_value_txt   varchar2(4000),
    computed_value_json  clob,
    value_data_type      varchar2(128),
    value_status         varchar2(20),
    failure_reason       varchar2(4000)
  );

  /**
   * Evaluate a single expression string using SRC/PARAM substitution and
   * registry-governed function guardrails.
   *
   * @param p_expr Expression text to evaluate
   * @param p_source_values Source column values as JSON object
   * @param p_params_json Runtime parameters as JSON object (PARAM.*)
   * @param p_tenant_id Optional tenant scope for registry allowlist
   * @param p_context_id Optional context scope for registry allowlist
   * @return computed_value_rec
   */
  function evaluate_expr(
    p_expr          in varchar2,
    p_source_values in clob,
    p_params_json   in clob default null,
    p_tenant_id     in varchar2 default null,
    p_context_id    in varchar2 default null
  ) return computed_value_rec;

  /**
   * Execute EXPRESSION rule.
   *
   * @param p_rule_payload rule_payload JSON with "expr" field
   * @param p_source_values Source column values as JSON object
   * @param p_params_json Runtime parameters as JSON object (PARAM.*)
   * @param p_tenant_id Optional tenant scope for metadata function governance
   * @param p_context_id Optional context scope for metadata function governance
   * @return computed_value_rec
   */
  function execute_expression(
    p_rule_payload  in clob,
    p_source_values in clob,
    p_params_json   in clob default null,
    p_tenant_id     in varchar2 default null,
    p_context_id    in varchar2 default null
  ) return computed_value_rec;

end md_expr_executor_pkg;
/

show errors package md_expr_executor_pkg;
