import os
from datetime import datetime

import oracledb
import streamlit as st


st.set_page_config(page_title="MD Metadata MVP", page_icon="DB", layout="wide")


def _normalize_db_value(value):
    if isinstance(value, oracledb.LOB):
        return value.read()
    return value


def get_connection():
    return oracledb.connect(
        user=st.session_state.db_user,
        password=st.session_state.db_password,
        dsn=st.session_state.db_dsn,
    )


def fetch_all(sql, binds=None):
    conn = None
    cur = None
    try:
        conn = get_connection()
        cur = conn.cursor()
        cur.execute(sql, binds or {})
        cols = [d[0] for d in cur.description]
        rows = [dict(zip(cols, [_normalize_db_value(v) for v in row])) for row in cur.fetchall()]
        return rows
    finally:
        if cur is not None:
            cur.close()
        if conn is not None:
            conn.close()


def fetch_one_value(sql, binds=None):
    conn = None
    cur = None
    try:
        conn = get_connection()
        cur = conn.cursor()
        cur.execute(sql, binds or {})
        row = cur.fetchone()
        return None if row is None else _normalize_db_value(row[0])
    finally:
        if cur is not None:
            cur.close()
        if conn is not None:
            conn.close()


def execute_dml(sql, binds=None):
    conn = None
    cur = None
    try:
        conn = get_connection()
        cur = conn.cursor()
        cur.execute(sql, binds or {})
        conn.commit()
    finally:
        if cur is not None:
            cur.close()
        if conn is not None:
            conn.close()


def nextval(seq_name):
    return fetch_one_value(f"select {seq_name}.nextval from dual")


def current_schema_name():
        return fetch_one_value("select sys_context('USERENV','CURRENT_SCHEMA') from dual")


def sync_md_columns_from_table(tenant_id, context_id, object_id, schema_name, table_name, delete_extra):
        conn = None
        cur = None
        try:
                conn = get_connection()
                cur = conn.cursor()

                cur.execute(
                        """
                        insert into md_column (
                            column_id,
                            tenant_id,
                            context_id,
                            object_id,
                            column_name,
                            data_type,
                            nullable_flag,
                            ordinal_position
                        )
                        select md_column_seq.nextval,
                                     :tenant_id,
                                     :context_id,
                                     :object_id,
                                     c.column_name,
                                     c.data_type,
                                     case c.nullable when 'N' then 'N' else 'Y' end,
                                     c.column_id
                            from all_tab_columns c
                         where c.owner = upper(:schema_name)
                             and c.table_name = upper(:table_name)
                             and not exists (
                                 select 1
                                     from md_column m
                                    where m.tenant_id = :tenant_id
                                        and m.context_id = :context_id
                                        and m.object_id = :object_id
                                        and upper(m.column_name) = upper(c.column_name)
                             )
                        """,
                        {
                                "tenant_id": tenant_id,
                                "context_id": context_id,
                                "object_id": object_id,
                                "schema_name": schema_name,
                                "table_name": table_name,
                        },
                )
                inserted = cur.rowcount

                deleted = 0
                if delete_extra:
                        cur.execute(
                                """
                                delete from md_column m
                                 where m.tenant_id = :tenant_id
                                     and m.context_id = :context_id
                                     and m.object_id = :object_id
                                     and not exists (
                                         select 1
                                             from all_tab_columns c
                                            where c.owner = upper(:schema_name)
                                                and c.table_name = upper(:table_name)
                                                and upper(c.column_name) = upper(m.column_name)
                                     )
                                """,
                                {
                                        "tenant_id": tenant_id,
                                        "context_id": context_id,
                                        "object_id": object_id,
                                        "schema_name": schema_name,
                                        "table_name": table_name,
                                },
                        )
                        deleted = cur.rowcount

                conn.commit()
                return inserted, deleted
        finally:
                if cur is not None:
                        cur.close()
                if conn is not None:
                        conn.close()


if "db_user" not in st.session_state:
    st.session_state.db_user = os.getenv("ORACLE_USER", "")
if "db_password" not in st.session_state:
    st.session_state.db_password = os.getenv("ORACLE_PASSWORD", "")
if "db_dsn" not in st.session_state:
    st.session_state.db_dsn = os.getenv("ORACLE_DSN", "")

st.title("Metadata UI MVP (MD_RULE / INPUT / OUTPUT)")
st.caption(
    "Release-scoped defaults: tenant_id, context_id, release_id are inherited from selected release."
)

with st.sidebar:
    st.subheader("Database")
    st.session_state.db_user = st.text_input("Username", value=st.session_state.db_user)
    st.session_state.db_password = st.text_input("Password", value=st.session_state.db_password, type="password")
    st.session_state.db_dsn = st.text_input("DSN", value=st.session_state.db_dsn, help="Example: host:1521/service_name")

    connected = False
    connect_error = None
    if st.button("Test Connection", use_container_width=True):
        try:
            msg = fetch_one_value("select 'connected' from dual")
            st.success(msg)
            connected = True
        except Exception as exc:
            st.error(f"Connection failed: {exc}")
            connect_error = exc

if not st.session_state.db_user or not st.session_state.db_password or not st.session_state.db_dsn:
    st.info("Enter DB credentials in the sidebar to continue.")
    st.stop()

schema_name_default = None
try:
    schema_name_default = current_schema_name()
except Exception:
    schema_name_default = None

try:
    releases = fetch_all(
        """
        select release_id,
               tenant_id,
               context_id,
               release_name,
               semantic_version,
               status
          from md_release
         order by release_id desc
        """
    )
except Exception as exc:
    st.error(f"Unable to load releases: {exc}")
    st.stop()

if not releases:
    st.warning("No rows in MD_RELEASE. Create a release first.")
    st.stop()

release_options = {
    f"{r['RELEASE_ID']} | {r['RELEASE_NAME']} | v{r['SEMANTIC_VERSION']} | {r['STATUS']}": r for r in releases
}

selected_label = st.selectbox("Release", options=list(release_options.keys()))
selected_release = release_options[selected_label]

tenant_id = selected_release["TENANT_ID"]
context_id = selected_release["CONTEXT_ID"]
release_id = selected_release["RELEASE_ID"]

c1, c2, c3 = st.columns(3)
c1.text_input("tenant_id", value=tenant_id, disabled=True)
c2.text_input("context_id", value=context_id, disabled=True)
c3.text_input("release_id", value=str(release_id), disabled=True)

