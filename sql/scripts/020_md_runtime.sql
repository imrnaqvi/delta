-- 020_md_runtime.sql
-- Runtime/change-processing model (Oracle 19c)
-- Notes:
-- 1) Uses selective FKs for hot runtime tables.
-- 2) Idempotency is enforced with event fingerprints and a 30-day expiry column.

prompt Creating MD runtime tables and sequences...

create table md_change_event_raw (
  change_event_raw_id       number primary key,
  tenant_id                 varchar2(64) not null,
  context_id                varchar2(64) not null,
  source_system_name        varchar2(100) not null,
  source_entity_name        varchar2(128) not null,
  source_event_ts           timestamp not null,
  source_event_id           varchar2(200),
  payload_json              clob not null check (payload_json is json),
  ingested_at               timestamp default systimestamp not null
);

create sequence md_change_event_raw_seq start with 1 increment by 1 nocache;

create table md_change_event (
  change_event_id           number primary key,
  tenant_id                 varchar2(64) not null,
  context_id                varchar2(64) not null,
  release_id                number,
  change_event_raw_id       number,
  event_type                varchar2(20) not null,
  source_system_name        varchar2(100) not null,
  source_entity_name        varchar2(128) not null,
  source_key_json           clob not null check (source_key_json is json),
  old_key_json              clob check (old_key_json is json),
  new_key_json              clob check (new_key_json is json),
  source_key_hash           varchar2(128) not null,
  event_ts                  timestamp not null,
  event_fingerprint         varchar2(200) not null,
  processing_status         varchar2(20) default 'NEW' not null,
  created_at                timestamp default systimestamp not null,
  constraint md_change_event_type_ck check (event_type in ('UPDATE','INSERT','DELETE','KEY_CHANGE')),
  constraint md_change_event_status_ck check (processing_status in ('NEW','SELECTED','APPLIED','FAILED','SKIPPED')),
  constraint md_change_event_uq unique (tenant_id, context_id, event_fingerprint),
  constraint md_change_event_release_fk foreign key (release_id) references md_release(release_id),
  constraint md_change_event_raw_fk foreign key (change_event_raw_id) references md_change_event_raw(change_event_raw_id)
);

create sequence md_change_event_seq start with 1 increment by 1 nocache;

create table md_change_event_column_delta (
  change_event_column_delta_id number primary key,
  tenant_id                 varchar2(64) not null,
  context_id                varchar2(64) not null,
  change_event_id           number not null,
  source_column_name        varchar2(128) not null,
  old_value_txt             varchar2(4000),
  new_value_txt             varchar2(4000),
  value_changed_flag        varchar2(1) default 'Y' not null,
  created_at                timestamp default systimestamp not null,
  constraint md_change_delta_flag_ck check (value_changed_flag in ('Y','N')),
  constraint md_change_delta_event_fk foreign key (change_event_id) references md_change_event(change_event_id)
);

create sequence md_change_event_col_delta_seq start with 1 increment by 1 nocache;

create table md_execution_policy (
  execution_policy_id        number primary key,
  tenant_id                 varchar2(64) not null,
  context_id                varchar2(64) not null,
  release_id                number,
  policy_name               varchar2(100) not null,
  ordering_key              varchar2(100) not null,
  tie_breaker               varchar2(100) not null,
  idempotency_days          number default 30 not null,
  default_delete_policy     varchar2(20) default 'HARD_DELETE' not null,
  active_flag               varchar2(1) default 'Y' not null,
  created_at                timestamp default systimestamp not null,
  constraint md_exec_delete_policy_ck check (default_delete_policy in ('HARD_DELETE','SOFT_DELETE','RULE_DEFINED')),
  constraint md_exec_active_ck check (active_flag in ('Y','N')),
  constraint md_exec_policy_uq unique (tenant_id, context_id, policy_name),
  constraint md_exec_release_fk foreign key (release_id) references md_release(release_id)
);

create sequence md_execution_policy_seq start with 1 increment by 1 nocache;

create table md_run (
  run_id                    number primary key,
  tenant_id                 varchar2(64) not null,
  context_id                varchar2(64) not null,
  release_id                number not null,
  run_mode                  varchar2(20) not null,
  run_status                varchar2(20) not null,
  started_at                timestamp default systimestamp not null,
  ended_at                  timestamp,
  initiated_by              varchar2(128) not null,
  input_summary_json        clob check (input_summary_json is json),
  override_request_id       number,
  constraint md_run_mode_ck check (run_mode in ('FULL','SELECTIVE')),
  constraint md_run_status_ck check (run_status in ('RUNNING','SUCCEEDED','FAILED','PARTIAL')),
  constraint md_run_release_fk foreign key (release_id) references md_release(release_id),
  constraint md_run_override_fk foreign key (override_request_id) references md_override_request(override_request_id)
);

