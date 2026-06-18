-- 030_md_audit.sql
-- Audit model with append-only enforcement (Oracle 19c)
-- Database-only immutability via trigger guards.

prompt Creating MD audit tables, sequences, and immutability triggers...

create table md_audit_event (
  audit_event_id            number primary key,
  tenant_id                 varchar2(64) not null,
  context_id                varchar2(64) not null,
  run_id                    number,
  release_id                number,
  event_ts                  timestamp default systimestamp not null,
  actor_id                  varchar2(128) not null,
  event_type                varchar2(60) not null,
  object_type               varchar2(60) not null,
  object_id_txt             varchar2(200),
  reason_code               varchar2(100),
  reason_detail             varchar2(2000),
  correlation_id            varchar2(200),
  previous_hash             varchar2(128),
  event_hash                varchar2(128) not null,
  payload_json              clob check (payload_json is json),
  immutable_flag            varchar2(1) default 'Y' not null,
  created_at                timestamp default systimestamp not null,
  constraint md_audit_immutable_ck check (immutable_flag in ('Y','N')),
  constraint md_audit_event_hash_uq unique (tenant_id, context_id, event_hash),
  constraint md_audit_run_fk foreign key (run_id) references md_run(run_id),
  constraint md_audit_release_fk foreign key (release_id) references md_release(release_id)
);

create sequence md_audit_event_seq start with 1 increment by 1 nocache;

create table md_audit_event_detail (
  audit_event_detail_id     number primary key,
  tenant_id                 varchar2(64) not null,
  context_id                varchar2(64) not null,
  audit_event_id            number not null,
  attr_name                 varchar2(200) not null,
  old_value_txt             varchar2(4000),
  new_value_txt             varchar2(4000),
  created_at                timestamp default systimestamp not null,
  constraint md_audit_detail_uq unique (tenant_id, context_id, audit_event_id, attr_name),
  constraint md_audit_detail_event_fk foreign key (audit_event_id) references md_audit_event(audit_event_id)
);

create sequence md_audit_event_detail_seq start with 1 increment by 1 nocache;

create or replace trigger md_audit_event_no_update_delete_trg
before update or delete on md_audit_event
for each row
begin
  raise_application_error(-20001, 'MD_AUDIT_EVENT is append-only. Updates and deletes are not allowed.');
end;
/

create or replace trigger md_audit_event_detail_no_update_delete_trg
before update or delete on md_audit_event_detail
for each row
begin
  raise_application_error(-20002, 'MD_AUDIT_EVENT_DETAIL is append-only. Updates and deletes are not allowed.');
end;
/

prompt MD audit script complete.
