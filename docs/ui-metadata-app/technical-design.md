# Technical Design: Metadata Streamlit UI

## 1. Architecture

Pattern:
1. Streamlit single-process UI
2. Direct Oracle connectivity via python-oracledb
3. SQL bind variables for all queries and inserts

Artifact:
1. [tools/streamlit_dual_app.py](tools/streamlit_dual_app.py)

## 2. Environment Fit

Supported in current laptop/workspace setup:
1. Python local execution in VS Code terminal
2. Streamlit lightweight UI runtime
3. Oracle DB connectivity without separate backend service

Why this is fast:
1. No frontend build toolchain
2. No API server to scaffold
3. Minimal deployment complexity for local use

## 3. Session Context Model

State variables in Streamlit session:
1. db_user
2. db_password
3. db_dsn
4. selected release row

Derived defaults:
1. tenant_id
2. context_id
3. release_id

All create operations read defaults from selected release.

## 4. Data Access Design

Helpers in app:
1. get_connection
2. fetch_all
3. fetch_one_value
4. execute_dml
5. nextval

Query patterns:
1. Release list from MD_RELEASE
2. Rule list scoped by tenant/context/release
3. Object and column lists scoped by tenant/context/release
4. Key definitions scoped by tenant/context/release

## 5. Insert Strategy

ID generation:
1. md_rule_seq
2. md_rule_input_seq
3. md_rule_output_seq
4. md_rule_target_action_seq

Transaction model:
1. Commit per insert action
2. Surface DB exception message directly in UI

## 6. Security And Safety Notes

1. Use bind parameters for SQL inputs.
2. Do not interpolate user text into SQL strings.
3. Password entry is masked in UI.
4. Credentials currently held in process session memory only.

## 7. Known Limitations

1. No authN/authZ in UI layer.
2. No JSON schema validation for payload fields.
3. No optimistic locking or concurrency controls.
4. No audit event writes from UI yet.

## 8. Recommended Near-Term Hardening

1. Add optional connection profile presets (non-secret fields only).
2. Add structured validation for JSON text areas.
3. Add release-status guardrails for published or retired releases.
4. Add confirmation dialogs for high-impact inserts.