create sequence md_run_seq start with 1 increment by 1 nocache;

create table md_run_parameter (
  run_parameter_id          number primary key,
  tenant_id                 varchar2(64) not null,
  context_id                varchar2(64) not null,
  run_id                    number not null,
  param_name                varchar2(128) not null,
  param_value_txt           varchar2(4000),
  param_data_type           varchar2(128),
  created_at                timestamp default systimestamp not null,
  constraint md_run_param_uq unique (tenant_id, context_id, run_id, param_name),
  constraint md_run_param_run_fk foreign key (run_id) references md_run(run_id)
);

create sequence md_run_parameter_seq start with 1 increment by 1 nocache;

create table md_run_parameter_snapshot (
  run_parameter_snapshot_id  number primary key,
  tenant_id                 varchar2(64) not null,
  context_id                varchar2(64) not null,
  run_id                    number not null,
  parameter_json            clob not null check (parameter_json is json),
  parameter_hash            varchar2(200) not null,
  captured_at               timestamp default systimestamp not null,
  constraint md_run_param_snap_uq unique (tenant_id, context_id, run_id),
  constraint md_run_param_snap_run_fk foreign key (run_id) references md_run(run_id)
);

create sequence md_run_parameter_snapshot_seq start with 1 increment by 1 nocache;

create table md_run_correlation_group (
  run_correlation_group_id   number primary key,
  tenant_id                 varchar2(64) not null,
  context_id                varchar2(64) not null,
  run_id                    number not null,
  anchor_change_event_id    number,
  correlation_key           varchar2(256) not null,
  grouped_at                timestamp default systimestamp not null,
  constraint md_run_corr_group_uq unique (tenant_id, context_id, run_id, correlation_key),
  constraint md_run_corr_group_run_fk foreign key (run_id) references md_run(run_id),
  constraint md_run_corr_group_evt_fk foreign key (anchor_change_event_id) references md_change_event(change_event_id)
);

create sequence md_run_correlation_group_seq start with 1 increment by 1 nocache;

create table md_run_source_snapshot (
  run_source_snapshot_id      number primary key,
  tenant_id                 varchar2(64) not null,
  context_id                varchar2(64) not null,
  run_id                    number not null,
  change_event_id           number,
  rule_id                   number,
  source_context_id         number,
  correlation_key           varchar2(256),
  source_values_json        clob not null check (source_values_json is json),
  created_at                timestamp default systimestamp not null,
  constraint md_run_src_snap_uq unique (tenant_id, context_id, run_id, change_event_id, rule_id),
  constraint md_run_src_snap_run_fk foreign key (run_id) references md_run(run_id),
  constraint md_run_src_snap_evt_fk foreign key (change_event_id) references md_change_event(change_event_id),
  constraint md_run_src_snap_ctx_fk foreign key (source_context_id) references md_source_context(source_context_id)
);

create sequence md_run_source_snapshot_seq start with 1 increment by 1 nocache;

create table md_processed_event (
  processed_event_id        number primary key,
  tenant_id                 varchar2(64) not null,
  context_id                varchar2(64) not null,
  event_fingerprint         varchar2(200) not null,
  change_event_id           number,
  run_id                    number,
  processed_at              timestamp default systimestamp not null,
  expires_at                timestamp default (systimestamp + interval '30' day) not null,
  processing_result         varchar2(20) not null,
  constraint md_proc_event_result_ck check (processing_result in ('APPLIED','SKIPPED','FAILED')),
  constraint md_proc_event_uq unique (tenant_id, context_id, event_fingerprint),
  constraint md_proc_event_change_fk foreign key (change_event_id) references md_change_event(change_event_id),
  constraint md_proc_event_run_fk foreign key (run_id) references md_run(run_id)
);

create sequence md_processed_event_seq start with 1 increment by 1 nocache;

create table md_run_selected_rule (
  run_selected_rule_id      number primary key,
  tenant_id                 varchar2(64) not null,
  context_id                varchar2(64) not null,
  run_id                    number not null,
  change_event_id           number,
  rule_id                   number not null,
  selection_reason          varchar2(100) not null,
  transitive_flag           varchar2(1) default 'N' not null,
  selected_at               timestamp default systimestamp not null,
  constraint md_run_sel_trans_ck check (transitive_flag in ('Y','N')),
  constraint md_run_sel_reason_ck check (selection_reason in ('DIRECT_COLUMN_LINK','TRANSITIVE_DEPENDENCY','MANUAL_OVERRIDE_INCLUDE')),
  constraint md_run_sel_rule_uq unique (tenant_id, context_id, run_id, change_event_id, rule_id),
  constraint md_run_sel_run_fk foreign key (run_id) references md_run(run_id)
);

