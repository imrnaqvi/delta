-- 031_md_source_enrichment_metadata_upgrade.sql
-- Incremental/idempotent upgrade for source enrichment projection alias + predicate metadata.

prompt Applying source enrichment metadata upgrade...

declare
  l_count number;
begin
  -- md_rule_input.output_alias
  select count(*)
    into l_count
    from user_tab_cols
   where table_name = 'MD_RULE_INPUT'
     and column_name = 'OUTPUT_ALIAS';

  if l_count = 0 then
    execute immediate 'alter table md_rule_input add (output_alias varchar2(128))';
  end if;

  select count(*)
    into l_count
    from user_constraints
   where table_name = 'MD_RULE_INPUT'
     and constraint_name = 'MD_RULE_INPUT_ALIAS_CK';

  if l_count = 0 then
    execute immediate q'[alter table md_rule_input add constraint md_rule_input_alias_ck check (output_alias is null or length(trim(output_alias)) > 0)]';
  end if;

  -- md_source_context_predicate
  select count(*) into l_count from user_tables where table_name = 'MD_SOURCE_CONTEXT_PREDICATE';
  if l_count = 0 then
    execute immediate q'[
      create table md_source_context_predicate (
        source_context_predicate_id number primary key,
        tenant_id                   varchar2(64) not null,
        context_id                  varchar2(64) not null,
        source_context_id           number not null,
        rule_id                     number,
        source_context_object_id    number not null,
        column_id                   number not null,
        operator_code               varchar2(20) not null,
        value_source_kind           varchar2(20) not null,
        value_expr                  clob,
        value_expr_to               clob,
        required_flag               varchar2(1) default 'Y' not null,
        null_behavior               varchar2(20) default 'SKIP_IF_NULL' not null,
        predicate_group_no          number default 1 not null,
        predicate_order_no          number default 1 not null,
        active_flag                 varchar2(1) default 'Y' not null,
        created_at                  timestamp default systimestamp not null,
        constraint md_src_ctx_pred_req_ck check (required_flag in ('Y','N')),
        constraint md_src_ctx_pred_null_beh_ck check (null_behavior in ('SKIP_IF_NULL','FAIL_IF_NULL','IS_NULL_IF_NULL')),
        constraint md_src_ctx_pred_active_ck check (active_flag in ('Y','N')),
        constraint md_src_ctx_pred_op_ck check (operator_code in ('EQ','NE','GT','GE','LT','LE','IN','BETWEEN','LIKE','IS_NULL','IS_NOT_NULL')),
        constraint md_src_ctx_pred_val_src_ck check (value_source_kind in ('EVENT_KEY','EVENT_OLD','EVENT_NEW','PARAM','LITERAL')),
        constraint md_src_ctx_pred_ctx_fk foreign key (source_context_id) references md_source_context(source_context_id),
        constraint md_src_ctx_pred_obj_fk foreign key (source_context_object_id) references md_source_context_object(source_context_object_id),
        constraint md_src_ctx_pred_col_fk foreign key (column_id) references md_column(column_id),
        constraint md_src_ctx_pred_rule_fk foreign key (rule_id) references md_rule(rule_id)
      )
    ]';
  end if;

  select count(*) into l_count from user_sequences where sequence_name = 'MD_SOURCE_CONTEXT_PREDICATE_SEQ';
  if l_count = 0 then
    execute immediate 'create sequence md_source_context_predicate_seq start with 1 increment by 1 nocache';
  end if;

  select count(*) into l_count from user_triggers where trigger_name = 'MD_SOURCE_CONTEXT_PRED_BI_TRG';
  if l_count = 0 then
    execute immediate q'[
      create or replace trigger md_source_context_pred_bi_trg
      before insert on md_source_context_predicate
      for each row
      when (new.source_context_predicate_id is null)
      begin
        :new.source_context_predicate_id := md_source_context_predicate_seq.nextval;
      end;
    ]';
  end if;

  select count(*) into l_count from user_indexes where index_name = 'MD_RULE_INPUT_ALIAS_IX';
  if l_count = 0 then
    execute immediate 'create index md_rule_input_alias_ix on md_rule_input (rule_id, output_alias)';
  end if;

  select count(*) into l_count from user_indexes where index_name = 'MD_SRC_CTX_PRED_LOOKUP_IX';
  if l_count = 0 then
    execute immediate 'create index md_src_ctx_pred_lookup_ix on md_source_context_predicate (tenant_id, context_id, source_context_id, active_flag, rule_id, predicate_group_no, predicate_order_no)';
  end if;

  select count(*) into l_count from user_indexes where index_name = 'MD_SRC_CTX_PRED_OBJ_IX';
  if l_count = 0 then
    execute immediate 'create index md_src_ctx_pred_obj_ix on md_source_context_predicate (source_context_object_id, column_id)';
  end if;
end;
/

prompt Source enrichment metadata upgrade complete.
