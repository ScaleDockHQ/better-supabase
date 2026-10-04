import type { KitContext, KitIdType, KitNames } from "../context.ts";
import type { KitLayout, KitModuleDefinition } from "../kit.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { EQUIVALENT_TRIGGERS, SCHEMA, SERVICE_CALLER } from "../shared.ts";

const NAMES: KitNames = {
  tables: {
    log: {
      name: "audit_log",
      columns: {
        id: "id",
        table: "table_name",
        record: "record_id",
        op: "op",
        old: "old_record",
        new: "new_record",
        changed: "changed",
        actor: "actor_id",
        actorRole: "actor_role",
        tenant: "org_id",
        at: "at",
        impersonatedBy: "impersonated_by",
        impersonationReason: "impersonation_reason",
        supportSession: "support_session_id",
        eventType: "event_type",
        category: "category",
        outcome: "outcome",
        source: "source",
        targetType: "target_type",
        metadata: "metadata",
        idempotencyKey: "idempotency_key",
      },
      optional: [
        "table",
        "record",
        "op",
        "old",
        "new",
        "changed",
        "actorRole",
        "impersonatedBy",
        "impersonationReason",
        "supportSession",
        "eventType",
        "category",
        "outcome",
        "source",
        "targetType",
        "metadata",
        "idempotencyKey",
      ],
    },
    restricted: {
      name: "audit_log_restricted",
      columns: {
        entry: "entry_id",
        old: "old_record",
        new: "new_record",
        ip: "ip_address",
        userAgent: "user_agent",
        metadata: "metadata",
      },
      optional: ["old", "new", "ip", "userAgent", "metadata"],
      optionalTable: true,
    },
  },
  hooks: ["audit_retention"],
};

export type AuditImpersonators = "show" | "hide";

/** `kits.audit.options.impersonators`: whether tenant readers see who impersonated. */
function impersonators(ctx: KitContext): AuditImpersonators {
  const value = ctx.text("impersonators", "show");
  if (value !== "show" && value !== "hide") {
    throw new TypeError(
      `kits.audit.options.impersonators must be "show" or "hide", not "${value}"`,
    );
  }
  return value;
}

/** A text expression as the id type, or null when it doesn't parse as one. */
function castId(value: string, idType: KitIdType): string {
  switch (idType) {
    case "uuid":
      return `case when ${value} ~ '^[0-9a-f-]{36}$' then (${value})::uuid end`;
    case "bigint":
      return `case when ${value} ~ '^-?[0-9]{1,18}$' then (${value})::bigint end`;
    case "integer":
      return `case when ${value} ~ '^-?[0-9]{1,9}$' then (${value})::integer end`;
    case "text":
      return value;
    default: {
      const unknown: never = idType;
      return unknown;
    }
  }
}

/** The restricted table is in use: an option when managed, a mapping when adopted. */
function restrictedOn(ctx: KitContext): boolean {
  return ctx.manages
    ? ctx.flag("restricted", false)
    : ctx.config.tables["restricted"] !== undefined &&
        ctx.hasTable("restricted");
}

/** `[column, value]` pairs for the logical columns the log has. */
function present(
  ctx: KitContext,
  table: string,
  pairs: readonly (readonly [string, string])[],
): { columns: string; values: string } {
  const kept = pairs.filter(([logical]) => ctx.has(table, logical));
  return {
    columns: kept.map(([logical]) => ctx.col(table, logical)).join(", "),
    values: kept.map(([, value]) => value).join(",\n    "),
  };
}