rules = fetch_all(
    """
    select rule_id,
           rule_name,
           rule_type,
                     status,
                     sql_select_query
      from md_rule
     where tenant_id = :tenant_id
       and context_id = :context_id
       and release_id = :release_id
     order by rule_name
    """,
    {"tenant_id": tenant_id, "context_id": context_id, "release_id": release_id},
)

columns = fetch_all(
    """
    select c.column_id,
           o.object_name,
           c.column_name
      from md_column c
      join md_object o
        on o.object_id = c.object_id
       and o.tenant_id = c.tenant_id
       and o.context_id = c.context_id
     where c.tenant_id = :tenant_id
       and c.context_id = :context_id
       and o.release_id = :release_id
     order by o.object_name, c.column_name
    """,
    {"tenant_id": tenant_id, "context_id": context_id, "release_id": release_id},
)

objects = fetch_all(
        """
        select object_id,
                     object_name,
                     object_type,
                     system_name
            from md_object
         where tenant_id = :tenant_id
             and context_id = :context_id
             and release_id = :release_id
         order by object_name
        """,
        {"tenant_id": tenant_id, "context_id": context_id, "release_id": release_id},
)

key_defs = fetch_all(
        """
        select key_id,
                     key_scope,
                     system_name,
                     entity_name,
                     key_name,
                     key_type
            from md_key_definition
         where tenant_id = :tenant_id
             and context_id = :context_id
             and release_id = :release_id
         order by key_name
        """,
        {"tenant_id": tenant_id, "context_id": context_id, "release_id": release_id},
)

change_events = fetch_all(
        """
        select change_event_id,
                     release_id,
                     event_type,
                     source_system_name,
                     source_entity_name,
                     source_key_hash,
                     event_fingerprint,
                     processing_status
            from md_change_event
         where tenant_id = :tenant_id
             and context_id = :context_id
         order by change_event_id desc
        """,
        {"tenant_id": tenant_id, "context_id": context_id},
)

rule_map = {f"{r['RULE_ID']} | {r['RULE_NAME']} | {r['RULE_TYPE']}": r["RULE_ID"] for r in rules}
col_map = {f"{c['COLUMN_ID']} | {c['OBJECT_NAME']}.{c['COLUMN_NAME']}": c["COLUMN_ID"] for c in columns}
rule_input_rows = fetch_all(
        """
        select ri.rule_input_id,
                     ri.rule_id,
                     r.rule_name,
                     ri.source_column_id,
                     c.column_name,
                     ri.required_flag,
                     ri.output_alias,
                     ri.dependency_condition_expr
            from md_rule_input ri
            join md_rule r
                on r.rule_id = ri.rule_id
             and r.tenant_id = ri.tenant_id
             and r.context_id = ri.context_id
            join md_column c
                on c.column_id = ri.source_column_id
             and c.tenant_id = ri.tenant_id
             and c.context_id = ri.context_id
         where ri.tenant_id = :tenant_id
             and ri.context_id = :context_id
             and r.release_id = :release_id
         order by ri.rule_input_id desc
        """,
        {"tenant_id": tenant_id, "context_id": context_id, "release_id": release_id},
)

rule_output_rows = fetch_all(
        """
        select ro.rule_output_id,
                     ro.rule_id,
                     r.rule_name,
                     ro.target_column_id,
                     c.column_name,
                     ro.output_expr
            from md_rule_output ro
            join md_rule r
                on r.rule_id = ro.rule_id
             and r.tenant_id = ro.tenant_id
             and r.context_id = ro.context_id
            join md_column c
                on c.column_id = ro.target_column_id
             and c.tenant_id = ro.tenant_id
             and c.context_id = ro.context_id
         where ro.tenant_id = :tenant_id
             and ro.context_id = :context_id
             and r.release_id = :release_id
         order by ro.rule_output_id desc
        """,
        {"tenant_id": tenant_id, "context_id": context_id, "release_id": release_id},
)

md_objects_rows = fetch_all(
        """
        select object_id,
                     system_name,
                     schema_name,
                     object_name,
                     object_type
            from md_object
         where tenant_id = :tenant_id
             and context_id = :context_id
             and release_id = :release_id
         order by object_name
        """,
        {"tenant_id": tenant_id, "context_id": context_id, "release_id": release_id},
)
object_map = {
    f"{o['OBJECT_ID']} | {o['SYSTEM_NAME']}.{o['OBJECT_NAME']} | {o['OBJECT_TYPE']}": o["OBJECT_ID"]
    for o in objects
}
key_map = {
    f"{k['KEY_ID']} | {k['KEY_SCOPE']} | {k['SYSTEM_NAME']}.{k['ENTITY_NAME']} | {k['KEY_NAME']}": k["KEY_ID"]
    for k in key_defs
}

tab_rule, tab_rule_manage, tab_input, tab_input_manage, tab_output, tab_output_manage, tab_action, tab_object, tab_event, tab_check = st.tabs([
    "Create MD_RULE",
    "Manage MD_RULE",
    "Create MD_RULE_INPUT",
    "Manage MD_RULE_INPUT",
    "Create MD_RULE_OUTPUT",
    "Manage MD_RULE_OUTPUT",
    "Create MD_RULE_TARGET_ACTION",
    "Manage MD_OBJECT + MD_COLUMN",
    "Manage MD_CHANGE_EVENT",
    "Literal from DUAL",
])

