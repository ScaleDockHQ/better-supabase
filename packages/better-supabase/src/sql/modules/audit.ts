import type { AuditEvents } from "../../blocks/audit/events.ts";
import type {
  BlockSqlContext,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlLayout, BlockSqlDefinition } from "../module-types.ts";
import type { BatchArgument } from "../shared.ts";
import type { AuditInsert } from "./audit-metadata.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { ACTING_MEMBER } from "../actor-guard.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  batchFunction,
  defaultPartition,
  ensureCheck,
  EQUIVALENT_TRIGGERS,
  MONTHLY_PARTITIONS,
  registerPartitions,
  SCHEMA,
  SERVICE_CALLER,
  revokeTable,
  triggerGrant,
} from "../shared.ts";
import { listEntries, reveal } from "./audit-api.ts";
import { appendOnly } from "./audit-append-only.ts";
import {
  CHAIN_CONTRACT,
  chainOn,
  chainSql,
  partitionedOn,
} from "./audit-chain.ts";
import { hasColumn, impersonators } from "./audit-columns.ts";
import { castId, entrySql, tenantFallbackSql } from "./audit-entry.ts";
import {
  eventInsert,
  metadataColumns,
  storedMetadata,
} from "./audit-metadata.ts";
import { REGISTRY_TABLE, forgetDropped, register } from "./audit-register.ts";
import {
  correlationIdSql,
  REQUEST_ID_OR_NULL,
  requestHeader,
  requestIdSql,
} from "./audit-request.ts";
import { retention } from "./audit-retention.ts";
import { revert } from "./audit-revert.ts";
import {
  actorKind,
  requestIpSql,
  subjectColumnsSql,
} from "./audit-subjects.ts";
import { auditTests } from "./audit-tests.ts";
import { AUDIT_UPGRADES } from "./audit-upgrades.ts";
import { auditWrite, tenantLabel } from "./audit-values.ts";
import { OPERATIONS, modulePermission } from "./permissions-model.ts";

const EVENTS: BlockSqlEvents<AuditEvents> = {
  "audit.revealed": {
    subject: "audit-entries",
    payload: ["organizationId", "entries"],
  },
};

const NAMES: BlockSqlNames = {
  events: EVENTS,
  options: [
    "appendOnly",
    "blockTables",
    "chain",
    "correlationIdHeader",
    "eventCategory",
    "eventRoles",
    "trustedRoles",
    "eventSource",
    "exempt",
    "impersonators",
    "ipHeader",
    "keepMappedMetadata",
    "metadataColumns",
    "partitioned",
    "readPolicy",
    "requestIdHeader",
    "restricted",
    "staffClaim",
    "subjectColumns",
    "tenantColumn",
    "tenantLabel",
    "tenantLabelKey",
    "values",
  ],
  tables: {
    log: {
      name: "audit_events",
      app: {},
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
      app: { onlyWhenMapped: true },
    },
    registry: REGISTRY_TABLE,
  },
  hooks: ["audit_retention"],
};

const ACTOR_LABEL = `coalesce(auth.jwt() -> 'user_metadata' ->> 'full_name', auth.jwt() ->> 'email')`;

