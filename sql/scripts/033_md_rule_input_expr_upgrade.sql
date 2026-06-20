-- 033_md_rule_input_expr_upgrade.sql
-- Incremental/idempotent upgrade for rule-scoped scalar input expressions.

prompt Applying rule input expression metadata upgrade...

declare
  l_count number;
begin
  select count(*) into l_count from user_tables where table_name = 'MD_RULE_INPUT_EXPR';
  if l_count = 0 then
    execute immediate q'[
      create table md_rule_input_expr (
        rule_input_expr_id        number primary key,
        tenant_id                 varchar2(64) not null,
        context_id                varchar2(64) not null,
        release_id                number not null,
        rule_id                   number not null,
        output_alias              varchar2(128),
        scalar_expr               clob not null,
        expression_order_no       number,
        required_flag             varchar2(1) default 'N' not null,
        active_flag               varchar2(1) default 'Y' not null,
        created_at                timestamp default systimestamp not null,
        constraint md_rule_input_expr_req_ck check (required_flag in ('Y','N')),
        constraint md_rule_input_expr_active_ck check (active_flag in ('Y','N')),
        constraint md_rule_input_expr_alias_ck check (output_alias is null or length(trim(output_alias)) > 0),
        constraint md_rule_input_expr_uq unique (tenant_id, context_id, release_id, rule_id, output_alias),
        constraint md_rule_input_expr_release_fk foreign key (release_id) references md_release(release_id),
        constraint md_rule_input_expr_rule_fk foreign key (rule_id) references md_rule(rule_id)
      )
    ]';
  end if;

  select count(*) into l_count from user_sequences where sequence_name = 'MD_RULE_INPUT_EXPR_SEQ';
  if l_count = 0 then
    execute immediate 'create sequence md_rule_input_expr_seq start with 1 increment by 1 nocache';
  end if;

  select count(*) into l_count from user_triggers where trigger_name = 'MD_RULE_INPUT_EXPR_BI_TRG';
  if l_count = 0 then
    execute immediate q'[
      create or replace trigger md_rule_input_expr_bi_trg
      before insert on md_rule_input_expr
      for each row
      when (new.rule_input_expr_id is null)
      begin
        :new.rule_input_expr_id := md_rule_input_expr_seq.nextval;
      end;
    ]';
  end if;

  select count(*) into l_count from user_indexes where index_name = 'MD_RULE_INPUT_EXPR_RULE_IX';
  if l_count = 0 then
    execute immediate 'create index md_rule_input_expr_rule_ix on md_rule_input_expr (tenant_id, context_id, rule_id, active_flag, expression_order_no)';
  end if;
end;
/

prompt Rule input expression metadata upgrade complete.