with tab_rule:
    with st.form("create_rule"):
        rule_name = st.text_input("rule_name")
        rule_type = st.selectbox("rule_type", ["EXPRESSION", "COLUMN_TO_ROW", "LOOKUP", "PLSQL_FUNC", "SQL_SELECT"])
        status = st.selectbox("status", ["DRAFT", "APPROVED", "PUBLISHED", "RETIRED"], index=2)
        created_by = st.text_input("created_by", value="streamlit_mvp")
        output_eval_failure_policy = st.selectbox("output_eval_failure_policy", ["CONTINUE", "FAIL_RULE"], index=0)
        active_flag = st.selectbox("active_flag", ["Y", "N"], index=0)
        selection_gate_enabled_flag = st.selectbox("selection_gate_enabled_flag", ["Y", "N"], index=0)
        sql_select_query = st.text_area("sql_select_query (optional)", height=80)
        rule_payload = st.text_area("rule_payload JSON (optional)", height=120)

        submit_rule = st.form_submit_button("Insert MD_RULE")

    if submit_rule:
        if not rule_name.strip() or not created_by.strip():
            st.error("rule_name and created_by are required.")
        else:
            try:
                rule_id = nextval("md_rule_seq")
                execute_dml(
                    """
                    insert into md_rule (
                      rule_id,
                      tenant_id,
                      context_id,
                      release_id,
                      rule_name,
                      rule_type,
                      status,
                      sql_select_query,
                      rule_payload,
                      output_eval_failure_policy,
                      selection_gate_enabled_flag,
                      active_flag,
                      created_by
                    ) values (
                      :rule_id,
                      :tenant_id,
                      :context_id,
                      :release_id,
                      :rule_name,
                      :rule_type,
                      :status,
                      :sql_select_query,
                      :rule_payload,
                      :output_eval_failure_policy,
                      :selection_gate_enabled_flag,
                      :active_flag,
                      :created_by
                    )
                    """,
                    {
                        "rule_id": rule_id,
                        "tenant_id": tenant_id,
                        "context_id": context_id,
                        "release_id": release_id,
                        "rule_name": rule_name.strip(),
                        "rule_type": rule_type,
                        "status": status,
                        "sql_select_query": (sql_select_query.strip() or None),
                        "rule_payload": (rule_payload.strip() or None),
                        "output_eval_failure_policy": output_eval_failure_policy,
                        "selection_gate_enabled_flag": selection_gate_enabled_flag,
                        "active_flag": active_flag,
                        "created_by": created_by.strip(),
                    },
                )
                st.success(f"Inserted MD_RULE with rule_id={rule_id}")
                st.rerun()
            except Exception as exc:
                st.error(f"Insert failed: {exc}")

with tab_rule_manage:
    if not rules:
        st.info("No rules in selected release.")
    else:
        manage_rule_map = {f"{r['RULE_ID']} | {r['RULE_NAME']} | {r['RULE_TYPE']} | {r['STATUS']}": r for r in rules}
        manage_rule_label = st.selectbox("rule to manage", options=list(manage_rule_map.keys()), key="manage_rule")
        manage_rule = manage_rule_map[manage_rule_label]
        manage_rule_id = manage_rule["RULE_ID"]

        with st.form("update_rule"):
            u_rule_name = st.text_input(
                "rule_name",
                value=manage_rule["RULE_NAME"],
                key=f"u_rule_name_{manage_rule_id}",
            )
            u_rule_type = st.selectbox(
                "rule_type",
                ["EXPRESSION", "COLUMN_TO_ROW", "LOOKUP", "PLSQL_FUNC", "SQL_SELECT"],
                index=["EXPRESSION", "COLUMN_TO_ROW", "LOOKUP", "PLSQL_FUNC", "SQL_SELECT"].index(manage_rule["RULE_TYPE"]),
                key=f"u_rule_type_{manage_rule_id}",
            )
            u_status = st.selectbox(
                "status",
                ["DRAFT", "APPROVED", "PUBLISHED", "RETIRED"],
                index=["DRAFT", "APPROVED", "PUBLISHED", "RETIRED"].index(manage_rule["STATUS"]),
                key=f"u_rule_status_{manage_rule_id}",
            )
            u_sql_select_query = st.text_area(
                "sql_select_query",
                value=manage_rule["SQL_SELECT_QUERY"] or "",
                height=120,
                key=f"u_sql_select_query_{manage_rule_id}",
            )
            do_update_rule = st.form_submit_button("Update MD_RULE")

        c_update, c_delete = st.columns(2)
        if do_update_rule:
            try:
                execute_dml(
                    """
                    update md_rule
                       set rule_name = :rule_name,
                           rule_type = :rule_type,
                           status = :status,
                           sql_select_query = :sql_select_query,
                           updated_at = systimestamp
                     where rule_id = :rule_id
                       and tenant_id = :tenant_id
                       and context_id = :context_id
                    """,
                    {
                        "rule_name": u_rule_name.strip(),
                        "rule_type": u_rule_type,
                        "status": u_status,
                        "sql_select_query": (u_sql_select_query.strip() or None),
                        "rule_id": manage_rule["RULE_ID"],
                        "tenant_id": tenant_id,
                        "context_id": context_id,
                    },
                )
                st.success("MD_RULE updated.")
                st.rerun()
            except Exception as exc:
                st.error(f"Update failed: {exc}")

        if c_delete.button("Delete Selected MD_RULE", type="secondary"):
            try:
                execute_dml(
                    """
                    delete from md_rule
                     where rule_id = :rule_id
                       and tenant_id = :tenant_id
                       and context_id = :context_id
                    """,
                    {
                        "rule_id": manage_rule["RULE_ID"],
                        "tenant_id": tenant_id,
                        "context_id": context_id,
                    },
                )
                st.success("MD_RULE deleted.")
                st.rerun()
            except Exception as exc:
                st.error(f"Delete failed: {exc}")

with tab_input:
    if not rule_map:
        st.info("No rules in selected release. Create MD_RULE first.")
    elif not col_map:
        st.info("No columns in selected release. Create metadata objects/columns first.")
    else:
        with st.form("create_rule_input"):
            rule_label = st.selectbox("rule", options=list(rule_map.keys()))
            source_col_label = st.selectbox("source_column", options=list(col_map.keys()))
            required_flag = st.selectbox("required_flag", ["Y", "N"], index=0)
            output_alias = st.text_input("output_alias (optional)")
            dependency_condition_expr = st.text_area("dependency_condition_expr (optional)", height=80)

            submit_input = st.form_submit_button("Insert MD_RULE_INPUT")

        if submit_input:
            try:
                rule_input_id = nextval("md_rule_input_seq")
                execute_dml(
                    """
                    insert into md_rule_input (
                      rule_input_id,
                      tenant_id,
                      context_id,
                      rule_id,
                      source_column_id,
                      output_alias,
                      required_flag,
                      dependency_condition_expr
                    ) values (
                      :rule_input_id,
                      :tenant_id,
                      :context_id,
                      :rule_id,
                      :source_column_id,
                      :output_alias,
                      :required_flag,
                      :dependency_condition_expr
                    )
                    """,
                    {
                        "rule_input_id": rule_input_id,
                        "tenant_id": tenant_id,
                        "context_id": context_id,
                        "rule_id": rule_map[rule_label],
                        "source_column_id": col_map[source_col_label],
                        "output_alias": (output_alias.strip() or None),
                        "required_flag": required_flag,
                        "dependency_condition_expr": (dependency_condition_expr.strip() or None),
                    },
                )
                st.success(f"Inserted MD_RULE_INPUT with rule_input_id={rule_input_id}")
            except Exception as exc:
                st.error(f"Insert failed: {exc}")

