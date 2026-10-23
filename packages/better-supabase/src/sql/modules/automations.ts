import type { AutomationsEvents } from "../../blocks/automations/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlString } from "../../core/template.ts";
import { FILTER_OPERATORS } from "../../list/filter-query.ts";
import { RANK_KEY_PATTERN, rankAfter } from "../rank-sql.ts";
import {
  fail,
  lockTable,
  raise,
  SERVICE_CALLER,
  schemaPreamble,
} from "../shared.ts";
import { defaultRulesSql } from "./automations-defaults-sql.ts";
import { operatorTable, rulesEvaluator } from "./automations-evaluate.ts";
import { moduleOperations } from "./permissions-model.ts";

const RULE_PAYLOAD = [
  "organizationId",
  "ruleId",
  "name",
  "subjectType",
  "trigger",
  "version",
] as const;

const EVENTS: BlockSqlEvents<AutomationsEvents> = {
  "rule.saved": { subject: "rules", payload: RULE_PAYLOAD },
  "rule.enabled": { subject: "rules", payload: RULE_PAYLOAD },
  "rule.disabled": { subject: "rules", payload: RULE_PAYLOAD },
  "rule.removed": { subject: "rules", payload: RULE_PAYLOAD },
  "rule.matched": {
    subject: "rules",
    payload: [
      "organizationId",
      "ruleId",
      "version",
      "subjectType",
      "subjectId",
      "trigger",
    ],
  },
};

const NAMES: BlockSqlNames = {
  entities: { rule: { table: "rules", singular: "rule", primary: true } },
  events: EVENTS,
  options: ["maxConditions", "maxDepth", "maxActions", "enable", "disable"],
  hooks: [],
  tables: {
    rules: {
      name: "rules",
      lifecycle: { tenant: "tenant" },
      columns: {
        id: "id",
        tenant: "organization_id",
        subjectType: "subject_type",
        trigger: "trigger",
        name: "name",
        description: "description",
        conditions: "conditions",
        actions: "actions",
        enabled: "enabled",
        stopProcessing: "stop_processing",
        rank: "rank",
        version: "version",
        createdBy: "created_by",
        updatedBy: "updated_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
        defaultKey: "default_key",
      },
    },
    defaults: {
      name: "rule_defaults",
      columns: {
        key: "key",
        block: "block",
        subjectType: "subject_type",
        trigger: "trigger",
        name: "name",
        description: "description",
        conditions: "conditions",
        actions: "actions",
        enabled: "enabled",
        updatedAt: "updated_at",
      },
    },
    versions: {
      name: "rule_versions",
      lifecycle: { tenant: "tenant" },
      columns: {
        rule: "rule_id",
        version: "version",
        tenant: "organization_id",
        name: "name",
        conditions: "conditions",
        actions: "actions",
        savedBy: "saved_by",
        savedAt: "saved_at",
      },
    },
    evaluations: {
      name: "rule_evaluations",
      lifecycle: { tenant: "tenant" },
      columns: {
        id: "id",
        tenant: "organization_id",
        rule: "rule_id",
        version: "version",
        subjectType: "subject_type",
        subjectId: "subject_id",
        trigger: "trigger",
        matched: "matched",
        results: "results",
        mode: "mode",
        evaluatedBy: "evaluated_by",
        evaluatedAt: "evaluated_at",
      },
    },
    fields: {
      name: "rule_fields",
      columns: {
        subjectType: "subject_type",
        id: "field_id",
        label: "label",
        description: "description",
        type: "type",
        path: "path",
        columnType: "column_type",
        nullable: "nullable",
        options: "options",
        operators: "operators",
        position: "position",
        updatedAt: "updated_at",
      },
    },
  },
};

const SUBJECT_TYPE = "^[a-z][a-z0-9_]{0,62}$";
const TRIGGER = "^[a-z][a-z0-9_]*([.:][a-z0-9_]+)*$";
const ACTION_KIND = "^[a-z][a-z0-9_]*([.][a-z0-9_]+)*$";
const FIELD_ID = "^[A-Za-z_][A-Za-z0-9_]*([.][A-Za-z_][A-Za-z0-9_]*)*$";

