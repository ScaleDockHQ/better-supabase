import type { SettingsEvents } from "../../blocks/settings/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";
import type { BlockSqlScope } from "../scope.ts";
import type { JsonSchemaCheck } from "../shared.ts";

import { isRecord } from "../../core/guards.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  recordTrigger,
  jsonSchemaChecks,
  ownRowPolicies,
  schemaPreamble,
  revokeTable,
} from "../shared.ts";
import { OPERATIONS, moduleOperations } from "./permissions-model.ts";

const EVENTS: BlockSqlEvents<SettingsEvents> = {
  "organization_setting.reset": {
    subject: "organizations",
    payload: ["organizationId", "key"],
  },
  "organization_setting.updated": {
    subject: "organizations",
    payload: ["organizationId", "key"],
  },
  "platform_setting.reset": { subject: "settings", payload: ["key"] },
  "platform_setting.updated": { subject: "settings", payload: ["key"] },
};

/** Who changed a setting and when: columns an app's settings table may lack. */
const STAMPS = ["updatedBy", "updatedAt"];

const NAMES: BlockSqlNames = {
  events: EVENTS,
  options: ["schemas", "platform"],
  tables: {
    user: {
      name: "user_settings",
      app: {},
      lifecycle: { user: "user" },
      optional: STAMPS,
      columns: {
        user: "user_id",
        key: "key",
        value: "value",
        updatedBy: "updated_by",
        updatedAt: "updated_at",
      },
    },
    organization: {
      name: "organization_settings",
      app: {},
      lifecycle: { tenant: "tenant" },
      optional: STAMPS,
      columns: {
        tenant: "organization_id",
        key: "key",
        value: "value",
        updatedBy: "updated_by",
        updatedAt: "updated_at",
      },
    },
    platform: {
      name: "platform_settings",
      app: {},
      optional: STAMPS,
      columns: {
        key: "key",
        value: "value",
        updatedBy: "updated_by",
        updatedAt: "updated_at",
      },
    },
  },
};

/**
 * Who reads a platform key: anyone, signed-in users, or staff with its
 * permission.
 */
type PlatformRead = "public" | "authenticated" | "staff";

interface PlatformKey {
  readonly key: string;
  readonly permission: string;
  readonly read: PlatformRead;
}

const READS: readonly PlatformRead[] = ["public", "authenticated", "staff"];

const isRead = (value: unknown): value is PlatformRead =>
  value === "public" || value === "authenticated" || value === "staff";

/**
 * The platform scope's defaults (`options.platform`: `permission` and `read`)
 * and its keys with their own `permission` and `read`, from
 * `options.schemas.platform`.
 */
function platformKeys(ctx: BlockSqlContext): {
  readonly fallback: {
    readonly permission: string;
    readonly read: PlatformRead;
  };
  readonly keys: readonly PlatformKey[];
} {
  const where = "blocks.settings.options";
  const option = ctx.option("platform") ?? {};

  if (!isRecord(option)) {
    throw new TypeError(`${where}.platform must be { permission?, read? }`);
  }

  const readOf = (value: unknown, at: string): PlatformRead | undefined => {
    if (value === undefined) {
      return undefined;
    }

    if (!isRead(value)) {
      throw new TypeError(`${at}.read must be ${READS.join(", ")}`);
    }

    return value;
  };

  const permissionOf = (value: unknown, at: string): string | undefined => {
    if (value === undefined) {
      return undefined;
    }

    if (typeof value !== "string" || value.length === 0) {
      throw new TypeError(`${at}.permission must be a permission key`);
    }

    return value;
  };

  const fallback = {
    permission:
      permissionOf(option["permission"], `${where}.platform`) ??
      ctx.permissionKey("platform", OPERATIONS["settings.platform"]),
    read: readOf(option["read"], `${where}.platform`) ?? "authenticated",
  };

  const raw = ctx.option("schemas");
  const schemas = isRecord(raw) && "schemas" in raw ? raw["schemas"] : raw;
  const entries = isRecord(schemas) ? schemas["platform"] : undefined;

  if (entries === undefined) {
    return { fallback, keys: [] };
  }

  if (!isRecord(entries)) {
    throw new TypeError(
      `${where}.schemas.platform: pass an object of key to schema`,
    );
  }

  const keys = Object.entries(entries).map(([key, entry]): PlatformKey => {
    const at = `${where}.schemas.platform.${key}`;
    const config = isRecord(entry) ? entry : {};

    return {
      key,
      permission: permissionOf(config["permission"], at) ?? fallback.permission,
      read: readOf(config["read"], at) ?? fallback.read,
    };
  });

  return { fallback, keys };
}