function managedTables(ctx: KitContext, restricted: boolean): string {
  const log = ctx.table("log");
  const c = (logical: string) => ctx.col("log", logical);
  const line = (logical: string, definition: string) =>
    ctx.has("log", logical) ? `\n  ${c(logical)} ${definition},` : "";
  const add = (logical: string, definition: string) =>
    ctx.has("log", logical)
      ? `\nalter table ${log} add column if not exists ${c(logical)} ${definition};`
      : "";
  const op = ctx.has("log", "op")
    ? `
alter table ${log} drop constraint if exists audit_log_op_check;
alter table ${log} drop constraint if exists bs_audit_op_check;
alter table ${log} add constraint bs_audit_op_check check (${c("op")} in ('insert', 'update', 'delete', 'event'));`
    : "";
  const table = ctx.has("log", "table")
    ? `\nalter table ${log} alter column ${c("table")} drop not null;`
    : "";
  const restrictedTable = restricted
    ? `
create table if not exists ${ctx.table("restricted")} (
  ${ctx.col("restricted", "entry")} bigint primary key references ${log} (${c("id")}) on delete cascade,
  ${ctx.col("restricted", "old")} jsonb,
  ${ctx.col("restricted", "new")} jsonb,
  ${ctx.col("restricted", "ip")} inet,
  ${ctx.col("restricted", "userAgent")} text,
  ${ctx.col("restricted", "metadata")} jsonb not null default '{}',
  created_at timestamptz not null default now()
);
alter table ${ctx.table("restricted")} enable row level security;
revoke all on ${ctx.table("restricted")} from anon, authenticated;`
    : "";
  return `create table if not exists ${log} (
  ${c("id")} bigint generated always as identity primary key,${line("table", "text")}${line("record", "text")}${line("op", "text not null")}${line("old", "jsonb")}${line("new", "jsonb")}${line("changed", "text[]")}${line("actor", "uuid")}${line("actorRole", "text")}
  ${c("tenant")} ${ctx.idType},
  ${c("at")} timestamptz not null default now()
);${op}${table}
-- Set when an admin acted as the user (the act claim).${add("impersonatedBy", "uuid")}${add("impersonationReason", "text")}${add("supportSession", "uuid")}
-- Semantic events (audit_event) and the per-table registry fill these.${add("eventType", "text")}${add("category", "text")}${add("outcome", "text")}${add("source", "text")}${add("targetType", "text")}${add("metadata", "jsonb")}${add("idempotencyKey", "text")}
${
  ctx.has("log", "table") && ctx.has("log", "record")
    ? `create index if not exists audit_log_record_idx on ${log} (${c("table")}, ${c("record")}, ${c("at")} desc);\n`
    : ""
}create index if not exists audit_log_org_idx on ${log} (${c("tenant")}, ${c("at")} desc);
create index if not exists audit_log_at_idx on ${log} (${c("at")});${
    ctx.has("log", "idempotencyKey")
      ? `
create unique index if not exists audit_log_idempotency_idx on ${log} (${c("tenant")}, ${c("idempotencyKey")}) nulls not distinct where ${c("idempotencyKey")} is not null;`
      : ""
  }
alter table ${log} enable row level security;
revoke all on ${log} from anon, authenticated;
grant select on ${log} to service_role;${restrictedTable}`;
}

const REGISTRY = `create table if not exists better_supabase.audited_tables (
  target regclass primary key,
  ignore text[] not null default '{}'
);
-- The primary key columns, read when the table is registered; composite keys are joined with ','.
alter table better_supabase.audited_tables add column if not exists key_columns text[] not null default '{id}';
-- Per-table event naming and redaction.
alter table better_supabase.audited_tables add column if not exists redact text[] not null default '{}';
alter table better_supabase.audited_tables add column if not exists category text;
alter table better_supabase.audited_tables add column if not exists event_prefix text;
alter table better_supabase.audited_tables add column if not exists target_type text;
alter table better_supabase.audited_tables add column if not exists tenant_column text;
alter table better_supabase.audited_tables enable row level security;
revoke all on better_supabase.audited_tables from anon, authenticated;

-- The client address PostgREST forwards, or null.
create or replace function better_supabase.request_ip()
returns inet
language plpgsql
stable
set search_path = ''
as $$
begin
  return nullif(trim(split_part(current_setting('request.headers', true)::json ->> 'x-forwarded-for', ',', 1)), '')::inet;
exception when others then
  return null;
end;
$$;`;

/** SQL that writes the restricted details of `entry_id`, when the table is in use. */
function restrictedInsert(
  ctx: KitContext,
  restricted: boolean,
  values: { old: string; new: string; metadata: string },
): string {
  if (!restricted) return "";
  const r = (logical: string) => ctx.col("restricted", logical);
  const pairs: (readonly [string, string])[] = [
    ["entry", "entry_id"],
    ["old", values.old],
    ["new", values.new],
    ["ip", "better_supabase.request_ip()"],
    [
      "userAgent",
      "current_setting('request.headers', true)::json ->> 'user-agent'",
    ],
    ["metadata", values.metadata],
  ];
  const kept = pairs.filter(
    ([logical]) => logical === "entry" || ctx.has("restricted", logical),
  );
  return `
  insert into ${ctx.table("restricted")} (${kept.map(([logical]) => r(logical)).join(", ")})
  values (${kept.map(([, value]) => value).join(", ")});`;
}

