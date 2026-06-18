create or replace package md_run_parameter_pkg as
  /**
   * MD_RUN_PARAMETER_PKG
   *
   * Loads, validates, and persists runtime parameters for a run.
   */

  function load_run_parameters(
    p_run_id      in number,
    p_tenant_id   in varchar2,
    p_context_id  in varchar2
  ) return clob;

  procedure persist_run_parameters(
    p_run_id      in number,
    p_tenant_id   in varchar2,
    p_context_id  in varchar2,
    p_params_json in clob
  );

  function get_parameter_value(
    p_params_json in clob,
    p_param_name  in varchar2
  ) return varchar2;

  procedure validate_required_parameters(
    p_run_id      in number,
    p_rule_id     in number,
    p_tenant_id   in varchar2,
    p_context_id  in varchar2,
    p_params_json in clob
  );

end md_run_parameter_pkg;
/

show errors package md_run_parameter_pkg;
