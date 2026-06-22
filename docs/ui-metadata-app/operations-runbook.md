# Operations Runbook: Metadata Streamlit UI

## 1. Run Locally

1. Install dependencies:
   pip install -r tools/requirements-streamlit.txt
2. Run app:
   streamlit run tools/streamlit_dual_app.py

## 2. Connection Inputs

Required fields:
1. Username
2. Password
3. DSN

Optional environment defaults:
1. ORACLE_USER
2. ORACLE_PASSWORD
3. ORACLE_DSN

## 3. Usage Checklist

1. Test connection in sidebar.
2. Select release.
3. Confirm tenant_id/context_id/release_id defaults.
4. Create records in required tabs.
5. Verify created IDs from success messages.

## 4. Common Errors

1. ORA-00001 unique constraint violation
Cause: duplicate business key row.
Action: adjust key fields or choose different rule name/combination.

2. ORA-02291 parent key not found
Cause: referenced parent metadata missing.
Action: create parent records first or correct selected release scope.

3. ORA-02290 check constraint violated
Cause: enum-like field values invalid.
Action: use allowed values from dropdowns.

4. ORA-01722 invalid number
Cause: non-numeric value entered where number expected.
Action: correct input value type.

## 5. Recovery Steps

1. If app errors on load, verify DB credentials and DSN.
2. If release list is empty, create MD_RELEASE row first.
3. If dropdowns empty, ensure supporting metadata exists for selected release.

## 6. Operational Guardrails

1. Use least-privilege DB user for UI operations.
2. Avoid direct production use without role controls and audit wiring.
3. Keep schema and app versions aligned when DDL evolves.
