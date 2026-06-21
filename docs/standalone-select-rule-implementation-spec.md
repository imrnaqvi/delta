# Standalone SELECT Rule Implementation Spec

## Status
Implemented (v1) and validated by 074 smoke assertions.

## 1) Scope

### In Scope
1. Introduce new rule type SQL_SELECT.
2. Execute complete standalone SELECT from md_rule.rule_payload.sql_query for SQL_SELECT rules.
3. Derive output aliases from result-set columns.
4. Enforce SELECT-only guardrails.
5. Preserve existing downstream runtime behavior:
   1. persist values in md_run_target_value
   2. consolidate winners in md_run_target_consolidation and md_run_target_consolidated_value
   3. execute consolidated actions via execute_consolidated_actions_for_run
6. Add dedicated smoke coverage for SQL_SELECT mode.

### Out Of Scope
1. Redesign source-context resolver for existing rule types.
2. Multi-row expansion semantics in v1.
3. New runtime tables for SQL_SELECT-specific persistence.

## 2) Functional Contract (Executable)
1. md_rule.rule_type accepts SQL_SELECT.
2. For SQL_SELECT, md_rule.rule_payload is JSON and stores query text in sql_query.
3. Query must pass guardrails and execute as query-only dynamic SQL.
4. Query must return exactly one row.
5. Returned column names are output aliases; values become computed outputs.
6. Derived outputs participate in existing target mapping resolution.
7. Rule-level failures follow existing continuation/failure policy behavior in execute_run.

## 3) Guardrails (Implementation Rules)

### 3.1 Allowed
1. SELECT query text.
2. UNION and UNION ALL.
3. SQL functions and analytic/window functions.
4. PL/SQL functions callable in SQL expressions.
5. WITH clause (enabled in v1).

### 3.2 Blocked
1. DML/DDL/privilege verbs at top-level or injected text:
   1. INSERT
   2. UPDATE
   3. DELETE
   4. MERGE
   5. CREATE
   6. ALTER
   7. DROP
   8. TRUNCATE
   9. GRANT
   10. REVOKE
2. PL/SQL block wrappers: BEGIN/DECLARE/END as executable block payload.
3. SQL*Plus directives and statement delimiters in payload.

### 3.3 Validation Behavior
1. Guardrail validation runs before execute immediate.
2. Violations produce rule-level FAILED result with explicit reason text.
3. Validation text should ignore matches inside quoted string literals when feasible.
4. If robust tokenization is deferred, conservative regex scan is acceptable for v1 with explicit residual risk note.

## 4) Metadata Changes

## 4.1 DDL Upgrade Script
Create new script: sql/scripts/036_md_sql_select_rule_upgrade.sql

Required changes:
1. Extend md_rule.rule_type check constraint to include SQL_SELECT.
2. Optional: add comment on md_rule.rule_payload documenting SQL_SELECT payload contract.
3. Optional flags deferred to v2 unless explicitly required.

Proposed skeleton:
```sql
prompt Applying SQL_SELECT rule metadata upgrade...

declare
  v_ck_name user_constraints.constraint_name%type;
begin
  select constraint_name
    into v_ck_name
    from user_constraints
   where table_name = 'MD_RULE'
     and constraint_type = 'C'
     and search_condition_vc like '%RULE_TYPE%';

  execute immediate 'alter table md_rule drop constraint ' || v_ck_name;

  execute immediate q'[
    alter table md_rule add constraint md_rule_type_ck
    check (rule_type in ('EXPRESSION','COLUMN_TO_ROW','LOOKUP','PLSQL_FUNC','SQL_SELECT'))
  ]';
exception
  when no_data_found then
    raise_application_error(-21001, 'MD_RULE type check constraint not found');
end;
/

comment on column md_rule.rule_payload is
  'JSON payload by rule type. For SQL_SELECT: stores query text and options.';
```

## 4.2 Payload Contract (v1)
1. Keep rule_payload as JSON for compatibility.
2. For SQL_SELECT use:
```json
{
  "sql_query": "select ...",
  "enforce_single_row": "Y",
  "enable_token_substitution": "Y"
}
```
3. sql_query is mandatory.

Rationale:
1. Preserves existing JSON check on md_rule.rule_payload.
2. Avoids immediate core-table redesign.

## 5) Runtime Flow Changes

