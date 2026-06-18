create or replace package md_lookup_executor_pkg as
  /**
   * MD_LOOKUP_EXECUTOR_PKG
   *
   * Executes LOOKUP rules: joins to reference tables and fetches enriched values.
   *
   * Payload example:
   *   {
   *     "lookup_table": "REF_SECURITY_MASTER",
   *     "join_key": {"SRC.SECURITY_ID": "REF_SECURITY_ID"},
   *     "return_columns": ["SECURITY_DESC", "SECURITY_STATUS"],
   *     "return_format": "json_object"
   *   }
   *
   * Execution:
   *   1. Parse payload for lookup_table, join_key, return_columns
   *   2. Build WHERE clause from join_key mapping
   *   3. Execute SELECT with source values
   *   4. Return results in requested format (json_object, semicolon_delimited, single_row)
   */

  type computed_value_rec is record (
    computed_value_txt   varchar2(4000),
    computed_value_json  clob,
    value_data_type      varchar2(128),
    value_status         varchar2(20),
    failure_reason       varchar2(4000)
  );

  /**
   * Execute LOOKUP rule.
   *
   * @param p_rule_payload rule_payload JSON with lookup_table, join_key, return_columns
   * @param p_source_values Source column values as JSON object
   * @return computed_value_rec
   */
  function execute_lookup(
    p_rule_payload  in clob,
    p_source_values in clob
  ) return computed_value_rec;

end md_lookup_executor_pkg;
/

show errors package md_lookup_executor_pkg;
