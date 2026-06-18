create or replace package md_plsql_func_executor_pkg as
  /**
   * MD_PLSQL_FUNC_EXECUTOR_PKG
   *
   * Executes PLSQL_FUNC rules: invokes stored PL/SQL functions/procedures.
   *
   * Payload example:
   *   {
   *     "function_owner": "APP",
   *     "function_name": "FN_COMPUTE_SECURITY_VALUE",
   *     "params": ["SRC.SECURITY_ID", "SRC.ISSUER_ID"],
   *     "return_type": "VARCHAR2"
   *   }
   *
   * Execution:
   *   1. Parse payload for function_owner, function_name, params, return_type
   *   2. Build dynamic CALL statement: {? = CALL owner.function(?, ?)}
   *   3. Bind input parameters from source_values
   *   4. Execute and capture return value
   */

  type computed_value_rec is record (
    computed_value_txt   varchar2(4000),
    computed_value_json  clob,
    value_data_type      varchar2(128),
    value_status         varchar2(20),
    failure_reason       varchar2(4000)
  );

  /**
   * Execute PLSQL_FUNC rule.
   *
   * @param p_rule_payload rule_payload JSON with function_owner, function_name, params, return_type
   * @param p_source_values Source column values as JSON object
   * @return computed_value_rec
   */
  function execute_plsql_func(
    p_rule_payload  in clob,
    p_source_values in clob
  ) return computed_value_rec;

end md_plsql_func_executor_pkg;
/

show errors package md_plsql_func_executor_pkg;