function triggerFunction(
  ctx: KitContext,
  tenantColumn: string,
  restricted: boolean,
): string {
  const snapshots = !restricted;
  const insert = present(ctx, "log", [
    ["table", "tg_table_schema || '.' || tg_table_name"],
    [
      "record",
      "(select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord))",
    ],
    ["op", "lower(tg_op)"],
    ...(snapshots
      ? ([
          ["old", "old_row"],
          ["new", "new_row"],
        ] as const)
      : []),
    ["changed", "changed_columns"],
    ["actor", "auth.uid()"],
    ["actorRole", "coalesce(auth.jwt() ->> 'role', current_user)"],
    [
      "tenant",
      castId(
        `row_data ->> coalesce(entry.tenant_column, ${sqlString(tenantColumn)})`,
        ctx.idType,
      ),
    ],
    [
      "impersonatedBy",
      "case when auth.jwt() -> 'act' ->> 'sub' ~ '^[0-9a-f-]{36}$' then (auth.jwt() -> 'act' ->> 'sub')::uuid end",
    ],
    ["impersonationReason", "auth.jwt() -> 'act' ->> 'reason'"],
    [
      "supportSession",
      "case when auth.jwt() -> 'act' ->> 'session_id' ~ '^[0-9a-f-]{36}$' then (auth.jwt() -> 'act' ->> 'session_id')::uuid end",
    ],
    [
      "eventType",
      "coalesce(entry.event_prefix, tg_table_name) || '.' || case tg_op when 'INSERT' then 'created' when 'UPDATE' then 'updated' else 'deleted' end",
    ],
    ["category", "coalesce(entry.category, 'data')"],
    ["outcome", "'success'"],
    ["source", "'database'"],
    ["targetType", "coalesce(entry.target_type, tg_table_name)"],
  ]);
  return `create or replace function better_supabase.audit_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  entry record;
  entry_id ${ctx.table("log")}.${ctx.col("log", "id")}%type;
  old_row jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  new_row jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  row_data jsonb := coalesce(new_row, old_row);
  changed_columns text[];
begin
  select coalesce(a.ignore, '{}') as ignore, coalesce(a.key_columns, '{id}') as key_columns,
    coalesce(a.redact, '{}') as redact, a.category, a.event_prefix, a.target_type, a.tenant_column
  into entry
  from (select 1) one
  left join better_supabase.audited_tables a on a.target = tg_relid::regclass;
  old_row := old_row - entry.ignore;
  new_row := new_row - entry.ignore;
  if tg_op = 'UPDATE' then
    select array_agg(key order by key) into changed_columns
    from jsonb_each(new_row) n
    where n.value is distinct from old_row -> n.key;
    if changed_columns is null then
      return null;
    end if;
  end if;
  -- Redacted columns stay in changed, with their values masked.
  old_row := old_row || coalesce((select jsonb_object_agg(k, '"[redacted]"'::jsonb) from unnest(entry.redact) k where old_row ? k), '{}');
  new_row := new_row || coalesce((select jsonb_object_agg(k, '"[redacted]"'::jsonb) from unnest(entry.redact) k where new_row ? k), '{}');
  insert into ${ctx.table("log")} (${insert.columns})
  values (
    ${insert.values}
  )
  returning ${ctx.col("log", "id")} into entry_id;${restrictedInsert(ctx, restricted, { old: "old_row", new: "new_row", metadata: "'{}'::jsonb" })}
  return null;
end;
$$;`;
}

