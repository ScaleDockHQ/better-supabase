import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../registry.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  columnRef,
  SERVICE_CALLER,
  schemaPreamble,
  tenantIn,
} from "../shared.ts";
import { MODULE_PERMISSIONS } from "./access-model.ts";
import { anonymizeSql } from "./data-lifecycle-anonymize.ts";

const NAMES: ModuleNames = {
  options: [
    "bucket",
    "grace",
    "exportTtl",
    "tables",
    "autoTables",
    "tenantRow",
    "anonymize",
  ],
  hooks: ["on_organization_purge"],
  tables: {
    exports: {
      name: "data_exports",
      columns: {
        id: "id",
        subject: "subject",
        user: "user_id",
        tenant: "organization_id",
        status: "status",
        bucket: "bucket",
        files: "files",
        error: "error",
        requestedBy: "requested_by",
        requestedAt: "requested_at",
        completedAt: "completed_at",
        expiresAt: "expires_at",
      },
    },
    deletions: {
      name: "organization_deletions",
      columns: {
        tenant: "organization_id",
        requestedBy: "requested_by",
        requestedAt: "requested_at",
        purgeAfter: "purge_after",
        cancelledAt: "cancelled_at",
        purgedAt: "purged_at",
        previouslyDisabled: "previously_disabled",
      },
    },
  },
};

/** An app table in `options.tables`: its user and tenant columns. */
export interface LifecycleTable {
  /** The column holding the user id, for user exports. */
  readonly user?: string;
  /** The tenant column, for organization exports and the purge. */
  readonly tenant?: string;
  /** Delete its tenant rows in the purge. Default true. */
  readonly purge?: boolean;
}

/** One table an export reads or the purge clears. */
interface Entry {
  readonly subject: "user" | "organization";
  /** `schema.table`, unquoted, for file names. */
  readonly name: string;
  /** Quoted, for `to_regclass`. */
  readonly table: string;
  /** Unquoted, for `%I`. */
  readonly column: string;
  readonly purge: boolean;
}

/** A Storage bucket id: Supabase allows 1 to 100 characters. */
const BUCKET = /^[a-z0-9][a-z0-9_.-]{0,99}$/;
const IDENT = /^[a-z_][a-z0-9_$]{0,62}$/;

function unquoted(ctx: ModuleContext, logical: string): string {
  const { schema, name } = ctx.tableName(logical);
  return `${schema}.${name}`;
}

/** The tables each installed module contributes, then `options.tables`. */
function entries(ctx: ModuleContext): readonly Entry[] {
  const list: Entry[] = [];
  const modules = ctx.installedModules.map((module) => ctx.of(module));
  for (const subject of ["user", "organization"] as const) {
    for (const of of modules) {
      for (const [logical, spec] of Object.entries(of.names.tables)) {
        const column =
          subject === "user" ? spec.lifecycle?.user : spec.lifecycle?.tenant;
        if (column === undefined) continue;
        if (!of.hasTable(logical) || !of.has(logical, column)) continue;
        list.push({
          subject,
          name: unquoted(of, logical),
          table: of.table(logical),
          column: of.col(logical, column).replaceAll('"', ""),
          purge: spec.lifecycle?.purge !== false,
        });
      }
    }
  }

  const where = "sql.modules.data-lifecycle.options.tables";
  const option = ctx.option("tables");
  if (option === undefined || option === "auto") return list;
  if (typeof option !== "object" || option === null || Array.isArray(option)) {
    throw new TypeError(
      `${where} must be an object of table names to { user, tenant, purge }`,
    );
  }
  for (const [key, value] of Object.entries(option)) {
    const parts = key.split(".");
    if (parts.length > 2 || !parts.every((part) => IDENT.test(part))) {
      throw new TypeError(
        `${where}: "${key}" must be "table" or "schema.table"`,
      );
    }
    const [schema = "public", table = key] =
      parts.length === 2 ? parts : ["public", key];
    if (typeof value !== "object" || value === null || Array.isArray(value)) {
      throw new TypeError(`${where}.${key} must be an object`);
    }
    // SAFETY: an object, and each field is checked below.
    const config = value as LifecycleTable;
    for (const column of [config.user, config.tenant]) {
      if (
        column !== undefined &&
        (typeof column !== "string" || !IDENT.test(column))
      ) {
        throw new TypeError(
          `${where}.${key}: column names must be lowercase identifiers`,
        );
      }
    }
    if (config.user === undefined && config.tenant === undefined) {
      throw new TypeError(`${where}.${key} needs a user or a tenant column`);
    }
    const base = {
      name: `${schema}.${table}`,
      table: `${sqlIdent(schema)}.${sqlIdent(table)}`,
      purge: config.purge !== false,
    };
    if (config.user !== undefined) {
      list.push({ ...base, subject: "user", column: config.user });
    }
    if (config.tenant !== undefined) {
      list.push({ ...base, subject: "organization", column: config.tenant });
    }
  }
  return list;
}

