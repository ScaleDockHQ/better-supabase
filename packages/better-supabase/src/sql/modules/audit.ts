import type { ModuleContext, ModuleIdType, ModuleNames } from "../context.ts";
import type { ModuleLayout, ModuleDefinition } from "../registry.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  EQUIVALENT_TRIGGERS,
  renameSql,
  SCHEMA,
  SERVICE_CALLER,
} from "../shared.ts";
import { MODULE_PERMISSIONS } from "./access-model.ts";
import { listEntries, reveal } from "./audit-api.ts";
import { hasColumn, impersonators } from "./audit-columns.ts";
import { auditTests } from "./audit-tests.ts";

const NAMES: ModuleNames = {
  options: [
    "appendOnly",
    "eventCategory",
    "eventRoles",
    "eventSource",
    "exempt",
    "impersonators",
    "readPolicy",
    "restricted",
    "tenantColumn",
  ],
  tables: {
    log: {
      name: "audit_events",
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
        tenant: "organization_id",
        occurredAt: "occurred_at",
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
        actorKind: "actor_kind",
        actorLabel: "actor_label",
        tenantLabel: "tenant_label",
        targetLabel: "target_label",
        summary: "summary",
        requestId: "request_id",
        correlationId: "correlation_id",
        scope: "scope",
      },
      optional: [
        "actorKind",
        "actorLabel",
        "tenantLabel",
        "targetLabel",
        "summary",
        "requestId",
        "correlationId",
        "scope",
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
      name: "audit_events_restricted",
      columns: {
        entry: "entry_id",
        old: "old_record",
        new: "new_record",
        ip: "ip_address",
        userAgent: "user_agent",
        metadata: "metadata",
        sessionId: "session_id",
        changedValues: "changed_values",
      },
      optional: [
        "old",
        "new",
        "ip",
        "userAgent",
        "metadata",
        "sessionId",
        "changedValues",
      ],
      optionalTable: true,
    },
  },
  hooks: ["audit_retention"],
};

