-- 032_md_context_prefetch_runtime_upgrade.sql
-- Incremental/idempotent upgrade for run-level source-context prefetch cache.

prompt Applying context prefetch runtime upgrade...

declare
  l_count number;
begin
  select count(*) into l_count from user_tables where table_name = 'MD_RUN_CONTEXT_SNAPSHOT';
  if l_count = 0 then
    execute immediate q'[
      create table md_run_context_snapshot (
        run_context_snapshot_id    number primary key,
        tenant_id                  varchar2(64) not null,
        context_id                 varchar2(64) not null,
        run_id                     number not null,
        change_event_id            number not null,
        source_context_id          number not null,
        source_values_json         clob not null check (source_values_json is json),
        created_at                 timestamp default systimestamp not null,
        constraint md_run_ctx_snap_uq unique (tenant_id, context_id, run_id, change_event_id, source_context_id),
        constraint md_run_ctx_snap_run_fk foreign key (run_id) references md_run(run_id),
        constraint md_run_ctx_snap_evt_fk foreign key (change_event_id) references md_change_event(change_event_id),
        constraint md_run_ctx_snap_ctx_fk foreign key (source_context_id) references md_source_context(source_context_id)
      )
    ]';
  end if;

  select count(*) into l_count from user_sequences where sequence_name = 'MD_RUN_CONTEXT_SNAPSHOT_SEQ';
  if l_count = 0 then
    execute immediate 'create sequence md_run_context_snapshot_seq start with 1 increment by 1 nocache';
  end if;

  select count(*) into l_count from user_triggers where trigger_name = 'MD_RUN_CONTEXT_SNAPSHOT_BI_TRG';
  if l_count = 0 then
    execute immediate q'[
      create or replace trigger md_run_context_snapshot_bi_trg
      before insert on md_run_context_snapshot
      for each row
      when (new.run_context_snapshot_id is null)
      begin
        :new.run_context_snapshot_id := md_run_context_snapshot_seq.nextval;
      end;
    ]';
  end if;

  select count(*) into l_count from user_indexes where index_name = 'MD_RUN_CTX_SNAP_RUN_IX';
  if l_count = 0 then
    execute immediate 'create index md_run_ctx_snap_run_ix on md_run_context_snapshot (run_id, change_event_id, source_context_id)';
  end if;
end;
/

prompt Context prefetch runtime upgrade complete.
