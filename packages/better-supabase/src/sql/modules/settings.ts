import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../registry.ts";

import { sqlString } from "../../core/template.ts";
import {
  type JsonSchemaCheck,
  jsonSchemaChecks,
  schemaPreamble,
  tenantIn,
} from "../shared.ts";
import { MODULE_PERMISSIONS } from "./access-model.ts";

const NAMES: ModuleNames = {
  options: ["schemas", "platform"],
  tables: {
    user: {
      name: "user_settings",
      lifecycle: { user: "user" },
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
      lifecycle: { tenant: "tenant" },
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
      columns: {
        key: "key",
        value: "value",
        updatedBy: "updated_by",
        updatedAt: "updated_at",
      },
    },
  },
};

/** Who reads a platform key: anyone, signed-in users, or staff with its permission. */
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
 * The platform scope's defaults (`options.platform`: `permission` and
 * `read`) and its keys with their own `permission` and `read`, from
 * `options.schemas.platform`.
 */
function platformKeys(ctx: ModuleContext): {
  readonly fallback: {
    readonly permission: string;
    readonly read: PlatformRead;
  };
  readonly keys: readonly PlatformKey[];
} {
  const where = "sql.modules.settings.options";
  const option = ctx.option("platform") ?? {};
  if (!isObject(option)) {
    throw new TypeError(`${where}.platform must be { permission?, read? }`);
  }
  const readOf = (value: unknown, at: string): PlatformRead | undefined => {
    if (value === undefined) return undefined;
    if (!isRead(value)) {
      throw new TypeError(`${at}.read must be ${READS.join(", ")}`);
    }
    return value;
  };
  const permissionOf = (value: unknown, at: string): string | undefined => {
    if (value === undefined) return undefined;
    if (typeof value !== "string" || value.length === 0) {
      throw new TypeError(`${at}.permission must be a permission key`);
    }
    return value;
  };
  const fallback = {
    permission:
      permissionOf(option["permission"], `${where}.platform`) ??
      ctx.permissionKey("platform", MODULE_PERMISSIONS.settings.platform),
    read: readOf(option["read"], `${where}.platform`) ?? "authenticated",
  };
  const raw = ctx.option("schemas");
  const schemas = isObject(raw) && "schemas" in raw ? raw["schemas"] : raw;
  const entries = isObject(schemas) ? schemas["platform"] : undefined;
  if (entries === undefined) return { fallback, keys: [] };
  if (!isObject(entries)) {
    throw new TypeError(
      `${where}.schemas.platform: pass an object of key to schema`,
    );
  }
  const keys = Object.entries(entries).map(([key, entry]): PlatformKey => {
    const at = `${where}.schemas.platform.${key}`;
    const config = isObject(entry) ? entry : {};
    return {
      key,
      permission: permissionOf(config["permission"], at) ?? fallback.permission,
      read: readOf(config["read"], at) ?? fallback.read,
    };
  });
  return { fallback, keys };
}

const readRule = (read: PlatformRead, permission: string): string =>
  read === "staff"
    ? `coalesce(better_supabase.is_platform(${sqlString(permission)}), false)`
    : "true";

const unquote = (ident: string): string =>
  ident.startsWith('"') ? ident.slice(1, -1).replaceAll('""', '"') : ident;

const isObject = (value: unknown): value is Readonly<Record<string, unknown>> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/**
 * The JSON Schema for one settings entry: a JSON Schema object, a Standard
 * Schema that implements Standard JSON Schema, or `{ schema }` holding either.
 * Libraries without Standard JSON Schema get no database check.
 */
function jsonSchemaOf(
  entry: unknown,
): Readonly<Record<string, unknown>> | undefined {
  if (!isObject(entry)) return undefined;
  const standard = entry["~standard"];
  if (standard === undefined) {
    return "schema" in entry ? jsonSchemaOf(entry["schema"]) : entry;
  }
  if (!isObject(standard)) return undefined;
  const jsonSchema = standard["jsonSchema"];
  if (!isObject(jsonSchema)) return undefined;
  const input = jsonSchema["input"];
  if (typeof input !== "function") return undefined;
  // SAFETY: Standard JSON Schema defines input as (options) => a JSON Schema object.
  const toJson = input as (options: { readonly target: string }) => unknown;
  const document = toJson({ target: "draft-2020-12" });
  return isObject(document) ? document : undefined;
}