### 5.1 Affected File List
1. plsql/packages/md_rule_executor_pkg.pkb
2. plsql/packages/md_rule_executor_pkg.pks (only if public types/procedures are extended; otherwise no spec change)
3. sql/scripts/036_md_sql_select_rule_upgrade.sql (new)
4. sql/scripts/074_md_sql_select_rule_smoke.sql (new)
5. docs/package-api-reference.md
6. docs/runtime-flow-and-dynamic-sql.md
7. docs/metadata-schema-reference.md
8. docs/change-impact-playbook.md
9. docs/engine-docs-index.md

### 5.2 md_rule_executor_pkg.pkb - Exact Additions

Add body-local record types:
1. t_sql_select_col_rec
   1. alias_name varchar2(128)
   2. value_txt varchar2(4000)
   3. value_json clob
   4. data_type varchar2(128)
2. t_sql_select_col_tab as table of t_sql_select_col_rec index by pls_integer

Add body-local helpers:
1. get_rule_payload_attr(p_rule_payload clob, p_attr varchar2) return varchar2
2. extract_sql_select_query(p_rule_payload clob) return clob
3. validate_sql_select_payload(p_sql_query clob)
4. apply_sql_select_tokens(
   p_sql_query in clob,
   p_source_values in clob,
   p_params_json in clob,
   p_change_event_id in number
) return clob
5. execute_sql_select_one_row(
   p_sql_query in clob,
   p_result_cols out t_sql_select_col_tab,
   p_failure_reason out varchar2
) return varchar2
   - returns COMPUTED or FAILED
6. persist_sql_select_outputs(
   p_run_id in number,
   p_rule_id in number,
   p_cols in t_sql_select_col_tab,
   p_tenant_id in varchar2,
   p_context_id in varchar2
)

Add integration point in execute_run:
1. In per-rule loop, after source retrieval and gate pass:
   1. if rule_type = 'SQL_SELECT' then
      1. parse payload and extract sql_query
      2. validate guardrails
      3. token substitute (if enabled)
      4. execute query expecting one row
      5. derive outputs from returned columns
      6. persist each alias/value via existing persist_target_value
      7. proceed with existing consolidation flow unchanged

Add integration point in execute_rule:
1. Support SQL_SELECT when manually invoked with p_source_values.

### 5.3 Dynamic SQL Execution Method
Preferred in v1:
1. Use dbms_sql for dynamic unknown-column result sets.
2. Steps:
   1. parse query
   2. describe columns
   3. execute
   4. fetch first row
   5. if no row => FAIL zero-row
   6. capture all column values as string/json-compatible text
   7. fetch second row; if exists => FAIL multi-row
3. Normalize column names to upper-case alias keys for persistence/matching.

### 5.4 Token Substitution Behavior
1. Reuse existing substitution semantics from executor paths:
   1. SRC/alias/PARAM via substitute_tokens-compatible logic
   2. OLD/NEW via substitute_change_delta_tokens where required
2. Keep substitution optional by payload flag enable_token_substitution.
3. When disabled, execute sql_query as provided.

## 6) Error Handling And Codes

Add new app error range (proposed): -21001..-21020
1. -21001: SQL_SELECT metadata/constraint mismatch
2. -21002: sql_query missing in payload
3. -21003: Guardrail violation (blocked token/statement)
4. -21004: SQL_SELECT returned zero rows
5. -21005: SQL_SELECT returned multiple rows
6. -21006: Duplicate/ambiguous derived alias
7. -21007: SQL_SELECT execution failure

Behavior:
1. Return FAILED computed result for rule-level path where possible.
2. Log reason in md_run_target_action synthetic failure trace for parity when output mapping cannot proceed.

## 7) File-by-File Edit Checklist

### 7.1 plsql/packages/md_rule_executor_pkg.pkb
1. Add SQL_SELECT payload extract/validate helpers.
2. Add dbms_sql one-row execution helper.
3. Add derived output persistence helper.
4. Add SQL_SELECT branch in execute_run per-rule logic.
5. Ensure existing consolidation/action execution code remains untouched.
6. Add diagnostic logging snippet for generated SQL_SELECT text in md_impact_trace (diagnostic type SQL_SELECT_SQL_TEXT).

### 7.2 plsql/packages/md_rule_executor_pkg.pks
1. Update package header comment to include SQL_SELECT in supported types.
2. No signature change required unless exposing new helper APIs (not recommended).