/** `options.autoTables`: every table in `schemas` with the tenant (or user) column. */
interface AutoTables {
  readonly schemas: readonly string[];
  readonly tenant: string | undefined;
  readonly user: string | undefined;
  /** `schema.table` names or globs (`public.*_archive`) to leave out. */
  readonly exclude: readonly string[];
  readonly purge: boolean;
}

function autoTablesOf(ctx: ModuleContext): AutoTables | undefined {
  const where = "sql.modules.data-lifecycle.options.autoTables";
  const option =
    ctx.option("tables") === "auto" ? {} : ctx.option("autoTables");
  if (option === undefined) return undefined;
  if (typeof option !== "object" || option === null || Array.isArray(option)) {
    throw new TypeError(
      `${where} must be an object of { schemas?, tenant?, user?, exclude?, purge? }`,
    );
  }
  // SAFETY: an object, and each field is checked below.
  const config = option as Record<string, unknown>;
  const list = (
    key: string,
    fallback: readonly string[],
  ): readonly string[] => {
    const value = config[key];
    if (value === undefined) return fallback;
    if (
      !Array.isArray(value) ||
      !value.every((item) => typeof item === "string")
    )
      throw new TypeError(`${where}.${key} must be a list of strings`);
    return value;
  };
  const column = (key: string, fallback?: string): string | undefined => {
    const value = config[key];
    if (value === undefined) return fallback;
    if (value === null) return undefined;
    if (typeof value !== "string" || !IDENT.test(value))
      throw new TypeError(`${where}.${key} must be a lowercase column name`);
    return value;
  };
  const schemas = list("schemas", ["public"]);
  for (const schema of schemas) {
    if (!IDENT.test(schema))
      throw new TypeError(`${where}.schemas: "${schema}" is not a schema name`);
  }
  return {
    schemas,
    tenant: column("tenant", "organization_id"),
    user: column("user"),
    exclude: list("exclude", []),
    purge: config["purge"] !== false,
  };
}

/** The catalog query that lists `auto` tables, minus the explicit ones. */
function autoTablesSql(auto: AutoTables, explicit: readonly Entry[]): string {
  const names = [...new Set(explicit.map((entry) => entry.name))].map(
    sqlString,
  );
  const excluded = auto.exclude.map(
    (pattern) =>
      `n.nspname || '.' || c.relname like ${sqlString(pattern.replaceAll("_", "\\_").replaceAll("*", "%"))}`,
  );
  const select = (subject: string, column: string): string => `
  select ${sqlString(subject)}::text, n.nspname || '.' || c.relname, format('%I.%I', n.nspname, c.relname), a.attname::text, ${String(auto.purge)}
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  join pg_catalog.pg_attribute a on a.attrelid = c.oid and a.attname = ${sqlString(column)} and not a.attisdropped
  where c.relkind in ('r', 'p')
    and n.nspname in (${auto.schemas.map(sqlString).join(", ")})
    and not c.relispartition${
      names.length > 0
        ? `
    and n.nspname || '.' || c.relname not in (${names.join(", ")})`
        : ""
    }${excluded
      .map(
        (rule) => `
    and not (${rule})`,
      )
      .join("")}`;
  return [
    ...(auto.tenant ? [select("organization", auto.tenant)] : []),
    ...(auto.user ? [select("user", auto.user)] : []),
  ].join("\n  union all");
}

function bucketOf(ctx: ModuleContext): string {
  const bucket = ctx.text("bucket", "data-exports");
  if (!BUCKET.test(bucket)) {
    throw new TypeError(
      "sql.modules.data-lifecycle.options.bucket must be 1 to 100 lowercase letters, digits, dots, dashes or underscores",
    );
  }
  return bucket;
}

/**
 * The tenant's own row the purge deletes last: `options.tenantRow`
 * (`schema.table.column`, `false` for none), else the organizations module's
 * table, else the table the access contract disables tenants in.
 */
function tenantRowOf(
  ctx: ModuleContext,
): { readonly table: string; readonly key: string } | undefined {
  const configured = ctx.option("tenantRow");
  if (configured === false) return undefined;
  if (configured !== undefined) {
    if (typeof configured !== "string") {
      throw new TypeError(
        'sql.modules.data-lifecycle.options.tenantRow must be "schema.table.column" or false',
      );
    }
    const ref = columnRef(
      "sql.modules.data-lifecycle.options.tenantRow",
      configured,
    );
    return { table: ref.table, key: ref.column };
  }
  if (ctx.installed("organizations")) {
    const organizations = ctx.of("organizations");
    return {
      table: organizations.table("organizations"),
      key: organizations.col("organizations", "id"),
    };
  }
  const disable = disabling(ctx);
  return disable ? { table: disable.table, key: disable.key } : undefined;
}