function limitOf(ctx: BlockSqlContext, name: string, fallback: number): number {
  const value = ctx.number(name, fallback);

  if (!Number.isInteger(value) || value < 1 || value > 1000) {
    throw new TypeError(
      `blocks.automations.options.${name} must be a whole number from 1 to 1000`,
    );
  }

  return value;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);
  const t = ctx.table("rules");
  const v = ctx.table("versions");
  const e = ctx.table("evaluations");
  const f = ctx.table("fields");
  const r = (column: string): string => ctx.col("rules", column);
  const rv = (column: string): string => ctx.col("versions", column);
  const re = (column: string): string => ctx.col("evaluations", column);
  const rf = (column: string): string => ctx.col("fields", column);
  const d = ctx.table("defaults");
  const rd = (column: string): string => ctx.col("defaults", column);
  const keys = moduleOperations("automations");
  const read = ctx.permission("read", keys.read);
  const edit = ctx.permission("edit", keys.edit);
  const publish = ctx.permission("publish", keys.publish);
  const admin = ctx.permission("admin", keys.admin);
  const maxConditions = limitOf(ctx, "maxConditions", 50);
  const maxDepth = limitOf(ctx, "maxDepth", 4);
  const maxActions = limitOf(ctx, "maxActions", 20);

  const can = (tenant: string, key: string): string =>
    `(${SERVICE_CALLER} or ${ctx.scope.can(tenant, key)})`;

  // Changing an enabled rule, or enabling one, takes the publish key.
  const keyFor = (enabled: string): string =>
    `case when ${enabled} then ${sqlString(publish)} else ${sqlString(edit)} end`;

  const canKey = (tenant: string, enabled: string): string =>
    `(${SERVICE_CALLER} or (case when ${enabled} then ${ctx.scope.can(tenant, publish)} else ${ctx.scope.can(tenant, edit)} end))`;

  const ruleJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${r("id")}, 'organizationId', ${row}.${r("tenant")}, 'subjectType', ${row}.${r("subjectType")}, 'trigger', ${row}.${r("trigger")}, 'name', ${row}.${r("name")}, 'description', ${row}.${r("description")}, 'conditions', ${row}.${r("conditions")}, 'actions', ${row}.${r("actions")}, 'enabled', ${row}.${r("enabled")}, 'stopProcessing', ${row}.${r("stopProcessing")}, 'rank', ${row}.${r("rank")}, 'version', ${row}.${r("version")}, 'createdBy', ${row}.${r("createdBy")}, 'updatedBy', ${row}.${r("updatedBy")}, 'createdAt', ${row}.${r("createdAt")}, 'updatedAt', ${row}.${r("updatedAt")}, 'defaultKey', ${row}.${r("defaultKey")})`;

  const fieldJson = (row: string): string =>
    `jsonb_build_object('subjectType', ${row}.${rf("subjectType")}, 'id', ${row}.${rf("id")}, 'label', ${row}.${rf("label")}, 'description', ${row}.${rf("description")}, 'type', ${row}.${rf("type")}, 'column', ${row}.${rf("path")}, 'columnType', ${row}.${rf("columnType")}, 'nullable', ${row}.${rf("nullable")}, 'options', ${row}.${rf("options")}, 'operators', ${row}.${rf("operators")})`;

  const evaluationJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${re("id")}::text, 'organizationId', ${row}.${re("tenant")}, 'ruleId', ${row}.${re("rule")}, 'version', ${row}.${re("version")}, 'subjectType', ${row}.${re("subjectType")}, 'subjectId', ${row}.${re("subjectId")}, 'trigger', ${row}.${re("trigger")}, 'matched', ${row}.${re("matched")}, 'results', ${row}.${re("results")}, 'mode', ${row}.${re("mode")}, 'evaluatedBy', ${row}.${re("evaluatedBy")}, 'evaluatedAt', ${row}.${re("evaluatedAt")})`;

  const ruleEvent = (type: string, row: string, actor = "auth.uid()"): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${row}.${r("tenant")}::text, 'ruleId', ${row}.${r("id")}::text, 'name', ${row}.${r("name")}, 'subjectType', ${row}.${r("subjectType")}, 'trigger', ${row}.${r("trigger")}, 'version', ${row}.${r("version")})`,
      subject: `'rules/' || ${row}.${r("id")}::text`,
      tenant: `${row}.${r("tenant")}`,
      audit: {
        category: "configuration",
        targetType: "rule",
        recordId: `${row}.${r("id")}::text`,
        targetLabel: `${row}.${r("name")}`,
        actor,
      },
    });

  const matchedEvent = ctx.record({
    type: "rule.matched",
    payload: `jsonb_build_object('organizationId', v_rule.${r("tenant")}::text, 'ruleId', v_rule.${r("id")}::text, 'version', v_rule.${r("version")}, 'subjectType', v_rule.${r("subjectType")}, 'subjectId', record_rule_evaluation.subject_id, 'trigger', v_rule.${r("trigger")})`,
    subject: `'rules/' || v_rule.${r("id")}::text`,
    tenant: `v_rule.${r("tenant")}`,
    audit: false,
  });

  const signatures = {
    sync: `${fn("sync_rule_fields")}(text, jsonb)`,
    fieldsList: `${fn("rule_fields_list")}(text)`,
    fieldMap: `${fn("rule_field_map")}(text)`,
    check: `${fn("rule_check")}(jsonb, jsonb, integer)`,
    save: `${fn("save_rule")}(${id}, jsonb)`,
    list: `${fn("rules_list")}(${id}, text, text, boolean)`,
    get: `${fn("rule_get")}(uuid)`,
    versions: `${fn("rule_versions_list")}(uuid)`,
    enable: `${fn("set_rule_enabled")}(uuid, boolean)`,
    rank: `${fn("rank_rule")}(uuid, text)`,
    remove: `${fn("remove_rule")}(uuid)`,
    matching: `${fn("matching_rules")}(${id}, text, text, jsonb, text)`,
    record: `${fn("record_rule_evaluation")}(uuid, text, boolean, jsonb, text)`,
    run: `${fn("run_rules")}(${id}, text, text, text, jsonb, text)`,
    install: `${fn("install_default_rules")}(${id})`,
    reset: `${fn("reset_default_rule")}(uuid)`,
    evaluations: `${fn("rule_evaluations_list")}(uuid, timestamptz, integer)`,
  };

  const pure = [
    `${fn("rule_text")}(jsonb)`,
    `${fn("rule_numeric")}(jsonb)`,
    `${fn("rule_boolean")}(jsonb)`,
    `${fn("rule_list")}(jsonb)`,
    `${fn("rule_moment")}(text, jsonb)`,
    `${fn("rule_bounds")}(text, jsonb, text, timestamptz)`,
    `${fn("rule_date")}(text, text, jsonb, jsonb, text, timestamptz)`,
    `${fn("rule_equal")}(text, jsonb, jsonb)`,
    `${fn("rule_positive")}(text, text, text, jsonb, jsonb, text, timestamptz)`,
    `${fn("rule_node")}(jsonb, jsonb, jsonb, text, timestamptz)`,
    `${fn("rule_evaluate")}(jsonb, jsonb, jsonb, text, timestamptz)`,
    `${fn("rule_matches")}(jsonb, jsonb, jsonb, text, timestamptz)`,
    signatures.check,
  ];

  const user = [
    signatures.fieldsList,
    signatures.fieldMap,
    signatures.save,
    signatures.list,
    signatures.get,
    signatures.versions,
    signatures.enable,
    signatures.rank,
    signatures.remove,
    signatures.reset,
    signatures.matching,
    signatures.record,
    signatures.evaluations,
  ];

  const service = [signatures.sync, signatures.run, signatures.install];

  const grants = [
    ...pure.map(
      (signature) => `revoke execute on function ${signature} from public;
