import type {
  ModuleContext,
  ModuleEvents,
  ModuleIdType,
  ModuleNames,
} from "../context.ts";
import type { ModuleLayout, ModuleDefinition } from "../registry.ts";
import type { AuditInsert } from "./audit-metadata.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  ensureCheck,
  EQUIVALENT_TRIGGERS,
  renameSql,
  SCHEMA,
  SERVICE_CALLER,
} from "../shared.ts";
import { MODULE_PERMISSIONS, modulePermission } from "./access-model.ts";
import { listEntries, reveal } from "./audit-api.ts";
import { hasColumn, impersonators } from "./audit-columns.ts";
import {
  eventInsert,
  metadataColumns,
  storedMetadata,
} from "./audit-metadata.ts";
import { REGISTER } from "./audit-register.ts";
import {
  correlationIdSql,
  REQUEST_ID_OR_NULL,
  requestHeader,
  requestIdSql,
} from "./audit-request.ts";
import { retention } from "./audit-retention.ts";
import { auditTests } from "./audit-tests.ts";
import { auditWrite, tenantLabel } from "./audit-values.ts";

const EVENTS: ModuleEvents = {
  "audit.revealed": {
    subject: "audit-entries",
    payload: ["organizationId", "entries"],
  },
};

const NAMES: ModuleNames = {
  events: EVENTS,
  options: [
    "appendOnly",
    "correlationIdHeader",
    "eventCategory",
    "eventRoles",
    "trustedRoles",
    "eventSource",
    "exempt",
    "impersonators",
    "keepMappedMetadata",
    "metadataColumns",
    "readPolicy",
    "requestIdHeader",
    "restricted",
    "tenantColumn",
    "tenantLabel",
    "tenantLabelKey",
    "values",
  ],
  tables: {
    log: {
      name: "audit_events",
      // Exports leave out the row snapshots and the impersonation details,
      // which describe other people.
      lifecycle: {
        user: "actor",
        tenant: "tenant",
        purge: false,
        omit: [
          "old",
          "new",
          "impersonatedBy",
          "impersonationReason",
          "supportSession",
        ],
      },
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
      return `case when ${value} ~* '^[0-9a-f-]{36}$' then (${value})::uuid end`;
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

/** The pairs every entry writes for the version 3 columns. */
function contextPairs(
  ctx: ModuleContext,
  tenant: string,
  values: {
    targetLabel: string;
    summary: string;
    correlationId: string;
    actorKind?: string;
    actorLabel?: string;
    requestId?: string;
    scope?: string;
  },
): (readonly [string, string])[] {
  return [
    ["actorKind", auditWrite(ctx, "actorKind", values.actorKind ?? ACTOR_KIND)],
    ["actorLabel", values.actorLabel ?? ACTOR_LABEL],
    ["tenantLabel", tenantLabel(ctx, tenant)],
    ["targetLabel", values.targetLabel],
    ["summary", values.summary],
    ["requestId", values.requestId ?? requestIdSql(ctx)],
    ["correlationId", values.correlationId],
    [
      "scope",
      auditWrite(
        ctx,
        "scope",
        values.scope ??
          `case when ${tenant} is null then 'platform' else 'tenant' end`,
      ),
    ],
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
): AuditInsert {
  const kept = pairs.filter(([logical]) => hasColumn(ctx, table, logical));
  return {
    columns: kept.map(([logical]) => ctx.col(table, logical)).join(", "),
    values: kept.map(([, value]) => value).join(",\n    "),
    pairs: kept.map(([logical, value]) => [
      ctx.config.columns[table]?.[logical] ??
        NAMES.tables[table]!.columns[logical]!,
      value,
    ]),
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
${ensureCheck(log, "bs_audit_op_check", `${c("op")} in ('insert', 'update', 'delete', 'event')`)}`
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
    ctx.has("log", "correlationId")
      ? `
create index if not exists audit_events_correlation_idx on ${log} (${c("correlationId")}) where ${c("correlationId")} is not null;`
      : ""
  }${
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

-- The request headers, or null outside a Data API request.
create or replace function better_supabase.request_headers()
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
begin
  return nullif(current_setting('request.headers', true), '')::jsonb;
exception when others then
  return null;
end;
$$;

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

${REQUEST_ID_OR_NULL}

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
  values: {
    old: string;
    new: string;
    metadata: string;
    changed?: string;
    ip?: string;
    userAgent?: string;
    sessionId?: string;
  },
): string {
  if (!restricted) return "";
  const r = (logical: string) => ctx.col("restricted", logical);
  const pairs: (readonly [string, string])[] = [
    ["entry", "entry_id"],
    ["old", values.old],
    ["new", values.new],
    ["ip", values.ip ?? "better_supabase.request_ip()"],
    ["userAgent", values.userAgent ?? requestHeader("user-agent")],
    ["metadata", values.metadata],
    ["sessionId", values.sessionId ?? "auth.jwt() ->> 'session_id'"],
    ["changedValues", values.changed ?? "null"],
  ];
  const kept = pairs.filter(
    ([logical]) => logical === "entry" || hasColumn(ctx, "restricted", logical),
  );
  return `
  insert into ${ctx.table("restricted")} (${kept.map(([logical]) => r(logical)).join(", ")})
  values (${kept.map(([, value]) => value).join(", ")});`;
}

/** `audit_event`'s restricted row, skipped when every restricted value is empty. */
function eventRestricted(ctx: ModuleContext, restricted: boolean): string {
  const insert = restrictedInsert(ctx, restricted, {
    old: "null",
    new: "null",
    metadata: "coalesce(restricted, '{}')",
    ip: "ip",
    userAgent: "user_agent",
    sessionId: "session_id",
  });
  if (insert === "") return "";
  return `
  if coalesce(restricted, '{}') <> '{}' or ip is not null or nullif(user_agent, '') is not null or nullif(session_id, '') is not null then${insert.replaceAll("\n  ", "\n    ")}
  end if;`;
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
    [
      "category",
      auditWrite(ctx, "category", "coalesce(entry.category, 'data')"),
    ],
    ["outcome", auditWrite(ctx, "outcome", "'success'")],
    ["source", auditWrite(ctx, "source", "'database'")],
    ["targetType", "coalesce(entry.target_type, tg_table_name)"],
    ...contextPairs(ctx, "row_tenant", {
      targetLabel: "row_data ->> entry.label_column",
      summary: "null",
      correlationId: correlationIdSql(ctx),
    }),
  ]);
  const tenantValue = castId(
    `row_data ->> coalesce(entry.tenant_column, ${sqlString(tenantColumn)})`,
    ctx.idType,
  );
  // The trigger reads the JWT and the request headers once per row, not once
  // per column that uses them.
  const once = (sql: string): string =>
    sql
      .replaceAll("auth.jwt()", "v_jwt")
      .replaceAll(
        /better_supabase\.request_header\(('[^']*')\)/g,
        "(v_headers ->> $1)",
      );
  const changedValues = restricted
    ? `
  -- One change per column, values cut at 1000 characters, for revealing a
  -- single change without the whole rows.
  select jsonb_object_agg(k, jsonb_build_object(
    'old', case when length((old_row -> k)::text) > 1000 then to_jsonb(left((old_row -> k)::text, 1000)) else old_row -> k end,
    'new', case when length((new_row -> k)::text) > 1000 then to_jsonb(left((new_row -> k)::text, 1000)) else new_row -> k end
  ))
  into changed_values
  from unnest(coalesce(changed_columns, array(select jsonb_object_keys(coalesce(new_row, old_row))))) k;`
    : "";
  return `create or replace function better_supabase.audit_row_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  entry record;
  settings jsonb;
  entry_id ${ctx.table("log")}.${ctx.col("log", "id")}%type;
  old_row jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  new_row jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  row_data jsonb := coalesce(new_row, old_row);
  changed_columns text[];
  changed_values jsonb;
  row_tenant ${ctx.idType};
  v_jwt jsonb := auth.jwt();
  v_headers jsonb := better_supabase.request_headers();
begin
  if tg_nargs > 0 then
    settings := tg_argv[0]::jsonb;
    select array(select jsonb_array_elements_text(coalesce(settings -> 'ignore', '[]'))) as ignore,
      coalesce(
        nullif(array(select jsonb_array_elements_text(coalesce(settings -> 'key_columns', '[]'))), '{}'),
        (select array_agg(c.attname::text order by k.ord)
         from pg_catalog.pg_index i
         cross join lateral unnest(i.indkey) with ordinality k(attnum, ord)
         join pg_catalog.pg_attribute c on c.attrelid = i.indrelid and c.attnum = k.attnum
         where i.indrelid = tg_relid and i.indisprimary),
        '{id}'
      ) as key_columns,
      array(select jsonb_array_elements_text(coalesce(settings -> 'redact', '[]'))) as redact,
      settings ->> 'category' as category, settings ->> 'event_prefix' as event_prefix,
      settings ->> 'target_type' as target_type, settings ->> 'tenant_column' as tenant_column,
      settings ->> 'label_column' as label_column
    into entry;
  else
    select coalesce(a.ignore, '{}') as ignore, coalesce(a.key_columns, '{id}') as key_columns,
      coalesce(a.redact, '{}') as redact, a.category, a.event_prefix, a.target_type, a.tenant_column,
      a.label_column
    into entry
    from (select 1) one
    left join better_supabase.audited_tables a on a.target = tg_relid::regclass;
  end if;
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
  new_row := new_row || coalesce((select jsonb_object_agg(k, '"[redacted]"'::jsonb) from unnest(entry.redact) k where new_row ? k), '{}');${changedValues}
  insert into ${ctx.table("log")} (${insert.columns})
  values (
    ${once(insert.values)}
  )
  returning ${ctx.col("log", "id")} into entry_id;${once(restrictedInsert(ctx, restricted, { old: "old_row", new: "new_row", metadata: "'{}'::jsonb", changed: "changed_values" }))}
  return null;
end;
$$;`;
}

/** `audit_event`'s argument types. */
const EVENT_ARGS = (id: string): string =>
  `text, text, text, text, text, text, ${id}, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text`;

const PREVIOUS_EVENT_ARGS = (id: string): readonly string[] => [
  `text, text, text, text, text, text, ${id}, jsonb, text, jsonb, uuid, text, text, text`,
  `text, text, text, text, text, text, ${id}, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text`,
];

function auditEvent(ctx: ModuleContext, restricted: boolean): string {
  const id = ctx.idType;
  const extra = metadataColumns(ctx);
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
      auditWrite(
        ctx,
        "category",
        `coalesce(category, ${sqlString(ctx.text("eventCategory", "system"))})`,
      ),
    ],
    ["outcome", auditWrite(ctx, "outcome", "coalesce(outcome, 'success')")],
    [
      "source",
      auditWrite(
        ctx,
        "source",
        `coalesce(source, ${sqlString(ctx.text("eventSource", "app"))})`,
      ),
    ],
    ["targetType", "target_type"],
    ["metadata", storedMetadata(ctx, extra)],
    ["idempotencyKey", "idempotency_key"],
    ...contextPairs(ctx, "tenant", {
      targetLabel: "target_label",
      summary: "summary",
      correlationId: `coalesce(better_supabase.request_id_or_null(correlation_id), ${correlationIdSql(ctx)})`,
      actorKind: `coalesce(actor_kind, ${ACTOR_KIND})`,
      actorLabel: `coalesce(actor_label, ${ACTOR_LABEL})`,
      requestId: `coalesce(better_supabase.request_id_or_null(request_id), ${requestIdSql(ctx)})`,
      scope:
        "coalesce(audit_event.scope, case when tenant is null then 'platform' else 'tenant' end)",
    }),
  ]);
  const roles = ctx.list("eventRoles", ["service_role"]);
  const noRestricted = restricted
    ? ""
    : `
  if restricted is not null or ip is not null or user_agent is not null or session_id is not null then
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
  // The body names its own function to qualify arguments (audit_event.tenant).
  const create = (name: string, trusted: boolean): string =>
    `create or replace function better_supabase.${name}(
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
  correlation_id text default null,
  actor_kind text default null,
  actor_label text default null,
  ip inet default null,
  user_agent text default null,
  session_id text default null,
  request_id text default null,
  scope text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing text;
  entry_id ${log}.${c("id")}%type;${extra.length > 0 ? "\n  entry_row jsonb;\n  entry_columns text;" : ""}
begin${noRestricted}
  ${
    trusted
      ? "actor_id := coalesce(actor_id, auth.uid());"
      : `if not (${SERVICE_CALLER}) then
    actor_id := auth.uid();
    actor_kind := null;
    actor_label := null;
    ip := ${restricted ? "better_supabase.request_ip()" : "null"};
    user_agent := ${restricted ? requestHeader("user-agent") : "null"};
    session_id := ${restricted ? "auth.jwt() ->> 'session_id'" : "null"};
    request_id := null;
    scope := null;
  elsif actor_id is null then
    actor_id := auth.uid();
  end if;`
  }${idempotent}${eventInsert(ctx, insert, extra)}${eventRestricted(ctx, restricted)}
  return entry_id::text;
end;
$$;
`.replaceAll("audit_event.", `${name}.`);
  return `-- Records a semantic app event (invoice.sent, member.invited) next to the
-- row changes. A repeated idempotency_key returns the first entry's id.
-- actor_id, actor_kind, actor_label, ip, user_agent, session_id, request_id
-- and scope are honoured for the service role and direct admin connections,
-- which never get the request's own address, user agent or session; everyone
-- else gets auth.uid() and the request's own values. restricted goes to the
-- restricted table, with no row when every restricted value is empty; without
-- that table, passing it fails instead of dropping the details.
drop function if exists better_supabase.audit_event(text, text, text, text, text, text, ${id}, jsonb, text, jsonb, uuid);
${PREVIOUS_EVENT_ARGS(id)
  .map(
    (args) => `drop function if exists better_supabase.audit_event(${args});`,
  )
  .join("\n")}
drop function if exists better_supabase.audit_event(${EVENT_ARGS(id)});
${create("audit_event", false)}revoke execute on function better_supabase.audit_event(${EVENT_ARGS(id)}) from public, anon, authenticated;
grant execute on function better_supabase.audit_event(${EVENT_ARGS(id)}) to ${roles.map(sqlIdent).join(", ")};

-- audit_event for the app's own security definer functions: it honours
-- actor_id, actor_kind, actor_label, scope and the request details from any
-- caller, so only the owner, the service role and
-- sql.modules.audit.options.trustedRoles may execute it. A function owned by
-- postgres calls it on behalf of a client with the real actor context.
drop function if exists better_supabase.audit_event_trusted(${EVENT_ARGS(id)});
${create("audit_event_trusted", true)}revoke execute on function better_supabase.audit_event_trusted(${EVENT_ARGS(id)}) from public, anon, authenticated;
grant execute on function better_supabase.audit_event_trusted(${EVENT_ARGS(id)}) to ${["service_role", ...ctx.list("trustedRoles", [])].map(sqlIdent).join(", ")};`;
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
  -- The setting first: the owner lookup runs only for a purge.
  if tg_op = 'DELETE' and current_setting('better_supabase.audit_purge', true) = 'on' then
    if current_user = (
      select r.rolname from pg_catalog.pg_proc p
      join pg_catalog.pg_roles r on r.oid = p.proowner
      where p.oid = to_regprocedure(${purge})
    ) then
      return old;
    end if;
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
  const viewAll = modulePermission(
    ctx,
    "viewAll",
    MODULE_PERMISSIONS.audit.viewAll,
  );
  const hidden = new Set(
    impersonators(ctx) === "hide"
      ? ["impersonatedBy", "impersonationReason", "supportSession"]
      : [],
  );
  const readable = [
    ...Object.keys(NAMES.tables["log"]!.columns)
      .filter(
        (logical) => hasColumn(ctx, "log", logical) && !hidden.has(logical),
      )
      .map(c),
    ...metadataColumns(ctx).map(([column]) => sqlIdent(column)),
  ];
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
    listEntries(ctx, restricted, metadataColumns(ctx)),
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
  integrates: ["access", "organizations"],
  dependencies: (layout) =>
    layout.modules?.["audit"]?.options?.["readPolicy"] === true
      ? ["access"]
      : [],
  target: "schema",
  modes: ["managed", "adopt"],
  version: 6,
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
        "text",
        "text",
        "inet",
        "text",
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
        "Renames audit_log to audit_events (with a read-only audit_log view, dropped in 0.6), at to occurred_at, org_id to organization_id and audit_trigger() to audit_row_change(); audit() takes redact, category, event_prefix, target_type and tenant_column; audit_event() records semantic events; purge_audit_log() takes a tenant.",
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
    {
      from: 3,
      description:
        "The row trigger reads the JWT and the request headers once per row; list_audit_events and count_audit_events filter only on the arguments you pass; per-tenant retention deletes tenant by tenant through the index.",
      sql: () => "",
    },
    {
      from: 4,
      description:
        "Drops the read-only audit_log view that 0.5 kept for the 0.4 names; read better_supabase.audit_events.",
      sql: (ctx) =>
        `drop view if exists ${sqlIdent(ctx.tableName("log").schema)}.audit_log;`,
    },
    {
      from: 5,
      description:
        "Row changes and audit_event read the request and correlation ids from the better_supabase.request_id and better_supabase.correlation_id settings, then from the requestIdHeader and correlationIdHeader headers, and keep only ids of up to 128 safe characters; managed logs index correlation_id.",
      sql: () => "",
    },
  ],
  deprecated: [
    {
      kind: "table",
      symbol: "better_supabase.audit_log",
      use: "better_supabase.audit_events (occurred_at, organization_id)",
      since: "0.5.0",
      removed: "0.6.0",
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
  data: () => `-- Registrations of tables dropped before bs_audit_forget_dropped existed.
delete from better_supabase.audited_tables a
where not exists (select 1 from pg_catalog.pg_class c where c.oid = a.target::oid);`,
  tests: (ctx, layout) =>
    auditTests(ctx, layout.auditedTables ?? [], restrictedOn(ctx)),
};
