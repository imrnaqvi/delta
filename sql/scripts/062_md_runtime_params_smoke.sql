-- 062_md_runtime_params_smoke.sql
-- Canonical runtime-parameter smoke wrapper.
-- Delegates to the combined early/late driver.

set serveroutput on

prompt Redirecting to canonical combined runtime parameter smoke test...
@c:\Users\imrna\delta\sql\scripts\064_md_runtime_params_smoke_combined.sql

prompt Canonical runtime parameter smoke wrapper complete.