with tab_input_manage:
    if not rule_input_rows:
        st.info("No MD_RULE_INPUT rows in selected release.")
    else:
        input_manage_map = {
            f"{r['RULE_INPUT_ID']} | rule={r['RULE_NAME']} | col={r['COLUMN_NAME']}": r
            for r in rule_input_rows
        }
        input_label = st.selectbox("MD_RULE_INPUT row", options=list(input_manage_map.keys()), key="manage_input")
        input_row = input_manage_map[input_label]
        input_row_id = input_row["RULE_INPUT_ID"]
        rule_keys = list(rule_map.keys())
        col_keys = list(col_map.keys())
        input_rule_label = next((k for k, v in rule_map.items() if v == input_row["RULE_ID"]), rule_keys[0])
        input_col_label = next((k for k, v in col_map.items() if v == input_row["SOURCE_COLUMN_ID"]), col_keys[0])

        with st.form("update_rule_input"):
            u_rule_input_rule = st.selectbox(
                "rule",
                options=rule_keys,
                index=rule_keys.index(input_rule_label),
                key=f"u_ri_rule_{input_row_id}",
            )
            u_rule_input_col = st.selectbox(
                "source_column",
                options=col_keys,
                index=col_keys.index(input_col_label),
                key=f"u_ri_col_{input_row_id}",
            )
            u_rule_input_req = st.selectbox(
                "required_flag",
                ["Y", "N"],
                index=0 if input_row["REQUIRED_FLAG"] == "Y" else 1,
                key=f"u_ri_req_{input_row_id}",
            )
            u_rule_input_alias = st.text_input(
                "output_alias",
                value=input_row["OUTPUT_ALIAS"] or "",
                key=f"u_ri_alias_{input_row_id}",
            )
            u_rule_input_dep = st.text_area(
                "dependency_condition_expr",
                value=input_row["DEPENDENCY_CONDITION_EXPR"] or "",
                height=80,
                key=f"u_ri_dep_{input_row_id}",
            )
            do_update_input = st.form_submit_button("Update MD_RULE_INPUT")

        if do_update_input:
            try:
                execute_dml(
                    """
                    update md_rule_input
                       set rule_id = :rule_id,
                           source_column_id = :source_column_id,
                           required_flag = :required_flag,
                           output_alias = :output_alias,
                           dependency_condition_expr = :dependency_condition_expr
                     where rule_input_id = :rule_input_id
                       and tenant_id = :tenant_id
                       and context_id = :context_id
                    """,
                    {
                        "rule_id": rule_map[u_rule_input_rule],
                        "source_column_id": col_map[u_rule_input_col],
                        "required_flag": u_rule_input_req,
                        "output_alias": (u_rule_input_alias.strip() or None),
                        "dependency_condition_expr": (u_rule_input_dep.strip() or None),
                        "rule_input_id": input_row["RULE_INPUT_ID"],
                        "tenant_id": tenant_id,
                        "context_id": context_id,
                    },
                )
                st.success("MD_RULE_INPUT updated.")
                st.rerun()
            except Exception as exc:
                st.error(f"Update failed: {exc}")

        if st.button("Delete Selected MD_RULE_INPUT", key="delete_rule_input"):
            try:
                execute_dml(
                    """
                    delete from md_rule_input
                     where rule_input_id = :rule_input_id
                       and tenant_id = :tenant_id
                       and context_id = :context_id
                    """,
                    {
                        "rule_input_id": input_row["RULE_INPUT_ID"],
                        "tenant_id": tenant_id,
                        "context_id": context_id,
                    },
                )
                st.success("MD_RULE_INPUT deleted.")
                st.rerun()
            except Exception as exc:
                st.error(f"Delete failed: {exc}")

with tab_output:
    if not rule_map:
        st.info("No rules in selected release. Create MD_RULE first.")
    elif not col_map:
        st.info("No columns in selected release. Create metadata objects/columns first.")
    else:
        with st.form("create_rule_output"):
            rule_label_out = st.selectbox("rule", options=list(rule_map.keys()), key="rule_for_output")
            target_col_label = st.selectbox("target_column", options=list(col_map.keys()))
            output_expr = st.text_area("output_expr (optional)", height=120)

            submit_output = st.form_submit_button("Insert MD_RULE_OUTPUT")

        if submit_output:
            try:
                rule_output_id = nextval("md_rule_output_seq")
                execute_dml(
                    """
                    insert into md_rule_output (
                      rule_output_id,
                      tenant_id,
                      context_id,
                      rule_id,
                      target_column_id,
                      output_expr
                    ) values (
                      :rule_output_id,
                      :tenant_id,
                      :context_id,
                      :rule_id,
                      :target_column_id,
                      :output_expr
                    )
                    """,
                    {
                        "rule_output_id": rule_output_id,
                        "tenant_id": tenant_id,
                        "context_id": context_id,
                        "rule_id": rule_map[rule_label_out],
                        "target_column_id": col_map[target_col_label],
                        "output_expr": (output_expr.strip() or None),
                    },
                )
                st.success(f"Inserted MD_RULE_OUTPUT with rule_output_id={rule_output_id}")
            except Exception as exc:
                st.error(f"Insert failed: {exc}")

