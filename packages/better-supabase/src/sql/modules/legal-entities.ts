import type { LegalEntitiesEvents } from "../../blocks/legal-entities/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { lockTable, schemaPreamble } from "../shared.ts";
import { legalEntityFunctions } from "./legal-entities-functions.ts";
import { moduleOperations } from "./permissions-model.ts";

const EVENTS: BlockSqlEvents<LegalEntitiesEvents> = {
  "legal_entity.created": {
    subject: "legal-entities",
    payload: ["organizationId", "legalEntityId", "code", "isDefault"],
  },
  "legal_entity.updated": {
    subject: "legal-entities",
    payload: ["organizationId", "legalEntityId", "code", "isDefault"],
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    legal_entity: {
      table: "entities",
      singular: "legal_entity",
      primary: true,
    },
    legal_entity_setting: {
      table: "settings",
      singular: "legal_entity_setting",
    },
  },
  events: EVENTS,
  hooks: [
    "before_legal_entity_create",
    "after_legal_entity_create",
    "before_legal_entity_update",
    "after_legal_entity_update",
  ],
  options: ["on"],
  tables: {
    entities: {
      name: "legal_entities",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        code: "code",
        name: "name",
        address: "address",
        vatNumber: "vat_number",
        cocNumber: "coc_number",
        iban: "iban",
        bic: "bic",
        logoAttachment: "logo_attachment_id",
        defaultCurrency: "default_currency",
        fiscal: "fiscal",
        isDefault: "is_default",
        archivedAt: "archived_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    settings: {
      name: "legal_entity_settings",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        tenant: "tenant_id",
        entity: "legal_entity_id",
        key: "key",
        value: "value",
        updatedBy: "updated_by",
        updatedAt: "updated_at",
      },
    },
  },
};

/**
 * The modules `options.on` can name, with the logical tables that gain a
 * nullable `legal_entity_id`. Each module is an `integrates` entry.
 */
const ON_TABLES: Readonly<
  Record<
    string,
    { readonly module: string; readonly tables: readonly string[] }
  >
> = {
  invoices: { module: "invoices", tables: ["invoices"] },
  quotes: { module: "quotes", tables: ["quotes"] },
  orders: { module: "orders", tables: ["orders"] },
  numbering: { module: "numbering", tables: ["sequences"] },
  accounting: { module: "accounting", tables: ["journals", "entries"] },
  inventory_locations: { module: "inventory", tables: ["locations"] },
  settings: { module: "settings", tables: ["organization"] },
};

/** The `on` values, in the order the docs list them. */
const ON_KEYS: readonly string[] = Object.keys(ON_TABLES);

/** The name of the column `options.on` adds, on every table it names. */
const LEGAL_ENTITY_COLUMN = "legal_entity_id";

/** `options.on`, checked: known keys whose module is installed and managed. */
function onKeys(ctx: BlockSqlContext): readonly string[] {
  const keys = ctx.list("on", []);

  for (const key of keys) {
    const target = ON_TABLES[key];

    if (target === undefined) {
      throw new TypeError(
        `blocks.legal-entities.options.on: "${key}" is not one of ${ON_KEYS.join(", ")}`,
      );
    }

    if (!ctx.installed(target.module)) {
      throw new TypeError(
        `blocks.legal-entities.options.on: "${key}" needs the ${target.module} block`,
      );
    }

    if (ctx.of(target.module).mode === "custom") {
      throw new TypeError(
        `blocks.legal-entities.options.on: "${key}" needs the ${target.module} tables; ${target.module} can't be in custom mode`,
      );
    }
  }

  return [...new Set(keys)];
}

/**
 * A nullable `legal_entity_id` on each table `options.on` names, tied to the
 * same tenant. A null column means the default entity (`legal_entity_of`).
 */
