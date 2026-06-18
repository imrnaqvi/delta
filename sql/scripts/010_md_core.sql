-- 010_md_core.sql
-- Core metadata model (Oracle 19c)
-- Conventions:
-- 1) MD_* naming for all metadata/runtime/audit tables
-- 2) Explicit sequences only for PK generation
-- 3) Tenant/context columns required across tables

prompt Creating MD core metadata tables and sequences...

create table md_release (
  release_id                number primary key,
  tenant_id                 varchar2(64) not null,
  context_id                varchar2(64) not null,
  release_name              varchar2(200) not null,
  semantic_version          varchar2(50) not null,
  status                    varchar2(20) not null,
  rollback_from_release_id  number,
  created_by                varchar2(128) not null,
  created_at                timestamp default systimestamp not null,
  approved_by               varchar2(128),
  approved_at               timestamp,
  published_at              timestamp,
  retired_at                timestamp,
  constraint md_release_status_ck check (status in ('DRAFT','APPROVED','PUBLISHED','RETIRED')),
  constraint md_release_uq unique (tenant_id, context_id, release_name, semantic_version),
  constraint md_release_rb_fk foreign key (rollback_from_release_id) references md_release(release_id)
);

create sequence md_release_seq start with 1 increment by 1 nocache;

create table md_object (
  object_id                 number primary key,
  tenant_id                 varchar2(64) not null,
  context_id                varchar2(64) not null,
  release_id                number not null,
  system_name               varchar2(100) not null,
  schema_name               varchar2(128) not null,
  object_name               varchar2(128) not null,
  object_type               varchar2(20) not null,
  created_at                timestamp default systimestamp not null,
  constraint md_object_type_ck check (object_type in ('TABLE','VIEW')),
  constraint md_object_uq unique (tenant_id, context_id, release_id, system_name, schema_name, object_name),
  constraint md_object_release_fk foreign key (release_id) references md_release(release_id)
);

create sequence md_object_seq start with 1 increment by 1 nocache;

create table md_column (
  column_id                 number primary key,
  tenant_id                 varchar2(64) not null,
  context_id                varchar2(64) not null,
  object_id                 number not null,
  column_name               varchar2(128) not null,
  data_type                 varchar2(128),
  nullable_flag             varchar2(1) default 'Y' not null,
  ordinal_position          number,
  created_at                timestamp default systimestamp not null,
  constraint md_column_nullable_ck check (nullable_flag in ('Y','N')),
  constraint md_column_uq unique (tenant_id, context_id, object_id, column_name),
  constraint md_column_object_fk foreign key (object_id) references md_object(object_id)
);

create sequence md_column_seq start with 1 increment by 1 nocache;

create table md_key_definition (
  key_id                    number primary key,
  tenant_id                 varchar2(64) not null,
  context_id                varchar2(64) not null,
  release_id                number not null,
  key_scope                 varchar2(20) not null,
  system_name               varchar2(100) not null,
  entity_name               varchar2(128) not null,
  key_name                  varchar2(128) not null,
  key_type                  varchar2(20) not null,
  active_flag               varchar2(1) default 'Y' not null,
  created_at                timestamp default systimestamp not null,
  constraint md_key_scope_ck check (key_scope in ('SOURCE','TARGET')),
  constraint md_key_type_ck check (key_type in ('NATURAL_COMPOSITE','SURROGATE')),
  constraint md_key_active_ck check (active_flag in ('Y','N')),
  constraint md_key_def_uq unique (tenant_id, context_id, release_id, key_scope, system_name, entity_name, key_name),
  constraint md_key_def_release_fk foreign key (release_id) references md_release(release_id)
);

create sequence md_key_definition_seq start with 1 increment by 1 nocache;

create table md_key_component (
  key_component_id          number primary key,
  tenant_id                 varchar2(64) not null,
  context_id                varchar2(64) not null,
  key_id                    number not null,
  column_id                 number not null,
  ordinal_position          number not null,
  created_at                timestamp default systimestamp not null,
  constraint md_key_comp_uq unique (tenant_id, context_id, key_id, ordinal_position),
  constraint md_key_comp_col_uq unique (tenant_id, context_id, key_id, column_id),
  constraint md_key_comp_key_fk foreign key (key_id) references md_key_definition(key_id),
  constraint md_key_comp_col_fk foreign key (column_id) references md_column(column_id)
);

create sequence md_key_component_seq start with 1 increment by 1 nocache;

create table md_key_mapping (
  key_mapping_id            number primary key,
  tenant_id                 varchar2(64) not null,
  context_id                varchar2(64) not null,
  release_id                number not null,
  source_key_id             number not null,
  target_key_id             number not null,
  mapping_expr              clob,
  active_flag               varchar2(1) default 'Y' not null,
  created_at                timestamp default systimestamp not null,
  constraint md_key_map_active_ck check (active_flag in ('Y','N')),
  constraint md_key_map_uq unique (tenant_id, context_id, release_id, source_key_id, target_key_id),
  constraint md_key_map_release_fk foreign key (release_id) references md_release(release_id),
  constraint md_key_map_source_fk foreign key (source_key_id) references md_key_definition(key_id),
  constraint md_key_map_target_fk foreign key (target_key_id) references md_key_definition(key_id)
);

