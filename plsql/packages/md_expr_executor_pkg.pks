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
   *
   * Execution:
   *   1. Extract "expr" from rule_payload JSON
   *   2. Substitute SRC.COL references with actual source values
   *   3. Evaluate expression via SQL or PL/SQL
   *   4. Return computed value
   */

  type computed_value_rec is record (
    computed_value_txt   varchar2(4000),
    computed_value_json  clob,
    value_data_type      varchar2(128),
    value_status         varchar2(20),
    failure_reason       varchar2(4000)
  );

  /**
   * Execute EXPRESSION rule.
   *
   * @param p_rule_payload rule_payload JSON with "expr" field
   * @param p_source_values Source column values as JSON object
   * @return computed_value_rec
   */
  function execute_expression(
    p_rule_payload  in clob,
    p_source_values in clob
  ) return computed_value_rec;

end md_expr_executor_pkg;
/

show errors package md_expr_executor_pkg;
