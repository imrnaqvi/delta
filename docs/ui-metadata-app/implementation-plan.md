# Implementation Plan: Metadata UI

## 1. Goal

Deliver useful metadata creation UX rapidly, then harden incrementally.

## 2. Phase Plan

### Phase A: MVP (Completed)
1. Release selection and scoped defaults
2. Create MD_RULE
3. Create MD_RULE_INPUT
4. Create MD_RULE_OUTPUT
5. Create MD_RULE_TARGET_ACTION
6. DUAL connection sanity tab

### Phase B: Fast Follow (1-2 sessions)
1. Add dependent dropdown filtering for object-column consistency
2. Add JSON validation for payload fields
3. Add release-status guardrails
4. Add post-insert summary panel

### Phase C: Structured Authoring (2-4 sessions)
1. Add target key/column map tabs
2. Add clone rule workflow
3. Add batch input/output row creation

### Phase D: Governance And Quality
1. Add optional audit writes
2. Add readiness checks before publishing
3. Add controlled role modes

## 3. Acceptance Criteria Per Phase

### Phase B
1. Invalid JSON blocked with clear error.
2. Target column list constrained by selected object.
3. Users warned before writing under published release.

### Phase C
1. Complete rule authoring possible without manual SQL for common patterns.
2. Clone flow reduces setup time by at least 50 percent.

### Phase D
1. Changes can be traced by actor and reason.
2. Pre-publish issues surfaced before runtime failures.

## 4. Delivery Notes

1. Keep one-file app structure until complexity justifies module split.
2. Prefer small vertical increments with immediate operator feedback.
3. Preserve bind-variable-only SQL policy.