function auditEvent(ctx: KitContext, restricted: boolean): string {
  const id = ctx.idType;
  const log = ctx.table("log");
  const c = (logical: string) => ctx.col("log", logical);
  const insert = present(ctx, "log", [
    ["table", "null"],
    ["record", "record_id"],
    ["op", "'event'"],
    ["actor", "actor_id"],
    ["actorRole", "coalesce(auth.jwt() ->> 'role', current_user)"],
    ["tenant", "tenant"],
    [
      "impersonatedBy",
      "case when auth.jwt() -> 'act' ->> 'sub' ~ '^[0-9a-f-]{36}$' then (auth.jwt() -> 'act' ->> 'sub')::uuid end",
    ],
    ["impersonationReason", "auth.jwt() -> 'act' ->> 'reason'"],
    [
      "supportSession",
      "case when auth.jwt() -> 'act' ->> 'session_id' ~ '^[0-9a-f-]{36}$' then (auth.jwt() -> 'act' ->> 'session_id')::uuid end",
    ],
    ["eventType", "event_type"],
    [
      "category",
      `coalesce(category, ${sqlString(ctx.text("eventCategory", "system"))})`,
    ],
    ["outcome", "coalesce(outcome, 'success')"],
    [
      "source",
      `coalesce(source, ${sqlString(ctx.text("eventSource", "app"))})`,
    ],
    ["targetType", "target_type"],
    ["metadata", "coalesce(metadata, '{}')"],
    ["idempotencyKey", "idempotency_key"],
  ]);
  const roles = ctx.list("eventRoles", ["service_role"]);
  const idempotent = ctx.has("log", "idempotencyKey")
    ? `
  if idempotency_key is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('better_supabase.audit_event'), pg_catalog.hashtext(coalesce(tenant::text, '') || ':' || idempotency_key));
    select l.${c("id")}::text into existing
    from ${log} l
    where l.${c("idempotencyKey")} = audit_event.idempotency_key
      and l.${c("tenant")} is not distinct from audit_event.tenant
    limit 1;
    if existing is not null then
      return existing;
    end if;
  end if;`
    : "";
  return `-- Records a semantic app event (invoice.sent, member.invited) next to the
-- row changes. A repeated idempotency_key returns the first entry's id.
-- actor_id is honoured for the service role and direct admin connections;
-- everyone else is auth.uid().
drop function if exists better_supabase.audit_event(text, text, text, text, text, text, ${id}, jsonb, text, jsonb, uuid);
create or replace function better_supabase.audit_event(
  event_type text,
  category text default null,
  outcome text default 'success',
  source text default null,
  target_type text default null,
  record_id text default null,
  tenant ${id} default null,
  metadata jsonb default '{}',
  idempotency_key text default null,
  restricted jsonb default null,
  actor_id uuid default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing text;
  entry_id ${log}.${c("id")}%type;
begin
  if not (${SERVICE_CALLER}) or actor_id is null then
    actor_id := auth.uid();
  end if;${idempotent}
  insert into ${log} (${insert.columns})
  values (
    ${insert.values}
  )
  returning ${c("id")} into entry_id;${restrictedInsert(ctx, restricted, { old: "null", new: "null", metadata: "coalesce(restricted, '{}')" })}
  return entry_id::text;
end;
$$;
revoke execute on function better_supabase.audit_event(text, text, text, text, text, text, ${id}, jsonb, text, jsonb, uuid) from public, anon, authenticated;
grant execute on function better_supabase.audit_event(text, text, text, text, text, text, ${id}, jsonb, text, jsonb, uuid) to ${roles.map(sqlIdent).join(", ")};`;
}

function appendOnly(ctx: KitContext): string {
  const log = ctx.table("log");
  const trigger = ctx.trigger("audit_append_only");
  if (!ctx.flag("appendOnly", false)) {
    return `drop trigger if exists ${trigger} on ${log};`;
  }
  return `-- Entries are append-only; purge_audit_log sets better_supabase.audit_purge
-- for its own transaction to delete old ones.
create or replace function better_supabase.audit_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and current_setting('better_supabase.audit_purge', true) = 'on' then
    return old;
  end if;
  raise exception 'audit log entries are append-only'
    using errcode = '42501', hint = 'Delete old entries with better_supabase.purge_audit_log()';
end;
$$;
drop trigger if exists ${trigger} on ${log};
create trigger ${trigger} before update or delete on ${log}
  for each row execute function better_supabase.audit_append_only();`;
}