/** The statement that disables a tenant, from the access contract. */
function disabling(
  ctx: ModuleContext,
): { table: string; key: string; column: string } | undefined {
  const configured = ctx.modules.access?.disabled?.tenant;
  if (typeof configured === "string") {
    const ref = columnRef("sql.modules.access.disabled.tenant", configured);
    return { table: ref.table, key: '"id"', column: ref.column };
  }
  if (configured) {
    if (configured.disabledAt === undefined) return undefined;
    return {
      table: configured.table
        .split(".")
        .map((part) => sqlIdent(part))
        .join("."),
      key: sqlIdent(configured.id),
      column: sqlIdent(configured.disabledAt),
    };
  }
  if (!ctx.installed("organizations")) return undefined;
  const organizations = ctx.of("organizations");
  if (
    !organizations.manages ||
    !organizations.has("organizations", "disabledAt")
  ) {
    return undefined;
  }
  return {
    table: organizations.table("organizations"),
    key: organizations.col("organizations", "id"),
    column: organizations.col("organizations", "disabledAt"),
  };
}

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const id = ctx.idType;
  const e = ctx.table("exports");
  const d = ctx.table("deletions");
  const ce = (logical: string): string => ctx.col("exports", logical);
  const cd = (logical: string): string => ctx.col("deletions", logical);
  const fn = (name: string): string => ctx.fn(name);
  const permissions = MODULE_PERMISSIONS["data-lifecycle"];
  const can = (tenant: string, action: keyof typeof permissions): string =>
    `coalesce(better_supabase.can('tenant', ${tenant}, ${ctx.permission(action, permissions[action])}), false)`;
  const bucket = sqlString(bucketOf(ctx));
  const grace = ctx.text("grace", "30 days");
  const exportTtl = ctx.text("exportTtl", "7 days");
  const tenant = ctx.of("tenant");
  const m = tenant.table("memberships");
  const mTenant = tenant.col("memberships", "tenant");
  const mUser = tenant.col("memberships", "user");
  const ownerRole = sqlString(
    ctx.installed("organizations")
      ? ctx.of("organizations").text("ownerRole", "owner")
      : "owner",
  );
  const disable = disabling(ctx);
  const list = entries(ctx);
  const values = list
    .map(
      (entry) =>
        `(${sqlString(entry.subject)}, ${sqlString(entry.name)}, ${sqlString(entry.table)}, ${sqlString(entry.column)}, ${String(entry.purge)})`,
    )
    .join(",\n    ");
  const auto = autoTablesOf(ctx);
  const explicitBody =
    list.length === 0
      ? "select null::text, null::text, null::text, null::text, null::boolean where false"
      : `select * from (values\n    ${values}\n  ) as t(subject, name, tbl, col, purge)`;
  const autoBody = auto ? autoTablesSql(auto, list) : "";
  const tablesBody = autoBody
    ? `${explicitBody}\n  union all${autoBody}`
    : explicitBody;

  const exportEvent = (type: string, extra = ""): string =>
    ctx.emit({
      type,
      payload: `jsonb_build_object('exportId', v_row.${ce("id")}, 'subject', v_row.${ce("subject")}, 'organizationId', v_row.${ce("tenant")}::text, 'userId', v_row.${ce("user")}, 'requestedBy', v_row.${ce("requestedBy")}${extra})`,
      subject: `'data-exports/' || v_row.${ce("id")}::text`,
      tenant: `v_row.${ce("tenant")}`,
    }) || "null;";
  // The tenant is gone once the purge ends, so the event carries no tenant
  // partition; organizationId stays in the payload.
  const purgedEvent =
    ctx.emit({
      type: "organization.purged",
      payload: `jsonb_build_object('organizationId', v_row.${cd("tenant")}::text, 'userId', null::uuid, 'purgeAfter', v_row.${cd("purgeAfter")})`,
      subject: `'organizations/' || v_row.${cd("tenant")}::text`,
      tenant: "null",
    }) || "null;";
  const deletionEvent = (type: string, actor: string): string =>
    ctx.emit({
      type,
      payload: `jsonb_build_object('organizationId', v_row.${cd("tenant")}::text, 'userId', ${actor}, 'purgeAfter', v_row.${cd("purgeAfter")})`,
      subject: `'organizations/' || v_row.${cd("tenant")}::text`,
      tenant: `v_row.${cd("tenant")}`,
    }) || "null;";

  const disableSql = disable
    ? `select ${disable.column} is not null into v_disabled from ${disable.table} where ${disable.key} = request_organization_deletion.tenant;
  update ${disable.table} set ${disable.column} = coalesce(${disable.column}, now()) where ${disable.key} = request_organization_deletion.tenant;`
    : "v_disabled := false;";
  const enableSql = disable
    ? `if not v_row.${cd("previouslyDisabled")} then
    update ${disable.table} set ${disable.column} = null where ${disable.key} = cancel_organization_deletion.tenant;
  end if;`
    : "";
  const tenantRow = tenantRowOf(ctx);
  // The tenant row goes last, after every table that references it.
  const organizationRow = tenantRow
    ? `begin
    delete from ${tenantRow.table} where ${tenantRow.key} = purge_organization.tenant;
  exception when foreign_key_violation or restrict_violation then
    raise exception 'Rows still reference the organization: %', sqlerrm
      using errcode = '23503', hint = 'ORGANIZATION_PURGE_BLOCKED';
  end;`
    : "";
  const skipTables = [
    `to_regclass(t.tbl) <> to_regclass(${sqlString(d)})`,
    ...(tenantRow
      ? [
          `to_regclass(t.tbl) is distinct from to_regclass(${sqlString(tenantRow.table)})`,
        ]
      : []),
  ].join(" and ");
  const platformKey = ctx.permissionKey("deletePlatform", "");
  const platform =
    platformKey === ""
      ? ""
      : `\n    and not coalesce(better_supabase.is_platform(${sqlString(platformKey)}), false)`;
  // The tenant module resolves the role name, also when memberships point at
  // a roles table (sql.modules.tenant.columns.role through a role id).
  const owner = `coalesce(better_supabase.organization_member_role(cancel_organization_deletion.tenant, auth.uid()) = ${ownerRole}, false)`;

  return `${schemaPreamble(ctx)}
-- Exports of a user's or an organization's data, written by the app's
-- export job as one NDJSON file per table under {id}/ in the ${bucketOf(ctx)} bucket.
create table if not exists ${e} (
  ${ce("id")} uuid primary key default gen_random_uuid(),
  ${ce("subject")} text not null check (${ce("subject")} in ('user', 'organization')),
  ${ce("user")} uuid references auth.users (id) on delete cascade,
  ${ce("tenant")} ${id},
  ${ce("status")} text not null default 'pending' check (${ce("status")} in ('pending', 'running', 'ready', 'failed')),
  ${ce("bucket")} text not null default ${bucket},
  ${ce("files")} text[] not null default '{}',
  ${ce("error")} text,
  ${ce("requestedBy")} uuid references auth.users (id) on delete set null default auth.uid(),
  ${ce("requestedAt")} timestamptz not null default now(),
  ${ce("completedAt")} timestamptz,
  ${ce("expiresAt")} timestamptz,
  check ((${ce("subject")} = 'user') = (${ce("user")} is not null)),
  check ((${ce("subject")} = 'organization') = (${ce("tenant")} is not null))
);
create unique index if not exists data_exports_open_user_idx on ${e} (${ce("user")}) where ${ce("status")} in ('pending', 'running') and ${ce("subject")} = 'user';
create unique index if not exists data_exports_open_tenant_idx on ${e} (${ce("tenant")}) where ${ce("status")} in ('pending', 'running') and ${ce("subject")} = 'organization';
create index if not exists data_exports_requested_by_idx on ${e} (${ce("requestedBy")});
alter table ${e} enable row level security;
revoke all on ${e} from anon, authenticated;
grant select on ${e} to authenticated;
grant all on ${e} to service_role;
drop policy if exists "data_exports_read" on ${e};
create policy "data_exports_read" on ${e} for select to authenticated
  using (${ce("requestedBy")} = (select auth.uid()) or ${tenantIn(ce("tenant"), ctx.permission("export", permissions.export))});

-- Organizations waiting for their purge. Requesting disables the tenant
-- through the access contract; cancelling enables it again unless it was
-- disabled before.
create table if not exists ${d} (
  ${cd("tenant")} ${id} primary key,
  ${cd("requestedBy")} uuid references auth.users (id) on delete set null default auth.uid(),
  ${cd("requestedAt")} timestamptz not null default now(),
  ${cd("purgeAfter")} timestamptz not null,
  ${cd("cancelledAt")} timestamptz,
  ${cd("purgedAt")} timestamptz,
  ${cd("previouslyDisabled")} boolean not null default false
);
create index if not exists organization_deletions_due_idx on ${d} (${cd("purgeAfter")}) where ${cd("cancelledAt")} is null and ${cd("purgedAt")} is null;
alter table ${d} enable row level security;
revoke all on ${d} from anon, authenticated;
grant all on ${d} to service_role;

-- What an export reads and the purge clears: subject, display name,
-- quoted table, column and whether the purge deletes it.
drop function if exists ${fn("data_lifecycle_tables")}();
create or replace function ${fn("data_lifecycle_tables")}()
returns table (subject text, name text, tbl text, col text, purge boolean)
language sql
${auto ? "stable" : "immutable"}
set search_path = ''
as $$
  ${tablesBody}
$$;

create or replace function ${fn("data_export_object_allowed")}(path text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  -- Files sit under <export id>/, so the primary key finds the one export.
  select exists (
    select 1 from ${e} x
    where x.${ce("id")} = case when split_part(path, '/', 1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then split_part(path, '/', 1)::uuid end
      and x.${ce("bucket")} = ${bucket}
      and x.${ce("status")} = 'ready'
      and (x.${ce("expiresAt")} is null or x.${ce("expiresAt")} > now())
      and path = any (x.${ce("files")})
      and (x.${ce("requestedBy")} = auth.uid() or (x.${ce("tenant")} is not null and ${can(`x.${ce("tenant")}`, "export")}))
  )
$$;
revoke execute on function ${fn("data_export_object_allowed")}(text) from public, anon;
grant execute on function ${fn("data_export_object_allowed")}(text) to authenticated, service_role;

drop policy if exists ${sqlIdent("bs_data_exports_select")} on storage.objects;
create policy ${sqlIdent("bs_data_exports_select")} on storage.objects for select to authenticated
  using (bucket_id = ${bucket} and ${fn("data_export_object_allowed")}(name));

-- The caller's own data (subject 'user') or a tenant's (needs the export
-- permission). An open export for the same subject is returned instead
-- of a second one.
create or replace function ${fn("request_data_export")}(subject text default 'user', tenant ${id} default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${e};
begin
  if auth.uid() is null then
    raise exception 'Sign in to export data' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
  end if;
  if request_data_export.subject = 'organization' then
    if request_data_export.tenant is null or not ${can("request_data_export.tenant", "export")} then
      raise exception 'You may not export this organization''s data' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
    end if;
    select * into v_row from ${e} x where x.${ce("tenant")} = request_data_export.tenant and x.${ce("subject")} = 'organization' and x.${ce("status")} in ('pending', 'running');
    if v_row.${ce("id")} is null then
      insert into ${e} (${ce("subject")}, ${ce("tenant")}) values ('organization', request_data_export.tenant) returning * into v_row;
      ${exportEvent("data_export.requested")}
    end if;
  elsif request_data_export.subject = 'user' then
    select * into v_row from ${e} x where x.${ce("user")} = auth.uid() and x.${ce("subject")} = 'user' and x.${ce("status")} in ('pending', 'running');
    if v_row.${ce("id")} is null then
      insert into ${e} (${ce("subject")}, ${ce("user")}) values ('user', auth.uid()) returning * into v_row;
      ${exportEvent("data_export.requested")}
    end if;
  else
    raise exception 'subject must be user or organization' using errcode = '22023', hint = 'DATA_EXPORT_SUBJECT';
  end if;
  return to_jsonb(v_row);
end;
$$;

create or replace function ${fn("list_data_exports")}(tenant ${id} default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x.*) order by x.${ce("requestedAt")} desc, x.${ce("id")}), '[]'::jsonb)
  from ${e} x
  where case when list_data_exports.tenant is null
    then x.${ce("subject")} = 'user' and x.${ce("user")} = auth.uid()
    else x.${ce("tenant")} = list_data_exports.tenant
  end
$$;

create or replace function ${fn("get_data_export")}(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x.*) from ${e} x where x.${ce("id")} = get_data_export.id
$$;

-- Starts a pending (or failed) export and returns it with the tables to
-- read (service role).
create or replace function ${fn("claim_data_export")}(id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row ${e};
begin
  if not (${SERVICE_CALLER}) then
    raise exception 'Only the service role runs exports' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
  end if;
  update ${e} x set ${ce("status")} = 'running', ${ce("error")} = null
  where x.${ce("id")} = claim_data_export.id and x.${ce("status")} in ('pending', 'failed')
  returning * into v_row;
  if v_row.${ce("id")} is null then
    return null;
  end if;
  return to_jsonb(v_row) || jsonb_build_object('tables', (
    select coalesce(jsonb_agg(t.name order by t.name), '[]'::jsonb)
    from ${fn("data_lifecycle_tables")}() t
    where t.subject = v_row.${ce("subject")} and to_regclass(t.tbl) is not null
  ));
end;
$$;

-- A page of the subject's rows in one table, after the ctid \`after\`
-- (service role): { rows, after }, with after null on the last page.
create or replace function ${fn("data_export_rows")}(id uuid, table_name text, after text default null, page_size integer default 1000)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row ${e};
  v_table record;
  v_type text;
  v_rows jsonb;
  v_after text;
begin
  if not (${SERVICE_CALLER}) then
    raise exception 'Only the service role runs exports' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
  end if;
  select * into v_row from ${e} x where x.${ce("id")} = data_export_rows.id and x.${ce("status")} = 'running';
  if v_row.${ce("id")} is null then
    raise exception 'No running export has this id' using errcode = 'P0002', hint = 'DATA_EXPORT_NOT_FOUND';
  end if;
  select * into v_table from ${fn("data_lifecycle_tables")}() t
  where t.subject = v_row.${ce("subject")} and t.name = data_export_rows.table_name;
  if v_table.tbl is null or to_regclass(v_table.tbl) is null then
    raise exception 'The export has no table %', data_export_rows.table_name using errcode = '22023', hint = 'DATA_EXPORT_TABLE';
  end if;
  select pg_catalog.format_type(a.atttypid, a.atttypmod) into v_type
  from pg_catalog.pg_attribute a
  where a.attrelid = to_regclass(v_table.tbl) and a.attname = v_table.col and not a.attisdropped;
  execute format(
    'select coalesce(jsonb_agg(to_jsonb(p.*) - ''_ctid'' order by p._ctid), ''[]''::jsonb), max(p._ctid)::text, count(*)
     from (select t.ctid as _ctid, t.* from %s t where t.%I = $1::%s and ($2::tid is null or t.ctid > $2::tid) order by t.ctid limit $3) p',
    v_table.tbl, v_table.col, v_type
  ) into v_rows, v_after
  using case when v_row.${ce("subject")} = 'user' then v_row.${ce("user")}::text else v_row.${ce("tenant")}::text end,
    data_export_rows.after, greatest(1, least(data_export_rows.page_size, 10000));
  return jsonb_build_object(
    'rows', v_rows,
    'after', case when jsonb_array_length(v_rows) < greatest(1, least(data_export_rows.page_size, 10000)) then null else v_after end
  );
end;
$$;

create or replace function ${fn("complete_data_export")}(id uuid, files text[])
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row ${e};
begin
  if not (${SERVICE_CALLER}) then
    raise exception 'Only the service role runs exports' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
  end if;
  update ${e} x set ${ce("status")} = 'ready', ${ce("files")} = complete_data_export.files,
    ${ce("completedAt")} = now(), ${ce("expiresAt")} = now() + ${sqlString(exportTtl)}::interval
  where x.${ce("id")} = complete_data_export.id and x.${ce("status")} = 'running'
  returning * into v_row;
  if v_row.${ce("id")} is null then
    raise exception 'No running export has this id' using errcode = 'P0002', hint = 'DATA_EXPORT_NOT_FOUND';
  end if;
  ${exportEvent("data_export.ready", `, 'files', to_jsonb(v_row.${ce("files")}), 'expiresAt', v_row.${ce("expiresAt")}`)}
  return to_jsonb(v_row);
end;
$$;

create or replace function ${fn("fail_data_export")}(id uuid, error text)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row ${e};
begin
  if not (${SERVICE_CALLER}) then
    raise exception 'Only the service role runs exports' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
  end if;
  update ${e} x set ${ce("status")} = 'failed', ${ce("error")} = fail_data_export.error, ${ce("completedAt")} = now()
  where x.${ce("id")} = fail_data_export.id and x.${ce("status")} = 'running'
  returning * into v_row;
  if v_row.${ce("id")} is null then
    return null;
  end if;
  ${exportEvent("data_export.failed", ", 'error', v_row." + ce("error"))}
  return to_jsonb(v_row);
end;
$$;

-- Schedules the purge after the grace period and disables the tenant.
-- Needs the delete permission; requesting again moves the purge date.
create or replace function ${fn("request_organization_deletion")}(tenant ${id}, grace interval default ${sqlString(grace)}::interval)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${d};
  v_disabled boolean;
begin
  if not (${SERVICE_CALLER}) and not ${can("request_organization_deletion.tenant", "delete")}${platform} then
    raise exception 'You may not delete this organization' using errcode = '42501', hint = 'ORGANIZATION_DELETION_FORBIDDEN';
  end if;
  if request_organization_deletion.grace < interval '0' then
    raise exception 'grace must not be negative' using errcode = '22023', hint = 'ORGANIZATION_DELETION_GRACE';
  end if;
  if exists (select 1 from ${d} x where x.${cd("tenant")} = request_organization_deletion.tenant and x.${cd("purgedAt")} is not null) then
    raise exception 'The organization was already purged' using errcode = 'P0002', hint = 'ORGANIZATION_PURGED';
  end if;
  ${disableSql}
  insert into ${d} as x (${cd("tenant")}, ${cd("requestedBy")}, ${cd("purgeAfter")}, ${cd("previouslyDisabled")})
  values (request_organization_deletion.tenant, auth.uid(), now() + request_organization_deletion.grace, coalesce(v_disabled, false))
  on conflict (${cd("tenant")}) do update set
    ${cd("requestedBy")} = excluded.${cd("requestedBy")},
    ${cd("requestedAt")} = now(),
    ${cd("purgeAfter")} = excluded.${cd("purgeAfter")},
    ${cd("previouslyDisabled")} = case when x.${cd("cancelledAt")} is null then x.${cd("previouslyDisabled")} else excluded.${cd("previouslyDisabled")} end,
    ${cd("cancelledAt")} = null
  returning * into v_row;
  ${deletionEvent("organization.deletion_requested", "auth.uid()")}
  return to_jsonb(v_row);
end;
$$;

-- The requester, an owner or the service role cancels a pending purge.
-- The tenant is disabled meanwhile, so this checks the membership row
-- instead of permissions.
create or replace function ${fn("cancel_organization_deletion")}(tenant ${id})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${d};
begin
  select * into v_row from ${d} x
  where x.${cd("tenant")} = cancel_organization_deletion.tenant and x.${cd("cancelledAt")} is null and x.${cd("purgedAt")} is null
  for update;
  if v_row.${cd("tenant")} is null then
    return null;
  end if;
  if not (${SERVICE_CALLER} or v_row.${cd("requestedBy")} = auth.uid() or ${owner})${platform} then
    raise exception 'You may not cancel this deletion' using errcode = '42501', hint = 'ORGANIZATION_DELETION_FORBIDDEN';
  end if;
  update ${d} x set ${cd("cancelledAt")} = now()
  where x.${cd("tenant")} = v_row.${cd("tenant")}
  returning * into v_row;
  ${enableSql}
  ${deletionEvent("organization.deletion_cancelled", "auth.uid()")}
  return to_jsonb(v_row);
end;
$$;

-- The pending deletion, for the organization's members.
create or replace function ${fn("organization_deletion")}(tenant ${id})
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select to_jsonb(x.*) from ${d} x
  where x.${cd("tenant")} = organization_deletion.tenant
    and x.${cd("cancelledAt")} is null
    and (${SERVICE_CALLER} or exists (select 1 from ${m} mm where mm.${mTenant} = organization_deletion.tenant and mm.${mUser} = auth.uid()))
$$;

create or replace function ${fn("due_organization_deletions")}(max_rows integer default 100)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x.*) order by x.${cd("purgeAfter")}), '[]'::jsonb)
  from (
    select * from ${d} y
    where y.${cd("purgeAfter")} <= now() and y.${cd("cancelledAt")} is null and y.${cd("purgedAt")} is null
    order by y.${cd("purgeAfter")}
    limit greatest(1, least(due_organization_deletions.max_rows, 1000))
  ) x
$$;

-- Deletes a due organization's rows (service role): the app's
-- on_organization_purge(tenant) hook first, then each purged table, then
-- the organization. Returns { organizationId, deleted: { table: rows } }.
create or replace function ${fn("purge_organization")}(tenant ${id})
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row ${d};
  v_table record;
  v_type text;
  v_count bigint;
  v_deleted jsonb := '{}'::jsonb;
  v_pending text[];
  v_left text[];
  v_name text;
  v_pass integer;
begin
  if not (${SERVICE_CALLER}) then
    raise exception 'Only the service role purges organizations' using errcode = '42501', hint = 'ORGANIZATION_DELETION_FORBIDDEN';
  end if;
  select * into v_row from ${d} x
  where x.${cd("tenant")} = purge_organization.tenant and x.${cd("cancelledAt")} is null and x.${cd("purgedAt")} is null
  for update;
  if v_row.${cd("tenant")} is null or v_row.${cd("purgeAfter")} > now() then
    raise exception 'No due deletion for this organization' using errcode = 'P0002', hint = 'ORGANIZATION_DELETION_NOT_DUE';
  end if;
  ${ctx.hook("on_organization_purge", [[id, "purge_organization.tenant"]])}
  -- Tables go in reverse order; a table whose rows another table still
  -- references (a restricting foreign key) waits for a later pass.
  v_pending := array(
    select t.name from ${fn("data_lifecycle_tables")}() t
    where t.subject = 'organization' and t.purge and to_regclass(t.tbl) is not null
      and ${skipTables}
    order by (row_number() over ()) desc
  );
  for v_pass in 1..10 loop
    exit when cardinality(v_pending) = 0;
    v_left := '{}';
    foreach v_name in array v_pending loop
      select * into v_table from ${fn("data_lifecycle_tables")}() t
      where t.subject = 'organization' and t.name = v_name;
      select pg_catalog.format_type(a.atttypid, a.atttypmod) into v_type
      from pg_catalog.pg_attribute a
      where a.attrelid = to_regclass(v_table.tbl) and a.attname = v_table.col and not a.attisdropped;
      begin
        execute format('delete from %s t where t.%I = $1::%s', v_table.tbl, v_table.col, v_type)
          using purge_organization.tenant::text;
        get diagnostics v_count = row_count;
        v_deleted := v_deleted || jsonb_build_object(v_name, coalesce((v_deleted ->> v_name)::bigint, 0) + v_count);
      exception when foreign_key_violation or restrict_violation or check_violation then
        -- Another table's rows still point here (or a set null action breaks
        -- a check on them): try again after the other tables.
        v_left := v_left || v_name;
      end;
    end loop;
    if v_left = v_pending then
      raise exception 'Rows in % still have references the purge does not delete', array_to_string(v_left, ', ')
        using errcode = '23503', hint = 'ORGANIZATION_PURGE_BLOCKED';
    end if;
    v_pending := v_left;
  end loop;
  update ${d} x set ${cd("purgedAt")} = now() where x.${cd("tenant")} = v_row.${cd("tenant")} returning * into v_row;
  ${organizationRow}
  ${purgedEvent}
  return jsonb_build_object('organizationId', v_row.${cd("tenant")}::text, 'deleted', v_deleted);
end;
$$;

-- Exports past expires_at, oldest first, with their files, for the purger to
-- remove from Storage before forget_data_exports drops the rows.
create or replace function ${fn("expired_data_exports")}(max_rows integer default 100)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x.${ce("id")}, 'bucket', x.${ce("bucket")}, 'files', to_jsonb(x.${ce("files")})) order by x.${ce("expiresAt")}), '[]'::jsonb)
  from (
    select * from ${e} y
    where y.${ce("expiresAt")} < now()
    order by y.${ce("expiresAt")}
    limit greatest(1, least(coalesce(max_rows, 100), 1000))
  ) x
$$;

-- Deletes the export rows (their files are already gone); returns how many.
create or replace function ${fn("forget_data_exports")}(ids uuid[])
returns integer
language sql
security definer
set search_path = ''
as $$
  with removed as (
    delete from ${e} x where x.${ce("id")} = any (forget_data_exports.ids) and x.${ce("expiresAt")} < now() returning 1
  )
  select count(*)::integer from removed
$$;

revoke execute on function ${fn("expired_data_exports")}(integer) from public, anon, authenticated;
revoke execute on function ${fn("forget_data_exports")}(uuid[]) from public, anon, authenticated;
grant execute on function ${fn("expired_data_exports")}(integer) to service_role;
${anonymizeSql(ctx)}
grant execute on function ${fn("forget_data_exports")}(uuid[]) to service_role;
revoke execute on function ${fn("data_lifecycle_tables")}() from public, anon, authenticated;
revoke execute on function ${fn("request_data_export")}(text, ${id}) from public, anon;
revoke execute on function ${fn("list_data_exports")}(${id}) from public, anon;
revoke execute on function ${fn("get_data_export")}(uuid) from public, anon;
revoke execute on function ${fn("claim_data_export")}(uuid) from public, anon, authenticated;
revoke execute on function ${fn("data_export_rows")}(uuid, text, text, integer) from public, anon, authenticated;
revoke execute on function ${fn("complete_data_export")}(uuid, text[]) from public, anon, authenticated;
revoke execute on function ${fn("fail_data_export")}(uuid, text) from public, anon, authenticated;
revoke execute on function ${fn("request_organization_deletion")}(${id}, interval) from public, anon;
revoke execute on function ${fn("cancel_organization_deletion")}(${id}) from public, anon;
revoke execute on function ${fn("organization_deletion")}(${id}) from public, anon;
revoke execute on function ${fn("due_organization_deletions")}(integer) from public, anon, authenticated;
revoke execute on function ${fn("purge_organization")}(${id}) from public, anon, authenticated;
grant execute on function ${fn("data_lifecycle_tables")}() to service_role;
grant execute on function ${fn("request_data_export")}(text, ${id}) to authenticated, service_role;
grant execute on function ${fn("list_data_exports")}(${id}) to authenticated, service_role;
grant execute on function ${fn("get_data_export")}(uuid) to authenticated, service_role;
grant execute on function ${fn("claim_data_export")}(uuid) to service_role;
grant execute on function ${fn("data_export_rows")}(uuid, text, text, integer) to service_role;
grant execute on function ${fn("complete_data_export")}(uuid, text[]) to service_role;
grant execute on function ${fn("fail_data_export")}(uuid, text) to service_role;
grant execute on function ${fn("request_organization_deletion")}(${id}, interval) to authenticated, service_role;
grant execute on function ${fn("cancel_organization_deletion")}(${id}) to authenticated, service_role;
grant execute on function ${fn("organization_deletion")}(${id}) to authenticated, service_role;
grant execute on function ${fn("due_organization_deletions")}(integer) to service_role;
grant execute on function ${fn("purge_organization")}(${id}) to service_role;`;
}