create sequence md_run_selected_rule_seq start with 1 increment by 1 nocache;

create table md_run_target_action (
  run_target_action_id      number primary key,
  tenant_id                 varchar2(64) not null,
  context_id                varchar2(64) not null,
  run_id                    number not null,
  change_event_id           number,
  rule_id                   number,
  target_object_id          number,
  target_system_name        varchar2(100) not null,
  target_entity_name        varchar2(128) not null,
  target_key_json           clob not null check (target_key_json is json),
  target_key_hash           varchar2(128) not null,
  target_column_name        varchar2(128),
  action_type               varchar2(20) not null,
  action_payload_json       clob check (action_payload_json is json),
  generated_sql_text        clob,
  bind_payload_json         clob check (bind_payload_json is json),
  execution_status          varchar2(20) default 'PLANNED' not null,
  rows_affected             number,
  error_code                number,
  error_message             varchar2(4000),
  applied_flag              varchar2(1) default 'N' not null,
  applied_at                timestamp,
  action_fingerprint        varchar2(200) not null,
  constraint md_run_tgt_action_ck check (action_type in ('UPDATE','INSERT','DELETE','SOFT_DELETE')),
  constraint md_run_tgt_exec_status_ck check (execution_status in ('PLANNED','EXECUTED','FAILED','SKIPPED')),
  constraint md_run_tgt_applied_ck check (applied_flag in ('Y','N')),
  constraint md_run_tgt_uq unique (tenant_id, context_id, run_id, action_fingerprint),
  constraint md_run_tgt_run_fk foreign key (run_id) references md_run(run_id),
  constraint md_run_tgt_obj_fk foreign key (target_object_id) references md_object(object_id)
);

create sequence md_run_target_action_seq start with 1 increment by 1 nocache;

create table md_run_target_value (
  run_target_value_id       number primary key,
  tenant_id                 varchar2(64) not null,
  context_id                varchar2(64) not null,
  run_id                    number not null,
  run_target_action_id      number,
  change_event_id           number,
  rule_id                   number,
  target_system_name        varchar2(100) not null,
  target_entity_name        varchar2(128) not null,
  target_key_json           clob not null check (target_key_json is json),
  target_key_hash           varchar2(128) not null,
  target_column_name        varchar2(128) not null,
  computed_value_txt        varchar2(4000),
  computed_value_json       clob check (computed_value_json is json),
  value_data_type           varchar2(128),
  value_status              varchar2(20) default 'COMPUTED' not null,
  applied_flag              varchar2(1) default 'N' not null,
  computed_at               timestamp default systimestamp not null,
  applied_at                timestamp,
  value_fingerprint         varchar2(200) not null,
  constraint md_run_tgt_value_status_ck check (value_status in ('COMPUTED','APPLIED','SKIPPED','FAILED')),
  constraint md_run_tgt_value_applied_ck check (applied_flag in ('Y','N')),
  constraint md_run_tgt_value_uq unique (tenant_id, context_id, run_id, value_fingerprint),
  constraint md_run_tgt_value_run_fk foreign key (run_id) references md_run(run_id),
  constraint md_run_tgt_value_action_fk foreign key (run_target_action_id) references md_run_target_action(run_target_action_id)
);

create sequence md_run_target_value_seq start with 1 increment by 1 nocache;

create table md_impact_trace (
  impact_trace_id           number primary key,
  tenant_id                 varchar2(64) not null,
  context_id                varchar2(64) not null,
  run_id                    number not null,
  change_event_id           number,
  source_ref_json           clob not null check (source_ref_json is json),
  rule_ref_json             clob not null check (rule_ref_json is json),
  target_ref_json           clob not null check (target_ref_json is json),
  created_at                timestamp default systimestamp not null,
  constraint md_impact_trace_run_fk foreign key (run_id) references md_run(run_id)
);

create sequence md_impact_trace_seq start with 1 increment by 1 nocache;

create table md_override_approval (
  override_approval_id      number primary key,
  tenant_id                 varchar2(64) not null,
  context_id                varchar2(64) not null,
  override_request_id       number not null,
  approver_id               varchar2(128) not null,
  approved_at               timestamp default systimestamp not null,
  approval_note             varchar2(2000),
  approval_status           varchar2(20) not null,
  constraint md_override_appr_status_ck check (approval_status in ('APPROVED','REJECTED')),
  constraint md_override_appr_req_uq unique (tenant_id, context_id, override_request_id),
  constraint md_override_appr_req_fk foreign key (override_request_id) references md_override_request(override_request_id)
);

create sequence md_override_approval_seq start with 1 increment by 1 nocache;

prompt MD runtime script complete.