/**
 * `sql.modules.settings.options.schemas`: `{ user, organization }` maps of
 * key to schema, or a `defineSettings()` result (its `schemas`).
 */
function settingsChecks(ctx: ModuleContext): readonly JsonSchemaCheck[] {
  const option = ctx.option("schemas");
  if (option === undefined) return [];
  const raw =
    isObject(option) && "schemas" in option ? option["schemas"] : option;
  if (!isObject(raw)) {
    throw new TypeError(
      "sql.modules.settings.options.schemas: pass { user, organization, platform } or a defineSettings() result",
    );
  }
  const checks: JsonSchemaCheck[] = [];
  for (const [scope, table] of [
    ["user", "user"],
    ["organization", "organization"],
    ["platform", "platform"],
  ] as const) {
    const entries = raw[scope];
    if (entries === undefined) continue;
    if (!isObject(entries)) {
      throw new TypeError(
        `sql.modules.settings.options.schemas.${scope}: pass an object of key to schema`,
      );
    }
    const target = ctx.tableName(table);
    for (const [key, entry] of Object.entries(entries)) {
      const schema = jsonSchemaOf(entry);
      if (!schema) continue;
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
      "sql.modules.settings.options.schemas: add the jsonb-schemas module, which installs pg_jsonschema for these checks",
    );
  }
  return checks;
}

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const id = ctx.idType;
  const u = ctx.table("user");
  const o = ctx.table("organization");
  const uc = (logical: string): string => ctx.col("user", logical);
  const oc = (logical: string): string => ctx.col("organization", logical);
  const fn = (name: string): string => ctx.fn(name);
  const permissions = MODULE_PERMISSIONS.settings;
  const can = (tenant: string, action: "read" | "update"): string =>
    `coalesce(better_supabase.can('tenant', ${tenant}, ${ctx.permission(action, permissions[action])}), false)`;
  const member = (tenant: string, action: "read" | "update"): string =>
    tenantIn(tenant, ctx.permission(action, permissions[action]));
  const KEY = `check (key ~ '^[A-Za-z][A-Za-z0-9_.:-]{0,127}$')`;
  const p = ctx.table("platform");
  const pc = (logical: string): string => ctx.col("platform", logical);
  const platform = platformKeys(ctx);
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
  const writeCheck = `${listedKeys}coalesce(better_supabase.is_platform(${byKey(
    (entry) => sqlString(entry.permission),
    sqlString(platform.fallback.permission),
  )}), false)`;
  const authenticatedRead = byKey(
    (entry) => readRule(entry.read, entry.permission),
    readRule(platform.fallback.read, platform.fallback.permission),
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
  ${uc("value")} jsonb not null,
  ${uc("updatedBy")} uuid references auth.users (id) on delete set null default auth.uid(),
  ${uc("updatedAt")} timestamptz not null default now(),
  primary key (${uc("user")}, ${uc("key")})
);
create index if not exists user_settings_updated_by_idx on ${u} (${uc("updatedBy")});
alter table ${u} enable row level security;
revoke all on ${u} from anon, authenticated;
grant select, insert, update, delete on ${u} to authenticated;
grant all on ${u} to service_role;
drop policy if exists "user_settings_own" on ${u};
create policy "user_settings_own" on ${u} for all to authenticated
  using (${uc("user")} = (select auth.uid()))
  with check (${uc("user")} = (select auth.uid()));

create table if not exists ${o} (
  ${oc("tenant")} ${id} not null,
  ${oc("key")} text not null ${KEY.replace("key", oc("key"))},
  ${oc("value")} jsonb not null,
  ${oc("updatedBy")} uuid references auth.users (id) on delete set null default auth.uid(),
  ${oc("updatedAt")} timestamptz not null default now(),
  primary key (${oc("tenant")}, ${oc("key")})
);
create index if not exists organization_settings_updated_by_idx on ${o} (${oc("updatedBy")});
alter table ${o} enable row level security;
revoke all on ${o} from anon, authenticated;
grant select, insert, update, delete on ${o} to authenticated;
grant all on ${o} to service_role;
drop policy if exists "organization_settings_read" on ${o};
create policy "organization_settings_read" on ${o} for select to authenticated
  using (${member(oc("tenant"), "read")});
