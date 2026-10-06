import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../registry.ts";

import {
  type JsonSchemaCheck,
  jsonSchemaChecks,
  schemaPreamble,
} from "../shared.ts";
import { MODULE_PERMISSIONS } from "./access-model.ts";

const NAMES: ModuleNames = {
  options: ["schemas"],
  tables: {
    user: {
      name: "user_settings",
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
      columns: {
        tenant: "organization_id",
        key: "key",
        value: "value",
        updatedBy: "updated_by",
        updatedAt: "updated_at",
      },
    },
  },
};

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
      "sql.modules.settings.options.schemas: pass { user, organization } or a defineSettings() result",
    );
  }
  const checks: JsonSchemaCheck[] = [];
  for (const [scope, table] of [
    ["user", "user"],
    ["organization", "organization"],
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
  const KEY = `check (key ~ '^[A-Za-z][A-Za-z0-9_.:-]{0,127}$')`;

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
  using (${can(oc("tenant"), "read")});
drop policy if exists "organization_settings_insert" on ${o};
create policy "organization_settings_insert" on ${o} for insert to authenticated
  with check (${can(oc("tenant"), "update")});
drop policy if exists "organization_settings_update" on ${o};
create policy "organization_settings_update" on ${o} for update to authenticated
  using (${can(oc("tenant"), "update")})
  with check (${can(oc("tenant"), "update")});
drop policy if exists "organization_settings_delete" on ${o};
create policy "organization_settings_delete" on ${o} for delete to authenticated
  using (${can(oc("tenant"), "update")});

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
  insert into ${u} (${uc("user")}, ${uc("key")}, ${uc("value")})
  values (auth.uid(), set_user_setting.key, coalesce(set_user_setting.value -> 'value', 'null'::jsonb))
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
  insert into ${o} (${oc("tenant")}, ${oc("key")}, ${oc("value")})
  values (set_organization_setting.tenant, set_organization_setting.key, coalesce(set_organization_setting.value -> 'value', 'null'::jsonb))
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
  ];
}

export const SETTINGS: ModuleDefinition = {
  name: "settings",
  title: "Settings",
  description:
    "Per-user and per-organization settings as key-value jsonb rows. Users read and write their own; organization settings check settings.read and settings.update. Keys with a JSON Schema in options.schemas get a pg_jsonschema check.",
  requires: ["tenant", "access"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