### 7.3 sql/scripts/036_md_sql_select_rule_upgrade.sql
1. Alter md_rule type check constraint.
2. Add payload contract comment.
3. Keep idempotent behavior (skip if SQL_SELECT already present).

### 7.4 sql/scripts/074_md_sql_select_rule_smoke.sql
1. Seed release/run/object/column/rule metadata for isolated test context.
2. Add SQL_SELECT rule rows with payload JSON for each scenario.
3. Seed target mappings and target table fixture.
4. Execute run and assert results.

### 7.5 docs updates
1. Add SQL_SELECT references to package API, runtime flow, schema reference, and impact playbook.
2. Add 074 smoke in engine-docs index and required validation sequence as appropriate.

## 8) Smoke Script Design (074)

## 8.1 Scenarios
1. Happy path simple SELECT with aliases.
2. UNION ALL allowed scenario.
3. SQL built-in function scenario.
4. PL/SQL function call scenario.
5. Blocked statement scenario (inject update/delete in payload) -> expected failure.
6. Zero-row result -> expected failure.
7. Multi-row result -> expected failure.

## 8.2 Assertions
1. Rule selected and executed count matches expected.
2. For success scenarios:
   1. md_run_target_value contains derived alias rows.
   2. md_run_target_consolidated_value contains winners for mapped target columns.
   3. md_run_target_action has CONSOLIDATED_EXECUTION status rows.
3. For failure scenarios:
   1. failed status and failure reason contains expected error code/message fragment.
   2. no invalid target writes are applied.
4. Script emits PASSED marker only when all assertions hold.

## 9) Acceptance Criteria (Implementation)
1. SQL_SELECT rules execute end-to-end under execute_run.
2. No source-context metadata is required for SQL_SELECT success path.
3. Output alias derivation from result columns works deterministically.
4. Guardrails block non-query payloads.
5. UNION and PL/SQL function calls inside SELECT succeed.
6. Zero-row and multi-row cardinality violations fail deterministically.
7. Existing consolidation semantics are unchanged and continue to pass 066 and 073.
8. Baseline smoke sequence plus 074 passes.

Implementation note:
1. 074 is designed with expected negative SQL_SELECT scenarios (blocked/zero-row/multi-row), so run_status can be FAILED while scripted assertions still conclude with PASSED marker.

## 10) Regression Plan
Run in this order:
1. sql/scripts/060_md_selector_smoke.sql
2. sql/scripts/061_md_cross_entity_context_smoke.sql
3. sql/scripts/064_md_runtime_params_smoke_combined.sql
4. sql/scripts/066_md_target_dml_smoke.sql
5. sql/scripts/073_md_target_consolidation_smoke.sql
6. sql/scripts/067_md_rule_selection_gate_smoke.sql
7. sql/scripts/068_md_expr_validator_smoke.sql
8. sql/scripts/069_md_expr_function_registry_smoke.sql
9. sql/scripts/074_md_sql_select_rule_smoke.sql

## 11) Rollback Plan
1. Revert package body/spec changes.
2. Drop/rollback 036 upgrade script effects (restore prior md_rule_type_ck definition).
3. Remove 074 smoke artifacts.
4. Re-run baseline smoke sequence to verify restoration.

## 12) Open Technical Notes
1. rule_payload currently has JSON check; use payload.sql_query string instead of raw SQL CLOB to stay compliant.
2. Guardrail parser should eventually move from regex-heavy validation to SQL parser-based validation for stronger safety.
3. If alias collisions occur after normalization, fail fast to avoid ambiguous mapping.

## Evidence References
1. docs/standalone-select-rule-design.md
2. docs/package-api-reference.md
3. docs/runtime-flow-and-dynamic-sql.md
4. docs/metadata-schema-reference.md
5. plsql/packages/md_rule_executor_pkg.pks
6. plsql/packages/md_rule_executor_pkg.pkb
7. sql/scripts/010_md_core.sql
8. sql/scripts/020_md_runtime.sql
9. sql/scripts/060_md_selector_smoke.sql
10. sql/scripts/061_md_cross_entity_context_smoke.sql
11. sql/scripts/064_md_runtime_params_smoke_combined.sql
12. sql/scripts/066_md_target_dml_smoke.sql
13. sql/scripts/067_md_rule_selection_gate_smoke.sql
14. sql/scripts/068_md_expr_validator_smoke.sql
15. sql/scripts/069_md_expr_function_registry_smoke.sql
16. sql/scripts/073_md_target_consolidation_smoke.sql
