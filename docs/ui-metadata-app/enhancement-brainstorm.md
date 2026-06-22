# Enhancement Brainstorm And Backlog: Metadata UI

## 1. Quick Wins (Minutes To Few Hours)

1. Inline JSON validation and pretty-format helper for rule_payload.
2. Dependent dropdown filtering:
3. target columns filtered by selected target object.
4. source columns filtered by source object.
5. Release guardrail banner when status is PUBLISHED or RETIRED.
6. Auto-suggest defaults by rule_type.
7. Copy form values from an existing rule as template.

## 2. Operator Productivity Enhancements

1. Clone rule flow including inputs/outputs/actions.
2. Multi-row create wizard for MD_RULE_INPUT and MD_RULE_OUTPUT.
3. Bulk paste table for column maps and key maps.
4. Draft save in local session before commit.
5. Last successful inserts panel with copyable IDs.

## 3. Quality And Governance

1. Pre-insert validation engine for required metadata relationships.
2. Context-aware warnings for likely configuration mistakes.
3. Optional write-through to audit tables with actor and reason.
4. Publish readiness mini-check from UI.

## 4. Safety Enhancements

1. Role modes:
2. Creator mode (insert only)
3. Reviewer mode (read-only)
4. Admin mode (future edit/delete)
5. Feature flags to hide advanced fields.
6. Soft guardrails for destructive action combinations.

## 5. UX Enhancements

1. Guided onboarding checklist for first-time user.
2. Collapsible advanced sections in each form.
3. Contextual help popovers with examples.
4. Dark/light theme support with high contrast controls.

## 6. Medium-Term Expansion

1. Add tabs for MD_RULE_TARGET_KEY_MAP and MD_RULE_TARGET_COLUMN_MAP.
2. Add MD_SOURCE_CONTEXT and predicate design forms.
3. Add import/export JSON package for release-scoped metadata.
4. Add side-by-side diff of two releases.

## 7. Prioritized Backlog

### Priority 1
1. Target-column filtering by selected object
2. JSON validation helper
3. Release-status guardrail
4. Clone existing rule

### Priority 2
1. Multi-row input/output wizard
2. Key-map and column-map tabs
3. Audit write option

### Priority 3
1. Import/export package
2. Release diff viewer
3. Role mode framework
