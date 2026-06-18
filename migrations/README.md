# Migrations

This folder tracks rollout order and rollback strategy for Oracle scripts in [sql/scripts](../sql/scripts).

## MD Metadata Rollout Order

Apply in this order:

1. [sql/scripts/005_md_drop.sql](../sql/scripts/005_md_drop.sql)
2. [sql/scripts/010_md_core.sql](../sql/scripts/010_md_core.sql)
3. [sql/scripts/015_md_seed_sample.sql](../sql/scripts/015_md_seed_sample.sql)
4. [sql/scripts/020_md_runtime.sql](../sql/scripts/020_md_runtime.sql)
5. [sql/scripts/030_md_audit.sql](../sql/scripts/030_md_audit.sql)
6. [sql/scripts/040_md_indexes.sql](../sql/scripts/040_md_indexes.sql)
7. [sql/scripts/050_md_pk_triggers.sql](../sql/scripts/050_md_pk_triggers.sql)

Notes:

1. Run [sql/scripts/005_md_drop.sql](../sql/scripts/005_md_drop.sql) only for reset/clean-room installs.
2. Sequence-based PKs are explicit; triggers in [sql/scripts/050_md_pk_triggers.sql](../sql/scripts/050_md_pk_triggers.sql) auto-populate IDs when null.
3. Runtime tables intentionally use selective foreign keys for hot paths.

## Rollback Strategy

1. Execute [sql/scripts/005_md_drop.sql](../sql/scripts/005_md_drop.sql).
2. Re-apply phased scripts from [sql/scripts/010_md_core.sql](../sql/scripts/010_md_core.sql) onward.

## Smoke Tests

Run after deployment to verify schema, seed data, and append-only audit controls.

```sql
-- 1) Core objects exist
select table_name
from user_tables
where table_name in (
	'MD_RELEASE',
	'MD_RULE',
	'MD_CHANGE_EVENT',
	'MD_RUN_TARGET_VALUE',
	'MD_AUDIT_EVENT'
)
order by table_name;

-- 2) PK triggers exist
select trigger_name, status
from user_triggers
where trigger_name in (
	'MD_RELEASE_BI_TRG',
	'MD_RULE_BI_TRG',
	'MD_CHANGE_EVENT_BI_TRG',
	'MD_AUDIT_EVENT_BI_TRG'
)
order by trigger_name;

-- 3) Seed sample exists
select tenant_id, context_id, release_name, semantic_version, status
from md_release
where tenant_id = 'TENANT_DEMO'
	and context_id = 'CTX_DEMO'
	and release_name = 'PHASE1_WAVE1';

-- 4) JSON columns enforce valid JSON
select constraint_name, table_name, status
from user_constraints
where table_name in (
	'MD_RULE',
	'MD_CHANGE_EVENT_RAW',
	'MD_CHANGE_EVENT',
	'MD_RUN_TARGET_ACTION',
	'MD_AUDIT_EVENT'
)
and constraint_type = 'C'
order by table_name, constraint_name;

-- 5) Runtime computed target values seed exists
select tenant_id,
	   context_id,
	   target_entity_name,
	   target_column_name,
	   computed_value_txt,
	   value_status,
	   applied_flag
from md_run_target_value
where tenant_id = 'TENANT_DEMO'
	and context_id = 'CTX_DEMO'
order by computed_at desc;

-- 6) Audit append-only guard (expect ORA-20001)
-- update md_audit_event set actor_id = 'X' where 1 = 0;
```

## SQLcl Example

```sql
@sql/scripts/010_md_core.sql
@sql/scripts/015_md_seed_sample.sql
@sql/scripts/020_md_runtime.sql
@sql/scripts/030_md_audit.sql
@sql/scripts/040_md_indexes.sql
@sql/scripts/050_md_pk_triggers.sql
```
