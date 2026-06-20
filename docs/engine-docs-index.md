# Engine Documentation Index

This index links the implementation-grade documentation set for the Oracle metadata engine.

## Core Documents

1. [System Architecture](docs/system-architecture.md)
2. [Metadata Schema Reference](docs/metadata-schema-reference.md)
3. [Package API Reference](docs/package-api-reference.md)
4. [Runtime Flow And Dynamic SQL](docs/runtime-flow-and-dynamic-sql.md)
5. [Error Handling And Observability](docs/error-handling-and-observability.md)
6. [Change Impact Playbook](docs/change-impact-playbook.md)
7. [Implementation Readiness Summary](docs/implementation-readiness-summary.md)

## Recommended Read Order By Role

### Business/Functional Analyst
1. [System Architecture](docs/system-architecture.md)
2. [Metadata Schema Reference](docs/metadata-schema-reference.md)
3. [Change Impact Playbook](docs/change-impact-playbook.md)

### Solution/Functional Designer
1. [System Architecture](docs/system-architecture.md)
2. [Runtime Flow And Dynamic SQL](docs/runtime-flow-and-dynamic-sql.md)
3. [Metadata Schema Reference](docs/metadata-schema-reference.md)
4. [Change Impact Playbook](docs/change-impact-playbook.md)

### PL/SQL Implementer
1. [Package API Reference](docs/package-api-reference.md)
2. [Runtime Flow And Dynamic SQL](docs/runtime-flow-and-dynamic-sql.md)
3. [Error Handling And Observability](docs/error-handling-and-observability.md)
4. [Change Impact Playbook](docs/change-impact-playbook.md)

### Reviewer/Test Architect
1. [Implementation Readiness Summary](docs/implementation-readiness-summary.md)
2. [Error Handling And Observability](docs/error-handling-and-observability.md)
3. [Change Impact Playbook](docs/change-impact-playbook.md)
4. [Runtime Flow And Dynamic SQL](docs/runtime-flow-and-dynamic-sql.md)

## Smoke Validation Entry Points

Primary sequence:
1. sql/scripts/060_md_selector_smoke.sql
2. sql/scripts/061_md_cross_entity_context_smoke.sql
3. sql/scripts/064_md_runtime_params_smoke_combined.sql
4. sql/scripts/066_md_target_dml_smoke.sql
5. sql/scripts/067_md_rule_selection_gate_smoke.sql
6. sql/scripts/068_md_expr_validator_smoke.sql
7. sql/scripts/069_md_expr_function_registry_smoke.sql

Wrapper scripts:
1. sql/scripts/062_md_runtime_params_smoke.sql
2. sql/scripts/063_md_runtime_params_smoke_late.sql

Cleanup helper:
1. sql/scripts/065_md_runtime_params_smoke_cleanup.sql

## Scope Notes

- These docs are derived from package specs and bodies under plsql/packages and smoke scripts under sql/scripts.
- DDL source of truth for table and datatype definitions is:
  - sql/scripts/010_md_core.sql
  - sql/scripts/020_md_runtime.sql