grant execute on function ${signature} to anon, authenticated, service_role;`,
    ),
    ...user.map(
      (signature) => `revoke execute on function ${signature} from public, anon;
grant execute on function ${signature} to authenticated, service_role;`,
    ),
    ...service.map(
      (
        signature,
      ) => `revoke execute on function ${signature} from public, anon, authenticated;
grant execute on function ${signature} to service_role;`,
    ),
  ].join("\n");

  return `${schemaPreamble(ctx)}
-- Tenant rules: a FilterQuery over a subject type's fields, tested when the
-- trigger event happens, and the actions the app runs when it matches.
create table if not exists ${t} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("tenant")} ${id} not null,
  ${r("subjectType")} text not null check (${r("subjectType")} ~ ${sqlString(SUBJECT_TYPE)}),
  ${r("trigger")} text not null check (length(${r("trigger")}) <= 128 and ${r("trigger")} ~ ${sqlString(TRIGGER)}),
  ${r("name")} text not null check (length(${r("name")}) between 1 and 200),
  ${r("description")} text check (length(${r("description")}) <= 2000),
  ${r("conditions")} jsonb not null,
  ${r("actions")} jsonb not null default '[]'::jsonb check (jsonb_typeof(${r("actions")}) = 'array'),
  ${r("enabled")} boolean not null default false,
  ${r("stopProcessing")} boolean not null default false,
  ${r("rank")} text collate "C" not null default 'V',
  ${r("version")} integer not null default 1,
  ${r("createdBy")} uuid references auth.users (id) on delete set null default auth.uid(),
  ${r("updatedBy")} uuid references auth.users (id) on delete set null default auth.uid(),
  ${r("createdAt")} timestamptz not null default now(),
  ${r("updatedAt")} timestamptz not null default now()
);
create index if not exists ${ctx.naming.rename("rules_trigger_idx")} on ${t} (${r("tenant")}, ${r("subjectType")}, ${r("trigger")}, ${r("rank")});
create index if not exists ${ctx.naming.rename("rules_created_by_idx")} on ${t} (${r("createdBy")}) where ${r("createdBy")} is not null;
create index if not exists ${ctx.naming.rename("rules_updated_by_idx")} on ${t} (${r("updatedBy")}) where ${r("updatedBy")} is not null;
alter table ${t} add column if not exists ${r("defaultKey")} text;
create unique index if not exists ${ctx.naming.rename("rules_default_key_idx")} on ${t} (${r("tenant")}, ${r("defaultKey")}) where ${r("defaultKey")} is not null;
${lockTable(t)}

-- The automations blocks ship (defineBlock automations). Each organization
-- gets its own copy in rules the first time its rules run or are listed, and
-- may turn it off or edit it; reset_default_rule restores the shipped one.
create table if not exists ${d} (
  ${rd("key")} text primary key check (length(${rd("key")}) <= 128 and ${rd("key")} ~ ${sqlString(ACTION_KIND)}),
  ${rd("block")} text not null,
  ${rd("subjectType")} text not null check (${rd("subjectType")} ~ ${sqlString(SUBJECT_TYPE)}),
  ${rd("trigger")} text not null check (length(${rd("trigger")}) <= 128 and ${rd("trigger")} ~ ${sqlString(TRIGGER)}),
  ${rd("name")} text not null check (length(${rd("name")}) between 1 and 200),
  ${rd("description")} text check (length(${rd("description")}) <= 2000),
  ${rd("conditions")} jsonb not null default '{"id": "root", "type": "group", "combinator": "and", "rules": []}'::jsonb,
  ${rd("actions")} jsonb not null default '[]'::jsonb check (jsonb_typeof(${rd("actions")}) = 'array'),
  ${rd("enabled")} boolean not null default true,
  ${rd("updatedAt")} timestamptz not null default now()
);
${lockTable(d)}

-- Every saved version of a rule's conditions and actions.
create table if not exists ${v} (
  ${rv("rule")} uuid not null references ${t} (${r("id")}) on delete cascade,
  ${rv("version")} integer not null,
  ${rv("tenant")} ${id} not null,
  ${rv("name")} text not null,
  ${rv("conditions")} jsonb not null,
  ${rv("actions")} jsonb not null,
  ${rv("savedBy")} uuid,
  ${rv("savedAt")} timestamptz not null default now(),
  primary key (${rv("rule")}, ${rv("version")})
);
create index if not exists ${ctx.naming.rename("rule_versions_tenant_idx")} on ${v} (${rv("tenant")});
${lockTable(v)}

-- Live and test evaluations: which rule version saw which subject, and the
-- truth of every condition and group.
create table if not exists ${e} (
  ${re("id")} bigint generated always as identity primary key,
  ${re("tenant")} ${id} not null,
  ${re("rule")} uuid not null references ${t} (${r("id")}) on delete cascade,
  ${re("version")} integer not null,
  ${re("subjectType")} text not null,
  ${re("subjectId")} text,
  ${re("trigger")} text not null,
  ${re("matched")} boolean not null,
  ${re("results")} jsonb not null default '{}'::jsonb,
  ${re("mode")} text not null default 'live' check (${re("mode")} in ('live', 'test')),
  ${re("evaluatedBy")} uuid,
  ${re("evaluatedAt")} timestamptz not null default now()
);
create index if not exists ${ctx.naming.rename("rule_evaluations_rule_idx")} on ${e} (${re("rule")}, ${re("evaluatedAt")} desc);
create index if not exists ${ctx.naming.rename("rule_evaluations_tenant_idx")} on ${e} (${re("tenant")}, ${re("evaluatedAt")} desc);
${lockTable(e)}