const readRule = (
  scope: BlockSqlScope,
  read: PlatformRead,
  permission: string,
): string =>
  read === "staff" ? scope.platform(sqlString(permission)) : "true";

const unquote = (ident: string): string =>
  ident.startsWith('"') ? ident.slice(1, -1).replaceAll('""', '"') : ident;

/**
 * The JSON Schema for one settings entry: a JSON Schema object, a Standard
 * Schema that implements Standard JSON Schema, or `{ schema }` holding either.
 * Libraries without Standard JSON Schema get no database check.
 */
function jsonSchemaOf(
  entry: unknown,
): Readonly<Record<string, unknown>> | undefined {
  if (!isRecord(entry)) {
    return undefined;
  }

  const standard = entry["~standard"];

  if (standard === undefined) {
    return "schema" in entry ? jsonSchemaOf(entry["schema"]) : entry;
  }

  if (!isRecord(standard)) {
    return undefined;
  }

  const jsonSchema = standard["jsonSchema"];

  if (!isRecord(jsonSchema)) {
    return undefined;
  }

  const input = jsonSchema["input"];

  if (typeof input !== "function") {
    return undefined;
  }

  // SAFETY: Standard JSON Schema defines input as (options) => a JSON Schema object.
  const toJson = input as (options: { readonly target: string }) => unknown;
  const document = toJson({ target: "draft-2020-12" });

  return isRecord(document) ? document : undefined;
}

/**
 * `blocks.settings.options.schemas`: `{ user, organization }` maps of key to
 * schema, or a `defineSettings()` result (its `schemas`).
 */
