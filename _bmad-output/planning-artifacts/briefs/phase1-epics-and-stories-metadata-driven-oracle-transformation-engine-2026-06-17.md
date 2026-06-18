# Phase 1 Epics and User Stories

## Scope Baseline

- Timeline: 8 weeks
- Cadence: weekly checkpoints with mid-phase gate in week 4
- Sources in scope: Security, Holding, Issuer
- Targets in scope: CRIMS_SECURITY, CRIMS_ISSUER, CRIMS_POSITION, CRIMS_SECURITY_INDUSTRY, CRIMS_SECURITY_RATING
- Mandatory complex rule: source columns to target rows
- Mandatory complex rule: target  column value derived from a complex SQL expression from multiple source columns from more than one source table ( join) with also invoking pl/sql functions
- Mandatory selective processing: source changes (update, insert, delete, key-change old->new) trigger only directly and transitively linked rules and only impacted target table/column actions

- KPI targets:
  - >=100,000 rows per full run (stretch 250,000)
  - <=15 minutes per full run, sustained for 3 consecutive runs
  - 100 percent lineage at table, column, and rule level
- Operating model: controlled central metadata publishing

## Epic 1: Metadata Foundation and Governance Controls

### Objective

Define and implement the metadata model and change controls that govern mappings, transformation rules, versions, lineage, and audit events.

### Story 1.1: Define canonical metadata schema

As a platform architect, I want a canonical metadata schema for mappings, rules, versions, lineage, and execution configuration so that transformation behavior is metadata-driven and consistent.


Acceptance criteria:
1. Metadata entities and relationships are documented and versioned.
2. Schema supports table-, column-, and rule-level lineage.
3. Schema supports column-to-row transformation specification.
4. Schema supports publish and rollback version semantics.
5. Schema explicitly links source columns to rule inputs and rule outputs to target columns.
6. Schema captures source key definitions (including composite keys) and target key definitions (including composite keys and surrogate mappings).
7. Schema supports key-propagation lineage from source key components to target key components.

### Story 1.2: Implement metadata lifecycle controls

As a platform operator, I want controlled lifecycle states for metadata so that only approved configurations are executable.

Acceptance criteria:
1. Metadata lifecycle states include draft, approved, published, and retired.
2. Only published versions are eligible for execution.
3. Rollback to prior published version is supported.
4. Publish actions are restricted to platform team roles.
5. Publish validation blocks metadata versions with unresolved source-column, rule-input, rule-output, or target-column lineage links.
6. Publish validation blocks metadata versions missing key mapping definitions for in-scope flows.

### Story 1.3: Implement audit logging for all required event types

As a governance stakeholder, I want complete metadata audit logs so that all material configuration and control changes are traceable.

Acceptance criteria:
1. Audit log captures: rule create/update/deactivate, mapping changes, version publish/rollback, runtime override approvals.
2. Audit records include who, what, when, and why.
3. Audit records are queryable by run, object, and date range.
4. Audit trail is immutable for released metadata versions.
5. Audit log captures selective-run inputs and outputs, including changed source keys, changed source columns, selected rules, and impacted target table/column actions.
6. Audit log captures manual include/exclude overrides for selective runs and their approval evidence.

### Story 1.4: Define change-event and impact-resolution metadata

As a platform architect, I want standardized change-event and impact-resolution metadata so that only impacted rules and targets are executed for source changes.

Acceptance criteria:
1. Change-event types include update, insert, delete, and key-change old->new.
2. Change-event schema supports source keys (including composite keys), changed column names, and old/new values.
3. Impact-resolution metadata maps source column changes to directly linked rules and transitively dependent rules.
4. Impact-resolution metadata maps selected rules to target table and target column actions (update/insert/delete).
5. Delete behavior is configurable per mapping/rule (hard delete, soft delete, or rule-defined behavior).

### Story 1.5: Implement selective execution control model

As a platform operator, I want deterministic and idempotent selective execution controls so that repeated processing of the same change events produces consistent outcomes.

Acceptance criteria:
1. Selective execution supports deterministic ordering of events and rule evaluation for the same input batch.
2. Reprocessing the same change-event batch is idempotent and does not produce duplicate target side effects.
3. Key-change old->new behavior is modeled distinctly from delete+insert semantics in lineage and audit.
4. Runtime manual include/exclude override capability is supported and restricted by role.
5. All overrides require approval evidence and are included in immutable audit records.

## Epic 2: Wave 1 Transformation Execution

### Objective

Implement and run metadata-driven Oracle-to-Oracle transformations for the approved Wave 1 source and target scope.

### Story 2.1: Build source-target mapping pack for Wave 1

As a data engineer, I want approved mappings from Security, Holding, and Issuer to the 5 CRIMS target tables so that end-to-end execution can run from metadata.

