-- 070_create_src_tgt_security_tables.sql
-- Create source and target security tables.

prompt Creating SRC_SECURITY and TGT_SEC_INDUSTRY tables...

begin
  execute immediate q'[
    create table src_security (
      asset_id   varchar2(30),
      sec_name   varchar2(30),
      sec_type   varchar2(30),
      gic_cd     varchar2(30),
      pic_cd     varchar2(30)
    )
  ]';
exception
  when others then
    if sqlcode != -955 then
      raise;
    end if;
end;
/

begin
  execute immediate q'[
    create table tgt_sec_industry (
      asset_id         varchar2(30),
      indust_class_cd  varchar2(30),
      indust_cd        varchar2(30)
    )
  ]';
exception
  when others then
    if sqlcode != -955 then
      raise;
    end if;
end;
/

prompt SRC_SECURITY and TGT_SEC_INDUSTRY table creation complete.