function settingsChecks(ctx: BlockSqlContext): readonly JsonSchemaCheck[] {
  const option = ctx.option("schemas");

  if (option === undefined) {
    return [];
  }

  const raw =
    isRecord(option) && "schemas" in option ? option["schemas"] : option;

  if (!isRecord(raw)) {
    throw new TypeError(
      "blocks.settings.options.schemas: pass { user, organization, platform } or a defineSettings() result",
    );
  }

  const checks: JsonSchemaCheck[] = [];

  for (const [scope, table] of [
    ["user", "user"],
    ["organization", "organization"],
    ["platform", "platform"],
  ] as const) {
    const entries = raw[scope];

    if (entries === undefined) {
      continue;
    }

    if (!isRecord(entries)) {
      throw new TypeError(
        `blocks.settings.options.schemas.${scope}: pass an object of key to schema`,
      );
    }

    const target = ctx.tableName(table);

    for (const [key, entry] of Object.entries(entries)) {
      const schema = jsonSchemaOf(entry);

      if (!schema) {
        continue;
      }

      checks.push({
        table: `${target.schema}.${target.name}`,
        column: unquote(ctx.col(table, "value")),
        schema,
        where: { column: unquote(ctx.col(table, "key")), value: key },
      });
    }
  }

  if (checks.length > 0 && !ctx.installed("jsonb-schemas")) {
    throw new TypeError(
      "blocks.settings.options.schemas: add the jsonb-schemas module, which installs pg_jsonschema for these checks",
    );
  }

  return checks;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const id = ctx.idType;
  const u = ctx.table("user");
  const o = ctx.table("organization");
  const uc = (logical: string): string => ctx.col("user", logical);
  const oc = (logical: string): string => ctx.col("organization", logical);
  const fn = (name: string): string => ctx.fn(name);
  const permissions = moduleOperations("settings");

  const can = (tenant: string, action: "read" | "update"): string =>
    ctx.can("tenant", tenant, ctx.permission(action, permissions[action]));

  const member = (tenant: string, action: "read" | "update"): string =>
    ctx.scope.check(tenant, ctx.permission(action, permissions[action]));

  const KEY = `check (key ~ '^[A-Za-z][A-Za-z0-9_.:-]{0,127}$')`;
  const p = ctx.table("platform");
  const pc = (logical: string): string => ctx.col("platform", logical);
  const platform = platformKeys(ctx);

  const stampLines = (table: string): string =>
    (
      [
        [
          "updatedBy",
          "uuid references auth.users (id) on delete set null default auth.uid()",
        ],
        ["updatedAt", "timestamptz not null default now()"],
      ] as const
    )
      .filter(([logical]) => ctx.has(table, logical))
      .map(([logical, type]) => `,\n  ${ctx.col(table, logical)} ${type}`)
      .join("");

  const stamps = (table: string): readonly (readonly [string, string])[] =>
    (
      [
        ["updatedBy", "auth.uid()"],
        ["updatedAt", "now()"],
      ] as const
    )
      .filter(([logical]) => ctx.has(table, logical))
      .map(([logical, value]) => [ctx.col(table, logical), value] as const);

  const stampColumns = (table: string): string =>
    stamps(table)
      .map(([column]) => `, ${column}`)
      .join("");

  const stampValues = (table: string): string =>
    stamps(table)
      .map(([, value]) => `, ${value}`)
      .join("");

  const stampSets = (table: string): string =>
    stamps(table)
      .map(([column, value]) => `, ${column} = ${value}`)
      .join("");

  const updatedByIndex = (table: string, name: string): string =>
    ctx.has(table, "updatedBy")
      ? `\ncreate index if not exists ${name} on ${ctx.table(table)} (${ctx.col(table, "updatedBy")});`
      : "";

  const uniqueOverApp = (table: string, columns: readonly string[]): string =>
    ctx.owns(table)
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName(table).name}_key`)} on ${ctx.table(table)} (${columns.map((logical) => ctx.col(table, logical)).join(", ")});`;

  const settingEvent = (
    type: string,
    col: (logical: string) => string,
  ): string => {
    const tenant = col === oc ? `v_row.${oc("tenant")}` : undefined;

    return ctx.record({
      type,
      payload: `jsonb_build_object(${tenant ? `'organizationId', ${tenant}::text, ` : ""}'key', v_row.${col("key")})`,
      subject: tenant
        ? `'organizations/' || ${tenant}::text || '/settings/' || v_row.${col("key")}`
        : `'settings/' || v_row.${col("key")}`,
      ...(tenant ? { tenant } : {}),
      audit: {
        category: "configuration",
        targetType: "setting",
        recordId: `v_row.${col("key")}`,
      },
    });
  };

  const byKey = (
    pick: (entry: PlatformKey) => string,
    fallback: string,
  ): string =>
    platform.keys.length === 0
      ? fallback
      : `case ${pc("key")} ${platform.keys
          .map((entry) => `when ${sqlString(entry.key)} then ${pick(entry)}`)
          .join(" ")} else ${fallback} end`;

  // With schemas.platform, only the keys it lists can be written.
  const listedKeys =
    platform.keys.length === 0
      ? ""
      : `${pc("key")} in (${platform.keys.map((entry) => sqlString(entry.key)).join(", ")}) and `;

  const writeCheck = `${listedKeys}${ctx.scope.platform(
    byKey(
      (entry) => sqlString(entry.permission),
      sqlString(platform.fallback.permission),
    ),
  )}`;

  const authenticatedRead = byKey(
    (entry) => readRule(ctx.scope, entry.read, entry.permission),
    readRule(ctx.scope, platform.fallback.read, platform.fallback.permission),
  );

  const publicKeys = platform.keys
    .filter((entry) => entry.read === "public")
    .map((entry) => sqlString(entry.key));

  const anonRead =
    platform.fallback.read === "public"
      ? publicKeys.length === platform.keys.length
        ? "true"
        : `${pc("key")} not in (${platform.keys
            .filter((entry) => entry.read !== "public")
            .map((entry) => sqlString(entry.key))
            .join(", ")})`
      : publicKeys.length === 0
        ? "false"
        : `${pc("key")} in (${publicKeys.join(", ")})`;

  return `${schemaPreamble(ctx)}
-- Settings as key-value rows. The app validates values with defineSettings();
-- keys with a JSON Schema also get a pg_jsonschema check below.
create table if not exists ${u} (
  ${uc("user")} uuid not null references auth.users (id) on delete cascade,
  ${uc("key")} text not null ${KEY.replace("key", uc("key"))},
  ${uc("value")} jsonb not null${stampLines("user")},
  primary key (${uc("user")}, ${uc("key")})
);${updatedByIndex("user", "user_settings_updated_by_idx")}${uniqueOverApp("user", ["user", "key"])}
alter table ${u} enable row level security;
${revokeTable(u)}
grant select, insert, update, delete on ${u} to authenticated;
grant all on ${u} to service_role;
${ownRowPolicies({
  table: u,
  legacy: "user_settings_own",
  name: (command) => `user_settings_own_${command}`,
  using: `${uc("user")} = (select auth.uid())`,
  check: `${uc("user")} = (select auth.uid())`,
})}

create table if not exists ${o} (
  ${oc("tenant")} ${id} not null,
  ${oc("key")} text not null ${KEY.replace("key", oc("key"))},
  ${oc("value")} jsonb not null${stampLines("organization")},
  primary key (${oc("tenant")}, ${oc("key")})
);${updatedByIndex("organization", ctx.naming.rename("organization_settings_updated_by_idx"))}${uniqueOverApp("organization", ["tenant", "key"])}
alter table ${o} enable row level security;
${revokeTable(o)}
grant select, insert, update, delete on ${o} to authenticated;
grant all on ${o} to service_role;
${renderPolicy(makePolicy({ name: ctx.naming.rename("organization_settings_read"), table: o, command: "select", roles: ["authenticated"], using: member(oc("tenant"), "read") }), { drop: true, target: o })}
${renderPolicy(makePolicy({ name: ctx.naming.rename("organization_settings_insert"), table: o, command: "insert", roles: ["authenticated"], check: can(oc("tenant"), "update") }), { drop: true, target: o })}
${renderPolicy(makePolicy({ name: ctx.naming.rename("organization_settings_update"), table: o, command: "update", roles: ["authenticated"], using: member(oc("tenant"), "update"), check: member(oc("tenant"), "update") }), { drop: true, target: o })}
${renderPolicy(makePolicy({ name: ctx.naming.rename("organization_settings_delete"), table: o, command: "delete", roles: ["authenticated"], using: member(oc("tenant"), "update") }), { drop: true, target: o })}

-- Platform settings: one row per key for the whole product, such as fee
-- rates or feature switches an admin console edits. Each key's permission
-- (is_platform) guards writes, and its read rule decides who sees it.
create table if not exists ${p} (
  ${pc("key")} text primary key ${KEY.replace("key", pc("key"))},
  ${pc("value")} jsonb not null${stampLines("platform")}
);${updatedByIndex("platform", "platform_settings_updated_by_idx")}${uniqueOverApp("platform", ["key"])}
alter table ${p} enable row level security;
${revokeTable(p)}
grant select on ${p} to anon;
grant select, insert, update, delete on ${p} to authenticated;
grant all on ${p} to service_role;
${renderPolicy(makePolicy({ table: p, name: "platform_settings_read", command: "select", roles: ["authenticated"], using: authenticatedRead }), { drop: true, target: p })}
${renderPolicy(makePolicy({ table: p, name: "platform_settings_read_public", command: "select", roles: ["anon"], using: anonRead }), { drop: true, target: p })}
${renderPolicy(makePolicy({ table: p, name: "platform_settings_insert", command: "insert", roles: ["authenticated"], check: writeCheck }), { drop: true, target: p })}
${renderPolicy(makePolicy({ table: p, name: "platform_settings_update", command: "update", roles: ["authenticated"], using: writeCheck, check: writeCheck }), { drop: true, target: p })}
${renderPolicy(makePolicy({ table: p, name: "platform_settings_delete", command: "delete", roles: ["authenticated"], using: writeCheck }), { drop: true, target: p })}

-- The functions run as the caller, so the policies above decide. set_*
-- takes the value inside an envelope, { "value": ... }, so strings and
-- numbers reach jsonb the same way over Postgres and the Data API.
create or replace function ${fn("get_user_settings")}()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(s.${uc("key")}, s.${uc("value")}), '{}'::jsonb)
  from ${u} s
  where s.${uc("user")} = auth.uid()
$$;

create or replace function ${fn("set_user_setting")}(key text, value jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  insert into ${u} (${uc("user")}, ${uc("key")}, ${uc("value")}${stampColumns("user")})
  values (auth.uid(), set_user_setting.key, coalesce(set_user_setting.value -> 'value', 'null'::jsonb)${stampValues("user")})
  on conflict (${uc("user")}, ${uc("key")}) do update
    set ${uc("value")} = excluded.${uc("value")}${stampSets("user")}
  returning ${uc("value")}
$$;

create or replace function ${fn("reset_user_setting")}(key text)
returns boolean
language sql
security invoker
set search_path = ''
as $$
  with removed as (
    delete from ${u} s where s.${uc("user")} = auth.uid() and s.${uc("key")} = reset_user_setting.key
    returning 1
  )
  select exists (select 1 from removed)
$$;

create or replace function ${fn("get_organization_settings")}(tenant ${id})
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(s.${oc("key")}, s.${oc("value")}), '{}'::jsonb)
  from ${o} s
  where s.${oc("tenant")} = get_organization_settings.tenant
$$;

create or replace function ${fn("set_organization_setting")}(tenant ${id}, key text, value jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  insert into ${o} (${oc("tenant")}, ${oc("key")}, ${oc("value")}${stampColumns("organization")})
  values (set_organization_setting.tenant, set_organization_setting.key, coalesce(set_organization_setting.value -> 'value', 'null'::jsonb)${stampValues("organization")})
  on conflict (${oc("tenant")}, ${oc("key")}) do update
    set ${oc("value")} = excluded.${oc("value")}${stampSets("organization")}
  returning ${oc("value")}
$$;

create or replace function ${fn("reset_organization_setting")}(tenant ${id}, key text)
returns boolean
language sql
security invoker
set search_path = ''
as $$
  with removed as (
    delete from ${o} s
    where s.${oc("tenant")} = reset_organization_setting.tenant and s.${oc("key")} = reset_organization_setting.key
    returning 1
  )
  select exists (select 1 from removed)
$$;

create or replace function ${fn("get_platform_settings")}()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(s.${pc("key")}, s.${pc("value")}), '{}'::jsonb)
  from ${p} s
$$;

create or replace function ${fn("set_platform_setting")}(key text, value jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  insert into ${p} (${pc("key")}, ${pc("value")}${stampColumns("platform")})
  values (set_platform_setting.key, coalesce(set_platform_setting.value -> 'value', 'null'::jsonb)${stampValues("platform")})
  on conflict (${pc("key")}) do update
    set ${pc("value")} = excluded.${pc("value")}${stampSets("platform")}
  returning ${pc("value")}
$$;

create or replace function ${fn("reset_platform_setting")}(key text)
returns boolean
language sql
security invoker
set search_path = ''
as $$
  with removed as (
    delete from ${p} s where s.${pc("key")} = reset_platform_setting.key
    returning 1
  )
  select exists (select 1 from removed)
$$;

revoke execute on function ${fn("get_platform_settings")}() from public;
revoke execute on function ${fn("set_platform_setting")}(text, jsonb) from public, anon;
revoke execute on function ${fn("reset_platform_setting")}(text) from public, anon;
grant execute on function ${fn("get_platform_settings")}() to anon, authenticated, service_role;
grant execute on function ${fn("set_platform_setting")}(text, jsonb) to authenticated, service_role;
grant execute on function ${fn("reset_platform_setting")}(text) to authenticated, service_role;
revoke execute on function ${fn("get_user_settings")}() from public, anon;
revoke execute on function ${fn("set_user_setting")}(text, jsonb) from public, anon;
revoke execute on function ${fn("reset_user_setting")}(text) from public, anon;
revoke execute on function ${fn("get_organization_settings")}(${id}) from public, anon;
revoke execute on function ${fn("set_organization_setting")}(${id}, text, jsonb) from public, anon;
revoke execute on function ${fn("reset_organization_setting")}(${id}, text) from public, anon;
grant execute on function ${fn("get_user_settings")}() to authenticated, service_role;
grant execute on function ${fn("set_user_setting")}(text, jsonb) to authenticated, service_role;
grant execute on function ${fn("reset_user_setting")}(text) to authenticated, service_role;
grant execute on function ${fn("get_organization_settings")}(${id}) to authenticated, service_role;
grant execute on function ${fn("set_organization_setting")}(${id}, text, jsonb) to authenticated, service_role;
grant execute on function ${fn("reset_organization_setting")}(${id}, text) to authenticated, service_role;

-- Records organization and platform setting changes; user settings are not
-- recorded.
${recordTrigger(ctx, {
  name: "record_organization_setting",
  table: o,
  written: settingEvent("organization_setting.updated", oc),
  removed: settingEvent("organization_setting.reset", oc),
})}
${recordTrigger(ctx, {
  name: "record_platform_setting",
  table: p,
  written: settingEvent("platform_setting.updated", pc),
  removed: settingEvent("platform_setting.reset", pc),
})}
${jsonSchemaChecks(settingsChecks(ctx))}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    { name: "get_user_settings", args: [], returns: "jsonb" },
    { name: "set_user_setting", args: ["text", "jsonb"], returns: "jsonb" },
    { name: "reset_user_setting", args: ["text"], returns: "boolean" },
    { name: "get_organization_settings", args: ["{id}"], returns: "jsonb" },
    {
      name: "set_organization_setting",
      args: ["{id}", "text", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "reset_organization_setting",
      args: ["{id}", "text"],
      returns: "boolean",
    },
    { name: "get_platform_settings", args: [], returns: "jsonb" },
    { name: "set_platform_setting", args: ["text", "jsonb"], returns: "jsonb" },
    { name: "reset_platform_setting", args: ["text"], returns: "boolean" },
  ];
}

export const SETTINGS: BlockSqlDefinition = {
  name: "settings",
  scopes: ["tenant"],
  title: "Settings",
  description:
    "Per-user, per-organization and platform-wide settings as key-value jsonb rows. Users read and write their own; organization settings check settings.read and settings.update; platform settings check a platform permission per key. Keys with a JSON Schema in options.schemas get a pg_jsonschema check.",
  requires: ["memberships", "permissions"],
  integrates: ["jsonb-schemas"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
