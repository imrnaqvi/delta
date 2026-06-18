-- 026_md_runtime_params_upgrade.sql
-- Incremental/idempotent upgrade for runtime parameter support.

prompt Applying runtime parameter upgrade...

declare
  l_count number;
begin
  select count(*) into l_count from user_tables where table_name = 'MD_RULE_PARAMETER_REQUIREMENT';
  if l_count = 0 then
    execute immediate q'[
      create table md_rule_parameter_requirement (
        rule_parameter_requirement_id number primary key,
        tenant_id                 varchar2(64) not null,
        context_id                varchar2(64) not null,
        release_id                number not null,
        rule_id                   number not null,
        param_name                varchar2(128) not null,
        param_data_type           varchar2(128),
        required_flag             varchar2(1) default 'Y' not null,
        default_value_txt         clob,
        created_at                timestamp default systimestamp not null,
        constraint md_rule_param_req_required_ck check (required_flag in ('Y','N')),
        constraint md_rule_param_req_uq unique (tenant_id, context_id, release_id, rule_id, param_name),
        constraint md_rule_param_req_release_fk foreign key (release_id) references md_release(release_id),
        constraint md_rule_param_req_rule_fk foreign key (rule_id) references md_rule(rule_id)
      )
    ]';
  end if;

  select count(*) into l_count from user_sequences where sequence_name = 'MD_RULE_PARAMETER_REQUIREMENT_SEQ';
  if l_count = 0 then
    execute immediate 'create sequence md_rule_parameter_requirement_seq start with 1 increment by 1 nocache';
  end if;

  select count(*) into l_count from user_tables where table_name = 'MD_RUN_PARAMETER';
  if l_count = 0 then
    execute immediate q'[
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
      )
    ]';
  end if;

  select count(*) into l_count from user_sequences where sequence_name = 'MD_RUN_PARAMETER_SEQ';
  if l_count = 0 then
    execute immediate 'create sequence md_run_parameter_seq start with 1 increment by 1 nocache';
  end if;

  select count(*) into l_count from user_tables where table_name = 'MD_RUN_PARAMETER_SNAPSHOT';
  if l_count = 0 then
    execute immediate q'[
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
      )
    ]';
  end if;

  select count(*) into l_count from user_sequences where sequence_name = 'MD_RUN_PARAMETER_SNAPSHOT_SEQ';
  if l_count = 0 then
    execute immediate 'create sequence md_run_parameter_snapshot_seq start with 1 increment by 1 nocache';
  end if;
end;
/

prompt Runtime parameter upgrade complete.
