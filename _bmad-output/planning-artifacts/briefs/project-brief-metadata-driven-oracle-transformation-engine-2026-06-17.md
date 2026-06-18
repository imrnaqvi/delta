---
title: Project Brief - Metadata-Driven Oracle Transformation Engine
project_name: delta
author: Imran
date: 2026-06-17
status: draft-v1
based_on:
  - _bmad-output/planning-artifacts/research/domain-meta-data-driven-oracle-based-data-transformation-engine-research-2026-06-16.md
  - _bmad-output/brainstorming/brainstorming-session-2026-06-16-222940.md
---

# Project Brief: Metadata-Driven Oracle Transformation Engine

## 1. Executive Summary

This project will deliver a metadata-driven Oracle-to-Oracle data transformation engine that supports hybrid deployment, governance-grade lineage, and audit-ready operations. The near-term strategy is a quick-win Phase 1 that proves high-value functionality through a bounded execution slice while preserving full-model architectural alignment for enterprise scale.

The brief is grounded in domain research showing strong market and regulatory pressure toward governance-centric, metadata-native transformation platforms across cloud and on-prem environments.

## 2. Business Context and Rationale

### 2.1 Why now

- Industry momentum is strong for governed hybrid data integration and transformation platforms.
- Regulatory and operational resilience expectations are increasing, especially for auditable controls and traceability.
- Competitive direction favors metadata-native platforms with policy-aware orchestration and explainable lineage.

### 2.2 Strategic positioning

The project differentiates on governance-grade execution rather than pure data movement speed by making metadata the control contract for mappings, transformation behavior, lineage, and audit evidence.

## 3. Problem Statement

Current transformation approaches are often pipeline-centric and difficult to govern at scale, especially across hybrid estates. Stakeholders need faster visible delivery while maintaining control, explainability, and auditability.

## 4. Project Goals

1. Deliver tangible stakeholder-visible progress early through a high-value Phase 1 slice.
2. Implement rich metadata-driven transformation execution for Oracle source-to-target flows.
3. Provide full rule-level lineage visibility, including complex column-to-row logic.
4. Provide governance-grade metadata audit trails from initial implementation.
5. Establish an architecture and metadata model that scales from initial scope to full enterprise coverage.

## 5. Scope Definition

### 5.1 Target end-state model (designed in Phase 1)

- Full metadata model aligned to approximately 10 source tables and 15 target tables.
- Hybrid-capable control and execution design.
- Policy, lineage, and audit constructs treated as first-class metadata entities.

### 5.2 Phase 1 execution scope (implemented in Phase 1)

- Source tables: Security, Holding, Issuer.
- Target tables: CRIMS_SECURITY, CRIMS_ISSUER, CRIMS_POSITION, CRIMS_SECURITY_INDUSTRY, CRIMS_SECURITY_RATING.
- Complex transformation requirement: include at least one transformation where source columns become target rows.

### 5.3 Included reporting and governance outputs

- Transformation report per run.
- Metadata changes audit log.
- KPI reporting for rows processed, execution duration, and lineage coverage.

### 5.4 Out of scope for Phase 1

- Full implementation of all 10-to-15 source/target flows.
- Federated metadata publishing model.
- Broad ecosystem connector expansion beyond the selected Wave 1 domain.

## 6. Delivery and Operating Model

### 6.1 Delivery cadence

- Phase 1 timeline: 8 weeks.
- Checkpoints: weekly demos.
- Governance milestone: formal mid-phase gate review.

### 6.2 Metadata operating model

- Controlled central model in Phase 1.
- Only platform team can publish metadata versions to execution environments.

## 7. Success Metrics and Acceptance Thresholds

### 7.1 KPI thresholds (adopted)

1. Rows processed:
   - Minimum: 100,000 rows per full run.
   - Stretch: 250,000 rows per full run.
2. Execution duration:
   - Maximum: 15 minutes end-to-end per full run.
   - Stability condition: achieved in 3 consecutive runs.
3. Lineage coverage:
   - 100 percent for in-scope transformations at table, column, and rule level.
   - Must include lineage for column-to-row transformation logic.

### 7.2 Demonstration readiness criteria

- Wave 1 flows execute end-to-end with consistent run reporting.
- KPI thresholds are met or trend positively against agreed checkpoints.
- Lineage and audit evidence are queryable and reviewable by stakeholders.

## 8. Governance and Audit Requirements

Phase 1 metadata audit log must include all five event classes:

1. Rule created, updated, deactivated.
2. Mapping changes (source-target field changes).
3. Version publish and rollback.
4. Runtime override approvals.
5. Who changed what, when, and why.

## 9. Stakeholders and Responsibilities

### 9.1 Primary stakeholders

- Business stakeholders for visible value and delivery confidence.
- Data platform and engineering teams for architecture and execution.
- Governance and risk stakeholders for control evidence and auditability.

### 9.2 Core accountability

- Platform team owns metadata publication control in Phase 1.
- Delivery team owns KPI progression and run transparency.
- Governance partners validate audit and lineage evidence completeness.

## 10. Risks and Mitigations

1. Risk: Scope overreach in first increment.
   - Mitigation: full-model design with partial execution strategy and mid-phase gate.
2. Risk: Complex transformation logic increases delivery uncertainty.
   - Mitigation: include one representative column-to-row transformation early and stabilize patterns.
3. Risk: Governance controls slow iteration.
   - Mitigation: central publish model with clear change workflow and weekly cadence.
4. Risk: KPI instability in early runs.
   - Mitigation: trend-based checkpointing and 3-run stability requirement.

## 11. Implementation Approach Summary

1. Define canonical metadata entities for mappings, rules, lineage, versioning, and audit.
2. Implement Wave 1 source-target flows and one complex transformation pattern.
3. Stand up run-level reporting and complete audit event capture.
4. Validate KPI thresholds and lineage completeness through weekly checkpoints.
5. Conduct formal mid-phase gate and adjust execution plan if needed.

## 12. Next-Step Recommendations

1. Confirm exact column-level mapping inventory for the three Wave 1 source tables.
2. Define the first representative column-to-row rule with test cases.
3. Finalize demo script aligned to the three KPIs and governance evidence.
4. Prepare gate-review checklist for week 4.

## 13. Brief Approval Snapshot

- Phase 1 strategy: full-model design plus partial execution.
- Scope baseline: approved.
- KPI thresholds: approved as-is.
- Audit event scope: all five events approved.
- Operating model: controlled central publish approved.
- Timeline and cadence: 8 weeks, weekly demos, mid-phase gate approved.