function data(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const bucket = sqlString(bucketOf(ctx));
  return `insert into storage.buckets (id, name, public)
values (${bucket}, ${bucket}, false)
on conflict (id) do nothing;`;
}

function contract(): readonly ModuleContractFunction[] {
  return [
    { name: "data_lifecycle_tables", args: [], returns: "record" },
    { name: "data_export_object_allowed", args: ["text"], returns: "boolean" },
    { name: "request_data_export", args: ["text", "{id}"], returns: "jsonb" },
    { name: "list_data_exports", args: ["{id}"], returns: "jsonb" },
    { name: "get_data_export", args: ["uuid"], returns: "jsonb" },
    { name: "claim_data_export", args: ["uuid"], returns: "jsonb" },
    {
      name: "data_export_rows",
      args: ["uuid", "text", "text", "integer"],
      returns: "jsonb",
    },
    {
      name: "complete_data_export",
      args: ["uuid", "text[]"],
      returns: "jsonb",
    },
    { name: "fail_data_export", args: ["uuid", "text"], returns: "jsonb" },
    {
      name: "request_organization_deletion",
      args: ["{id}", "interval"],
      returns: "jsonb",
    },
    { name: "cancel_organization_deletion", args: ["{id}"], returns: "jsonb" },
    { name: "expired_data_exports", args: ["integer"], returns: "jsonb" },
    { name: "forget_data_exports", args: ["uuid[]"], returns: "integer" },
    { name: "organization_deletion", args: ["{id}"], returns: "jsonb" },
    { name: "due_organization_deletions", args: ["integer"], returns: "jsonb" },
    { name: "purge_organization", args: ["{id}"], returns: "jsonb" },
    { name: "anonymize_due", args: ["integer"], returns: "jsonb" },
  ];
}

export const DATA_LIFECYCLE: ModuleDefinition = {
  internal: ["data_export_object_allowed"],
  name: "data-lifecycle",
  title: "Data lifecycle",
  description:
    "Data exports per user or organization from every installed module's tables and the app's, written to a private bucket by the app's export job, and organization deletion with a grace period that disables the tenant before a purge job deletes its rows.",
  requires: ["tenant", "access"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 2,
  names: NAMES,
  contract,
  upgrades: [
    {
      from: 1,
      description:
        "The storage policy for export files finds the export by the id in the file path.",
      sql: () => "",
    },
  ],
  build,
  data,
};
