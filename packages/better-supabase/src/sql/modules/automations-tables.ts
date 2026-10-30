import type { AutomationsEvents } from "../../blocks/automations/events.ts";
import type { BlockSqlContext, BlockSqlEvents } from "../context.ts";

import { SUBJECT_TYPE_SQL_PATTERN } from "../../core/subject-type.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";
import { FILTER_OPERATORS } from "../../list/filter-query.ts";
import { lockTable } from "../shared.ts";

const RULE_PAYLOAD = [
  "organizationId",
  "ruleId",
  "name",
  "subjectType",
  "trigger",
  "version",
] as const;

export const AUTOMATION_EVENTS: BlockSqlEvents<AutomationsEvents> = {
  "automation.created": { subject: "rules", payload: RULE_PAYLOAD },
  "automation.updated": { subject: "rules", payload: RULE_PAYLOAD },
  "automation.enabled": { subject: "rules", payload: RULE_PAYLOAD },
  "automation.disabled": { subject: "rules", payload: RULE_PAYLOAD },
  "automation.deleted": { subject: "rules", payload: RULE_PAYLOAD },
  "automation.matched": {
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

export const SUBJECT_TYPE: string = SUBJECT_TYPE_SQL_PATTERN;
export const TRIGGER = "^[a-z][a-z0-9_]*([.:][a-z0-9_]+)*$";
export const ACTION_KIND = "^[a-z][a-z0-9_]*([.][a-z0-9_]+)*$";
const FIELD_ID = "^[A-Za-z_][A-Za-z0-9_]*([.][A-Za-z_][A-Za-z0-9_]*)*$";

/**
 * A logical column of `table`, quoted, or an empty string when the app's table
 * lacks it; every use of a missing one is guarded with `ctx.has`.
 */
export const columnOf =
  (ctx: BlockSqlContext, table: string) =>
  (column: string): string =>
    ctx.has(table, column) ? ctx.col(table, column) : "";

/**
 * `create table` for `table` with the entries whose column it has; a null
 * column is a table constraint.
 */
function createTable(
  ctx: BlockSqlContext,
  table: string,
  entries: readonly (readonly [string | null, string])[],
): string {
  return `create table if not exists ${ctx.table(table)} (\n  ${entries
    .filter(([column]) => column === null || ctx.has(table, column))
    .map(([column, definition]) =>
      column === null ? definition : `${ctx.col(table, column)} ${definition}`,
    )
    .join(",\n  ")}\n);`;
}

/** The unique index an `on conflict` target needs over the app's table. */
function appKey(
  ctx: BlockSqlContext,
  table: string,
  what: string,
  columns: readonly string[],
): string {
  return ctx.owns(table)
    ? ""
    : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName(table).name}_${what}_key`)} on ${ctx.table(table)} (${columns.map((column) => ctx.col(table, column)).join(", ")});`;
}

/** The tables of the automations module. */
export function rulesTablesSql(ctx: BlockSqlContext): string {
  const id = ctx.idType;
  const t = ctx.table("rules");
  const v = ctx.table("versions");
  const e = ctx.table("evaluations");
  const f = ctx.table("fields");
  const d = ctx.table("defaults");
  const r = columnOf(ctx, "rules");
  const rd = columnOf(ctx, "defaults");
  const rv = columnOf(ctx, "versions");
  const re = columnOf(ctx, "evaluations");
  const rf = columnOf(ctx, "fields");

  const byIndex = (column: string, name: string): string =>
    ctx.has("rules", column)
      ? `\ncreate index if not exists ${ctx.naming.rename(name)} on ${t} (${r(column)}) where ${r(column)} is not null;`
      : "";

  const defaultKey = ctx.has("rules", "defaultKey")
    ? `\nalter table ${t} add column if not exists ${r("defaultKey")} text;
create unique index if not exists ${ctx.naming.rename("rules_default_key_idx")} on ${t} (${r("tenant")}, ${r("defaultKey")}) where ${r("defaultKey")} is not null;`
    : "";

  return `-- Tenant rules: a FilterQuery over a subject type's fields, tested when the
-- trigger event happens, and the actions the app runs when it matches.
${createTable(ctx, "rules", [
  ["id", "uuid primary key default gen_random_uuid()"],
  ["tenant", `${id} not null`],
  [
    "subjectType",
    `text not null check (${r("subjectType")} ~ ${sqlString(SUBJECT_TYPE)})`,
  ],
  [
    "trigger",
    `text not null check (length(${r("trigger")}) <= 128 and ${r("trigger")} ~ ${sqlString(TRIGGER)})`,
  ],
  ["name", `text not null check (length(${r("name")}) between 1 and 200)`],
  ["description", `text check (length(${r("description")}) <= 2000)`],
  ["conditions", "jsonb not null"],
  [
    "actions",
    `jsonb not null default '[]'::jsonb check (jsonb_typeof(${r("actions")}) = 'array')`,
  ],
  ["enabled", "boolean not null default false"],
  ["stopProcessing", "boolean not null default false"],
  ["rank", `text collate "C" not null default 'V'`],
  ["version", "integer not null default 1"],
  [
    "createdBy",
    "uuid references auth.users (id) on delete set null default auth.uid()",
  ],
  [
    "updatedBy",
    "uuid references auth.users (id) on delete set null default auth.uid()",
  ],
  ["createdAt", "timestamptz not null default now()"],
  ["updatedAt", "timestamptz not null default now()"],
])}
create index if not exists ${ctx.naming.rename("rules_trigger_idx")} on ${t} (${r("tenant")}, ${r("subjectType")}, ${r("trigger")}, ${r("rank")});${byIndex("createdBy", "rules_created_by_idx")}${byIndex("updatedBy", "rules_updated_by_idx")}${defaultKey}
${lockTable(t)}

-- The automations blocks ship (defineBlock automations). Each organization
-- gets its own copy in rules the first time its rules run or are listed, and
-- may turn it off or edit it; reset_default_rule restores the shipped one.
${createTable(ctx, "defaults", [
  [
    "key",
    `text primary key check (length(${rd("key")}) <= 128 and ${rd("key")} ~ ${sqlString(ACTION_KIND)})`,
  ],
  ["block", "text not null"],
  [
    "subjectType",
    `text not null check (${rd("subjectType")} ~ ${sqlString(SUBJECT_TYPE)})`,
  ],
  [
    "trigger",
    `text not null check (length(${rd("trigger")}) <= 128 and ${rd("trigger")} ~ ${sqlString(TRIGGER)})`,
  ],
  ["name", `text not null check (length(${rd("name")}) between 1 and 200)`],
  ["description", `text check (length(${rd("description")}) <= 2000)`],
  [
    "conditions",
    `jsonb not null default '{"id": "root", "type": "group", "combinator": "and", "rules": []}'::jsonb`,
  ],
  [
    "actions",
    `jsonb not null default '[]'::jsonb check (jsonb_typeof(${rd("actions")}) = 'array')`,
  ],
  ["enabled", "boolean not null default true"],
  ["updatedAt", "timestamptz not null default now()"],
])}${appKey(ctx, "defaults", "key", ["key"])}
${lockTable(d)}

-- Every saved version of a rule's conditions and actions.
${createTable(ctx, "versions", [
  ["rule", `uuid not null references ${t} (${r("id")}) on delete cascade`],
  ["version", "integer not null"],
  ["tenant", `${id} not null`],
  ["name", "text not null"],
  ["conditions", "jsonb not null"],
  ["actions", "jsonb not null"],
  ["savedBy", "uuid"],
  ["savedAt", "timestamptz not null default now()"],
  [null, `primary key (${rv("rule")}, ${rv("version")})`],
])}
create index if not exists ${ctx.naming.rename("rule_versions_tenant_idx")} on ${v} (${rv("tenant")});${appKey(ctx, "versions", "version", ["rule", "version"])}
${lockTable(v)}

-- Live and test evaluations: which rule version saw which subject, and the
-- truth of every condition and group.
${createTable(ctx, "evaluations", [
  ["id", "bigint generated always as identity primary key"],
  ["tenant", `${id} not null`],
  ["rule", `uuid not null references ${t} (${r("id")}) on delete cascade`],
  ["version", "integer not null"],
  ["subjectType", "text not null"],
  ["subjectId", "text"],
  ["trigger", "text not null"],
  ["matched", "boolean not null"],
  ["results", "jsonb not null default '{}'::jsonb"],
  [
    "mode",
    `text not null default 'live' check (${re("mode")} in ('live', 'test'))`,
  ],
  ["evaluatedBy", "uuid"],
  ["evaluatedAt", "timestamptz not null default now()"],
])}
create index if not exists ${ctx.naming.rename("rule_evaluations_rule_idx")} on ${e} (${re("rule")}, ${re("evaluatedAt")} desc);
create index if not exists ${ctx.naming.rename("rule_evaluations_tenant_idx")} on ${e} (${re("tenant")}, ${re("evaluatedAt")} desc);
${lockTable(e)}

-- The fields rules may test, per subject type. The app declares them in code
-- (defineRuleFields) and syncs them with the service role.
${createTable(ctx, "fields", [
  [
    "subjectType",
    `text not null check (${rf("subjectType")} ~ ${sqlString(SUBJECT_TYPE)})`,
  ],
  [
    "id",
    `text not null check (length(${rf("id")}) <= 128 and ${rf("id")} ~ ${sqlString(FIELD_ID)})`,
  ],
  ["label", "text not null"],
  ["description", "text"],
  [
    "type",
    `text not null check (${rf("type")} in (${Object.keys(FILTER_OPERATORS).map(sqlString).join(", ")}))`,
  ],
  ["path", `text not null check (${rf("path")} ~ ${sqlString(FIELD_ID)})`],
  ["columnType", "text not null"],
  ["nullable", "boolean not null default true"],
  ["options", "jsonb"],
  ["operators", "jsonb"],
  ["position", "integer not null default 0"],
  ["updatedAt", "timestamptz not null default now()"],
  [null, `primary key (${rf("subjectType")}, ${rf("id")})`],
  [
    null,
    `check (${rf("type")} <> 'date' or ${rf("columnType")} in ('date', 'timestamp', 'timestamptz'))`,
  ],
])}${appKey(ctx, "fields", "field", ["subjectType", "id"])}
${lockTable(f)}`;
}