drop policy if exists "organization_settings_insert" on ${o};
create policy "organization_settings_insert" on ${o} for insert to authenticated
  with check (${can(oc("tenant"), "update")});
drop policy if exists "organization_settings_update" on ${o};
create policy "organization_settings_update" on ${o} for update to authenticated
  using (${member(oc("tenant"), "update")})
  with check (${member(oc("tenant"), "update")});
drop policy if exists "organization_settings_delete" on ${o};
create policy "organization_settings_delete" on ${o} for delete to authenticated
  using (${member(oc("tenant"), "update")});

-- Platform settings: one row per key for the whole product, such as fee
-- rates or feature switches an admin console edits. Each key's permission
-- (is_platform) guards writes, and its read rule decides who sees it.
create table if not exists ${p} (
  ${pc("key")} text primary key ${KEY.replace("key", pc("key"))},
  ${pc("value")} jsonb not null,
  ${pc("updatedBy")} uuid references auth.users (id) on delete set null default auth.uid(),
  ${pc("updatedAt")} timestamptz not null default now()
);
create index if not exists platform_settings_updated_by_idx on ${p} (${pc("updatedBy")});
alter table ${p} enable row level security;
revoke all on ${p} from anon, authenticated;
grant select on ${p} to anon;
grant select, insert, update, delete on ${p} to authenticated;
grant all on ${p} to service_role;
drop policy if exists "platform_settings_read" on ${p};
create policy "platform_settings_read" on ${p} for select to authenticated
  using (${authenticatedRead});
drop policy if exists "platform_settings_read_public" on ${p};
create policy "platform_settings_read_public" on ${p} for select to anon
  using (${anonRead});
drop policy if exists "platform_settings_insert" on ${p};
create policy "platform_settings_insert" on ${p} for insert to authenticated
  with check (${writeCheck});
drop policy if exists "platform_settings_update" on ${p};
create policy "platform_settings_update" on ${p} for update to authenticated
  using (${writeCheck})
  with check (${writeCheck});
drop policy if exists "platform_settings_delete" on ${p};
create policy "platform_settings_delete" on ${p} for delete to authenticated
  using (${writeCheck});

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
  insert into ${u} (${uc("user")}, ${uc("key")}, ${uc("value")}, ${uc("updatedBy")}, ${uc("updatedAt")})
  values (auth.uid(), set_user_setting.key, coalesce(set_user_setting.value -> 'value', 'null'::jsonb), auth.uid(), now())
  on conflict (${uc("user")}, ${uc("key")}) do update
    set ${uc("value")} = excluded.${uc("value")}, ${uc("updatedBy")} = auth.uid(), ${uc("updatedAt")} = now()
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
  insert into ${o} (${oc("tenant")}, ${oc("key")}, ${oc("value")}, ${oc("updatedBy")}, ${oc("updatedAt")})
  values (set_organization_setting.tenant, set_organization_setting.key, coalesce(set_organization_setting.value -> 'value', 'null'::jsonb), auth.uid(), now())
  on conflict (${oc("tenant")}, ${oc("key")}) do update
    set ${oc("value")} = excluded.${oc("value")}, ${oc("updatedBy")} = auth.uid(), ${oc("updatedAt")} = now()
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
  insert into ${p} (${pc("key")}, ${pc("value")}, ${pc("updatedBy")}, ${pc("updatedAt")})
  values (set_platform_setting.key, coalesce(set_platform_setting.value -> 'value', 'null'::jsonb), auth.uid(), now())
  on conflict (${pc("key")}) do update
    set ${pc("value")} = excluded.${pc("value")}, ${pc("updatedBy")} = auth.uid(), ${pc("updatedAt")} = now()
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
${jsonSchemaChecks(settingsChecks(ctx))}`;
}

function contract(): readonly ModuleContractFunction[] {
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

export const SETTINGS: ModuleDefinition = {
  name: "settings",
  title: "Settings",
  description:
    "Per-user, per-organization and platform-wide settings as key-value jsonb rows. Users read and write their own; organization settings check settings.read and settings.update; platform settings check a platform permission per key. Keys with a JSON Schema in options.schemas get a pg_jsonschema check.",
  requires: ["tenant", "access"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