with tab_output_manage:
    if not rule_output_rows:
        st.info("No MD_RULE_OUTPUT rows in selected release.")
    else:
        output_manage_map = {
            f"{r['RULE_OUTPUT_ID']} | rule={r['RULE_NAME']} | col={r['COLUMN_NAME']}": r
            for r in rule_output_rows
        }
        output_label = st.selectbox("MD_RULE_OUTPUT row", options=list(output_manage_map.keys()), key="manage_output")
        output_row = output_manage_map[output_label]
        output_row_id = output_row["RULE_OUTPUT_ID"]
        rule_keys = list(rule_map.keys())
        col_keys = list(col_map.keys())
        output_rule_label = next((k for k, v in rule_map.items() if v == output_row["RULE_ID"]), rule_keys[0])
        output_col_label = next((k for k, v in col_map.items() if v == output_row["TARGET_COLUMN_ID"]), col_keys[0])

        with st.form("update_rule_output"):
            u_rule_output_rule = st.selectbox(
                "rule",
                options=rule_keys,
                index=rule_keys.index(output_rule_label),
                key=f"u_ro_rule_{output_row_id}",
            )
            u_rule_output_col = st.selectbox(
                "target_column",
                options=col_keys,
                index=col_keys.index(output_col_label),
                key=f"u_ro_col_{output_row_id}",
            )
            u_rule_output_expr = st.text_area(
                "output_expr",
                value=output_row["OUTPUT_EXPR"] or "",
                height=120,
                key=f"u_ro_expr_{output_row_id}",
            )
            do_update_output = st.form_submit_button("Update MD_RULE_OUTPUT")

        if do_update_output:
            try:
                execute_dml(
                    """
                    update md_rule_output
                       set rule_id = :rule_id,
                           target_column_id = :target_column_id,
                           output_expr = :output_expr
                     where rule_output_id = :rule_output_id
                       and tenant_id = :tenant_id
                       and context_id = :context_id
                    """,
                    {
                        "rule_id": rule_map[u_rule_output_rule],
                        "target_column_id": col_map[u_rule_output_col],
                        "output_expr": (u_rule_output_expr.strip() or None),
                        "rule_output_id": output_row["RULE_OUTPUT_ID"],
                        "tenant_id": tenant_id,
                        "context_id": context_id,
                    },
                )
                st.success("MD_RULE_OUTPUT updated.")
                st.rerun()
            except Exception as exc:
                st.error(f"Update failed: {exc}")

        if st.button("Delete Selected MD_RULE_OUTPUT", key="delete_rule_output"):
            try:
                execute_dml(
                    """
                    delete from md_rule_output
                     where rule_output_id = :rule_output_id
                       and tenant_id = :tenant_id
                       and context_id = :context_id
                    """,
                    {
                        "rule_output_id": output_row["RULE_OUTPUT_ID"],
                        "tenant_id": tenant_id,
                        "context_id": context_id,
                    },
                )
                st.success("MD_RULE_OUTPUT deleted.")
                st.rerun()
            except Exception as exc:
                st.error(f"Delete failed: {exc}")

with tab_action:
    if not rule_map:
        st.info("No rules in selected release. Create MD_RULE first.")
    elif not object_map:
        st.info("No objects in selected release. Create MD_OBJECT first.")
    else:
        with st.form("create_rule_target_action"):
            rule_label_action = st.selectbox("rule", options=list(rule_map.keys()), key="rule_for_action")
            target_object_label = st.selectbox("target_object", options=list(object_map.keys()))
            action_type = st.selectbox("action_type", ["UPDATE", "INSERT", "DELETE", "SOFT_DELETE"], index=0)
            execution_mode = st.selectbox("execution_mode", ["APPLY", "PREVIEW"], index=0)
            missing_row_policy = st.selectbox("missing_row_policy", ["ERROR", "INSERT", "SKIP"], index=0)
            delete_policy = st.selectbox("delete_policy", ["RULE_DEFINED", "HARD_DELETE", "SOFT_DELETE"], index=0)

            key_options = ["<None>"] + list(key_map.keys())
            target_key_label = st.selectbox("target_key (optional)", options=key_options)

            col_options = ["<None>"] + list(col_map.keys())
            target_col_label_action = st.selectbox("target_column (optional)", options=col_options)

            action_condition_expr = st.text_area("action_condition_expr (optional)", height=90)

            submit_action = st.form_submit_button("Insert MD_RULE_TARGET_ACTION")

        if submit_action:
            try:
                rule_target_action_id = nextval("md_rule_target_action_seq")
                execute_dml(
                    """
                    insert into md_rule_target_action (
                      rule_target_action_id,
                      tenant_id,
                      context_id,
                      release_id,
                      rule_id,
                      target_object_id,
                      target_key_id,
                      target_column_id,
                      action_type,
                      execution_mode,
                      missing_row_policy,
                      delete_policy,
                      action_condition_expr
                    ) values (
                      :rule_target_action_id,
                      :tenant_id,
                      :context_id,
                      :release_id,
                      :rule_id,
                      :target_object_id,
                      :target_key_id,
                      :target_column_id,
                      :action_type,
                      :execution_mode,
                      :missing_row_policy,
                      :delete_policy,
                      :action_condition_expr
                    )
                    """,
                    {
                        "rule_target_action_id": rule_target_action_id,
                        "tenant_id": tenant_id,
                        "context_id": context_id,
                        "release_id": release_id,
                        "rule_id": rule_map[rule_label_action],
                        "target_object_id": object_map[target_object_label],
                        "target_key_id": None if target_key_label == "<None>" else key_map[target_key_label],
                        "target_column_id": None if target_col_label_action == "<None>" else col_map[target_col_label_action],
                        "action_type": action_type,
                        "execution_mode": execution_mode,
                        "missing_row_policy": missing_row_policy,
                        "delete_policy": delete_policy,
                        "action_condition_expr": (action_condition_expr.strip() or None),
                    },
                )
                st.success(f"Inserted MD_RULE_TARGET_ACTION with rule_target_action_id={rule_target_action_id}")
            except Exception as exc:
                st.error(f"Insert failed: {exc}")