-- The fields rules may test, per subject type. The app declares them in code
-- (defineRuleFields) and syncs them with the service role.
create table if not exists ${f} (
  ${rf("subjectType")} text not null check (${rf("subjectType")} ~ ${sqlString(SUBJECT_TYPE)}),
  ${rf("id")} text not null check (length(${rf("id")}) <= 128 and ${rf("id")} ~ ${sqlString(FIELD_ID)}),
  ${rf("label")} text not null,
  ${rf("description")} text,
  ${rf("type")} text not null check (${rf("type")} in (${Object.keys(FILTER_OPERATORS).map(sqlString).join(", ")})),
  ${rf("path")} text not null check (${rf("path")} ~ ${sqlString(FIELD_ID)}),
  ${rf("columnType")} text not null,
  ${rf("nullable")} boolean not null default true,
  ${rf("options")} jsonb,
  ${rf("operators")} jsonb,
  ${rf("position")} integer not null default 0,
  ${rf("updatedAt")} timestamptz not null default now(),
  primary key (${rf("subjectType")}, ${rf("id")}),
  check (${rf("type")} <> 'date' or ${rf("columnType")} in ('date', 'timestamp', 'timestamptz'))
);
${lockTable(f)}

${rulesEvaluator(ctx)}

-- Checks a tree against a field map and the operator table; returns the
-- number of conditions. Raises RULE_INVALID with the reason.
create or replace function ${fn("rule_check")}(node jsonb, fields jsonb, depth integer default 1)
returns integer
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_operators constant jsonb := ${operatorTable()};
  v_field jsonb;
  v_path text;
  v_operator text;
  v_arity text;
  v_count integer := 0;
  v_child jsonb;
begin
  if jsonb_typeof(node) is distinct from 'object' or jsonb_typeof(node -> 'id') is distinct from 'string'
    or length(node ->> 'id') not between 1 and 64 then
    ${fail("RULE_INVALID", "Every condition and group needs an id", "22023")}
  end if;
  if node ->> 'type' = 'rule' then
    if jsonb_typeof(node -> 'path') is distinct from 'array' or jsonb_array_length(node -> 'path') = 0 then
      ${fail("RULE_INVALID", "A condition needs a field path", "22023")}
    end if;
    v_operator := coalesce(node ->> 'operator', '');
    if v_operator = '' then
      return 0;
    end if;
    select string_agg(p.value, '.' order by p.n) into v_path
    from jsonb_array_elements_text(node -> 'path') with ordinality p(value, n);
    v_field := fields -> v_path;
    if v_field is null then
      ${raise("No rule field %", "22023", "RULE_FIELD_UNKNOWN", "v_path")}
    end if;
    v_arity := v_operators -> (v_field ->> 'type') ->> v_operator;
    if v_arity is null or (jsonb_typeof(v_field -> 'operators') = 'array' and not (v_field -> 'operators') ? v_operator) then
      ${raise("The field % has no operator %", "22023", "RULE_OPERATOR_INVALID", "v_path", "v_operator")}
    end if;
    if (v_arity = 'one' and coalesce(jsonb_typeof(node -> 'value'), 'null') = 'null')
      or (v_arity = 'one' and v_field ->> 'type' = 'date' and jsonb_typeof(node -> 'value') is distinct from 'object')
      or (v_arity = 'many' and (jsonb_typeof(node -> 'value') is distinct from 'array' or jsonb_array_length(node -> 'value') not between 1 and 100))
      or (v_arity = 'range' and (jsonb_typeof(node -> 'value') is distinct from 'array' or jsonb_array_length(node -> 'value') <> 2)) then
      ${raise("The condition on % has no valid value for %", "22023", "RULE_VALUE_INVALID", "v_path", "v_operator")}
    end if;
    if (node -> 'value') is not null and v_arity <> 'none' and length((node -> 'value')::text) > 10000 then
      ${raise("The value for % is too long", "22023", "RULE_VALUE_INVALID", "v_path")}
    end if;
    return 1;
  end if;
  if node ->> 'type' is distinct from 'group' or coalesce(node ->> 'combinator', '') not in ('and', 'or')
    or jsonb_typeof(node -> 'rules') is distinct from 'array' then
    ${fail("RULE_INVALID", "A group needs a combinator (and, or) and a list of rules", "22023")}
  end if;
  if depth > ${String(maxDepth)} then
    ${fail("RULE_INVALID", `Groups nest at most ${String(maxDepth)} deep`, "22023")}
  end if;
  for v_child in select x.value from jsonb_array_elements(node -> 'rules') x loop
    v_count := v_count + ${fn("rule_check")}(v_child, fields, depth + 1);
  end loop;
  if v_count > ${String(maxConditions)} then
    ${fail("RULE_INVALID", `A rule holds at most ${String(maxConditions)} conditions`, "22023")}
  end if;
  return v_count;
end;
$$;