/** The pairs every entry writes for the version 3 columns. */
function contextPairs(
  ctx: BlockSqlContext,
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
    [
      "actorKind",
      auditWrite(ctx, "actorKind", values.actorKind ?? actorKind(ctx)),
    ],
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

/**
 * The restricted table is in use: an option when managed, a mapping when
 * adopted.
 */
function restrictedOn(ctx: BlockSqlContext): boolean {
  return ctx.owns("log")
    ? ctx.flag("restricted", false)
    : !ctx.owns("restricted") && ctx.hasTable("restricted");
}

/** `[column, value]` pairs for the logical columns the log has. */
function present(
  ctx: BlockSqlContext,
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

/** `subjectColumns`: indexed columns generated from the row and event JSON. */
function subjects(ctx: BlockSqlContext, log: string): string {
  const sources = (["new", "old", "metadata"] as const)
    .filter((logical) => ctx.has("log", logical))
    .map((logical) => ctx.col("log", logical));

  const taken = [
    ...Object.keys(NAMES.tables["log"]!.columns).map(
      (logical) =>
        ctx.config.columns["log"]?.[logical] ??
        NAMES.tables["log"]!.columns[logical]!,
    ),
    ...metadataColumns(ctx).map(([column]) => column),
  ];

  return subjectColumnsSql(ctx, log, sources, taken);
}

function managedTables(ctx: BlockSqlContext, restricted: boolean): string {
  const log = ctx.table("log");
  const partitioned = partitionedOn(ctx);
  const sequence = `better_supabase.${ctx.naming.rename("audit_events_id_seq")}`;
  const fallback = `better_supabase.${ctx.naming.rename("audit_events_default")}`;
  const c = (logical: string) => ctx.col("log", logical);
  const subjectDdl = subjects(ctx, log);

  const line = (logical: string, definition: string) =>
    ctx.has("log", logical) ? `\n  ${c(logical)} ${definition},` : "";

  const add = (logical: string, definition: string) =>
    ctx.has("log", logical)
      ? `\nalter table ${log} add column if not exists ${c(logical)} ${definition};`
      : "";

  const op = ctx.has("log", "op")
    ? `
alter table ${log} drop constraint if exists audit_log_op_check;
${ensureCheck(log, "bsb_audit_op_check", `${c("op")} in ('insert', 'update', 'delete', 'event')`)}`
    : "";

  const table = ctx.has("log", "table")
    ? `\nalter table ${log} alter column ${c("table")} drop not null;`
    : "";

  const restrictedTable = restricted
    ? `
create table if not exists ${ctx.table("restricted")} (
  ${ctx.col("restricted", "entry")} bigint primary key${partitioned ? "" : ` references ${log} (${c("id")}) on delete cascade`},
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
${revokeTable(ctx.table("restricted"))}`
    : "";

  const head = partitioned
    ? `-- Partitioned by month on occurred_at: the key includes it, and a purge
-- drops whole months. A log created before the option stays as it is.
create sequence if not exists ${sequence};
create table if not exists ${log} (
  ${c("id")} bigint not null default nextval('${sequence}'),`
    : `create table if not exists ${log} (
  ${c("id")} bigint generated always as identity primary key,`;

  const tail = partitioned
    ? `,
  primary key (${c("id")}, ${c("occurredAt")})
) partition by range (${c("occurredAt")});
${defaultPartition(log, fallback)}`
    : `
);`;

  return `${head}${line("table", "text")}${line("record", "text")}${line("op", "text not null")}${line("old", "jsonb")}${line("new", "jsonb")}${line("changed", "text[]")}${line("actor", "uuid")}${line("actorRole", "text")}
  ${c("tenant")} ${ctx.idType},
  ${c("occurredAt")} timestamptz not null default now()${tail}${op}${table}
-- Set when an admin acted as the user (the act claim).${add("impersonatedBy", "uuid")}${add("impersonationReason", "text")}${add("supportSession", "uuid")}
-- Semantic events (audit_event) and the per-table registry fill these.${add("eventType", "text")}${add("category", "text")}${add("outcome", "text")}${add("source", "text")}${add("targetType", "text")}${add("metadata", "jsonb")}${add("idempotencyKey", "text")}
-- Who acted and on what, as it was then, for audit pages.${add("actorKind", "text")}${add("actorLabel", "text")}${add("tenantLabel", "text")}${add("targetLabel", "text")}${add("summary", "text")}${add("requestId", "text")}${add("correlationId", "text")}${add("scope", "text")}
${
  ctx.has("log", "table") && ctx.has("log", "record")
    ? `create index if not exists audit_events_record_idx on ${log} (${c("table")}, ${c("record")}, ${c("occurredAt")} desc);\n`
    : ""
}create index if not exists ${ctx.naming.rename("audit_events_organization_idx")} on ${log} (${c("tenant")}, ${c("occurredAt")} desc);
create index if not exists audit_events_occurred_at_idx on ${log} (${c("occurredAt")});${
    ctx.has("log", "correlationId")
      ? `
create index if not exists audit_events_correlation_idx on ${log} (${c("correlationId")}) where ${c("correlationId")} is not null;`
      : ""
  }${
    ctx.has("log", "idempotencyKey")
      ? `
create ${partitioned ? "" : "unique "}index if not exists audit_events_idempotency_idx on ${log} (${c("idempotencyKey")}, ${c("tenant")}) nulls not distinct where ${c("idempotencyKey")} is not null;`
      : ""
  }
${subjectDdl === "" ? "" : `${subjectDdl}\n`}alter table ${log} enable row level security;
${revokeTable(log)}
grant select on ${log} to service_role;${restrictedTable}${
    partitioned ? `\n\n${MONTHLY_PARTITIONS}\n${registerPartitions(log)}` : ""
  }`;
}

function registry(ctx: BlockSqlContext): string {
  const table = ctx.table("registry");
  const r = (logical: string) => ctx.col("registry", logical);

  const add = (logical: string, definition: string) =>
    ctx.has("registry", logical)
      ? `\nalter table ${table} add column if not exists ${r(logical)} ${definition};`
      : "";

  return `create table if not exists ${table} (
  ${r("target")} regclass primary key${ctx.has("registry", "ignore") ? `,\n  ${r("ignore")} text[] not null default '{}'` : ""}
);${
    ctx.has("registry", "keyColumns")
      ? `
-- The primary key columns, read when the table is registered; composite keys are joined with ','.${add("keyColumns", "text[] not null default '{id}'")}`
      : ""
  }
-- Per-table event naming and redaction.${add("redact", "text[] not null default '{}'")}${add("category", "text")}${add("eventPrefix", "text")}${add("targetType", "text")}${add("tenantColumn", "text")}${add("labelColumn", "text")}
alter table ${table} enable row level security;
${revokeTable(table)}

${ACTING_MEMBER}

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

${REQUEST_ID_OR_NULL}`;
}

/**
 * SQL that writes the restricted details of `entry_id`, when the table is in
 * use.
 */
function restrictedInsert(
  ctx: BlockSqlContext,
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
  if (!restricted) {
    return "";
  }

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
function eventRestricted(ctx: BlockSqlContext, restricted: boolean): string {
  const insert = restrictedInsert(ctx, restricted, {
    old: "null",
    new: "null",
    metadata: "coalesce(restricted, '{}')",
    ip: "ip",
    userAgent: "user_agent",
    sessionId: "session_id",
  });

  if (insert === "") {
    return "";
  }

  return `
  if coalesce(restricted, '{}') <> '{}' or ip is not null or nullif(user_agent, '') is not null or nullif(session_id, '') is not null then${insert.replaceAll("\n  ", "\n    ")}
  end if;`;
}

function triggerFunction(
  ctx: BlockSqlContext,
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
    ["actor", "coalesce(auth.uid(), better_supabase.acting_member())"],
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
  path_value text;
  path_step jsonb;
begin
  -- An import run with imports.audit 'summary' audits one entry per entity at
  -- its end instead of one per row (ADR 0141).
  if current_setting('better_supabase.import_audit', true) = 'summary' and better_supabase.import_run() is not null then
    return null;
  end if;
${entrySql(ctx)}
  row_tenant := ${tenantValue};
${tenantFallbackSql(ctx.idType)}
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
$$;
${triggerGrant("better_supabase.audit_row_change()")}`;
}

/** `audit_event`'s argument types. */
const EVENT_ARGS = (id: string): string =>
  `text, text, text, text, text, text, ${id}, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text, uuid, uuid, text`;

/** `audit_event`'s arguments, as the keys of an `audit_event_many` element. */
const EVENT_KEYS = (id: string): readonly BatchArgument[] => [
  ["event_type", "text"],
  ["category", "text"],
  ["outcome", "text", "'success'"],
  ["source", "text"],
  ["target_type", "text"],
  ["record_id", "text"],
  ["tenant", id],
  ["metadata", "jsonb", "'{}'"],
  ["idempotency_key", "text"],
  ["restricted", "jsonb"],
  ["actor_id", "uuid"],
  ["summary", "text"],
  ["target_label", "text"],
  ["correlation_id", "text"],
  ["actor_kind", "text"],
  ["actor_label", "text"],
  ["ip", "inet"],
  ["user_agent", "text"],
  ["session_id", "text"],
  ["request_id", "text"],
  ["scope", "text"],
  ["support_session", "uuid"],
  ["impersonated_by", "uuid"],
  ["impersonation_reason", "text"],
];

const PREVIOUS_EVENT_ARGS = (id: string): readonly string[] => [
  `text, text, text, text, text, text, ${id}, jsonb, text, jsonb, uuid, text, text, text`,
  `text, text, text, text, text, text, ${id}, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text`,
  `text, text, text, text, text, text, ${id}, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text`,
];

/** `audit_event_trusted`'s signatures before the current one. */
const PREVIOUS_TRUSTED_ARGS = (id: string): readonly string[] => [
  `text, text, text, text, text, text, ${id}, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text`,
];

function auditEvent(ctx: BlockSqlContext, restricted: boolean): string {
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
      "coalesce(audit_event.impersonated_by, case when auth.jwt() -> 'act' ->> 'sub' ~ '^[0-9a-f-]{36}$' then (auth.jwt() -> 'act' ->> 'sub')::uuid end)",
    ],
    [
      "impersonationReason",
      "coalesce(audit_event.impersonation_reason, auth.jwt() -> 'act' ->> 'reason')",
    ],
    [
      "supportSession",
      "coalesce(audit_event.support_session, case when auth.jwt() -> 'act' ->> 'session_id' ~ '^[0-9a-f-]{36}$' then (auth.jwt() -> 'act' ->> 'session_id')::uuid end)",
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
      actorKind: `coalesce(actor_kind, ${actorKind(ctx)})`,
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
        ctx.owns("log")
          ? "Set blocks.audit.options.restricted to true."
          : "Map blocks.audit.tables.restricted to the table for sensitive details.",
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
  scope text default null,
  support_session uuid default null,
  impersonated_by uuid default null,
  impersonation_reason text default null
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
  -- imports.audit 'summary' (ADR 0141): the run audits per entity at its end.
  if current_setting('better_supabase.import_audit', true) = 'summary' and better_supabase.import_run() is not null then
    return null;
  end if;
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
    if (select auth.jwt()) -> 'act' is not null or impersonated_by is distinct from auth.uid() then
      support_session := null;
      impersonated_by := null;
      impersonation_reason := null;
    end if;
  elsif actor_id is null then
    actor_id := coalesce(auth.uid(), better_supabase.acting_member());
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
-- else gets auth.uid() and the request's own values. support_session,
-- impersonated_by and impersonation_reason fill the impersonation columns;
-- other callers may only name themselves as impersonated_by, from a token
-- without an act claim (an admin starting or ending their own support
-- session), and otherwise get the act claim's values. restricted goes to the
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

-- audit_event for a batch of events in one call (the outbox sink): each
-- element takes audit_event's argument names as keys, keeps its checks and
-- returns {"id"} or {"error"} in order.
${batchFunction({
  name: "better_supabase.audit_event_many",
  call: "better_supabase.audit_event",
  args: EVENT_KEYS(id),
  returns: "text",
  result: "id",
  hint: "AUDIT_BATCH",
})}
revoke execute on function better_supabase.audit_event_many(jsonb) from public, anon, authenticated;
grant execute on function better_supabase.audit_event_many(jsonb) to ${roles.map(sqlIdent).join(", ")};

-- audit_event for the app's own security definer functions: it honours
-- actor_id, actor_kind, actor_label, scope and the request details from any
-- caller, so only the owner, the service role and
-- blocks.audit.options.trustedRoles may execute it. A function owned by
-- postgres calls it on behalf of a client with the real actor context.
${PREVIOUS_TRUSTED_ARGS(id)
  .map(
    (args) =>
      `drop function if exists better_supabase.audit_event_trusted(${args});`,
  )
  .join("\n")}
drop function if exists better_supabase.audit_event_trusted(${EVENT_ARGS(id)});
${create("audit_event_trusted", true)}revoke execute on function better_supabase.audit_event_trusted(${EVENT_ARGS(id)}) from public, anon, authenticated;
grant execute on function better_supabase.audit_event_trusted(${EVENT_ARGS(id)}) to ${["service_role", ...ctx.list("trustedRoles", [])].map(sqlIdent).join(", ")};`;
}

function readPolicy(ctx: BlockSqlContext): string {
  const log = ctx.table("log");

  if (!ctx.flag("readPolicy", false)) {
    return ctx.owns("log")
      ? `drop policy if exists bsb_audit_read on ${log};
drop function if exists ${ctx.fn("audit_read_tenants")}();
drop function if exists ${ctx.fn("audit_reads_all")}();`
      : "";
  }

  const c = (logical: string) => ctx.col("log", logical);
  const view = ctx.permission("view", OPERATIONS["audit.view"]);
  const viewAll = modulePermission(ctx, "viewAll", OPERATIONS["audit.viewAll"]);

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

  return `-- Members read their tenant's entries with the ${ctx.permissionKey("view", OPERATIONS["audit.view"])} permission;
-- platform staff read every entry. PL/pgSQL resolves tenant_ids_with and
-- is_platform when it runs, so this file installs before the access module's.
create or replace function ${ctx.fn("audit_read_tenants")}()
returns setof ${ctx.idType}
language plpgsql
stable
set search_path = ''
as $$
begin
  return query select t::${ctx.idType} from ${ctx.scope.ids(view)} t;
end;
$$;
create or replace function ${ctx.fn("audit_reads_all")}()
returns boolean
language plpgsql
stable
set search_path = ''
as $$
begin
  return ${ctx.scope.platform(viewAll)};
end;
$$;
revoke execute on function ${ctx.fn("audit_read_tenants")}() from public, anon;
revoke execute on function ${ctx.fn("audit_reads_all")}() from public, anon;
grant execute on function ${ctx.fn("audit_read_tenants")}() to authenticated, service_role;
grant execute on function ${ctx.fn("audit_reads_all")}() to authenticated, service_role;
${renderPolicy(
  makePolicy({
    table: log,
    name: "bsb_audit_read",
    command: "select",
    roles: ["authenticated"],
    using: `${c("tenant")} in (select ${ctx.fn("audit_read_tenants")}())
    or (select ${ctx.fn("audit_reads_all")}())`,
  }),
  { drop: true, target: log },
)}
${
  hidden.size > 0
    ? `revoke select on ${log} from authenticated;
-- impersonators: "hide" leaves out who acted as the user.
grant select (${readable.join(", ")}) on ${log} to authenticated;`
    : `grant select on ${log} to authenticated;`
}`;
}

function auditSql(ctx: BlockSqlContext, layout: BlockSqlLayout): string {
  const restricted = restrictedOn(ctx);

  const tenantColumn = ctx.text(
    "tenantColumn",
    layout.tenantColumn ?? "organization_id",
  );

  return [
    SCHEMA,
    registry(ctx),
    requestIpSql(ctx),
    ctx.manages ? managedTables(ctx, restricted) : "",
    triggerFunction(ctx, tenantColumn, restricted),
    EQUIVALENT_TRIGGERS.trim(),
    register(ctx),
    auditEvent(ctx, restricted),
    appendOnly(ctx),
    chainSql(ctx),
    readPolicy(ctx),
    retention(ctx),
    listEntries(ctx, restricted, metadataColumns(ctx)),
    reveal(ctx, restricted),
    revert(ctx, restricted),
  ]
    .filter(Boolean)
    .join("\n\n");
}

export const AUDIT: BlockSqlDefinition = {
  name: "audit",
  title: "Audit log",
  description:
    "Records inserts, updates and deletes with the actor and changed columns for tables you register, plus semantic events through audit_event(), with redaction, an append-only guard, a tenant read policy and per-tenant retention as options.",
  requires: [],
  integrates: ["permissions", "organizations", "data-lifecycle"],
  dependencies: (layout) =>
    layout.modules?.["audit"]?.options?.["readPolicy"] === true
      ? ["permissions"]
      : [],
  target: "schema",
  modes: ["managed"],
  version: 9,
  names: NAMES,
  contract: (ctx) => [
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
        "uuid",
        "uuid",
        "text",
      ],
      returns: "text",
    },
    { name: "audit_event_many", args: ["jsonb"], returns: "jsonb" },
    {
      name: "purge_audit_log",
      args: ["interval", "integer", "{id}", "boolean"],
      returns: "integer",
    },
    ...(chainOn(ctx) ? CHAIN_CONTRACT : []),
  ],
  upgrades: AUDIT_UPGRADES,
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
  data: (
    ctx,
  ) => `-- Registrations of tables dropped before bsb_audit_forget_dropped existed.
${forgetDropped(ctx)}`,
  tests: (ctx, layout) =>
    auditTests(ctx, layout.auditedTables ?? [], restrictedOn(ctx)),
};
