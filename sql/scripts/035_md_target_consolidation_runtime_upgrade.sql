-- 035_md_target_consolidation_runtime_upgrade.sql
-- Incremental/idempotent runtime upgrade for consolidated target execution artifacts.

prompt Applying target consolidation runtime upgrade...

declare
  l_count number;
begin
  -- Consolidation header table.
  select count(*) into l_count from user_tables where table_name = 'MD_RUN_TARGET_CONSOLIDATION';
  if l_count = 0 then
    execute immediate q'[
      create table md_run_target_consolidation (
        run_target_consolidation_id   number primary key,
        tenant_id                     varchar2(64) not null,
        context_id                    varchar2(64) not null,
        run_id                        number not null,
        change_event_id               number not null,
        target_entity_name            varchar2(256) not null,
        target_key_json               clob not null,
        target_key_hash               varchar2(128) not null,
        consolidation_status          varchar2(20) default 'READY' not null,
        winning_value_count           number default 0 not null,
        source_rule_count             number default 0 not null,
        created_at                    timestamp default systimestamp not null,
        updated_at                    timestamp default systimestamp not null,
        constraint md_run_tgt_cons_status_ck check (consolidation_status in ('READY','PARTIAL','FAILED','EXECUTED')),
        constraint md_run_tgt_cons_uq unique (
          tenant_id, context_id, run_id, change_event_id, target_entity_name, target_key_hash
        ),
        constraint md_run_tgt_cons_run_fk foreign key (run_id) references md_run(run_id),
        constraint md_run_tgt_cons_evt_fk foreign key (change_event_id) references md_change_event(change_event_id)
      )
    ]';
  end if;

  -- Consolidated winner values table.
  select count(*) into l_count from user_tables where table_name = 'MD_RUN_TARGET_CONSOLIDATED_VALUE';
  if l_count = 0 then
    execute immediate q'[
      create table md_run_target_consolidated_value (
        run_target_consolidated_value_id number primary key,
        run_target_consolidation_id      number not null,
        tenant_id                        varchar2(64) not null,
        context_id                       varchar2(64) not null,
        run_id                           number not null,
        change_event_id                  number not null,
        target_entity_name               varchar2(256) not null,
        target_key_hash                  varchar2(128) not null,
        target_column_name               varchar2(128) not null,
        computed_value_txt               varchar2(4000),
        computed_value_json              clob,
        value_data_type                  varchar2(30),
        winner_rule_id                   number not null,
        winner_priority_no               number not null,
        value_fingerprint                varchar2(128) not null,
        created_at                       timestamp default systimestamp not null,
        updated_at                       timestamp default systimestamp not null,
        constraint md_run_tgt_cons_val_uq unique (
          tenant_id, context_id, run_id, change_event_id, target_entity_name, target_key_hash, target_column_name
        ),
        constraint md_run_tgt_cons_val_fk foreign key (run_target_consolidation_id)
          references md_run_target_consolidation(run_target_consolidation_id)
      )
    ]';
  end if;

  -- Add optional linkage and phase marker on existing action trace table.
  select count(*) into l_count from user_tab_cols
   where table_name = 'MD_RUN_TARGET_ACTION' and column_name = 'EXECUTION_PHASE';
  if l_count = 0 then
    execute immediate q'[alter table md_run_target_action add (execution_phase varchar2(30) default 'PER_RULE_DIAGNOSTIC' not null)]';
  end if;

  select count(*) into l_count from user_tab_cols
   where table_name = 'MD_RUN_TARGET_ACTION' and column_name = 'RUN_TARGET_CONSOLIDATION_ID';
  if l_count = 0 then
    execute immediate 'alter table md_run_target_action add (run_target_consolidation_id number)';
  end if;

  select count(*) into l_count from user_constraints
   where table_name = 'MD_RUN_TARGET_ACTION' and constraint_name = 'MD_RUN_TGT_ACT_PHASE_CK';
  if l_count = 0 then
    execute immediate q'[
      alter table md_run_target_action
      add constraint md_run_tgt_act_phase_ck
      check (execution_phase in ('PER_RULE_DIAGNOSTIC','CONSOLIDATED_EXECUTION'))
    ]';
  end if;

  select count(*) into l_count from user_constraints
   where table_name = 'MD_RUN_TARGET_ACTION' and constraint_name = 'MD_RUN_TGT_ACT_CONS_FK';
  if l_count = 0 then
    execute immediate q'[
      alter table md_run_target_action
      add constraint md_run_tgt_act_cons_fk
      foreign key (run_target_consolidation_id)
      references md_run_target_consolidation(run_target_consolidation_id)
    ]';
  end if;

  -- Sequences.
  select count(*) into l_count from user_sequences where sequence_name = 'MD_RUN_TARGET_CONS_SEQ';
  if l_count = 0 then
    execute immediate 'create sequence md_run_target_cons_seq start with 1 increment by 1 nocache';
  end if;

  select count(*) into l_count from user_sequences where sequence_name = 'MD_RUN_TARGET_CONS_VAL_SEQ';
  if l_count = 0 then
    execute immediate 'create sequence md_run_target_cons_val_seq start with 1 increment by 1 nocache';
  end if;

  -- Supporting indexes.
  select count(*) into l_count from user_indexes where index_name = 'MD_RUN_TGT_CONS_LOOKUP_IX';
  if l_count = 0 then
    begin
      execute immediate q'[
        create index md_run_tgt_cons_lookup_ix
        on md_run_target_consolidation (tenant_id, context_id, run_id, change_event_id, target_entity_name, target_key_hash)
      ]';
    exception
      when others then
        if sqlcode not in (-955, -1408) then
          raise;
        end if;
    end;
  end if;

  select count(*) into l_count from user_indexes where index_name = 'MD_RUN_TGT_CONS_VAL_IX';
  if l_count = 0 then
    begin
      execute immediate q'[
        create index md_run_tgt_cons_val_ix
        on md_run_target_consolidated_value (tenant_id, context_id, run_id, change_event_id, target_entity_name)
      ]';
    exception
      when others then
        if sqlcode not in (-955, -1408) then
          raise;
        end if;
    end;
  end if;
end;
/

prompt Target consolidation runtime upgrade complete.