function onColumns(ctx: BlockSqlContext): string {
  const entities = ctx.table("entities");
  const e = (column: string): string => ctx.col("entities", column);
  const lines: string[] = [];

  for (const key of onKeys(ctx)) {
    const target = ON_TABLES[key];

    if (target === undefined) {
      continue;
    }

    const own = ctx.of(target.module);

    for (const table of target.tables) {
      if (!own.owns(table) && !own.appOwned.includes(table)) {
        continue;
      }

      const tenant = own.col(table, "tenant");
      const name = own.tableName(table).name;
      const constraint = sqlIdent(`bsb_${name}_legal_entity_fk`);
      const index = sqlIdent(`bsb_${name}_legal_entity_idx`);

      lines.push(`alter table ${own.table(table)} add column if not exists ${LEGAL_ENTITY_COLUMN} uuid;
alter table ${own.table(table)} drop constraint if exists ${constraint};
alter table ${own.table(table)} add constraint ${constraint} foreign key (${tenant}, ${LEGAL_ENTITY_COLUMN}) references ${entities} (${e("tenant")}, ${e("id")}) on delete restrict;
create index if not exists ${index} on ${own.table(table)} (${tenant}, ${LEGAL_ENTITY_COLUMN}) where ${LEGAL_ENTITY_COLUMN} is not null;`);
    }
  }

  return lines.join("\n");
}

