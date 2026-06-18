-- 025_md_context_graph_upgrade.sql
-- Incremental/idempotent upgrade for cross-entity source context graph + correlation runtime.

prompt Applying context-graph and correlation upgrade...

declare
  l_count number;
begin
  select count(*) into l_count from user_tables where table_name = 'MD_SOURCE_CONTEXT';
  if l_count = 0 then
    execute immediate q'[
      create table md_source_context (
        source_context_id         number primary key,
        tenant_id                 varchar2(64) not null,
        context_id                varchar2(64) not null,
        release_id                number not null,
        context_name              varchar2(200) not null,
        anchor_object_id          number not null,
        active_flag               varchar2(1) default 'Y' not null,
        created_at                timestamp default systimestamp not null,
        constraint md_src_ctx_active_ck check (active_flag in ('Y','N')),
        constraint md_src_ctx_uq unique (tenant_id, context_id, release_id, context_name),
        constraint md_src_ctx_release_fk foreign key (release_id) references md_release(release_id),
        constraint md_src_ctx_anchor_fk foreign key (anchor_object_id) references md_object(object_id)
      )
    ]';
  end if;

  select count(*) into l_count from user_sequences where sequence_name = 'MD_SOURCE_CONTEXT_SEQ';
  if l_count = 0 then
    execute immediate 'create sequence md_source_context_seq start with 1 increment by 1 nocache';
  end if;

  select count(*) into l_count from user_tables where table_name = 'MD_SOURCE_CONTEXT_OBJECT';
  if l_count = 0 then
    execute immediate q'[
      create table md_source_context_object (
        source_context_object_id  number primary key,
        tenant_id                 varchar2(64) not null,
        context_id                varchar2(64) not null,
        source_context_id         number not null,
        object_id                 number not null,
        object_alias              varchar2(64) not null,
        role_type                 varchar2(20) not null,
        required_flag             varchar2(1) default 'Y' not null,
        created_at                timestamp default systimestamp not null,
        constraint md_src_ctx_obj_role_ck check (role_type in ('ANCHOR','JOINED')),
        constraint md_src_ctx_obj_req_ck check (required_flag in ('Y','N')),
        constraint md_src_ctx_obj_alias_uq unique (tenant_id, context_id, source_context_id, object_alias),
        constraint md_src_ctx_obj_ref_uq unique (tenant_id, context_id, source_context_id, object_id),
        constraint md_src_ctx_obj_ctx_fk foreign key (source_context_id) references md_source_context(source_context_id),
        constraint md_src_ctx_obj_obj_fk foreign key (object_id) references md_object(object_id)
      )
    ]';
  end if;

  select count(*) into l_count from user_sequences where sequence_name = 'MD_SOURCE_CONTEXT_OBJECT_SEQ';
  if l_count = 0 then
    execute immediate 'create sequence md_source_context_object_seq start with 1 increment by 1 nocache';
  end if;

  select count(*) into l_count from user_tables where table_name = 'MD_SOURCE_CONTEXT_JOIN';
  if l_count = 0 then
    execute immediate q'[
      create table md_source_context_join (
        source_context_join_id    number primary key,
        tenant_id                 varchar2(64) not null,
        context_id                varchar2(64) not null,
        source_context_id         number not null,
        left_alias                varchar2(64) not null,
        right_alias               varchar2(64) not null,
        join_type                 varchar2(20) not null,
        join_expr                 clob not null,
        active_flag               varchar2(1) default 'Y' not null,
        created_at                timestamp default systimestamp not null,
        constraint md_src_ctx_join_type_ck check (join_type in ('INNER','LEFT')),
        constraint md_src_ctx_join_active_ck check (active_flag in ('Y','N')),
        constraint md_src_ctx_join_uq unique (tenant_id, context_id, source_context_id, left_alias, right_alias),
        constraint md_src_ctx_join_ctx_fk foreign key (source_context_id) references md_source_context(source_context_id)
      )
    ]';
  end if;

  select count(*) into l_count from user_sequences where sequence_name = 'MD_SOURCE_CONTEXT_JOIN_SEQ';
  if l_count = 0 then
    execute immediate 'create sequence md_source_context_join_seq start with 1 increment by 1 nocache';
  end if;

  select count(*) into l_count from user_tables where table_name = 'MD_RULE_SOURCE_CONTEXT';
  if l_count = 0 then
    execute immediate q'[
      create table md_rule_source_context (
        rule_source_context_id     number primary key,
        tenant_id                  varchar2(64) not null,
        context_id                 varchar2(64) not null,
        release_id                 number not null,
        rule_id                    number not null,
        source_context_id          number not null,
        active_flag                varchar2(1) default 'Y' not null,
        created_at                 timestamp default systimestamp not null,
        constraint md_rule_src_ctx_active_ck check (active_flag in ('Y','N')),
        constraint md_rule_src_ctx_uq unique (tenant_id, context_id, release_id, rule_id),
        constraint md_rule_src_ctx_release_fk foreign key (release_id) references md_release(release_id),
        constraint md_rule_src_ctx_rule_fk foreign key (rule_id) references md_rule(rule_id),
        constraint md_rule_src_ctx_ctx_fk foreign key (source_context_id) references md_source_context(source_context_id)
      )
    ]';
  end if;

  select count(*) into l_count from user_sequences where sequence_name = 'MD_RULE_SOURCE_CONTEXT_SEQ';
  if l_count = 0 then
    execute immediate 'create sequence md_rule_source_context_seq start with 1 increment by 1 nocache';
  end if;

  select count(*) into l_count from user_tables where table_name = 'MD_RULE_SOURCE_OBJECT';
  if l_count = 0 then
    execute immediate q'[
      create table md_rule_source_object (
        rule_source_object_id      number primary key,
        tenant_id                  varchar2(64) not null,
        context_id                 varchar2(64) not null,
        rule_id                    number not null,
        object_id                  number not null,
        source_alias               varchar2(30) not null,
        role_code                  varchar2(20) default 'JOINED' not null,
        anchor_flag                varchar2(1) default 'N' not null,
        active_flag                varchar2(1) default 'Y' not null,
        created_at                 timestamp default systimestamp not null,
        constraint md_rule_src_obj_role_ck check (role_code in ('ANCHOR','JOINED')),
        constraint md_rule_src_obj_anchor_ck check (anchor_flag in ('Y','N')),
        constraint md_rule_src_obj_active_ck check (active_flag in ('Y','N')),
        constraint md_rule_src_obj_alias_uq unique (tenant_id, context_id, rule_id, source_alias),
        constraint md_rule_src_obj_uq unique (tenant_id, context_id, rule_id, object_id),
        constraint md_rule_src_obj_rule_fk foreign key (rule_id) references md_rule(rule_id),
        constraint md_rule_src_obj_obj_fk foreign key (object_id) references md_object(object_id)
      )
    ]';
  end if;

  select count(*) into l_count from user_sequences where sequence_name = 'MD_RULE_SOURCE_OBJECT_SEQ';
  if l_count = 0 then
    execute immediate 'create sequence md_rule_source_object_seq start with 1 increment by 1 nocache';
  end if;

  select count(*) into l_count from user_tables where table_name = 'MD_RULE_SOURCE_JOIN';
  if l_count = 0 then
    execute immediate q'[
      create table md_rule_source_join (
        rule_source_join_id        number primary key,
        tenant_id                  varchar2(64) not null,
        context_id                 varchar2(64) not null,
        rule_id                    number not null,
        join_order                 number not null,
        left_source_object_id      number not null,
        right_source_object_id     number not null,
        join_type                  varchar2(10) default 'INNER' not null,
        join_condition_expr        clob not null,
        active_flag                varchar2(1) default 'Y' not null,
        created_at                 timestamp default systimestamp not null,
        constraint md_rule_src_join_type_ck check (join_type in ('INNER','LEFT')),
        constraint md_rule_src_join_active_ck check (active_flag in ('Y','N')),
        constraint md_rule_src_join_order_uq unique (tenant_id, context_id, rule_id, join_order),
        constraint md_rule_src_join_uq unique (tenant_id, context_id, rule_id, left_source_object_id, right_source_object_id),
        constraint md_rule_src_join_rule_fk foreign key (rule_id) references md_rule(rule_id),
        constraint md_rule_src_join_left_fk foreign key (left_source_object_id) references md_rule_source_object(rule_source_object_id),
        constraint md_rule_src_join_right_fk foreign key (right_source_object_id) references md_rule_source_object(rule_source_object_id)
      )
    ]';
  end if;

  select count(*) into l_count from user_sequences where sequence_name = 'MD_RULE_SOURCE_JOIN_SEQ';
  if l_count = 0 then
    execute immediate 'create sequence md_rule_source_join_seq start with 1 increment by 1 nocache';
  end if;

  select count(*) into l_count from user_tables where table_name = 'MD_CORRELATION_POLICY';
  if l_count = 0 then
    execute immediate q'[
      create table md_correlation_policy (
        correlation_policy_id       number primary key,
        tenant_id                  varchar2(64) not null,
        context_id                 varchar2(64) not null,
        release_id                 number not null,
        policy_name                varchar2(100) not null,
        correlation_mode           varchar2(30) default 'SOURCE_KEY_HASH' not null,
        window_minutes             number default 15 not null,
        active_flag                varchar2(1) default 'Y' not null,
        created_at                 timestamp default systimestamp not null,
        constraint md_corr_policy_mode_ck check (correlation_mode in ('SOURCE_KEY_HASH')),
        constraint md_corr_policy_window_ck check (window_minutes >= 0),
        constraint md_corr_policy_active_ck check (active_flag in ('Y','N')),
        constraint md_corr_policy_uq unique (tenant_id, context_id, release_id, policy_name),
        constraint md_corr_policy_rel_fk foreign key (release_id) references md_release(release_id)
      )
    ]';
  end if;

  select count(*) into l_count from user_sequences where sequence_name = 'MD_CORRELATION_POLICY_SEQ';
  if l_count = 0 then
    execute immediate 'create sequence md_correlation_policy_seq start with 1 increment by 1 nocache';
  end if;

  select count(*) into l_count from user_tables where table_name = 'MD_RUN_CORRELATION_GROUP';
  if l_count = 0 then
    execute immediate q'[
      create table md_run_correlation_group (
        run_correlation_group_id   number primary key,
        tenant_id                  varchar2(64) not null,
        context_id                 varchar2(64) not null,
        run_id                     number not null,
        anchor_change_event_id     number,
        correlation_key            varchar2(256) not null,
        grouped_at                 timestamp default systimestamp not null,
        constraint md_run_corr_group_uq unique (tenant_id, context_id, run_id, correlation_key),
        constraint md_run_corr_group_run_fk foreign key (run_id) references md_run(run_id),
        constraint md_run_corr_group_evt_fk foreign key (anchor_change_event_id) references md_change_event(change_event_id)
      )
    ]';
  end if;

  select count(*) into l_count from user_sequences where sequence_name = 'MD_RUN_CORRELATION_GROUP_SEQ';
  if l_count = 0 then
    execute immediate 'create sequence md_run_correlation_group_seq start with 1 increment by 1 nocache';
  end if;

  select count(*) into l_count from user_tables where table_name = 'MD_RUN_SOURCE_SNAPSHOT';
  if l_count = 0 then
    execute immediate q'[
      create table md_run_source_snapshot (
        run_source_snapshot_id      number primary key,
        tenant_id                  varchar2(64) not null,
        context_id                 varchar2(64) not null,
        run_id                     number not null,
        change_event_id            number,
        rule_id                    number,
        source_context_id          number,
        correlation_key            varchar2(256),
        source_values_json         clob not null check (source_values_json is json),
        created_at                 timestamp default systimestamp not null,
        constraint md_run_src_snap_uq unique (tenant_id, context_id, run_id, change_event_id, rule_id),
        constraint md_run_src_snap_run_fk foreign key (run_id) references md_run(run_id),
        constraint md_run_src_snap_evt_fk foreign key (change_event_id) references md_change_event(change_event_id),
        constraint md_run_src_snap_ctx_fk foreign key (source_context_id) references md_source_context(source_context_id)
      )
    ]';
  end if;

  select count(*) into l_count from user_sequences where sequence_name = 'MD_RUN_SOURCE_SNAPSHOT_SEQ';
  if l_count = 0 then
    execute immediate 'create sequence md_run_source_snapshot_seq start with 1 increment by 1 nocache';
  end if;
end;
/

prompt Context-graph and correlation upgrade complete.
