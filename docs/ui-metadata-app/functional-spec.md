# Functional Specification: Metadata Streamlit UI MVP

## 1. Purpose

Provide a very fast, operator-friendly UI for creating metadata records with release-scoped defaults.

Primary create flows:
1. MD_RULE
2. MD_RULE_INPUT
3. MD_RULE_OUTPUT
4. MD_RULE_TARGET_ACTION

## 2. Target Users

1. Metadata implementer
2. Functional designer
3. QA/test engineer preparing controlled test metadata

## 3. Scope

In scope:
1. Connect to Oracle DB from Streamlit UI
2. Select one release per user session
3. Default tenant_id, context_id, release_id from selected release
4. Create records in target metadata tables
5. Basic inline validation and DB error display

Out of scope for MVP:
1. Edit and delete workflows
2. Bulk import
3. Approval workflow
4. Role-based access control in UI layer

## 4. Core Workflow

1. User enters DB connection details
2. User selects release from MD_RELEASE
3. App resolves default scope values
4. User opens create tab and submits form
5. App inserts row with bind variables and sequence-generated PK
6. App shows success or error

## 5. Functional Requirements

### FR-1 Release Context Selection
1. App shall list releases from MD_RELEASE.
2. App shall derive tenant_id and context_id from selected release.
3. App shall apply selected release scope to all insert operations in session.

### FR-2 Create MD_RULE
1. App shall collect required MD_RULE fields.
2. App shall support SQL_SELECT rule_type.
3. App shall allow optional sql_select_query and optional rule_payload JSON.

### FR-3 Create MD_RULE_INPUT
1. App shall allow selecting rule within selected release.
2. App shall allow selecting source column within selected release objects.
3. App shall insert optional output_alias and dependency_condition_expr.

### FR-4 Create MD_RULE_OUTPUT
1. App shall allow selecting rule within selected release.
2. App shall allow selecting target column within selected release objects.
3. App shall insert optional output_expr.

### FR-5 Create MD_RULE_TARGET_ACTION
1. App shall allow selecting rule and target object in selected release.
2. App shall support optional target key and target column.
3. App shall support action_type, execution_mode, missing_row_policy, and delete_policy.

### FR-6 Diagnostics Utility
1. App shall include a simple DUAL query tab for connection sanity check.

## 6. UX Requirements

1. One-page layout with tabs.
2. Release context always visible.
3. Clear success and error messages per operation.
4. No hidden defaults for release scope values.

## 7. Data Rules

1. release_id, tenant_id, context_id are read from selected MD_RELEASE row.
2. Rule and column dropdown data must be filtered by release scope.
3. ID generation uses DB sequences.

## 8. Success Metrics

1. First metadata row created within 2 minutes after app launch.
2. No manual SQL required for common create flows.
3. Insert errors are understandable and actionable.