/** A text expression as the id type, or null when it doesn't parse as one. */
function castId(value: string, idType: ModuleIdType): string {
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

/** The request header `name`, or null outside a Data API request. */
const requestHeader = (name: string): string =>
  `better_supabase.request_header(${sqlString(name)})`;

/** How the caller acted: service, support, impersonation, oauth-client, user or system. */
const ACTOR_KIND = `case
      when coalesce(auth.jwt() ->> 'role', '') = 'service_role' then 'service'
      when auth.jwt() -> 'act' ->> 'kind' = 'support' then 'support'
      when auth.jwt() -> 'act' is not null then 'impersonation'
      when auth.jwt() ->> 'client_id' is not null then 'oauth-client'
      when auth.uid() is not null then 'user'
      else 'system'
    end`;

const ACTOR_LABEL = `coalesce(auth.jwt() -> 'user_metadata' ->> 'full_name', auth.jwt() ->> 'email')`;

/** The tenant's name as it was, from the organizations module's table when installed. */
function tenantLabel(ctx: ModuleContext, tenant: string): string {
  if (!ctx.installed("organizations")) return "null";
  const organizations = ctx.of("organizations");
  if (!organizations.has("organizations", "name")) return "null";
  return `(select o.${organizations.col("organizations", "name")}::text from ${organizations.table("organizations")} o where o.${organizations.col("organizations", "id")} = ${tenant})`;
}

/** The pairs every entry writes for the version 3 columns. */
function contextPairs(
  ctx: ModuleContext,
  tenant: string,
  values: { targetLabel: string; summary: string; correlationId: string },
): (readonly [string, string])[] {
  return [
    ["actorKind", ACTOR_KIND],
    ["actorLabel", ACTOR_LABEL],
    ["tenantLabel", tenantLabel(ctx, tenant)],
    ["targetLabel", values.targetLabel],
    ["summary", values.summary],
    ["requestId", requestHeader("x-request-id")],
    ["correlationId", values.correlationId],
    ["scope", `case when ${tenant} is null then 'platform' else 'tenant' end`],
  ];
}

/** The restricted table is in use: an option when managed, a mapping when adopted. */
function restrictedOn(ctx: ModuleContext): boolean {
  return ctx.manages
    ? ctx.flag("restricted", false)
    : ctx.config.tables["restricted"] !== undefined &&
        ctx.hasTable("restricted");
}

/** `[column, value]` pairs for the logical columns the log has. */
function present(
  ctx: ModuleContext,
  table: string,
  pairs: readonly (readonly [string, string])[],
): { columns: string; values: string } {
  const kept = pairs.filter(([logical]) => hasColumn(ctx, table, logical));
  return {
    columns: kept.map(([logical]) => ctx.col(table, logical)).join(", "),
    values: kept.map(([, value]) => value).join(",\n    "),
  };
}

function managedTables(ctx: ModuleContext, restricted: boolean): string {
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
alter table ${ctx.table("restricted")} add column if not exists ${ctx.col("restricted", "sessionId")} text;
alter table ${ctx.table("restricted")} add column if not exists ${ctx.col("restricted", "changedValues")} jsonb;
alter table ${ctx.table("restricted")} enable row level security;
revoke all on ${ctx.table("restricted")} from anon, authenticated;`
    : "";
  return `create table if not exists ${log} (
  ${c("id")} bigint generated always as identity primary key,${line("table", "text")}${line("record", "text")}${line("op", "text not null")}${line("old", "jsonb")}${line("new", "jsonb")}${line("changed", "text[]")}${line("actor", "uuid")}${line("actorRole", "text")}
  ${c("tenant")} ${ctx.idType},
  ${c("occurredAt")} timestamptz not null default now()
);${op}${table}
-- Set when an admin acted as the user (the act claim).${add("impersonatedBy", "uuid")}${add("impersonationReason", "text")}${add("supportSession", "uuid")}
-- Semantic events (audit_event) and the per-table registry fill these.${add("eventType", "text")}${add("category", "text")}${add("outcome", "text")}${add("source", "text")}${add("targetType", "text")}${add("metadata", "jsonb")}${add("idempotencyKey", "text")}
-- Who acted and on what, as it was then, for audit pages.${add("actorKind", "text")}${add("actorLabel", "text")}${add("tenantLabel", "text")}${add("targetLabel", "text")}${add("summary", "text")}${add("requestId", "text")}${add("correlationId", "text")}${add("scope", "text")}
${
  ctx.has("log", "table") && ctx.has("log", "record")
    ? `create index if not exists audit_events_record_idx on ${log} (${c("table")}, ${c("record")}, ${c("occurredAt")} desc);\n`
    : ""
}create index if not exists audit_events_organization_idx on ${log} (${c("tenant")}, ${c("occurredAt")} desc);
create index if not exists audit_events_occurred_at_idx on ${log} (${c("occurredAt")});${
    ctx.has("log", "idempotencyKey")
      ? `
create unique index if not exists audit_events_idempotency_idx on ${log} (${c("idempotencyKey")}, ${c("tenant")}) nulls not distinct where ${c("idempotencyKey")} is not null;`
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
alter table better_supabase.audited_tables add column if not exists label_column text;
alter table better_supabase.audited_tables enable row level security;
revoke all on better_supabase.audited_tables from anon, authenticated;

-- One request header, or null outside a Data API request.
create or replace function better_supabase.request_header(name text)
returns text
language plpgsql
stable
set search_path = ''
as $$
begin
  return nullif(current_setting('request.headers', true), '')::jsonb ->> request_header.name;
exception when others then
  return null;
end;
$$;

-- The client address the API gateway appended to x-forwarded-for (the
-- right-most hop; clients can forge the ones before it), or null.
create or replace function better_supabase.request_ip()
returns inet
language plpgsql
stable
set search_path = ''
as $$
begin
  return nullif(trim(reverse(split_part(reverse(current_setting('request.headers', true)::json ->> 'x-forwarded-for'), ',', 1))), '')::inet;
exception when others then
  return null;
end;
$$;`;

/** SQL that writes the restricted details of `entry_id`, when the table is in use. */
function restrictedInsert(
  ctx: ModuleContext,
  restricted: boolean,
  values: { old: string; new: string; metadata: string; changed?: string },
): string {
  if (!restricted) return "";
  const r = (logical: string) => ctx.col("restricted", logical);
  const pairs: (readonly [string, string])[] = [
    ["entry", "entry_id"],
    ["old", values.old],
    ["new", values.new],
    ["ip", "better_supabase.request_ip()"],
    ["userAgent", requestHeader("user-agent")],
    ["metadata", values.metadata],
    ["sessionId", "auth.jwt() ->> 'session_id'"],
    ["changedValues", values.changed ?? "null"],
  ];
  const kept = pairs.filter(
    ([logical]) => logical === "entry" || hasColumn(ctx, "restricted", logical),
  );
  return `
  insert into ${ctx.table("restricted")} (${kept.map(([logical]) => r(logical)).join(", ")})
  values (${kept.map(([, value]) => value).join(", ")});`;
}

function triggerFunction(
  ctx: ModuleContext,
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
    ["tenant", "row_tenant"],
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
    ...contextPairs(ctx, "row_tenant", {
      targetLabel: "row_data ->> entry.label_column",
      summary: "null",
      correlationId: requestHeader("x-correlation-id"),
    }),
  ]);
  const tenantValue = castId(
    `row_data ->> coalesce(entry.tenant_column, ${sqlString(tenantColumn)})`,
    ctx.idType,
  );
  return `create or replace function better_supabase.audit_row_change()
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
  changed_values jsonb;
  row_tenant ${ctx.idType};
begin
  select coalesce(a.ignore, '{}') as ignore, coalesce(a.key_columns, '{id}') as key_columns,
    coalesce(a.redact, '{}') as redact, a.category, a.event_prefix, a.target_type, a.tenant_column,
    a.label_column
  into entry
  from (select 1) one
  left join better_supabase.audited_tables a on a.target = tg_relid::regclass;
  row_tenant := ${tenantValue};
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
  -- One change per column, values cut at 1000 characters, for revealing a
  -- single change without the whole rows.
  select jsonb_object_agg(k, jsonb_build_object(
    'old', case when length((old_row -> k)::text) > 1000 then to_jsonb(left((old_row -> k)::text, 1000)) else old_row -> k end,
    'new', case when length((new_row -> k)::text) > 1000 then to_jsonb(left((new_row -> k)::text, 1000)) else new_row -> k end
  ))
  into changed_values
  from unnest(coalesce(changed_columns, array(select jsonb_object_keys(coalesce(new_row, old_row))))) k;
  insert into ${ctx.table("log")} (${insert.columns})
  values (
    ${insert.values}
  )
  returning ${ctx.col("log", "id")} into entry_id;${restrictedInsert(ctx, restricted, { old: "old_row", new: "new_row", metadata: "'{}'::jsonb", changed: "changed_values" })}
  return null;
end;
$$;`;
}

/** `audit_event`'s argument types. */
const EVENT_ARGS = (id: string): string =>
  `text, text, text, text, text, text, ${id}, jsonb, text, jsonb, uuid, text, text, text`;

function auditEvent(ctx: ModuleContext, restricted: boolean): string {
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
    ...contextPairs(ctx, "tenant", {
      targetLabel: "target_label",
      summary: "summary",
      correlationId: `coalesce(correlation_id, ${requestHeader("x-correlation-id")})`,
    }),
  ]);
  const roles = ctx.list("eventRoles", ["service_role"]);
  const noRestricted = restricted
    ? ""
    : `
  if restricted is not null then
    raise exception 'audit_event got restricted details, and the audit module has no restricted table'
      using errcode = '22023', hint = ${sqlString(
        ctx.manages
          ? "Set sql.modules.audit.options.restricted to true."
          : "Map sql.modules.audit.tables.restricted to the table for sensitive details.",
      )};
  end if;`;
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
-- everyone else is auth.uid(). restricted goes to the restricted table;
-- without that table, passing it fails instead of dropping the details.
drop function if exists better_supabase.audit_event(text, text, text, text, text, text, ${id}, jsonb, text, jsonb, uuid);
drop function if exists better_supabase.audit_event(${EVENT_ARGS(id)});
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
  actor_id uuid default null,
  summary text default null,
  target_label text default null,
  correlation_id text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing text;
  entry_id ${log}.${c("id")}%type;
begin${noRestricted}
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
revoke execute on function better_supabase.audit_event(${EVENT_ARGS(id)}) from public, anon, authenticated;
grant execute on function better_supabase.audit_event(${EVENT_ARGS(id)}) to ${roles.map(sqlIdent).join(", ")};`;
}

function appendOnly(ctx: ModuleContext): string {
  const log = ctx.table("log");
  const trigger = ctx.trigger("audit_append_only");
  const truncate = ctx.trigger("audit_no_truncate");
  if (!ctx.flag("appendOnly", ctx.manages)) {
    return `drop trigger if exists ${trigger} on ${log};
drop trigger if exists ${truncate} on ${log};`;
  }
  const purge = sqlString(
    `better_supabase.purge_audit_log(interval, integer, ${ctx.idType}, boolean)`,
  );
  return `-- Entries are append-only. purge_audit_log deletes old ones: it runs as its
-- owner and sets better_supabase.audit_purge, and a role that only sets the
-- setting is not the owner.
create or replace function better_supabase.audit_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE'
    and current_setting('better_supabase.audit_purge', true) = 'on'
    and current_user = (
      select r.rolname from pg_catalog.pg_proc p
      join pg_catalog.pg_roles r on r.oid = p.proowner
      where p.oid = to_regprocedure(${purge})
    )
  then
    return old;
  end if;
  raise exception 'audit log entries are append-only'
    using errcode = '42501', hint = 'Delete old entries with better_supabase.purge_audit_log()';
end;
$$;
revoke execute on function better_supabase.audit_append_only() from public, anon, authenticated;
drop trigger if exists ${trigger} on ${log};
create trigger ${trigger} before update or delete on ${log}
  for each row execute function better_supabase.audit_append_only();
drop trigger if exists ${truncate} on ${log};
create trigger ${truncate} before truncate on ${log}
  for each statement execute function better_supabase.audit_append_only();`;
}

function readPolicy(ctx: ModuleContext): string {
  const log = ctx.table("log");
  if (!ctx.flag("readPolicy", false)) {
    return ctx.manages
      ? `drop policy if exists bs_audit_read on ${log};
drop function if exists ${ctx.fn("audit_read_tenants")}();
drop function if exists ${ctx.fn("audit_reads_all")}();`
      : "";
  }
  const c = (logical: string) => ctx.col("log", logical);
  const view = ctx.permission("view", MODULE_PERMISSIONS.audit.view);
  const viewAll = ctx.permission("viewAll", MODULE_PERMISSIONS.audit.viewAll);
  const hidden = new Set(
    impersonators(ctx) === "hide"
      ? ["impersonatedBy", "impersonationReason", "supportSession"]
      : [],
  );
  const readable = Object.keys(NAMES.tables["log"]!.columns)
    .filter((logical) => hasColumn(ctx, "log", logical) && !hidden.has(logical))
    .map(c);
  return `-- Members read their tenant's entries with the ${ctx.permissionKey("view", MODULE_PERMISSIONS.audit.view)} permission;
-- platform staff read every entry. PL/pgSQL resolves tenant_ids_with and
-- is_platform when it runs, so this file installs before the access module's.
create or replace function ${ctx.fn("audit_read_tenants")}()
returns setof ${ctx.idType}
language plpgsql
stable
set search_path = ''
as $$
begin
  return query select t::${ctx.idType} from better_supabase.tenant_ids_with(${view}) t;
end;
$$;
create or replace function ${ctx.fn("audit_reads_all")}()
returns boolean
language plpgsql
stable
set search_path = ''
as $$
begin
  return better_supabase.is_platform(${viewAll});
end;
$$;
revoke execute on function ${ctx.fn("audit_read_tenants")}() from public, anon;
revoke execute on function ${ctx.fn("audit_reads_all")}() from public, anon;
grant execute on function ${ctx.fn("audit_read_tenants")}() to authenticated, service_role;
grant execute on function ${ctx.fn("audit_reads_all")}() to authenticated, service_role;
drop policy if exists bs_audit_read on ${log};
create policy bs_audit_read on ${log} for select to authenticated
  using (
    ${c("tenant")} in (select ${ctx.fn("audit_read_tenants")}())
    or (select ${ctx.fn("audit_reads_all")}())
  );
${
  hidden.size > 0
    ? `revoke select on ${log} from authenticated;
-- impersonators: "hide" leaves out who acted as the user.
grant select (${readable.join(", ")}) on ${log} to authenticated;`
    : `grant select on ${log} to authenticated;`
}`;
}

function retention(ctx: ModuleContext): string {
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
    -- Not a literal name, so plpgsql_check passes without the hook.
    execute format(
      ${sqlString(`with gone as (
      delete from ${log}
      where ${c("id")} in (
        select l.${c("id")} from ${log} l
        where l.${c("occurredAt")} < now() - coalesce(%s(l.${c("tenant")}), $1)
        order by l.${c("occurredAt")}
        limit $2
      )
      returning 1
    )
    select count(*)::integer from gone`)},
      to_regprocedure(${signature})::oid::regproc
    ) into purged using older_than, batch;
  else
    with gone as (
      delete from ${log}
      where ${c("id")} in (
        select l.${c("id")} from ${log} l
        where l.${c("occurredAt")} < now() - older_than
          and (not for_tenant or l.${c("tenant")} is not distinct from purge_audit_log.tenant)
        order by l.${c("occurredAt")}
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
create or replace function better_supabase.audit_events_tenants(older_than interval default '1 day')
returns setof ${id}
language sql
stable
security definer
set search_path = ''
as $$
  select distinct l.${c("tenant")} from ${log} l
  where l.${c("occurredAt")} < now() - older_than
$$;
revoke execute on function better_supabase.audit_events_tenants(interval) from public, anon, authenticated;
grant execute on function better_supabase.audit_events_tenants(interval) to service_role;`;
}

const REGISTER = `drop function if exists better_supabase.audit(regclass, text[]);
drop function if exists better_supabase.audit(regclass, text[], boolean);
drop function if exists better_supabase.audit(regclass, text[], boolean, text[], text, text, text, text);

-- select better_supabase.audit('public.customers', ignore => '{updated_at}');
-- redact => '{api_key}' masks values but keeps them in changed;
-- event_prefix, category and target_type name the entries (event_prefix.created);
-- tenant_column overrides the module's tenant column for this table, and
-- label_column names the column kept as the entry's target label.
-- replace_trigger => true drops another audit trigger on the table.
create or replace function better_supabase.audit(
  target regclass,
  ignore text[] default '{}',
  replace_trigger boolean default false,
  redact text[] default '{}',
  category text default null,
  event_prefix text default null,
  target_type text default null,
  tenant_column text default null,
  label_column text default null
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
    (target, ignore, key_columns, redact, category, event_prefix, target_type, tenant_column, label_column)
  values (
    audit.target, audit.ignore, coalesce(keys, '{id}'), audit.redact, audit.category,
    audit.event_prefix, audit.target_type, audit.tenant_column, audit.label_column
  )
  on conflict on constraint audited_tables_pkey do update
    set ignore = excluded.ignore, key_columns = excluded.key_columns, redact = excluded.redact,
      category = excluded.category, event_prefix = excluded.event_prefix,
      target_type = excluded.target_type, tenant_column = excluded.tenant_column,
      label_column = excluded.label_column;
  execute format('drop trigger if exists bs_audit on %s', target);
  execute format(
    'create trigger bs_audit after insert or update or delete on %s for each row execute function better_supabase.audit_row_change()',
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
$$;

-- The audit() calls for every table in schema_name with tenant_column,
-- except tables whose name matches an exempt pattern (like 'audit_%').
-- Paste them into a schema file: static calls keep their place in a
-- pg-delta diff, where a loop over the catalog runs before the tables exist.
--   select better_supabase.audit_schema_calls('public', 'tenant_id', '{audit_%}');
create or replace function better_supabase.audit_schema_calls(
  schema_name text,
  tenant_column text,
  exempt text[] default '{}'
)
returns setof text
language sql
stable
set search_path = ''
as $$
  select format('select better_supabase.audit(%L);', format('%I.%I', n.nspname, c.relname))
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  where n.nspname = schema_name
    and c.relkind in ('r', 'p')
    and not c.relispartition
    and exists (
      select 1 from pg_catalog.pg_attribute a
      where a.attrelid = c.oid and a.attname = tenant_column and a.attnum > 0 and not a.attisdropped
    )
    and not exists (select 1 from unnest(exempt) e where c.relname like e)
  order by c.relname
$$;

-- Registers those tables now, for a migration or a one-off script; tables
-- already registered keep their own settings. Returns how many it added.
create or replace function better_supabase.audit_schema(
  schema_name text,
  tenant_column text,
  exempt text[] default '{}'
)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  registered integer := 0;
  target regclass;
begin
  for target in
    select format('%I.%I', n.nspname, c.relname)::regclass
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = schema_name
      and c.relkind in ('r', 'p')
      and not c.relispartition
      and exists (
        select 1 from pg_catalog.pg_attribute a
        where a.attrelid = c.oid and a.attname = audit_schema.tenant_column and a.attnum > 0 and not a.attisdropped
      )
      and not exists (select 1 from unnest(exempt) e where c.relname like e)
      and not exists (
        select 1 from better_supabase.audited_tables t where t.target = format('%I.%I', n.nspname, c.relname)::regclass
      )
    order by c.relname
  loop
    perform better_supabase.audit(target);
    registered := registered + 1;
  end loop;
  return registered;
end;
$$;

revoke execute on function better_supabase.audit(regclass, text[], boolean, text[], text, text, text, text, text) from public, anon, authenticated;
revoke execute on function better_supabase.unaudit(regclass) from public, anon, authenticated;
revoke execute on function better_supabase.audit_schema_calls(text, text, text[]) from public, anon, authenticated;
revoke execute on function better_supabase.audit_schema(text, text, text[]) from public, anon, authenticated;`;

/** The 0.4 table name and columns, read-only, until the next minor release. */
function legacyView(ctx: ModuleContext): string {
  const log = ctx.table("log");
  const view = `${sqlIdent(ctx.tableName("log").schema)}.audit_log`;
  return `-- Recreated, since new log columns change what l.* expands to.
drop view if exists ${view};
create view ${view}
  with (security_invoker = true) as
  select l.*, l.${ctx.col("log", "occurredAt")} as at, l.${ctx.col("log", "tenant")} as org_id
  from ${log} l;
comment on view ${view} is 'deprecated: use ${ctx.tableName("log").schema}.${ctx.tableName("log").name}';
revoke all on ${view} from anon, authenticated;
grant select on ${view} to service_role;`;
}

function auditSql(ctx: ModuleContext, layout: ModuleLayout): string {
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
    listEntries(ctx, restricted),
    reveal(ctx, restricted),
  ]
    .filter(Boolean)
    .join("\n\n");
}

export const AUDIT: ModuleDefinition = {
  name: "audit",
  title: "Audit log",
  description:
    "Records inserts, updates and deletes with the actor and changed columns for tables you register, plus semantic events through audit_event(), with redaction, an append-only guard, a tenant read policy and per-tenant retention as options.",
  requires: [],
  dependencies: (layout) =>
    layout.modules?.["audit"]?.options?.["readPolicy"] === true
      ? ["access"]
      : [],
  target: "schema",
  modes: ["managed", "adopt"],
  version: 3,
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
        "text",
        "text",
        "text",
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
        "Renames audit_log to audit_events (with a read-only audit_log view until 0.6), at to occurred_at, org_id to organization_id and audit_trigger() to audit_row_change(); audit() takes redact, category, event_prefix, target_type and tenant_column; audit_event() records semantic events; purge_audit_log() takes a tenant.",
      sql: (ctx) =>
        [
          ctx.manages
            ? renameSql({
                schema: ctx.tableName("log").schema,
                table: "audit_log",
                tables: [["audit_log", ctx.tableName("log").name]],
                columns: [
                  ["at", "occurred_at"],
                  ["org_id", "organization_id"],
                ],
                indexes: [
                  ["audit_log_record_idx", "audit_events_record_idx"],
                  ["audit_log_org_idx", "audit_events_organization_idx"],
                ],
              })
            : "",
          renameSql({
            schema: "better_supabase",
            table: "audited_tables",
            functions: [["audit_trigger", "audit_row_change", ""]],
          }),
          "drop function if exists better_supabase.audit(regclass, text[], boolean);",
          "drop function if exists better_supabase.purge_audit_log(interval, integer);",
        ]
          .filter(Boolean)
          .join("\n"),
    },
    {
      from: 2,
      description:
        "Entries record the actor kind and label, the tenant and target labels, a summary, the request and correlation ids and the scope (managed tables; adopted ones map the columns they have); the restricted table keeps the session id and per-column changes; audit() takes label_column and audit_event() takes summary, target_label and correlation_id; audit_schema_calls() and audit_schema() register a schema's tenant tables.",
      sql: (ctx) =>
        [
          "drop function if exists better_supabase.audit(regclass, text[], boolean, text[], text, text, text, text);",
          `drop function if exists better_supabase.audit_event(text, text, text, text, text, text, ${ctx.idType}, jsonb, text, jsonb, uuid);`,
        ].join("\n"),
    },
  ],
  deprecated: [
    {
      kind: "table",
      symbol: "better_supabase.audit_log",
      use: "better_supabase.audit_events (occurred_at, organization_id)",
      since: "0.5.0",
      wrapper: (ctx) => (ctx.manages ? legacyView(ctx) : ""),
    },
    {
      kind: "function",
      symbol: "better_supabase.audit_trigger",
      use: "better_supabase.audit_row_change()",
      since: "0.5.0",
      removed: "0.5.0",
    },
  ],
  build: auditSql,
  tests: (ctx, layout) =>
    auditTests(ctx, layout.auditedTables ?? [], restrictedOn(ctx)),
};
