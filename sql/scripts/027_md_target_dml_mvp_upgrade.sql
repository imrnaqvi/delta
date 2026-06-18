-- 027_md_target_dml_mvp_upgrade.sql
-- Incremental/idempotent upgrade for target DML MVP metadata/runtime support.

prompt Applying target DML MVP upgrade...

declare
  l_count number;
begin
  -- ===== Extend md_rule_target_action =====
  select count(*) into l_count
    from user_tab_cols
   where table_name = 'MD_RULE_TARGET_ACTION'
     and column_name = 'TARGET_KEY_ID';
  if l_count = 0 then
    execute immediate 'alter table md_rule_target_action add (target_key_id number)';
  end if;

  select count(*) into l_count
    from user_tab_cols
   where table_name = 'MD_RULE_TARGET_ACTION'
     and column_name = 'EXECUTION_MODE';
  if l_count = 0 then
    execute immediate q'[alter table md_rule_target_action add (execution_mode varchar2(20) default 'APPLY' not null)]';
  end if;

  select count(*) into l_count
    from user_tab_cols
   where table_name = 'MD_RULE_TARGET_ACTION'
     and column_name = 'MISSING_ROW_POLICY';
  if l_count = 0 then
    execute immediate q'[alter table md_rule_target_action add (missing_row_policy varchar2(20) default 'ERROR' not null)]';
  end if;

  select count(*) into l_count
    from user_tab_cols
   where table_name = 'MD_RULE_TARGET_ACTION'
     and column_name = 'DELETE_POLICY';
  if l_count = 0 then
    execute immediate q'[alter table md_rule_target_action add (delete_policy varchar2(20) default 'RULE_DEFINED' not null)]';
  end if;

  select count(*) into l_count from user_constraints where constraint_name = 'MD_RULE_TGT_EXEC_MODE_CK';
  if l_count = 0 then
    execute immediate q'[alter table md_rule_target_action add constraint md_rule_tgt_exec_mode_ck check (execution_mode in ('PREVIEW','APPLY'))]';
  end if;

  select count(*) into l_count from user_constraints where constraint_name = 'MD_RULE_TGT_MISSING_ROW_CK';
  if l_count = 0 then
    execute immediate q'[alter table md_rule_target_action add constraint md_rule_tgt_missing_row_ck check (missing_row_policy in ('ERROR','INSERT','SKIP'))]';
  end if;

  select count(*) into l_count from user_constraints where constraint_name = 'MD_RULE_TGT_DEL_POLICY_CK';
  if l_count = 0 then
    execute immediate q'[alter table md_rule_target_action add constraint md_rule_tgt_del_policy_ck check (delete_policy in ('HARD_DELETE','SOFT_DELETE','RULE_DEFINED'))]';
  end if;

  select count(*) into l_count from user_constraints where constraint_name = 'MD_RULE_TGT_KEY_FK';
  if l_count = 0 then
    execute immediate 'alter table md_rule_target_action add constraint md_rule_tgt_key_fk foreign key (target_key_id) references md_key_definition(key_id)';
  end if;

  -- ===== Create md_rule_target_key_map =====
  select count(*) into l_count from user_tables where table_name = 'MD_RULE_TARGET_KEY_MAP';
  if l_count = 0 then
    execute immediate q'[
      create table md_rule_target_key_map (
        rule_target_key_map_id     number primary key,
        tenant_id                  varchar2(64) not null,
        context_id                 varchar2(64) not null,
        release_id                 number not null,
        rule_target_action_id      number not null,
        target_key_component_id    number not null,
        source_kind                varchar2(20) not null,
        source_expr                clob not null,
        required_flag              varchar2(1) default 'Y' not null,
        created_at                 timestamp default systimestamp not null,
        constraint md_rule_tgt_key_map_kind_ck check (source_kind in ('SOURCE_ALIAS','PARAM','RULE_OUTPUT','EXPR','LITERAL')),
        constraint md_rule_tgt_key_map_req_ck check (required_flag in ('Y','N')),
        constraint md_rule_tgt_key_map_uq unique (tenant_id, context_id, rule_target_action_id, target_key_component_id),
        constraint md_rule_tgt_key_map_rel_fk foreign key (release_id) references md_release(release_id),
        constraint md_rule_tgt_key_map_act_fk foreign key (rule_target_action_id) references md_rule_target_action(rule_target_action_id),
        constraint md_rule_tgt_key_map_comp_fk foreign key (target_key_component_id) references md_key_component(key_component_id)
      )
    ]';
  end if;

  select count(*) into l_count from user_sequences where sequence_name = 'MD_RULE_TARGET_KEY_MAP_SEQ';
  if l_count = 0 then
    execute immediate 'create sequence md_rule_target_key_map_seq start with 1 increment by 1 nocache';
  end if;

  execute immediate q'[
    create or replace trigger md_rule_target_key_map_bi_trg
    before insert on md_rule_target_key_map
    for each row
    when (new.rule_target_key_map_id is null)
    begin
      :new.rule_target_key_map_id := md_rule_target_key_map_seq.nextval;
    end;
  ]';

  -- ===== Create md_rule_target_column_map =====
  select count(*) into l_count from user_tables where table_name = 'MD_RULE_TARGET_COLUMN_MAP';
  if l_count = 0 then
    execute immediate q'[
      create table md_rule_target_column_map (
        rule_target_column_map_id  number primary key,
        tenant_id                  varchar2(64) not null,
        context_id                 varchar2(64) not null,
        release_id                 number not null,
        rule_target_action_id      number not null,
        target_column_id           number not null,
        value_source_kind          varchar2(20) not null,
        value_expr                 clob,
        required_flag              varchar2(1) default 'Y' not null,
        write_on_insert_flag       varchar2(1) default 'Y' not null,
        write_on_update_flag       varchar2(1) default 'Y' not null,
        created_at                 timestamp default systimestamp not null,
        constraint md_rule_tgt_col_map_kind_ck check (value_source_kind in ('COMPUTED_VALUE_TXT','COMPUTED_VALUE_JSON','SOURCE_ALIAS','PARAM','EXPR','LITERAL')),
        constraint md_rule_tgt_col_map_req_ck check (required_flag in ('Y','N')),
        constraint md_rule_tgt_col_map_ins_ck check (write_on_insert_flag in ('Y','N')),
        constraint md_rule_tgt_col_map_upd_ck check (write_on_update_flag in ('Y','N')),
        constraint md_rule_tgt_col_map_uq unique (tenant_id, context_id, rule_target_action_id, target_column_id),
        constraint md_rule_tgt_col_map_rel_fk foreign key (release_id) references md_release(release_id),
        constraint md_rule_tgt_col_map_act_fk foreign key (rule_target_action_id) references md_rule_target_action(rule_target_action_id),
        constraint md_rule_tgt_col_map_col_fk foreign key (target_column_id) references md_column(column_id)
      )
    ]';
  end if;

  select count(*) into l_count from user_sequences where sequence_name = 'MD_RULE_TARGET_COLUMN_MAP_SEQ';
  if l_count = 0 then
    execute immediate 'create sequence md_rule_target_column_map_seq start with 1 increment by 1 nocache';
  end if;

  execute immediate q'[
    create or replace trigger md_rule_target_col_map_bi_trg
    before insert on md_rule_target_column_map
    for each row
    when (new.rule_target_column_map_id is null)
    begin
      :new.rule_target_column_map_id := md_rule_target_column_map_seq.nextval;
    end;
  ]';

  -- ===== Extend md_run_target_action =====
  select count(*) into l_count
    from user_tab_cols
   where table_name = 'MD_RUN_TARGET_ACTION'
     and column_name = 'TARGET_OBJECT_ID';
  if l_count = 0 then
    execute immediate 'alter table md_run_target_action add (target_object_id number)';
  end if;

  select count(*) into l_count
    from user_tab_cols
   where table_name = 'MD_RUN_TARGET_ACTION'
     and column_name = 'GENERATED_SQL_TEXT';
  if l_count = 0 then
    execute immediate 'alter table md_run_target_action add (generated_sql_text clob)';
  end if;

  select count(*) into l_count
    from user_tab_cols
   where table_name = 'MD_RUN_TARGET_ACTION'
     and column_name = 'BIND_PAYLOAD_JSON';
  if l_count = 0 then
    execute immediate 'alter table md_run_target_action add (bind_payload_json clob)';
  end if;

  select count(*) into l_count
    from user_tab_cols
   where table_name = 'MD_RUN_TARGET_ACTION'
     and column_name = 'EXECUTION_STATUS';
  if l_count = 0 then
    execute immediate q'[alter table md_run_target_action add (execution_status varchar2(20) default 'PLANNED' not null)]';
  end if;

  select count(*) into l_count
    from user_tab_cols
   where table_name = 'MD_RUN_TARGET_ACTION'
     and column_name = 'ROWS_AFFECTED';
  if l_count = 0 then
    execute immediate 'alter table md_run_target_action add (rows_affected number)';
  end if;

  select count(*) into l_count
    from user_tab_cols
   where table_name = 'MD_RUN_TARGET_ACTION'
     and column_name = 'ERROR_CODE';
  if l_count = 0 then
    execute immediate 'alter table md_run_target_action add (error_code number)';
  end if;

  select count(*) into l_count
    from user_tab_cols
   where table_name = 'MD_RUN_TARGET_ACTION'
     and column_name = 'ERROR_MESSAGE';
  if l_count = 0 then
    execute immediate 'alter table md_run_target_action add (error_message varchar2(4000))';
  end if;

  select count(*) into l_count from user_constraints where constraint_name = 'MD_RUN_TGT_BIND_JSON_CK';
  if l_count = 0 then
    execute immediate 'alter table md_run_target_action add constraint md_run_tgt_bind_json_ck check (bind_payload_json is json)';
  end if;

  select count(*) into l_count from user_constraints where constraint_name = 'MD_RUN_TGT_EXEC_STATUS_CK';
  if l_count = 0 then
    execute immediate q'[alter table md_run_target_action add constraint md_run_tgt_exec_status_ck check (execution_status in ('PLANNED','EXECUTED','FAILED','SKIPPED'))]';
  end if;

  select count(*) into l_count from user_constraints where constraint_name = 'MD_RUN_TGT_OBJ_FK';
  if l_count = 0 then
    execute immediate 'alter table md_run_target_action add constraint md_run_tgt_obj_fk foreign key (target_object_id) references md_object(object_id)';
  end if;

  -- ===== Indexes =====
  select count(*) into l_count from user_indexes where index_name = 'MD_RULE_TGT_KEY_IX';
  if l_count = 0 then
    execute immediate 'create index md_rule_tgt_key_ix on md_rule_target_action (target_key_id, execution_mode, action_type)';
  end if;

  select count(*) into l_count from user_indexes where index_name = 'MD_RULE_TGT_KEY_MAP_ACT_IX';
  if l_count = 0 then
    execute immediate 'create index md_rule_tgt_key_map_act_ix on md_rule_target_key_map (tenant_id, context_id, rule_target_action_id)';
  end if;

  select count(*) into l_count from user_indexes where index_name = 'MD_RULE_TGT_COL_MAP_ACT_IX';
  if l_count = 0 then
    execute immediate 'create index md_rule_tgt_col_map_act_ix on md_rule_target_column_map (tenant_id, context_id, rule_target_action_id)';
  end if;

  select count(*) into l_count from user_indexes where index_name = 'MD_TGT_ACTION_EXEC_IX';
  if l_count = 0 then
    execute immediate 'create index md_tgt_action_exec_ix on md_run_target_action (execution_status, applied_flag, applied_at)';
  end if;

  select count(*) into l_count from user_indexes where index_name = 'MD_TGT_ACTION_OBJ_IX';
  if l_count = 0 then
    execute immediate 'create index md_tgt_action_obj_ix on md_run_target_action (run_id, target_object_id, rule_id)';
  end if;
end;
/

prompt Target DML MVP upgrade complete.