function readPolicy(ctx: KitContext): string {
  const log = ctx.table("log");
  if (!ctx.flag("readPolicy", false)) {
    return ctx.manages ? `drop policy if exists bs_audit_read on ${log};` : "";
  }
  const c = (logical: string) => ctx.col("log", logical);
  const view = ctx.permission("view", "audit.view");
  const viewAll = ctx.permission("viewAll", "audit.view");
  const hidden = new Set(
    impersonators(ctx) === "hide"
      ? ["impersonatedBy", "impersonationReason", "supportSession"]
      : [],
  );
  const readable = Object.keys(NAMES.tables["log"]!.columns)
    .filter((logical) => ctx.has("log", logical) && !hidden.has(logical))
    .map(c);
  return `-- Members read their tenant's entries with the ${ctx.permissionKey("view", "audit.view")} permission;
-- platform staff read every entry.
drop policy if exists bs_audit_read on ${log};
create policy bs_audit_read on ${log} for select to authenticated
  using (
    ${c("tenant")} in (select better_supabase.tenant_ids_with(${view}))
    or (select better_supabase.is_platform(${viewAll}))
  );
${
  hidden.size > 0
    ? `revoke select on ${log} from authenticated;
-- impersonators: "hide" leaves out who acted as the user.
grant select (${readable.join(", ")}) on ${log} to authenticated;`
    : `grant select on ${log} to authenticated;`
}`;
}

function retention(ctx: KitContext): string {
  const log = ctx.table("log");
  const c = (logical: string) => ctx.col("log", logical);
  const id = ctx.idType;
  const hook = ctx.hookTarget("audit_retention");
  const signature = sqlString(`${hook}(${id})`);
  return `-- Deletes up to batch entries older than older_than and returns how many.
-- With an audit_retention(tenant) function, each tenant keeps its own
-- interval (a plan's days, say); null falls back to older_than. With
-- for_tenant, only entries of tenant (null: entries without one).
-- Nightly with pg_cron or the jobs drain route:
--   select better_supabase.purge_audit_log();
drop function if exists better_supabase.purge_audit_log(interval, integer);
create or replace function better_supabase.purge_audit_log(
  older_than interval default '1 year',
  batch integer default 10000,
  tenant ${id} default null,
  for_tenant boolean default false
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  purged integer;
begin
  perform set_config('better_supabase.audit_purge', 'on', true);
  if not for_tenant and to_regprocedure(${signature}) is not null then
    with gone as (
      delete from ${log}
      where ${c("id")} in (
        select l.${c("id")} from ${log} l
        where l.${c("at")} < now() - coalesce(${hook}(l.${c("tenant")}), older_than)
        order by l.${c("at")}
        limit batch
      )
      returning 1
    )
    select count(*)::integer into purged from gone;
  else
    with gone as (
      delete from ${log}
      where ${c("id")} in (
        select l.${c("id")} from ${log} l
        where l.${c("at")} < now() - older_than
          and (not for_tenant or l.${c("tenant")} is not distinct from purge_audit_log.tenant)
        order by l.${c("at")}
        limit batch
      )
      returning 1
    )
    select count(*)::integer into purged from gone;
  end if;
  perform set_config('better_supabase.audit_purge', 'off', true);
  return purged;
end;
$$;
revoke execute on function better_supabase.purge_audit_log(interval, integer, ${id}, boolean) from public, anon, authenticated;
grant execute on function better_supabase.purge_audit_log(interval, integer, ${id}, boolean) to service_role;

-- Tenants with entries older than older_than, for a retention callback in TypeScript.
create or replace function better_supabase.audit_log_tenants(older_than interval default '1 day')
returns setof ${id}
language sql
stable
security definer
set search_path = ''
as $$
  select distinct l.${c("tenant")} from ${log} l
  where l.${c("at")} < now() - older_than
$$;
revoke execute on function better_supabase.audit_log_tenants(interval) from public, anon, authenticated;
grant execute on function better_supabase.audit_log_tenants(interval) to service_role;`;
}

