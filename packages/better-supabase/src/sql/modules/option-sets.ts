import type { OptionSetsEvents } from "../../blocks/option-sets/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";
import type { OptionNames } from "./option-sets-sql.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { lockTable, schemaPreamble } from "../shared.ts";
import { brandSourceOf } from "./brand-source.ts";
import { optionBindings } from "./option-sets-bindings.ts";
import {
  defaultSet,
  levelTrigger,
  optionColumn,
  setFunctions,
} from "./option-sets-sql.ts";
import { moduleOperations } from "./permissions-model.ts";

const setEvent = {
  subject: "option-sets",
  payload: ["organizationId", "optionSetId", "subjectType", "field", "key"],
} as const;

const itemEvent = {
  subject: "option-sets",
  payload: ["organizationId", "optionSetId", "itemId", "key", "level"],
} as const;

const EVENTS: BlockSqlEvents<OptionSetsEvents> = {
  "option_set.created": setEvent,
  "option_set.updated": setEvent,
  "option_set_item.created": itemEvent,
  "option_set_item.updated": itemEvent,
  "option_set_item.archived": {
    subject: "option-sets",
    payload: ["organizationId", "optionSetId", "itemId"],
  },
  "option_set_item.restored": {
    subject: "option-sets",
    payload: ["organizationId", "optionSetId", "itemId"],
  },
};

const tenantExport = { tenant: "tenant", export: true } as const;