Acceptance criteria:
1. Mappings exist for all in-scope source and target tables.
2. Mapping validations pass before publish.
3. Mapping pack has explicit version identifier.
4. Mapping pack is linked to lineage metadata.
5. Mapping pack defines source and target keys for each in-scope flow, including composite key structures where applicable.
6. Mapping pack links each mapped target column to source columns through rule inputs/outputs.

### Story 2.2: Implement complex column-to-row transformation rule

As a transformation designer, I want at least one production-grade column-to-row rule in Wave 1 so that complex transformation capability is proven early.

Acceptance criteria:
1. Rule is fully metadata-defined, not hardcoded.
2. Rule executes successfully in end-to-end run.
3. Rule lineage is visible at rule and column level.
4. Rule output is validated against expected test cases.
5. Rule metadata includes explicit source-column dependencies and target-column outputs for selective execution.
6. Rule participates in impact resolution so source column changes select this rule only when dependency conditions are met.

### Story 2.3: Execute full Wave 1 run and verify data quality

As a delivery lead, I want repeatable full runs for Wave 1 so that stakeholders can see reliable progress.

Acceptance criteria:
1. Full run executes across all in-scope flows.
2. Data quality checks pass for required fields and key constraints.
3. Failures are classified with actionable error categories.
4. Run outputs are stored and available for reporting.
5. Selective run mode accepts source change events (update/insert/delete/key-change) with source keys and changed column values.
6. Selective run mode executes only directly and transitively impacted rules.
7. Selective run mode produces only impacted target actions: target row update by key, target insert, or target delete/soft-delete as configured.
8. Selective run outputs include explainable impact trace: source key/column -> selected rules -> target table/column action.
9. Re-running the same selective input batch is idempotent and yields consistent target outcomes.

## Epic 3: Observability, Lineage, and Reporting

### Objective

Provide stakeholder-visible run reporting, full lineage transparency, and KPI tracking for demo and governance reviews.

### Story 3.1: Implement transformation run report

As a business stakeholder, I want per-run transformation reporting so that I can see operational progress clearly.

Acceptance criteria:
1. Report includes rows processed, execution duration, and lineage coverage.
2. Report supports run-level drilldown by flow.
3. Report history is available for trend view across weekly demos.
4. Report output is available in stakeholder-readable format.

### Story 3.2: Implement full lineage reporting

As a governance stakeholder, I want full lineage reporting so that transformation behavior is explainable and auditable.

Acceptance criteria:
1. Table-level lineage is complete for all in-scope flows.
2. Column-level lineage is complete for mapped fields.
3. Rule-level lineage is complete including column-to-row logic.
4. Lineage gaps block release readiness.

### Story 3.3: Implement KPI threshold tracking and alerts

As a delivery manager, I want KPI tracking against agreed thresholds so that readiness decisions are objective.

Acceptance criteria:
1. KPI dashboard compares actuals vs thresholds for each run.
2. Stability logic verifies duration target across 3 consecutive runs.
3. Threshold misses are flagged with severity and cause context.
4. Mid-phase gate report can be generated from tracked data.

## Epic 4: Delivery Governance and Mid-Phase Gate

### Objective

Institutionalize weekly checkpoint governance and execute a formal week-4 gate decision for scope, quality, and risk control.

### Story 4.1: Establish weekly checkpoint operating rhythm

As a program lead, I want a weekly checkpoint ritual so that progress, risks, and decisions are transparent.

Acceptance criteria:
1. Weekly checkpoint template is defined and adopted.
2. Each checkpoint records scope progress, KPI status, and risks.
3. Action owners and due dates are captured.
4. Stakeholder sign-off status is visible each week.

### Story 4.2: Conduct week-4 mid-phase gate review

As a steering stakeholder, I want a formal gate review in week 4 so that continuation decisions are evidence-based.

Acceptance criteria:
1. Gate package includes KPI trajectory, lineage status, audit evidence, and risk posture.
2. Decision outcomes are explicit: continue, continue-with-corrections, or re-scope.
3. Corrective actions are baselined if gaps are identified.
4. Gate decision is documented and communicated.

### Story 4.3: Enforce controlled central publish process

As a platform owner, I want centralized publish governance so that Phase 1 execution risk is contained.

Acceptance criteria:
1. Publish authority is restricted to platform team roles.
2. Publish request workflow and approval evidence are logged.
3. Emergency override path exists with mandatory approval logging.
4. Unauthorized publish attempts are blocked and audited.

## Suggested Implementation Sequence

1. Epic 1 first for metadata and governance baseline.
2. Epic 2 starts once first publishable metadata pack is approved.
3. Epic 3 in parallel with Epic 2 after first executable run.
4. Epic 4 runs throughout, with week-4 gate as hard milestone.

## Definition of Done for Phase 1

1. Wave 1 in-scope flows execute from published metadata without hardcoded rule behavior.
2. Column-to-row complex transformation is demonstrated and validated.
3. All three KPI thresholds are met according to agreed acceptance rules.
4. Full lineage and all five audit event classes are complete and reviewable.
5. Controlled central publishing model is operational and evidenced.
