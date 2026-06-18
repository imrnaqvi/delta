# Session Design and Code Preferences

This note captures design and code preferences that were established during the 2026-06-18 session.

## Execution Architecture

- Prefer PL/SQL package-based execution over application-side or Java executor artifacts for this metadata-driven engine.
- Keep a single orchestration entrypoint in `md_rule_executor_pkg`, with rule-type-specific logic delegated to focused executor packages.
- Keep `change_event_id` in the run execution flow so rule execution remains tied to a concrete source event.
- Prefer fully functional execution logic over placeholder skeletons once the design direction is settled.

## Metadata-Driven Runtime Design

- Support cross-entity derivations through metadata-driven source-context graphs and correlation, rather than hardcoded joins.
- Treat runtime parameters such as `NAV_DATE` and `ASOF_DATE` as first-class execution inputs.
- Resolve source context strictly: if a required alias is missing, fail fast instead of silently degrading behavior.

## Smoke Test Structure

- Maintain a single canonical runtime-parameter smoke driver in `sql/scripts/064_md_runtime_params_smoke_combined.sql`.
- Keep older entry scripts such as `062` and `063` as wrappers that delegate to the canonical combined driver.
- Separate smoke test data cleanup and rollback from the main smoke driver into a dedicated cleanup script.

## Delivery and Validation Preferences

- Prefer direct code changes and working implementation over extended design-only discussion.
- Prefer a single-sprint implementation flow when the work can be completed end-to-end.
- Prefer the MCP SQLcl execution path for smoke-script validation instead of terminal `sql` or `sqlcl` execution.

## Notes

- This file captures design and coding preferences observed in-session, not a full architecture specification.
- Response-style preferences are tracked separately in memory and are not repeated here unless they affect implementation workflow.