const REGISTER = `drop function if exists better_supabase.audit(regclass, text[]);
drop function if exists better_supabase.audit(regclass, text[], boolean);

-- select better_supabase.audit('public.customers', ignore => '{updated_at}');
-- redact => '{api_key}' masks values but keeps them in changed;
-- event_prefix, category and target_type name the entries (event_prefix.created);
-- tenant_column overrides the module's tenant column for this table.
-- replace_trigger => true drops another audit trigger on the table.
create or replace function better_supabase.audit(
  target regclass,
  ignore text[] default '{}',
  replace_trigger boolean default false,
  redact text[] default '{}',
  category text default null,
  event_prefix text default null,
  target_type text default null,
  tenant_column text default null
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  keys text[];
begin
  perform better_supabase.replace_equivalent_triggers(
    target, 'bs_audit', 'audit', replace_trigger
  );
  select array_agg(c.attname::text order by k.ord) into keys
  from pg_catalog.pg_index i
  cross join lateral unnest(i.indkey) with ordinality k(attnum, ord)
  join pg_catalog.pg_attribute c on c.attrelid = i.indrelid and c.attnum = k.attnum
  where i.indrelid = audit.target and i.indisprimary;
  insert into better_supabase.audited_tables as a
    (target, ignore, key_columns, redact, category, event_prefix, target_type, tenant_column)
  values (
    audit.target, audit.ignore, coalesce(keys, '{id}'), audit.redact, audit.category,
    audit.event_prefix, audit.target_type, audit.tenant_column
  )
  on conflict on constraint audited_tables_pkey do update
    set ignore = excluded.ignore, key_columns = excluded.key_columns, redact = excluded.redact,
      category = excluded.category, event_prefix = excluded.event_prefix,
      target_type = excluded.target_type, tenant_column = excluded.tenant_column;
  execute format('drop trigger if exists bs_audit on %s', target);
  execute format(
    'create trigger bs_audit after insert or update or delete on %s for each row execute function better_supabase.audit_trigger()',
    target
  );
end;
$$;

create or replace function better_supabase.unaudit(target regclass)
returns void
language plpgsql
set search_path = ''
as $$
begin
  execute format('drop trigger if exists bs_audit on %s', target);
  delete from better_supabase.audited_tables a where a.target = unaudit.target;
end;
$$;`;

function auditSql(ctx: KitContext, layout: KitLayout): string {
  const restricted = restrictedOn(ctx);
  const tenantColumn = ctx.text(
    "tenantColumn",
    layout.tenantColumn ?? "organization_id",
  );
  return [
    SCHEMA,
    REGISTRY,
    ctx.manages ? managedTables(ctx, restricted) : "",
    triggerFunction(ctx, tenantColumn, restricted),
    EQUIVALENT_TRIGGERS.trim(),
    REGISTER,
    auditEvent(ctx, restricted),
    appendOnly(ctx),
    readPolicy(ctx),
    retention(ctx),
  ]
    .filter(Boolean)
    .join("\n\n");
}

export const AUDIT: KitModuleDefinition = {
  name: "audit",
  title: "Audit log",
  description:
    "Records inserts, updates and deletes with the actor and changed columns for tables you register, plus semantic events through audit_event(), with redaction, an append-only guard, a tenant read policy and per-tenant retention as options.",
  requires: [],
  dependencies: (layout) =>
    layout.kits?.["audit"]?.options?.["readPolicy"] === true ? ["access"] : [],
  target: "schema",
  modes: ["managed", "adopt"],
  version: 2,
  names: NAMES,
  contract: () => [
    {
      name: "audit",
      args: [
        "regclass",
        "text[]",
        "boolean",
        "text[]",
        "text",
        "text",
        "text",
        "text",
      ],
      returns: "void",
    },
    {
      name: "audit_event",
      args: [
        "text",
        "text",
        "text",
        "text",
        "text",
        "text",
        "{id}",
        "jsonb",
        "text",
        "jsonb",
        "uuid",
      ],
      returns: "text",
    },
    {
      name: "purge_audit_log",
      args: ["interval", "integer", "{id}", "boolean"],
      returns: "integer",
    },
  ],
  upgrades: [
    {
      from: 1,
      description:
        "audit() takes redact, category, event_prefix, target_type and tenant_column; audit_event() records semantic events; purge_audit_log() takes a tenant.",
      sql: () =>
        [
          "drop function if exists better_supabase.audit(regclass, text[], boolean);",
          "drop function if exists better_supabase.purge_audit_log(interval, integer);",
        ].join("\n"),
    },
  ],
  build: auditSql,
};