with tab_object:
    st.subheader("MD_OBJECT")
    st.caption("Physical table list excludes names like MD% and tables already seeded in MD_OBJECT for the selected release.")
    md_object_seed_schema = st.text_input(
        "Physical schema for MD_OBJECT seed",
        value=(schema_name_default or ""),
        key="md_object_seed_schema",
    ).strip().upper()

    physical_tables = []
    if md_object_seed_schema:
        try:
            physical_tables = fetch_all(
                """
                select t.owner,
                       t.table_name
                  from all_tables t
                 where t.owner = upper(:owner)
                   and t.table_name not like 'MD%'
                   and not exists (
                       select 1
                         from md_object o
                        where o.tenant_id = :tenant_id
                          and o.context_id = :context_id
                          and o.release_id = :release_id
                          and upper(o.schema_name) = upper(t.owner)
                          and upper(o.object_name) = upper(t.table_name)
                   )
                 order by t.table_name
                """,
                {
                    "owner": md_object_seed_schema,
                    "tenant_id": tenant_id,
                    "context_id": context_id,
                    "release_id": release_id,
                },
            )
        except Exception as exc:
            st.error(f"Unable to load physical tables for schema {md_object_seed_schema}: {exc}")

    if physical_tables:
        with st.form("create_md_object"):
            tbl_map = {f"{t['OWNER']}.{t['TABLE_NAME']}": t for t in physical_tables}
            tbl_label = st.selectbox("Physical table", options=list(tbl_map.keys()))
            table_rec = tbl_map[tbl_label]
            o_system_name = st.text_input("system_name", value="TARGET")
            o_schema_name = st.text_input("schema_name", value=table_rec["OWNER"])
            o_object_name = st.text_input("object_name", value=table_rec["TABLE_NAME"])
            o_object_type = st.selectbox("object_type", ["TABLE", "VIEW"], index=0)
            create_obj = st.form_submit_button("Insert MD_OBJECT")

        if create_obj:
            try:
                object_id = nextval("md_object_seq")
                execute_dml(
                    """
                    insert into md_object (
                      object_id,
                      tenant_id,
                      context_id,
                      release_id,
                      system_name,
                      schema_name,
                      object_name,
                      object_type
                    ) values (
                      :object_id,
                      :tenant_id,
                      :context_id,
                      :release_id,
                      :system_name,
                      :schema_name,
                      :object_name,
                      :object_type
                    )
                    """,
                    {
                        "object_id": object_id,
                        "tenant_id": tenant_id,
                        "context_id": context_id,
                        "release_id": release_id,
                        "system_name": o_system_name.strip(),
                        "schema_name": o_schema_name.strip().upper(),
                        "object_name": o_object_name.strip().upper(),
                        "object_type": o_object_type,
                    },
                )
                st.success(f"Inserted MD_OBJECT with object_id={object_id}")
                st.rerun()
            except Exception as exc:
                st.error(f"Insert failed: {exc}")
    else:
        st.info("No eligible physical tables found for the selected schema.")

    st.subheader("Update/Delete MD_OBJECT")
    if not md_objects_rows:
        st.info("No MD_OBJECT rows for selected release.")
    else:
        object_manage_map = {
            f"{o['OBJECT_ID']} | {o['SYSTEM_NAME']}.{o['OBJECT_NAME']} ({o['OBJECT_TYPE']})": o
            for o in md_objects_rows
        }
        object_label = st.selectbox("MD_OBJECT row", options=list(object_manage_map.keys()), key="manage_object")
        object_row = object_manage_map[object_label]
        object_row_id = object_row["OBJECT_ID"]

        with st.form("update_md_object"):
            u_obj_system = st.text_input(
                "system_name",
                value=object_row["SYSTEM_NAME"],
                key=f"u_obj_system_{object_row_id}",
            )
            u_obj_schema = st.text_input(
                "schema_name",
                value=object_row["SCHEMA_NAME"],
                key=f"u_obj_schema_{object_row_id}",
            )
            u_obj_name = st.text_input(
                "object_name",
                value=object_row["OBJECT_NAME"],
                key=f"u_obj_name_{object_row_id}",
            )
            u_obj_type = st.selectbox(
                "object_type",
                ["TABLE", "VIEW"],
                index=0 if object_row["OBJECT_TYPE"] == "TABLE" else 1,
                key=f"u_obj_type_{object_row_id}",
            )
            do_update_obj = st.form_submit_button("Update MD_OBJECT")

        if do_update_obj:
            try:
                execute_dml(
                    """
                    update md_object
                       set system_name = :system_name,
                           schema_name = :schema_name,
                           object_name = :object_name,
                           object_type = :object_type
                     where object_id = :object_id
                       and tenant_id = :tenant_id
                       and context_id = :context_id
                    """,
                    {
                        "system_name": u_obj_system.strip(),
                        "schema_name": u_obj_schema.strip().upper(),
                        "object_name": u_obj_name.strip().upper(),
                        "object_type": u_obj_type,
                        "object_id": object_row["OBJECT_ID"],
                        "tenant_id": tenant_id,
                        "context_id": context_id,
                    },
                )
                st.success("MD_OBJECT updated.")
                st.rerun()
            except Exception as exc:
                st.error(f"Update failed: {exc}")

        if st.button("Delete Selected MD_OBJECT", key="delete_md_object"):
            try:
                execute_dml(
                    """
                    delete from md_object
                     where object_id = :object_id
                       and tenant_id = :tenant_id
                       and context_id = :context_id
                    """,
                    {
                        "object_id": object_row["OBJECT_ID"],
                        "tenant_id": tenant_id,
                        "context_id": context_id,
                    },
                )
                st.success("MD_OBJECT deleted.")
                st.rerun()
            except Exception as exc:
                st.error(f"Delete failed: {exc}")

        st.subheader("Seed MD_COLUMN from Selected MD_OBJECT")
        st.caption(f"Source: {object_row['SCHEMA_NAME']}.{object_row['OBJECT_NAME']}")

        if st.button("Add All Missing Columns"):
            try:
                ins, _ = sync_md_columns_from_table(
                    tenant_id,
                    context_id,
                    object_row["OBJECT_ID"],
                    object_row["SCHEMA_NAME"],
                    object_row["OBJECT_NAME"],
                    delete_extra=False,
                )
                st.success(f"Added missing columns: {ins}")
                st.rerun()
            except Exception as exc:
                st.error(f"Sync failed: {exc}")

        object_columns = fetch_all(
            """
            select column_id,
                   column_name,
                   data_type,
                   nullable_flag,
                   ordinal_position
              from md_column
             where tenant_id = :tenant_id
               and context_id = :context_id
               and object_id = :object_id
             order by ordinal_position nulls last, column_name
            """,
            {
                "tenant_id": tenant_id,
                "context_id": context_id,
                "object_id": object_row["OBJECT_ID"],
            },
        )

        if object_columns:
            col_del_map = {
                f"{c['COLUMN_ID']} | {c['COLUMN_NAME']} | {c['DATA_TYPE']}": c
                for c in object_columns
            }
            col_del_label = st.selectbox("Delete MD_COLUMN row", options=list(col_del_map.keys()), key="delete_col_pick")
            if st.button("Delete Selected MD_COLUMN"):
                try:
                    execute_dml(
                        """
                        delete from md_column
                         where column_id = :column_id
                           and tenant_id = :tenant_id
                           and context_id = :context_id
                        """,
                        {
                            "column_id": col_del_map[col_del_label]["COLUMN_ID"],
                            "tenant_id": tenant_id,
                            "context_id": context_id,
                        },
                    )
                    st.success("MD_COLUMN deleted.")
                    st.rerun()
                except Exception as exc:
                    st.error(f"Delete failed: {exc}")

        with st.form("add_md_column_manual"):
            m_col_name = st.text_input("Manual add column_name")
            m_data_type = st.text_input("data_type", value="VARCHAR2")
            m_nullable = st.selectbox("nullable_flag", ["Y", "N"], index=0)
            m_ordinal = st.number_input("ordinal_position", min_value=1, value=1)
            add_manual_col = st.form_submit_button("Add MD_COLUMN")

        if add_manual_col:
            try:
                column_id = nextval("md_column_seq")
                execute_dml(
                    """
                    insert into md_column (
                      column_id,
                      tenant_id,
                      context_id,
                      object_id,
                      column_name,
                      data_type,
                      nullable_flag,
                      ordinal_position
                    ) values (
                      :column_id,
                      :tenant_id,
                      :context_id,
                      :object_id,
                      :column_name,
                      :data_type,
                      :nullable_flag,
                      :ordinal_position
                    )
                    """,
                    {
                        "column_id": column_id,
                        "tenant_id": tenant_id,
                        "context_id": context_id,
                        "object_id": object_row["OBJECT_ID"],
                        "column_name": m_col_name.strip().upper(),
                        "data_type": m_data_type.strip().upper(),
                        "nullable_flag": m_nullable,
                        "ordinal_position": int(m_ordinal),
                    },
                )
                st.success(f"Inserted MD_COLUMN with column_id={column_id}")
                st.rerun()
            except Exception as exc:
                st.error(f"Insert failed: {exc}")

