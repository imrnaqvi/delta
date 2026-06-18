create or replace package md_column_to_row_executor_pkg as
  /**
   * MD_COLUMN_TO_ROW_EXECUTOR_PKG
   *
   * Executes COLUMN_TO_ROW rules: transforms normalized source row(s) into denormalized target row(s).
   *
   * Payload example:
   *   {
   *     "source_table": "SRC_ATTRIBUTES",
   *     "pk_columns": ["ENTITY_ID"],
   *     "pivot_column": "ATTR_NAME",
   *     "value_column": "ATTR_VALUE",
   *     "row_filters": [
   *       {"attr_name": "COLOR", "target_column": "COLOR"},
   *       {"attr_name": "SIZE", "target_column": "SIZE"}
   *     ]
   *   }
   *
   * Execution:
   *   1. Query source_table WHERE pk_columns match
   *   2. Pivot rows by pivot_column, collecting value_column
   *   3. Return as JSON object or flattened structure
   */

  type computed_value_rec is record (
    computed_value_txt   varchar2(4000),
    computed_value_json  clob,
    value_data_type      varchar2(128),
    value_status         varchar2(20),
    failure_reason       varchar2(4000)
  );

  /**
   * Execute COLUMN_TO_ROW rule.
   *
   * @param p_rule_payload rule_payload JSON with source_table, pk_columns, pivot_column, row_filters
   * @param p_source_values Source key values as JSON object
   * @return computed_value_rec
   */
  function execute_column_to_row(
    p_rule_payload  in clob,
    p_source_values in clob
  ) return computed_value_rec;

end md_column_to_row_executor_pkg;
/

show errors package md_column_to_row_executor_pkg;