-- Replaces a subject type's field catalog (service role). fields is an array
-- of { id, label, description, type, column, columnType, nullable, options,
-- operators }; returns how many fields the subject type has.
create or replace function ${fn("sync_rule_fields")}(subject_type text, fields jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_count integer;
begin
  if not (${SERVICE_CALLER}) then
    ${fail("RULE_FORBIDDEN", "Only the service role syncs rule fields")}
  end if;
  if jsonb_typeof(fields) is distinct from 'array' then
    ${fail("RULE_FIELDS_INVALID", "fields must be an array", "22023")}
  end if;
  insert into ${f} (${rf("subjectType")}, ${rf("id")}, ${rf("label")}, ${rf("description")}, ${rf("type")}, ${rf("path")}, ${rf("columnType")}, ${rf("nullable")}, ${rf("options")}, ${rf("operators")}, ${rf("position")})
  select sync_rule_fields.subject_type, x.value ->> 'id', coalesce(x.value ->> 'label', x.value ->> 'id'), x.value ->> 'description',
    x.value ->> 'type', coalesce(x.value ->> 'column', x.value ->> 'id'), coalesce(x.value ->> 'columnType', 'text'),
    coalesce((x.value ->> 'nullable')::boolean, true), x.value -> 'options', x.value -> 'operators', x.n::integer
  from jsonb_array_elements(fields) with ordinality x(value, n)
  on conflict (${rf("subjectType")}, ${rf("id")}) do update set
    ${rf("label")} = excluded.${rf("label")},
    ${rf("description")} = excluded.${rf("description")},
    ${rf("type")} = excluded.${rf("type")},
    ${rf("path")} = excluded.${rf("path")},
    ${rf("columnType")} = excluded.${rf("columnType")},
    ${rf("nullable")} = excluded.${rf("nullable")},
    ${rf("options")} = excluded.${rf("options")},
    ${rf("operators")} = excluded.${rf("operators")},
    ${rf("position")} = excluded.${rf("position")},
    ${rf("updatedAt")} = now();
  delete from ${f} x
  where x.${rf("subjectType")} = sync_rule_fields.subject_type
    and not exists (select 1 from jsonb_array_elements(fields) y where y.value ->> 'id' = x.${rf("id")});
  select count(*) into v_count from ${f} x where x.${rf("subjectType")} = sync_rule_fields.subject_type;
  return v_count;
exception when check_violation or not_null_violation then
  ${fail("RULE_FIELDS_INVALID", "A rule field has an invalid id, type, column or column type", "22023")}
end;
$$;

-- The field catalog, for the editor: one subject type, or all of them.
create or replace function ${fn("rule_fields_list")}(subject_type text default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(${fieldJson("x")} order by x.${rf("subjectType")}, x.${rf("position")}), '[]'::jsonb)
  from ${f} x
  where rule_fields_list.subject_type is null or x.${rf("subjectType")} = rule_fields_list.subject_type
$$;

-- The fields argument of rule_evaluate for a subject type.
create or replace function ${fn("rule_field_map")}(subject_type text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(x.${rf("id")}, jsonb_build_object(
    'type', x.${rf("type")}, 'column', x.${rf("path")}, 'columnType', x.${rf("columnType")},
    'nullable', x.${rf("nullable")}, 'operators', x.${rf("operators")}
  )), '{}'::jsonb)
  from ${f} x where x.${rf("subjectType")} = rule_field_map.subject_type
$$;

-- Creates or changes a rule. rule is { id?, version?, subjectType, trigger,
-- name, description, conditions, actions, enabled, stopProcessing }; keys
-- left out keep their value. Creating or changing a disabled rule takes the
-- edit permission; enabling one, or changing an enabled one, takes publish.
-- version, when given, must be the stored one.
create or replace function ${fn("save_rule")}(tenant ${id}, rule jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old ${t};
  v_row ${t};
  v_subject_type text;
  v_trigger text;
  v_name text;
  v_description text;
  v_conditions jsonb;
  v_actions jsonb;
  v_enabled boolean;
  v_stop boolean;
  v_fields jsonb;
  v_action jsonb;
begin
  if jsonb_typeof(rule) is distinct from 'object' then
    ${fail("RULE_INVALID", "rule must be an object", "22023")}
  end if;
  v_id := nullif(rule ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from ${t} x where x.${r("id")} = v_id and x.${r("tenant")} = save_rule.tenant for update;
    if v_old.${r("id")} is null then
      ${fail("RULE_NOT_FOUND", "No rule in this organization has this id", "P0002")}
    end if;
    if rule ? 'version' and (rule ->> 'version')::integer is distinct from v_old.${r("version")} then
      ${fail("RULE_CONFLICT", "The rule changed since it was read", "40001")}
    end if;
    if rule ? 'subjectType' and rule ->> 'subjectType' is distinct from v_old.${r("subjectType")} then
      ${fail("RULE_INVALID", "A rule's subject type can't change", "22023")}
    end if;
  end if;
  v_subject_type := coalesce(v_old.${r("subjectType")}, rule ->> 'subjectType');
  v_trigger := coalesce(rule ->> 'trigger', v_old.${r("trigger")});
  v_name := coalesce(nullif(trim(rule ->> 'name'), ''), v_old.${r("name")});
  v_description := case when rule ? 'description' then nullif(trim(rule ->> 'description'), '') else v_old.${r("description")} end;
  v_conditions := coalesce(rule -> 'conditions', v_old.${r("conditions")}, '{"id": "root", "type": "group", "combinator": "and", "rules": []}'::jsonb);
  v_actions := coalesce(rule -> 'actions', v_old.${r("actions")}, '[]'::jsonb);
  v_enabled := coalesce((rule ->> 'enabled')::boolean, v_old.${r("enabled")}, false);
  v_stop := coalesce((rule ->> 'stopProcessing')::boolean, v_old.${r("stopProcessing")}, false);
  if not ${canKey("save_rule.tenant", `(v_enabled or coalesce(v_old.${r("enabled")}, false))`)} then
    ${raise("You need % to save this rule", "42501", "RULE_FORBIDDEN", keyFor(`(v_enabled or coalesce(v_old.${r("enabled")}, false))`))}
  end if;
  if v_subject_type is null or v_subject_type !~ ${sqlString(SUBJECT_TYPE)} then
    ${fail("RULE_INVALID", "A rule needs a subject type", "22023")}
  end if;
  if v_trigger is null or length(v_trigger) > 128 or v_trigger !~ ${sqlString(TRIGGER)} then
    ${fail("RULE_INVALID", "A rule needs a trigger such as expense.submitted", "22023")}
  end if;
  if v_name is null or length(v_name) > 200 then
    ${fail("RULE_INVALID", "A rule needs a name of at most 200 characters", "22023")}
  end if;
  v_fields := ${fn("rule_field_map")}(v_subject_type);
  if v_fields = '{}'::jsonb and v_old.${r("defaultKey")} is null then
    ${raise("No rule fields for %; sync them first", "22023", "RULE_SUBJECT_UNKNOWN", "v_subject_type")}
  end if;
  perform ${fn("rule_check")}(v_conditions, v_fields, 1);
  if jsonb_typeof(v_actions) is distinct from 'array' or jsonb_array_length(v_actions) > ${String(maxActions)} then
    ${fail("RULE_ACTIONS_INVALID", `actions must be an array of at most ${String(maxActions)} entries`, "22023")}
  end if;
  for v_action in select x.value from jsonb_array_elements(v_actions) x loop
    if jsonb_typeof(v_action) is distinct from 'object' or v_action ->> 'kind' is null
      or length(v_action ->> 'kind') > 128 or v_action ->> 'kind' !~ ${sqlString(ACTION_KIND)}
      or (v_action ? 'config' and jsonb_typeof(v_action -> 'config') is distinct from 'object') then
      ${fail("RULE_ACTIONS_INVALID", "Every action needs a kind such as approvals.request and an optional config object", "22023")}
    end if;
  end loop;
  if v_old.${r("id")} is null then
    insert into ${t} (${r("tenant")}, ${r("subjectType")}, ${r("trigger")}, ${r("name")}, ${r("description")}, ${r("conditions")}, ${r("actions")}, ${r("enabled")}, ${r("stopProcessing")}, ${r("rank")})
    values (save_rule.tenant, v_subject_type, v_trigger, v_name, v_description, v_conditions, v_actions, v_enabled, v_stop,
      ${rankAfter(`(select max(x.${r("rank")} collate "C") from ${t} x where x.${r("tenant")} = save_rule.tenant and x.${r("subjectType")} = v_subject_type)`)})
    returning * into v_row;
  elsif v_old.${r("trigger")} = v_trigger and v_old.${r("name")} = v_name
    and v_old.${r("description")} is not distinct from v_description
    and v_old.${r("conditions")} = v_conditions and v_old.${r("actions")} = v_actions
    and v_old.${r("enabled")} = v_enabled and v_old.${r("stopProcessing")} = v_stop then
    return ${ruleJson("v_old")};
  else
    update ${t} x set
      ${r("trigger")} = v_trigger,
      ${r("name")} = v_name,
      ${r("description")} = v_description,
      ${r("conditions")} = v_conditions,
      ${r("actions")} = v_actions,
      ${r("enabled")} = v_enabled,
      ${r("stopProcessing")} = v_stop,
      ${r("version")} = x.${r("version")} + 1,
      ${r("updatedBy")} = auth.uid(),
      ${r("updatedAt")} = now()
    where x.${r("id")} = v_old.${r("id")}
    returning * into v_row;
  end if;
  insert into ${v} (${rv("rule")}, ${rv("version")}, ${rv("tenant")}, ${rv("name")}, ${rv("conditions")}, ${rv("actions")}, ${rv("savedBy")})
  values (v_row.${r("id")}, v_row.${r("version")}, v_row.${r("tenant")}, v_row.${r("name")}, v_row.${r("conditions")}, v_row.${r("actions")}, auth.uid())
  on conflict do nothing;
  ${ruleEvent("rule.saved", "v_row")}
  if v_row.${r("enabled")} and not coalesce(v_old.${r("enabled")}, false) then
    ${ruleEvent("rule.enabled", "v_row")}
  elsif not v_row.${r("enabled")} and coalesce(v_old.${r("enabled")}, false) then
    ${ruleEvent("rule.disabled", "v_row")}
  end if;
  return ${ruleJson("v_row")};
end;
$$;

-- An organization's rules in evaluation order, filtered by subject type,
-- trigger and enabled when given.
create or replace function ${fn("rules_list")}(tenant ${id}, subject_type text default null, trigger text default null, enabled boolean default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not ${can("rules_list.tenant", read)} then
    ${fail("RULE_FORBIDDEN", "You may not read this organization's rules")}
  end if;
  perform ${fn("install_default_rules")}(rules_list.tenant);
  return (
    select coalesce(jsonb_agg(${ruleJson("x")} order by x.${r("subjectType")}, x.${r("trigger")}, x.${r("rank")} collate "C"), '[]'::jsonb)
    from ${t} x
    where x.${r("tenant")} = rules_list.tenant
      and (rules_list.subject_type is null or x.${r("subjectType")} = rules_list.subject_type)
      and (rules_list.trigger is null or x.${r("trigger")} = rules_list.trigger)
      and (rules_list.enabled is null or x.${r("enabled")} = rules_list.enabled)
  );
end;
$$;

-- One rule, or null when the caller can't read it.
create or replace function ${fn("rule_get")}(id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row ${t};
begin
  select * into v_row from ${t} x where x.${r("id")} = rule_get.id;
  if v_row.${r("id")} is null or not ${can(`v_row.${r("tenant")}`, read)} then
    return null;
  end if;
  return ${ruleJson("v_row")};
end;
$$;

-- A rule's saved versions, newest first.
create or replace function ${fn("rule_versions_list")}(id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant ${id};
begin
  select x.${r("tenant")} into v_tenant from ${t} x where x.${r("id")} = rule_versions_list.id;
  if v_tenant is null or not ${can("v_tenant", read)} then
    return '[]'::jsonb;
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'ruleId', x.${rv("rule")}, 'version', x.${rv("version")}, 'name', x.${rv("name")},
      'conditions', x.${rv("conditions")}, 'actions', x.${rv("actions")},
      'savedBy', x.${rv("savedBy")}, 'savedAt', x.${rv("savedAt")}
    ) order by x.${rv("version")} desc), '[]'::jsonb)
    from ${v} x where x.${rv("rule")} = rule_versions_list.id
  );
end;
$$;

-- Turns a rule on or off (publish permission).
create or replace function ${fn("set_rule_enabled")}(id uuid, enabled boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t};
begin
  select * into v_row from ${t} x where x.${r("id")} = set_rule_enabled.id for update;
  if v_row.${r("id")} is null or not ${can(`v_row.${r("tenant")}`, read)} then
    ${fail("RULE_NOT_FOUND", "No rule you can read has this id", "P0002")}
  end if;
  if not ${can(`v_row.${r("tenant")}`, publish)} then
    ${fail("RULE_FORBIDDEN", "Publishing rules needs the publish permission")}
  end if;
  if v_row.${r("enabled")} = coalesce(set_rule_enabled.enabled, false) then
    return ${ruleJson("v_row")};
  end if;
  update ${t} x set ${r("enabled")} = coalesce(set_rule_enabled.enabled, false), ${r("updatedBy")} = auth.uid(), ${r("updatedAt")} = now()
  where x.${r("id")} = v_row.${r("id")} returning * into v_row;
  if v_row.${r("enabled")} then
    ${ruleEvent("rule.enabled", "v_row")}
  else
    ${ruleEvent("rule.disabled", "v_row")}
  end if;
  return ${ruleJson("v_row")};
end;
$$;

-- Moves a rule to a rank key the client computed with rankBetween.
create or replace function ${fn("rank_rule")}(id uuid, rank text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t};
begin
  select * into v_row from ${t} x where x.${r("id")} = rank_rule.id for update;
  if v_row.${r("id")} is null or not ${can(`v_row.${r("tenant")}`, read)} then
    ${fail("RULE_NOT_FOUND", "No rule you can read has this id", "P0002")}
  end if;
  if not ${canKey(`v_row.${r("tenant")}`, `v_row.${r("enabled")}`)} then
    ${raise("You need % to move this rule", "42501", "RULE_FORBIDDEN", keyFor(`v_row.${r("enabled")}`))}
  end if;
  if rank_rule.rank is null or rank_rule.rank !~ ${RANK_KEY_PATTERN} then
    ${fail("RULE_RANK_INVALID", "rank must be a key from rankBetween", "22023")}
  end if;
  update ${t} x set ${r("rank")} = rank_rule.rank, ${r("updatedAt")} = now()
  where x.${r("id")} = v_row.${r("id")} returning * into v_row;
  return ${ruleJson("v_row")};
end;
$$;

-- Removes a rule with its versions and evaluations (admin permission);
-- false when there is none the caller may remove.
create or replace function ${fn("remove_rule")}(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t};
begin
  select * into v_row from ${t} x where x.${r("id")} = remove_rule.id;
  if v_row.${r("id")} is null or not ${can(`v_row.${r("tenant")}`, admin)} then
    return false;
  end if;
  if v_row.${r("defaultKey")} is not null then
    ${fail("RULE_DEFAULT", "A block ships this automation; turn it off instead of removing it", "22023")}
  end if;
  delete from ${t} x where x.${r("id")} = v_row.${r("id")};
  ${ruleEvent("rule.removed", "v_row")}
  return true;
end;
$$;

-- The enabled rules for a trigger that match subject, in rank order, each
-- with its results; a matched rule with stop_processing ends the list.
create or replace function ${fn("matching_rules")}(tenant ${id}, subject_type text, trigger text, subject jsonb, time_zone text default 'UTC')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_fields jsonb;
  v_rule ${t};
  v_result jsonb;
  v_matches jsonb := '[]'::jsonb;
begin
  if not ${can("matching_rules.tenant", read)} then
    ${fail("RULE_FORBIDDEN", "You may not read this organization's rules")}
  end if;
  v_fields := ${fn("rule_field_map")}(matching_rules.subject_type);
  for v_rule in
    select * from ${t} x
    where x.${r("tenant")} = matching_rules.tenant and x.${r("subjectType")} = matching_rules.subject_type
      and x.${r("trigger")} = matching_rules.trigger and x.${r("enabled")}
    order by x.${r("rank")} collate "C"
  loop
    v_result := ${fn("rule_evaluate")}(v_rule.${r("conditions")}, matching_rules.subject, v_fields, coalesce(matching_rules.time_zone, 'UTC'), now());
    if (v_result ->> 'matched')::boolean then
      v_matches := v_matches || jsonb_build_array(jsonb_build_object('rule', ${ruleJson("v_rule")}, 'results', v_result -> 'results'));
      exit when v_rule.${r("stopProcessing")};
    end if;
  end loop;
  return v_matches;
end;
$$;

-- Logs one evaluation. Live entries come from the service role and emit
-- rule.matched when they match; a test entry takes the edit permission.
create or replace function ${fn("record_rule_evaluation")}(rule uuid, subject_id text, matched boolean, results jsonb default '{}'::jsonb, mode text default 'live')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rule ${t};
  v_row ${e};
begin
  select * into v_rule from ${t} x where x.${r("id")} = record_rule_evaluation.rule;
  if v_rule.${r("id")} is null then
    ${fail("RULE_NOT_FOUND", "No rule has this id", "P0002")}
  end if;
  if coalesce(record_rule_evaluation.mode, 'live') not in ('live', 'test') then
    ${fail("RULE_INVALID", "mode is live or test", "22023")}
  end if;
  if coalesce(record_rule_evaluation.mode, 'live') = 'live' and not (${SERVICE_CALLER}) then
    ${fail("RULE_FORBIDDEN", "Only the service role records live evaluations")}
  end if;
  if not ${can(`v_rule.${r("tenant")}`, edit)} then
    ${fail("RULE_FORBIDDEN", "Testing rules needs the edit permission")}
  end if;
  insert into ${e} (${re("tenant")}, ${re("rule")}, ${re("version")}, ${re("subjectType")}, ${re("subjectId")}, ${re("trigger")}, ${re("matched")}, ${re("results")}, ${re("mode")}, ${re("evaluatedBy")})
  values (v_rule.${r("tenant")}, v_rule.${r("id")}, v_rule.${r("version")}, v_rule.${r("subjectType")}, record_rule_evaluation.subject_id, v_rule.${r("trigger")},
    coalesce(record_rule_evaluation.matched, false), coalesce(record_rule_evaluation.results, '{}'::jsonb), coalesce(record_rule_evaluation.mode, 'live'), auth.uid())
  returning * into v_row;
  if v_row.${re("mode")} = 'live' and v_row.${re("matched")} then
    ${matchedEvent}
  end if;
  return ${evaluationJson("v_row")};
end;
$$;

-- For database triggers and jobs (service role): evaluates the enabled rules
-- for a trigger, logs each one live and returns the matches as
-- matching_rules does. A null subject_type tests every rule for the trigger,
-- each against its own subject type's fields.
create or replace function ${fn("run_rules")}(tenant ${id}, subject_type text, trigger text, subject_id text, subject jsonb, time_zone text default 'UTC')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fields jsonb;
  v_rule ${t};
  v_result jsonb;
  v_matches jsonb := '[]'::jsonb;
begin
  if not (${SERVICE_CALLER}) then
    ${fail("RULE_FORBIDDEN", "Only the service role runs rules")}
  end if;
  perform ${fn("install_default_rules")}(run_rules.tenant);
  v_fields := ${fn("rule_field_map")}(run_rules.subject_type);
  for v_rule in
    select * from ${t} x
    where x.${r("tenant")} = run_rules.tenant
      and (run_rules.subject_type is null or x.${r("subjectType")} = run_rules.subject_type)
      and x.${r("trigger")} = run_rules.trigger and x.${r("enabled")}
    order by x.${r("rank")} collate "C"
  loop
    if run_rules.subject_type is null then
      v_fields := ${fn("rule_field_map")}(v_rule.${r("subjectType")});
    end if;
    v_result := ${fn("rule_evaluate")}(v_rule.${r("conditions")}, run_rules.subject, v_fields, coalesce(run_rules.time_zone, 'UTC'), now());
    perform ${fn("record_rule_evaluation")}(v_rule.${r("id")}, run_rules.subject_id, (v_result ->> 'matched')::boolean, v_result -> 'results', 'live');
    if (v_result ->> 'matched')::boolean then
      v_matches := v_matches || jsonb_build_array(jsonb_build_object('rule', ${ruleJson("v_rule")}, 'results', v_result -> 'results'));
      exit when v_rule.${r("stopProcessing")};
    end if;
  end loop;
  return v_matches;
end;
$$;

${defaultRulesSql({ ctx, can, canKey, keyFor, read, ruleEvent, ruleJson })}

-- A rule's evaluation log, newest first.
create or replace function ${fn("rule_evaluations_list")}(rule uuid, before timestamptz default null, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant ${id};
begin
  select x.${r("tenant")} into v_tenant from ${t} x where x.${r("id")} = rule_evaluations_list.rule;
  if v_tenant is null or not ${can("v_tenant", read)} then
    return '[]'::jsonb;
  end if;
  return (
    select coalesce(jsonb_agg(${evaluationJson("y")} order by y.${re("evaluatedAt")} desc, y.${re("id")} desc), '[]'::jsonb)
    from (
      select * from ${e} x
      where x.${re("rule")} = rule_evaluations_list.rule
        and (rule_evaluations_list.before is null or x.${re("evaluatedAt")} < rule_evaluations_list.before)
      order by x.${re("evaluatedAt")} desc, x.${re("id")} desc
      limit least(greatest(coalesce(rule_evaluations_list.page_size, 50), 1), 200)
    ) y
  );
end;
$$;

${grants}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "rule_evaluate",
      args: ["jsonb", "jsonb", "jsonb", "text", "timestamptz"],
      returns: "jsonb",
    },
    {
      name: "rule_matches",
      args: ["jsonb", "jsonb", "jsonb", "text", "timestamptz"],
      returns: "boolean",
    },
    {
      name: "rule_check",
      args: ["jsonb", "jsonb", "integer"],
      returns: "integer",
    },
    { name: "sync_rule_fields", args: ["text", "jsonb"], returns: "integer" },
    { name: "rule_fields_list", args: ["text"], returns: "jsonb" },
    { name: "rule_field_map", args: ["text"], returns: "jsonb" },
    { name: "save_rule", args: ["{id}", "jsonb"], returns: "jsonb" },
    {
      name: "rules_list",
      args: ["{id}", "text", "text", "boolean"],
      returns: "jsonb",
    },
    { name: "rule_get", args: ["uuid"], returns: "jsonb" },
    { name: "rule_versions_list", args: ["uuid"], returns: "jsonb" },
    { name: "set_rule_enabled", args: ["uuid", "boolean"], returns: "jsonb" },
    { name: "rank_rule", args: ["uuid", "text"], returns: "jsonb" },
    { name: "remove_rule", args: ["uuid"], returns: "boolean" },
    {
      name: "matching_rules",
      args: ["{id}", "text", "text", "jsonb", "text"],
      returns: "jsonb",
    },
    {
      name: "record_rule_evaluation",
      args: ["uuid", "text", "boolean", "jsonb", "text"],
      returns: "jsonb",
    },
    {
      name: "run_rules",
      args: ["{id}", "text", "text", "text", "jsonb", "text"],
      returns: "jsonb",
    },
    { name: "install_default_rules", args: ["{id}"], returns: "integer" },
    { name: "reset_default_rule", args: ["uuid"], returns: "jsonb" },
    {
      name: "rule_evaluations_list",
      args: ["uuid", "timestamptz", "integer"],
      returns: "jsonb",
    },
  ];
}

export const RULES: BlockSqlDefinition = {
  name: "automations",
  scopes: ["tenant"],
  title: "Rules",
  description:
    "Tenant-editable automations: a filter tree over a subject type's field catalog, tested when a trigger event happens, with action references the action registry runs. Blocks ship default automations (rule_defaults) that every organization gets a copy of, may turn off or edit, and can reset. rule_matches() evaluates a tree in SQL the same way evaluateFilterQuery does in TypeScript.",
  requires: ["memberships", "permissions"],
  integrates: [],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