with tab_event:
    st.subheader("MD_CHANGE_EVENT")
    with st.form("create_change_event"):
        ce_release_id = st.number_input("release_id", min_value=1, value=int(release_id))
        ce_event_type = st.selectbox("event_type", ["UPDATE", "INSERT", "DELETE", "KEY_CHANGE"])
        ce_source_system = st.text_input("source_system_name", value="SRC")
        ce_source_entity = st.text_input("source_entity_name")
        ce_source_key_json = st.text_area("source_key_json", value='{}', height=80)
        ce_old_key_json = st.text_area("old_key_json (optional)", value="", height=60)
        ce_new_key_json = st.text_area("new_key_json (optional)", value="", height=60)
        ce_source_key_hash = st.text_input("source_key_hash")
        ce_event_fingerprint = st.text_input("event_fingerprint", value=f"UI_EVT_{datetime.now().strftime('%Y%m%d%H%M%S')}")
        ce_processing_status = st.selectbox("processing_status", ["NEW", "SELECTED", "APPLIED", "FAILED", "SKIPPED"], index=0)
        ce_submit = st.form_submit_button("Insert MD_CHANGE_EVENT")

    if ce_submit:
        try:
            change_event_id = nextval("md_change_event_seq")
            execute_dml(
                """
                insert into md_change_event (
                  change_event_id,
                  tenant_id,
                  context_id,
                  release_id,
                  event_type,
                  source_system_name,
                  source_entity_name,
                  source_key_json,
                  old_key_json,
                  new_key_json,
                  source_key_hash,
                  event_ts,
                  event_fingerprint,
                  processing_status
                ) values (
                  :change_event_id,
                  :tenant_id,
                  :context_id,
                  :release_id,
                  :event_type,
                  :source_system_name,
                  :source_entity_name,
                  :source_key_json,
                  :old_key_json,
                  :new_key_json,
                  :source_key_hash,
                  systimestamp,
                  :event_fingerprint,
                  :processing_status
                )
                """,
                {
                    "change_event_id": change_event_id,
                    "tenant_id": tenant_id,
                    "context_id": context_id,
                    "release_id": int(ce_release_id),
                    "event_type": ce_event_type,
                    "source_system_name": ce_source_system.strip(),
                    "source_entity_name": ce_source_entity.strip(),
                    "source_key_json": ce_source_key_json.strip(),
                    "old_key_json": ce_old_key_json.strip() or None,
                    "new_key_json": ce_new_key_json.strip() or None,
                    "source_key_hash": ce_source_key_hash.strip(),
                    "event_fingerprint": ce_event_fingerprint.strip(),
                    "processing_status": ce_processing_status,
                },
            )
            st.success(f"Inserted MD_CHANGE_EVENT with change_event_id={change_event_id}")
            st.rerun()
        except Exception as exc:
            st.error(f"Insert failed: {exc}")

    if change_events:
        event_map = {
            f"{e['CHANGE_EVENT_ID']} | {e['EVENT_TYPE']} | {e['SOURCE_ENTITY_NAME']} | {e['PROCESSING_STATUS']}": e
            for e in change_events
        }
        selected_event_label = st.selectbox("Change event", options=list(event_map.keys()), key="manage_event")
        selected_event = event_map[selected_event_label]
        event_id = selected_event["CHANGE_EVENT_ID"]

        with st.form("update_change_event"):
            u_event_type = st.selectbox(
                "event_type",
                ["UPDATE", "INSERT", "DELETE", "KEY_CHANGE"],
                index=["UPDATE", "INSERT", "DELETE", "KEY_CHANGE"].index(selected_event["EVENT_TYPE"]),
                key=f"u_event_type_{event_id}",
            )
            u_source_system = st.text_input(
                "source_system_name",
                value=selected_event["SOURCE_SYSTEM_NAME"],
                key=f"u_event_source_system_{event_id}",
            )
            u_source_entity = st.text_input(
                "source_entity_name",
                value=selected_event["SOURCE_ENTITY_NAME"],
                key=f"u_event_source_entity_{event_id}",
            )
            u_source_key_hash = st.text_input(
                "source_key_hash",
                value=selected_event["SOURCE_KEY_HASH"],
                key=f"u_event_source_key_hash_{event_id}",
            )
            u_event_fingerprint = st.text_input(
                "event_fingerprint",
                value=selected_event["EVENT_FINGERPRINT"],
                key=f"u_event_fingerprint_{event_id}",
            )
            u_status = st.selectbox(
                "processing_status",
                ["NEW", "SELECTED", "APPLIED", "FAILED", "SKIPPED"],
                index=["NEW", "SELECTED", "APPLIED", "FAILED", "SKIPPED"].index(selected_event["PROCESSING_STATUS"]),
                key=f"u_event_status_{event_id}",
            )
            do_update_event = st.form_submit_button("Update MD_CHANGE_EVENT")

        if do_update_event:
            try:
                execute_dml(
                    """
                    update md_change_event
                       set event_type = :event_type,
                           source_system_name = :source_system_name,
                           source_entity_name = :source_entity_name,
                           source_key_hash = :source_key_hash,
                           event_fingerprint = :event_fingerprint,
                           processing_status = :processing_status
                     where change_event_id = :change_event_id
                       and tenant_id = :tenant_id
                       and context_id = :context_id
                    """,
                    {
                        "event_type": u_event_type,
                        "source_system_name": u_source_system.strip(),
                        "source_entity_name": u_source_entity.strip(),
                        "source_key_hash": u_source_key_hash.strip(),
                        "event_fingerprint": u_event_fingerprint.strip(),
                        "processing_status": u_status,
                        "change_event_id": selected_event["CHANGE_EVENT_ID"],
                        "tenant_id": tenant_id,
                        "context_id": context_id,
                    },
                )
                st.success("MD_CHANGE_EVENT updated.")
                st.rerun()
            except Exception as exc:
                st.error(f"Update failed: {exc}")

        if st.button("Delete Selected MD_CHANGE_EVENT", key="delete_change_event"):
            try:
                execute_dml(
                    """
                    delete from md_change_event
                     where change_event_id = :change_event_id
                       and tenant_id = :tenant_id
                       and context_id = :context_id
                    """,
                    {
                        "change_event_id": selected_event["CHANGE_EVENT_ID"],
                        "tenant_id": tenant_id,
                        "context_id": context_id,
                    },
                )
                st.success("MD_CHANGE_EVENT deleted.")
                st.rerun()
            except Exception as exc:
                st.error(f"Delete failed: {exc}")

        st.subheader("MD_CHANGE_EVENT_COLUMN_DELTA")
        deltas = fetch_all(
            """
            select change_event_column_delta_id,
                   source_column_name,
                   old_value_txt,
                   new_value_txt,
                   value_changed_flag
              from md_change_event_column_delta
             where tenant_id = :tenant_id
               and context_id = :context_id
               and change_event_id = :change_event_id
             order by change_event_column_delta_id
            """,
            {
                "tenant_id": tenant_id,
                "context_id": context_id,
                "change_event_id": event_id,
            },
        )

        with st.form("create_delta"):
            d_col_name = st.text_input("source_column_name")
            d_old = st.text_input("old_value_txt")
            d_new = st.text_input("new_value_txt")
            d_changed = st.selectbox("value_changed_flag", ["Y", "N"], index=0)
            do_add_delta = st.form_submit_button("Insert MD_CHANGE_EVENT_COLUMN_DELTA")

        if do_add_delta:
            try:
                delta_id = nextval("md_change_event_col_delta_seq")
                execute_dml(
                    """
                    insert into md_change_event_column_delta (
                      change_event_column_delta_id,
                      tenant_id,
                      context_id,
                      change_event_id,
                      source_column_name,
                      old_value_txt,
                      new_value_txt,
                      value_changed_flag
                    ) values (
                      :delta_id,
                      :tenant_id,
                      :context_id,
                      :change_event_id,
                      :source_column_name,
                      :old_value_txt,
                      :new_value_txt,
                      :value_changed_flag
                    )
                    """,
                    {
                        "delta_id": delta_id,
                        "tenant_id": tenant_id,
                        "context_id": context_id,
                        "change_event_id": event_id,
                        "source_column_name": d_col_name.strip().upper(),
                        "old_value_txt": d_old or None,
                        "new_value_txt": d_new or None,
                        "value_changed_flag": d_changed,
                    },
                )
                st.success(f"Inserted delta row id={delta_id}")
                st.rerun()
            except Exception as exc:
                st.error(f"Insert failed: {exc}")

        if deltas:
            delta_map = {
                f"{d['CHANGE_EVENT_COLUMN_DELTA_ID']} | {d['SOURCE_COLUMN_NAME']}": d
                for d in deltas
            }
            delta_label = st.selectbox("Delta row", options=list(delta_map.keys()), key="manage_delta")
            delta_row = delta_map[delta_label]
            delta_row_id = delta_row["CHANGE_EVENT_COLUMN_DELTA_ID"]

            with st.form("update_delta"):
                u_d_col_name = st.text_input(
                    "source_column_name",
                    value=delta_row["SOURCE_COLUMN_NAME"],
                    key=f"u_d_col_name_{delta_row_id}",
                )
                u_d_old = st.text_input(
                    "old_value_txt",
                    value=delta_row["OLD_VALUE_TXT"] or "",
                    key=f"u_d_old_{delta_row_id}",
                )
                u_d_new = st.text_input(
                    "new_value_txt",
                    value=delta_row["NEW_VALUE_TXT"] or "",
                    key=f"u_d_new_{delta_row_id}",
                )
                u_d_changed = st.selectbox(
                    "value_changed_flag",
                    ["Y", "N"],
                    index=0 if delta_row["VALUE_CHANGED_FLAG"] == "Y" else 1,
                    key=f"u_d_changed_{delta_row_id}",
                )
                do_update_delta = st.form_submit_button("Update Delta")

            if do_update_delta:
                try:
                    execute_dml(
                        """
                        update md_change_event_column_delta
                           set source_column_name = :source_column_name,
                               old_value_txt = :old_value_txt,
                               new_value_txt = :new_value_txt,
                               value_changed_flag = :value_changed_flag
                         where change_event_column_delta_id = :delta_id
                           and tenant_id = :tenant_id
                           and context_id = :context_id
                        """,
                        {
                            "source_column_name": u_d_col_name.strip().upper(),
                            "old_value_txt": u_d_old or None,
                            "new_value_txt": u_d_new or None,
                            "value_changed_flag": u_d_changed,
                            "delta_id": delta_row["CHANGE_EVENT_COLUMN_DELTA_ID"],
                            "tenant_id": tenant_id,
                            "context_id": context_id,
                        },
                    )
                    st.success("Delta updated.")
                    st.rerun()
                except Exception as exc:
                    st.error(f"Update failed: {exc}")

            if st.button("Delete Selected Delta", key="delete_delta"):
                try:
                    execute_dml(
                        """
                        delete from md_change_event_column_delta
                         where change_event_column_delta_id = :delta_id
                           and tenant_id = :tenant_id
                           and context_id = :context_id
                        """,
                        {
                            "delta_id": delta_row["CHANGE_EVENT_COLUMN_DELTA_ID"],
                            "tenant_id": tenant_id,
                            "context_id": context_id,
                        },
                    )
                    st.success("Delta deleted.")
                    st.rerun()
                except Exception as exc:
                    st.error(f"Delete failed: {exc}")
        else:
            st.info("No delta rows for selected event.")
    else:
        st.info("No MD_CHANGE_EVENT rows for selected tenant/context.")

with tab_check:
    with st.form("dual_check"):
        literal_value = st.text_input("Value", value="hello world")
        submit_dual = st.form_submit_button("Run select :v from dual")

    if submit_dual:
        try:
            out = fetch_one_value("select :v as input_value from dual", {"v": literal_value})
            st.code(str(out))
        except Exception as exc:
            st.error(f"Query failed: {exc}")
