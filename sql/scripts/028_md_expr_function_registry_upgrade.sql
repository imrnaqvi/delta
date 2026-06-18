-- 028_md_expr_function_registry_upgrade.sql
-- Incremental/idempotent upgrade for optional expression function governance registry.

prompt Applying expression function registry upgrade...

declare
  l_count number;
begin
  select count(*) into l_count from user_tables where table_name = 'MD_EXPR_ALLOWED_FUNCTION';
  if l_count = 0 then
    execute immediate q'[
      create table md_expr_allowed_function (
        expr_allowed_function_id   number primary key,
        tenant_id                  varchar2(64) not null,
        context_id                 varchar2(64) not null,
        function_name              varchar2(128) not null,
        active_flag                varchar2(1) default 'Y' not null,
        created_by                 varchar2(128),
        created_at                 timestamp default systimestamp not null,
        updated_at                 timestamp,
        constraint md_expr_fn_active_ck check (active_flag in ('Y','N')),
        constraint md_expr_fn_uq unique (tenant_id, context_id, function_name)
      )
    ]';
  end if;

  select count(*) into l_count from user_sequences where sequence_name = 'MD_EXPR_ALLOWED_FUNCTION_SEQ';
  if l_count = 0 then
    execute immediate 'create sequence md_expr_allowed_function_seq start with 1 increment by 1 nocache';
  end if;

  execute immediate q'[
    create or replace trigger md_expr_allowed_fn_bi_trg
    before insert on md_expr_allowed_function
    for each row
    when (new.expr_allowed_function_id is null)
    begin
      :new.expr_allowed_function_id := md_expr_allowed_function_seq.nextval;
    end;
  ]';

  select count(*) into l_count from user_indexes where index_name = 'MD_EXPR_FN_SCOPE_IX';
  if l_count = 0 then
    execute immediate 'create index md_expr_fn_scope_ix on md_expr_allowed_function (tenant_id, context_id, active_flag, function_name)';
  end if;
end;
/

prompt Expression function registry upgrade complete.