create sequence md_key_mapping_seq start with 1 increment by 1 nocache;

create table md_rule (
  rule_id                   number primary key,
  tenant_id                 varchar2(64) not null,
  context_id                varchar2(64) not null,
  release_id                number not null,
  rule_name                 varchar2(200) not null,
  rule_type                 varchar2(40) not null,
  status                    varchar2(20) not null,
  rule_payload              clob check (rule_payload is json),
  selection_gate_expr       clob,
  selection_gate_enabled_flag varchar2(1) default 'Y' not null,
  active_flag               varchar2(1) default 'Y' not null,
  created_by                varchar2(128) not null,
  created_at                timestamp default systimestamp not null,
  updated_at                timestamp,
  constraint md_rule_type_ck check (rule_type in ('EXPRESSION','COLUMN_TO_ROW','LOOKUP','PLSQL_FUNC')),
  constraint md_rule_status_ck check (status in ('DRAFT','APPROVED','PUBLISHED','RETIRED')),
  constraint md_rule_gate_enabled_ck check (selection_gate_enabled_flag in ('Y','N')),
  constraint md_rule_active_ck check (active_flag in ('Y','N')),
  constraint md_rule_uq unique (tenant_id, context_id, release_id, rule_name),
  constraint md_rule_release_fk foreign key (release_id) references md_release(release_id)
);

create sequence md_rule_seq start with 1 increment by 1 nocache;

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
);

create sequence md_expr_allowed_function_seq start with 1 increment by 1 nocache;

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
);

create sequence md_source_context_seq start with 1 increment by 1 nocache;

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
);

create sequence md_source_context_object_seq start with 1 increment by 1 nocache;

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
);

create sequence md_source_context_join_seq start with 1 increment by 1 nocache;

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
);

create sequence md_rule_source_context_seq start with 1 increment by 1 nocache;

create table md_rule_input (
  rule_input_id             number primary key,
  tenant_id                 varchar2(64) not null,
  context_id                varchar2(64) not null,
  rule_id                   number not null,
  source_column_id          number not null,
  required_flag             varchar2(1) default 'Y' not null,
  dependency_condition_expr clob,
  created_at                timestamp default systimestamp not null,
  constraint md_rule_input_req_ck check (required_flag in ('Y','N')),
  constraint md_rule_input_uq unique (tenant_id, context_id, rule_id, source_column_id),
  constraint md_rule_input_rule_fk foreign key (rule_id) references md_rule(rule_id),
  constraint md_rule_input_col_fk foreign key (source_column_id) references md_column(column_id)
);

create sequence md_rule_input_seq start with 1 increment by 1 nocache;

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
);

create sequence md_rule_parameter_requirement_seq start with 1 increment by 1 nocache;

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
);

create sequence md_rule_source_object_seq start with 1 increment by 1 nocache;

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
);

create sequence md_rule_source_join_seq start with 1 increment by 1 nocache;

create table md_rule_output (
  rule_output_id            number primary key,
  tenant_id                 varchar2(64) not null,
  context_id                varchar2(64) not null,
  rule_id                   number not null,
  target_column_id          number not null,
  output_expr               clob,
  created_at                timestamp default systimestamp not null,
  constraint md_rule_output_uq unique (tenant_id, context_id, rule_id, target_column_id),
  constraint md_rule_output_rule_fk foreign key (rule_id) references md_rule(rule_id),
  constraint md_rule_output_col_fk foreign key (target_column_id) references md_column(column_id)
);

create sequence md_rule_output_seq start with 1 increment by 1 nocache;

create table md_rule_dependency (
  rule_dependency_id        number primary key,
  tenant_id                 varchar2(64) not null,
  context_id                varchar2(64) not null,
  release_id                number not null,
  upstream_rule_id          number not null,
  downstream_rule_id        number not null,
  dependency_type           varchar2(30) not null,
  active_flag               varchar2(1) default 'Y' not null,
  created_at                timestamp default systimestamp not null,
  constraint md_rule_dep_type_ck check (dependency_type in ('COLUMN_FLOW','DERIVATION','AGGREGATION','LOOKUP_CHAIN')),
  constraint md_rule_dep_active_ck check (active_flag in ('Y','N')),
  constraint md_rule_dep_uq unique (tenant_id, context_id, release_id, upstream_rule_id, downstream_rule_id),
  constraint md_rule_dep_release_fk foreign key (release_id) references md_release(release_id),
  constraint md_rule_dep_up_fk foreign key (upstream_rule_id) references md_rule(rule_id),
  constraint md_rule_dep_down_fk foreign key (downstream_rule_id) references md_rule(rule_id)
);

create sequence md_rule_dependency_seq start with 1 increment by 1 nocache;