const NAMES: BlockSqlNames = {
  entities: {
    optionSet: { table: "sets", singular: "option_set", primary: true },
  },
  events: EVENTS,
  hooks: [],
  options: ["brand"],
  tables: {
    sets: {
      name: "option_sets",
      lifecycle: tenantExport,
      app: {},
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        field: "field",
        scope: "scope_id",
        key: "key",
        name: "name",
        isDefault: "is_default",
        archivedAt: "archived_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    items: {
      name: "option_set_items",
      lifecycle: tenantExport,
      app: {},
      columns: {
        id: "id",
        tenant: "tenant_id",
        set: "option_set_id",
        key: "key",
        systemKey: "system_key",
        label: "label",
        color: "color",
        icon: "icon",
        rank: "rank",
        level: "level",
        description: "description",
        archivedAt: "archived_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
  },
};

function namesOf(ctx: BlockSqlContext): OptionNames {
  const keys = moduleOperations("option-sets");

  return {
    idType: ctx.idType,
    read: ctx.permission("read", keys.read),
    manage: ctx.permission("manage", keys.manage),
    t: (table) => ctx.table(table),
    c: (table, column) => ctx.col(table, column),
  };
}

function tables(ctx: BlockSqlContext, names: OptionNames): string {
  const { t, c, idType } = names;
  const s = (column: string): string => c("sets", column);
  const i = (column: string): string => c("items", column);

  // Over the app's table the render drops the inline keys the module relies on.
  const key = (
    table: string,
    suffix: string,
    columns: string,
    nulls = "",
  ): string =>
    ctx.owns(table)
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName(table).name}_${suffix}`)} on ${t(table)} (${columns})${nulls};`;

  const read = (table: string, tenant: string): string =>
    renderPolicy(
      makePolicy({
        table: t(table),
        name: `${ctx.tableName(table).name}_read`,
        command: "select",
        roles: ["authenticated"],
        using: ctx.scope.check(tenant, names.read),
      }),
      { target: t(table) },
    );

  return `
create table if not exists ${t("sets")} (
  ${s("id")} uuid primary key default gen_random_uuid(),
  ${s("tenant")} ${idType} not null,
  ${s("subjectType")} text not null,
  ${s("field")} text not null check (${s("field")} ~ '^[a-z][a-z0-9_]{0,62}$'),
  ${s("scope")} text,
  ${s("key")} text not null check (${s("key")} ~ '^[a-z][a-z0-9_-]{0,62}$'),
  ${s("name")} text not null check (length(${s("name")}) between 1 and 200),
  ${s("isDefault")} boolean not null default false,
  ${s("archivedAt")} timestamptz,
  ${s("createdAt")} timestamptz not null default now(),
  ${s("updatedAt")} timestamptz not null default now(),
  unique nulls not distinct (${s("tenant")}, ${s("subjectType")}, ${s("field")}, ${s("scope")}, ${s("key")})
);${key("sets", "key_key", `${s("tenant")}, ${s("subjectType")}, ${s("field")}, ${s("scope")}, ${s("key")}`, " nulls not distinct")}
create unique index if not exists ${ctx.naming.rename("option_sets_default_idx")} on ${t("sets")} (${s("tenant")}, ${s("subjectType")}, ${s("field")}, coalesce(${s("scope")}, ''))
  where ${s("isDefault")} and ${s("archivedAt")} is null;
${lockTable(t("sets"), { read: true })}
${read("sets", s("tenant"))}

create table if not exists ${t("items")} (
  ${i("id")} uuid primary key default gen_random_uuid(),
  ${i("tenant")} ${idType} not null,
  ${i("set")} uuid not null references ${t("sets")} (${s("id")}) on delete cascade,
  ${i("key")} text not null check (${i("key")} ~ '^[a-z][a-z0-9_-]{0,62}$'),
  ${i("systemKey")} text,
  ${i("label")} text not null check (length(${i("label")}) between 1 and 200),
  ${i("color")} text check (${i("color")} is null or length(${i("color")}) <= 50),
  ${i("icon")} text check (${i("icon")} is null or length(${i("icon")}) <= 100),
  ${i("rank")} text collate "C" not null default 'V',
  ${i("level")} integer not null,
  ${i("description")} text check (${i("description")} is null or length(${i("description")}) <= 1000),
  ${i("archivedAt")} timestamptz,
  ${i("createdAt")} timestamptz not null default now(),
  ${i("updatedAt")} timestamptz not null default now(),
  unique (${i("set")}, ${i("key")})
);${key("items", "key_key", `${i("set")}, ${i("key")}`)}
create unique index if not exists ${ctx.naming.rename("option_set_items_system_key_idx")} on ${t("items")} (${i("set")}, ${i("systemKey")}) where ${i("systemKey")} is not null;
create index if not exists ${ctx.naming.rename("option_set_items_set_idx")} on ${t("items")} (${i("set")}, ${i("rank")});
${lockTable(t("items"), { read: true })}
${read("items", i("tenant"))}
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const names = namesOf(ctx);
  const bindings = optionBindings(ctx);
  const brand = brandSourceOf(ctx, `blocks.${ctx.instance}.options.brand`);

  return `${schemaPreamble(ctx)}
-- Option sets (ADR 0243): tenant-editable items for a field such as priority,
-- each with a level that is written to the record's own column, and starter
-- items per brand.
${tables(ctx, names)}
-- The column that holds the chosen item, on each bound table.
${bindings.map((binding) => optionColumn(names, binding)).join("\n")}
${defaultSet(ctx, names, bindings, brand)}${bindings.map((binding) => levelTrigger(ctx, names, binding)).join("")}${setFunctions(ctx, names, bindings)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    { name: "list_option_sets", args: ["{id}", "jsonb"], returns: "jsonb" },
    {
      name: "ensure_option_set",
      args: ["{id}", "text", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "save_option_set",
      args: ["{id}", "uuid", "text", "text", "text", "text", "text", "boolean"],
      returns: "jsonb",
    },
    {
      name: "save_option_set_item",
      args: ["uuid", "uuid", "text", "text", "integer", "text", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "rank_option_set_item",
      args: ["uuid", "text"],
      returns: "boolean",
    },
    {
      name: "archive_option_set_item",
      args: ["uuid", "uuid"],
      returns: "boolean",
    },
    { name: "restore_option_set_item", args: ["uuid"], returns: "boolean" },
  ];
}

export const OPTION_SETS: BlockSqlDefinition = {
  name: "option-sets",
  scopes: ["tenant"],
  title: "Option sets",
  description:
    "Tenant-editable items for a field such as priority or severity: ordered items with a label, color, icon and a level written to the record's own column, replacement when an item is removed, and starter items per brand.",
  requires: ["memberships", "permissions", "subjects"],
  integrates: ["outbox", "audit"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