function tables(ctx: BlockSqlContext): string {
  const entities = ctx.table("entities");
  const settings = ctx.table("settings");
  const e = (column: string): string => ctx.col("entities", column);
  const s = (column: string): string => ctx.col("settings", column);
  const read = ctx.permission("read", moduleOperations("legal-entities").read);

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  const attachments =
    ctx.installed("attachments") && ctx.of("attachments").manages
      ? ctx.of("attachments")
      : undefined;

  const readPolicy = (logical: string, tenant: string): string =>
    renderPolicy(
      makePolicy({
        table: ctx.table(logical),
        name: ctx.owns(logical)
          ? name(logical, "read")
          : sqlIdent(`bsb_${ctx.tableName(logical).name}_read`),
        command: "select",
        roles: ["authenticated"],
        using: ctx.scope.check(tenant, read),
      }),
      { drop: true, target: ctx.table(logical) },
    );

  const text = (column: string, max: number): string =>
    `${e(column)} text check (${e(column)} is null or length(${e(column)}) between 1 and ${String(max)})`;

  return `
-- The legal entities of an organization: the companies that issue documents,
-- keep books and pay tax. Contacts, products and members stay shared.
create table if not exists ${entities} (
  ${e("id")} uuid primary key default gen_random_uuid(),
  ${e("tenant")} ${ctx.idType} not null,
  ${e("code")} text not null check (${e("code")} ~ '^[A-Za-z0-9][A-Za-z0-9_.-]{0,31}$'),
  ${e("name")} text not null check (length(${e("name")}) between 1 and 200),
  ${e("address")} jsonb not null default '{}'::jsonb check (jsonb_typeof(${e("address")}) = 'object'),
  ${text("vatNumber", 50)},
  ${text("cocNumber", 50)},
  ${text("iban", 34)},
  ${text("bic", 11)},
  ${e("logoAttachment")} uuid${attachments === undefined ? "" : ` references ${attachments.table("attachments")} (${attachments.col("attachments", "id")}) on delete set null`},
  ${e("defaultCurrency")} text check (${e("defaultCurrency")} is null or ${e("defaultCurrency")} ~ '^[A-Z]{3}$'),
  -- { "fiscalYearStartMonth": 1 to 12, "taxPeriod": "monthly" or "quarterly" }.
  ${e("fiscal")} jsonb not null default '{"fiscalYearStartMonth": 1, "taxPeriod": "quarterly"}'::jsonb check (jsonb_typeof(${e("fiscal")}) = 'object'),
  ${e("isDefault")} boolean not null default false,
  ${e("archivedAt")} timestamptz,
  ${e("createdAt")} timestamptz not null default now(),
  ${e("updatedAt")} timestamptz not null default now(),
  unique (${e("tenant")}, ${e("code")}),
  unique (${e("tenant")}, ${e("id")}),
  check (not (${e("isDefault")} and ${e("archivedAt")} is not null))
);
-- One default entity per organization.
create unique index if not exists ${name("entities", "default_idx")} on ${entities} (${e("tenant")}) where ${e("isDefault")};
create index if not exists ${name("entities", "logo_idx")} on ${entities} (${e("logoAttachment")}) where ${e("logoAttachment")} is not null;
${lockTable(entities, { read: true })}
${readPolicy("entities", e("tenant"))}

-- Settings that differ per legal entity; resolve_setting falls back to the
-- organization's setting, then to the code default.
create table if not exists ${settings} (
  ${s("tenant")} ${ctx.idType} not null,
  ${s("entity")} uuid not null,
  ${s("key")} text not null check (${s("key")} ~ '^[A-Za-z][A-Za-z0-9_.:-]{0,127}$'),
  ${s("value")} jsonb not null,
  ${s("updatedBy")} uuid references auth.users (id) on delete set null default auth.uid(),
  ${s("updatedAt")} timestamptz not null default now(),
  primary key (${s("entity")}, ${s("key")}),
  foreign key (${s("tenant")}, ${s("entity")}) references ${entities} (${e("tenant")}, ${e("id")}) on delete cascade
);
create index if not exists ${name("settings", "tenant_idx")} on ${settings} (${s("tenant")}, ${s("entity")});
${
  ctx.owns("settings")
    ? ""
    : `create unique index if not exists ${name("settings", "key_idx")} on ${settings} (${s("entity")}, ${s("key")});
`
}create index if not exists ${name("settings", "updated_by_idx")} on ${settings} (${s("updatedBy")}) where ${s("updatedBy")} is not null;
${lockTable(settings, { read: true })}
${readPolicy("settings", s("tenant"))}
${onColumns(ctx)}
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  if (ctx.of("settings").mode === "custom") {
    throw new TypeError(
      "blocks.legal-entities needs the settings tables; settings can't be in custom mode",
    );
  }

  return `${schemaPreamble(ctx)}
-- Legal entities inside one organization (ADR 0142): their details, the
-- default entity, per-entity settings, and the optional legal_entity_id
-- column on the tables blocks.legal-entities.options.on names.
${tables(ctx)}
${legalEntityFunctions(ctx)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "create_legal_entity",
      args: [
        "{id}",
        "text",
        "text",
        "jsonb",
        "text",
        "text",
        "text",
        "text",
        "uuid",
        "text",
        "jsonb",
        "boolean",
      ],
      returns: "jsonb",
    },
    { name: "update_legal_entity", args: ["uuid", "jsonb"], returns: "jsonb" },
    { name: "set_default_legal_entity", args: ["uuid"], returns: "jsonb" },
    {
      name: "set_legal_entity_archived",
      args: ["uuid", "boolean"],
      returns: "jsonb",
    },
    { name: "get_legal_entity", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_legal_entities",
      args: ["{id}", "boolean"],
      returns: "jsonb",
    },
    { name: "legal_entity_of", args: ["{id}", "uuid"], returns: "uuid" },
    { name: "get_legal_entity_settings", args: ["uuid"], returns: "jsonb" },
    {
      name: "set_legal_entity_setting",
      args: ["uuid", "text", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "reset_legal_entity_setting",
      args: ["uuid", "text"],
      returns: "boolean",
    },
    {
      name: "resolve_setting",
      args: ["{id}", "text", "uuid"],
      returns: "jsonb",
    },
  ];
}

export const LEGAL_ENTITIES: BlockSqlDefinition = {
  name: "legal-entities",
  scopes: ["tenant"],
  title: "Legal entities",
  description:
    "Several legal entities inside one organization, each with its VAT and chamber numbers, bank account, logo and fiscal settings and one default per organization. Settings resolve from the legal entity to the organization to the code default, and options.on adds a nullable legal_entity_id to invoices, quotes, orders, numbering, accounting, inventory locations and settings; null means the default entity.",
  requires: ["memberships", "permissions", "settings"],
  integrates: [
    "attachments",
    "invoices",
    "quotes",
    "orders",
    "numbering",
    "accounting",
    "inventory",
    "outbox",
    "audit",
  ],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