create table md_rule_dependency_condition (
  rule_dependency_condition_id number primary key,
  tenant_id                 varchar2(64) not null,
  context_id                varchar2(64) not null,
  rule_dependency_id        number not null,
  condition_expr            clob,
  created_at                timestamp default systimestamp not null,
  constraint md_rule_dep_cond_fk foreign key (rule_dependency_id) references md_rule_dependency(rule_dependency_id)
);

create sequence md_rule_dep_condition_seq start with 1 increment by 1 nocache;

create table md_rule_target_action (
  rule_target_action_id     number primary key,
  tenant_id                 varchar2(64) not null,
  context_id                varchar2(64) not null,
  release_id                number not null,
  rule_id                   number not null,
  target_object_id          number not null,
  target_key_id             number,
  target_column_id          number,
  action_type               varchar2(20) not null,
  execution_mode            varchar2(20) default 'APPLY' not null,
  missing_row_policy        varchar2(20) default 'ERROR' not null,
  delete_policy             varchar2(20) default 'RULE_DEFINED' not null,
  action_condition_expr     clob,
  created_at                timestamp default systimestamp not null,
  constraint md_rule_tgt_action_ck check (action_type in ('UPDATE','INSERT','DELETE','SOFT_DELETE')),
  constraint md_rule_tgt_exec_mode_ck check (execution_mode in ('PREVIEW','APPLY')),
  constraint md_rule_tgt_missing_row_ck check (missing_row_policy in ('ERROR','INSERT','SKIP')),
  constraint md_rule_tgt_del_policy_ck check (delete_policy in ('HARD_DELETE','SOFT_DELETE','RULE_DEFINED')),
  constraint md_rule_tgt_action_uq unique (tenant_id, context_id, release_id, rule_id, target_object_id, target_column_id, action_type),
  constraint md_rule_tgt_release_fk foreign key (release_id) references md_release(release_id),
  constraint md_rule_tgt_rule_fk foreign key (rule_id) references md_rule(rule_id),
  constraint md_rule_tgt_obj_fk foreign key (target_object_id) references md_object(object_id),
  constraint md_rule_tgt_key_fk foreign key (target_key_id) references md_key_definition(key_id),
  constraint md_rule_tgt_col_fk foreign key (target_column_id) references md_column(column_id)
);

create sequence md_rule_target_action_seq start with 1 increment by 1 nocache;

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
);

create sequence md_rule_target_key_map_seq start with 1 increment by 1 nocache;

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
);

create sequence md_rule_target_column_map_seq start with 1 increment by 1 nocache;

create table md_delete_policy (
  delete_policy_id          number primary key,
  tenant_id                 varchar2(64) not null,
  context_id                varchar2(64) not null,
  release_id                number not null,
  scope_type                varchar2(20) not null,
  scope_id                  number,
  policy_code               varchar2(20) not null,
  active_flag               varchar2(1) default 'Y' not null,
  created_at                timestamp default systimestamp not null,
  constraint md_delete_scope_ck check (scope_type in ('GLOBAL','MAPPING','RULE')),
  constraint md_delete_policy_ck check (policy_code in ('HARD_DELETE','SOFT_DELETE','RULE_DEFINED')),
  constraint md_delete_active_ck check (active_flag in ('Y','N')),
  constraint md_delete_policy_uq unique (tenant_id, context_id, release_id, scope_type, scope_id),
  constraint md_delete_release_fk foreign key (release_id) references md_release(release_id)
);

create sequence md_delete_policy_seq start with 1 increment by 1 nocache;

create table md_publish_validation_result (
  publish_validation_result_id number primary key,
  tenant_id                 varchar2(64) not null,
  context_id                varchar2(64) not null,
  release_id                number not null,
  validation_code           varchar2(100) not null,
  severity                  varchar2(10) not null,
  blocking_flag             varchar2(1) default 'Y' not null,
  object_ref                varchar2(400),
  detail_message            varchar2(2000),
  created_at                timestamp default systimestamp not null,
  constraint md_pub_val_sev_ck check (severity in ('INFO','WARN','ERROR')),
  constraint md_pub_val_block_ck check (blocking_flag in ('Y','N')),
  constraint md_pub_val_release_fk foreign key (release_id) references md_release(release_id)
);

create sequence md_publish_validation_result_seq start with 1 increment by 1 nocache;

create table md_override_request (
  override_request_id       number primary key,
  tenant_id                 varchar2(64) not null,
  context_id                varchar2(64) not null,
  release_id                number,
  run_scope_json            clob check (run_scope_json is json),
  include_rules_json        clob check (include_rules_json is json),
  exclude_rules_json        clob check (exclude_rules_json is json),
  reason_code               varchar2(100) not null,
  reason_detail             varchar2(2000),
  requested_by              varchar2(128) not null,
  requested_at              timestamp default systimestamp not null,
  status                    varchar2(20) not null,
  constraint md_override_status_ck check (status in ('REQUESTED','APPROVED','REJECTED','EXPIRED')),
  constraint md_override_release_fk foreign key (release_id) references md_release(release_id)
);

create sequence md_override_request_seq start with 1 increment by 1 nocache;

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
);

create sequence md_correlation_policy_seq start with 1 increment by 1 nocache;

prompt MD core metadata script complete.
