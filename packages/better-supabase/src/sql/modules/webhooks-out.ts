import type { WebhooksEvents } from "../../blocks/webhooks/events.ts";
import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleEvents,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition, ModuleLayout } from "../module-types.ts";
import type { HookNames } from "./webhooks-out-sql.ts";

import { sqlIdent } from "../../core/template.ts";
import {
  defaultPartition,
  defaultPartitionName,
  lockTable,
  MONTHLY_PARTITIONS,
  registerPartitions,
  schemaPreamble,
  updatedAt,
} from "../shared.ts";
import {
  ADDED_COLUMNS,
  functions,
  hookNames,
  WEBHOOK_STATUSES,
} from "./webhooks-out-sql.ts";

const EVENTS: ModuleEvents<WebhooksEvents> = {
  "webhook.disabled": {
    subject: "webhooks",
    payload: ["endpointId", "organizationId", "failingSince"],
    retries: true,
  },
  "webhook.secret_rotated": {
    subject: "webhooks",
    payload: ["endpointId", "organizationId"],
  },
};

const NAMES: ModuleNames = {
  events: EVENTS,
  options: [
    "allowHttp",
    "defaultFormat",
    "disableAfter",
    "eventIdType",
    "partitioned",
    "runIdType",
    "secretStorage",
    "statuses",
  ],
  tables: {
    endpoints: {
      name: "webhook_endpoints",
      lifecycle: { tenant: "tenant", credentials: ["credentialRef"] },
      columns: {
        id: "id",
        tenant: "organization_id",
        name: "name",
        url: "url",
        enabled: "enabled",
        eventTypes: "event_types",
        permissions: "permissions",
        batch: "batch",
        signing: "signing",
        format: "format",
        credentialRef: "credential_ref",
        failingSince: "failing_since",
        disabledAt: "disabled_at",
        disabledReason: "disabled_reason",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: [
        "tenant",
        "name",
        "permissions",
        "batch",
        "signing",
        "format",
        "credentialRef",
        "failingSince",
        "disabledAt",
        "disabledReason",
        "createdBy",
        "updatedAt",
      ],
    },
    secrets: {
      name: "webhook_endpoint_secrets",
      // Purged with the tenant (a trigger drops the Vault secret), never exported.
      lifecycle: { tenant: "tenant", export: false },
      columns: {
        id: "id",
        endpoint: "endpoint_id",
        tenant: "organization_id",
        secret: "secret",
        vaultId: "vault_secret_id",
        expiresAt: "expires_at",
        createdAt: "created_at",
      },
      optional: ["tenant", "secret", "vaultId", "expiresAt"],
    },
    deliveries: {
      name: "webhook_deliveries",
      lifecycle: { tenant: "tenant" },
      columns: {
        id: "id",
        tenant: "organization_id",
        endpoint: "endpoint_id",
        event: "event_id",
        run: "run_id",
        type: "event_type",
        subject: "subject",
        payload: "payload",
        status: "status",
        attempt: "attempt",
        availableAt: "available_at",
        leasedUntil: "leased_until",
        responseStatus: "response_status",
        responseBody: "response_body",
        durationMs: "duration_ms",
        lastError: "last_error",
        processedAt: "processed_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: [
        "tenant",
        "event",
        "run",
        "subject",
        "responseStatus",
        "responseBody",
        "durationMs",
        "lastError",
        "processedAt",
        "updatedAt",
      ],
    },
  },
  hooks: ["after_webhook_delivery"],
};

const FORMAT = /^[a-z][a-z0-9-]{0,39}$/;

/** `blocks.webhooks-out.options.defaultFormat`, checked before it reaches SQL. */
function defaultFormat(ctx: ModuleContext): string {
  const format = ctx.text("defaultFormat", "cloudevents");

  if (!FORMAT.test(format)) {
    throw new TypeError(
      `blocks.webhooks-out.options.defaultFormat "${format}" must match ${String(FORMAT)}`,
    );
  }

  return format;
}

const formatColumn = (column: string, fallback: string): string =>
  `text not null default '${fallback}' check (${column} ~ '^[a-z][a-z0-9-]{0,39}$')`;

/**
 * The column default follows `defaultFormat`; `add column` alone keeps the
 * default of the table that first had the column.
 */
function formatDefault(ctx: ModuleContext, n: HookNames): string {
  return n.has("endpoints", "format")
    ? `alter table ${n.table("endpoints")} alter column ${n.col("endpoints", "format")} set default '${defaultFormat(ctx)}';\n`
    : "";
}

export const ADOPTED_FORMAT_ERROR =
  'blocks.webhooks-out: the adopted endpoints table maps no format column, so every endpoint gets options.defaultFormat. Set it explicitly: "standard" keeps the 0.8 body, "cloudevents" sends CloudEvents. Or map columns.endpoints.format.';

/**
 * Without a format column every endpoint uses `defaultFormat`, whose default
 * changed from the 0.8 body to `cloudevents` in 0.9, so an adopted table has to
 * choose it.
 */
function requireAdoptedFormat(ctx: ModuleContext, n: HookNames): void {
  if (
    ctx.mode === "adopt" &&
    !n.has("endpoints", "format") &&
    ctx.option("defaultFormat") === undefined
  ) {
    throw new TypeError(ADOPTED_FORMAT_ERROR);
  }
}

/** `add column if not exists` for columns a table created by version 2 lacks. */
function added(
  n: HookNames,
  table: string,
  columns: readonly (readonly [string, string])[],
): string {
  return columns
    .filter(([logical]) => n.has(table, logical))
    .map(
      ([logical, definition]) =>
        `alter table ${n.table(table)} add column if not exists ${n.col(table, logical)} ${definition};\n`,
    )
    .join("");
}

function tables(ctx: ModuleContext, n: HookNames): string {
  if (!ctx.manages) {
    return "";
  }

  const id = ctx.idType;
  const d = (logical: string) => n.col("endpoints", logical);
  const s = (logical: string) => n.col("secrets", logical);
  const v = (logical: string) => n.col("deliveries", logical);

  const opt = (table: string, logical: string, definition: string) =>
    n.has(table, logical) ? [`${n.col(table, logical)} ${definition}`] : [];

  const policy = (table: string, name: string, body: string) => `
drop policy if exists ${sqlIdent(name)} on ${n.table(table)};
create policy ${sqlIdent(name)} on ${n.table(table)} ${body};`;

  const scoped = n.clientAccess;
  const signingType = `text not null default 'v1' check (${d("signing")} in ('v1', 'v1a'))`;
  const formatType = formatColumn(d("format"), defaultFormat(ctx));
  const credentialRefType = `jsonb check (${d("credentialRef")} is null or (jsonb_typeof(${d("credentialRef")}) = 'object' and ${d("credentialRef")} ? 'provider'))`;

  const urlCheck = n.allowHttp
    ? `check (${d("url")} ~* '^https?://')`
    : `check (${d("url")} ~* '^https://')`;

  const endpoints = `
create table if not exists ${n.table("endpoints")} (
  ${[
    `${d("id")} uuid primary key default gen_random_uuid()`,
    ...opt("endpoints", "tenant", `${id} not null`),
    ...opt(
      "endpoints",
      "name",
      `text not null check (length(trim(${d("name")})) > 0)`,
    ),
    `${d("url")} text not null ${urlCheck}`,
    `${d("enabled")} boolean not null default true`,
    `${d("eventTypes")} text[] not null default '{}'`,
    ...opt("endpoints", "permissions", "text[]"),
    ...opt("endpoints", "batch", "boolean not null default false"),
    ...opt("endpoints", "signing", signingType),
    ...opt("endpoints", "format", formatType),
    ...opt("endpoints", "credentialRef", credentialRefType),
    ...opt("endpoints", "failingSince", "timestamptz"),
    ...opt("endpoints", "disabledAt", "timestamptz"),
    ...opt("endpoints", "disabledReason", "text"),
    ...opt(
      "endpoints",
      "createdBy",
      "uuid references auth.users (id) on delete set null default auth.uid()",
    ),
    `${d("createdAt")} timestamptz not null default now()`,
    ...opt("endpoints", "updatedAt", "timestamptz not null default now()"),
  ].join(",\n  ")}
);
${added(n, "endpoints", [
  ["permissions", "text[]"],
  ["batch", "boolean not null default false"],
  ["signing", signingType],
  ["format", formatType],
  ["credentialRef", credentialRefType],
])}${formatDefault(ctx, n)}create index if not exists webhook_endpoints_types_idx on ${n.table("endpoints")} using gin (${d("eventTypes")});
${n.has("endpoints", "tenant") ? `create index if not exists webhook_endpoints_tenant_idx on ${n.table("endpoints")} (${d("tenant")});\n` : ""}${n.has("endpoints", "createdBy") ? `create index if not exists webhook_endpoints_created_by_idx on ${n.table("endpoints")} (${d("createdBy")});\n` : ""}${n.has("endpoints", "updatedAt") ? `${updatedAt(n.table("endpoints"), d("updatedAt"))}\n` : ""}${lockTable(n.table("endpoints"))}${
    scoped
      ? `
grant select, insert, update, delete on ${n.table("endpoints")} to authenticated;${policy(
          "endpoints",
          "bsb_webhook_endpoints_read",
          `for select to authenticated using (${n.member(d("tenant"), "view")})`,
        )}
drop policy if exists bsb_webhook_endpoints_write on ${n.table("endpoints")};${policy(
          "endpoints",
          "bsb_webhook_endpoints_insert",
          `for insert to authenticated with check (${n.member(d("tenant"), "manage")})`,
        )}${policy(
          "endpoints",
          "bsb_webhook_endpoints_update",
          `for update to authenticated using (${n.member(d("tenant"), "manage")}) with check (${n.member(d("tenant"), "manage")})`,
        )}${policy(
          "endpoints",
          "bsb_webhook_endpoints_delete",
          `for delete to authenticated using (${n.member(d("tenant"), "manage")})`,
        )}`
      : ""
  }`;

  const secrets = `
create table if not exists ${n.table("secrets")} (
  ${[
    `${s("id")} uuid primary key default gen_random_uuid()`,
    `${s("endpoint")} uuid not null references ${n.table("endpoints")} (${d("id")}) on delete cascade`,
    ...opt("secrets", "tenant", id),
    ...(n.vault
      ? [`${s("vaultId")} uuid not null`]
      : [`${s("secret")} text not null`]),
    ...opt("secrets", "expiresAt", "timestamptz"),
    `${s("createdAt")} timestamptz not null default now()`,
  ].join(",\n  ")}
);
create index if not exists webhook_endpoint_secrets_endpoint_idx on ${n.table("secrets")} (${s("endpoint")});
${lockTable(n.table("secrets"))}`;

  const fallback = defaultPartitionName(ctx.tableName("deliveries"));

  const deliveries = `
create table if not exists ${n.table("deliveries")} (
  ${[
    n.partitioned
      ? `${v("id")} uuid not null default gen_random_uuid()`
      : `${v("id")} uuid primary key default gen_random_uuid()`,
    ...opt("deliveries", "tenant", id),
    `${v("endpoint")} uuid not null references ${n.table("endpoints")} (${d("id")}) on delete cascade`,
    ...opt("deliveries", "event", n.eventIdType),
    ...opt("deliveries", "run", n.runIdType),
    `${v("type")} text not null`,
    ...opt("deliveries", "subject", "text"),
    `${v("payload")} jsonb not null default '{}'`,
    `${v("status")} text not null default 'pending' check (${v("status")} in (${WEBHOOK_STATUSES.map((status) => `'${status}'`).join(", ")}))`,
    `${v("attempt")} integer not null default 0 check (${v("attempt")} >= 0)`,
    `${v("availableAt")} timestamptz not null default now()`,
    `${v("leasedUntil")} timestamptz`,
    ...opt("deliveries", "responseStatus", "integer"),
    ...opt("deliveries", "responseBody", "text"),
    ...opt("deliveries", "durationMs", "integer"),
    ...opt("deliveries", "lastError", "text"),
    ...opt("deliveries", "processedAt", "timestamptz"),
    `${v("createdAt")} timestamptz not null default now()`,
    ...opt("deliveries", "updatedAt", "timestamptz not null default now()"),
    ...(n.partitioned ? [`primary key (${v("id")}, ${v("createdAt")})`] : []),
  ].join(",\n  ")}
)${n.partitioned ? ` partition by range (${v("createdAt")});\n${defaultPartition(n.table("deliveries"), fallback)}` : ";"}
${added(n, "deliveries", [["subject", "text"]])}create index if not exists webhook_deliveries_due_idx on ${n.table("deliveries")} (${v("availableAt")}, ${v("leasedUntil")}) where ${v("status")} in ('pending', 'retrying', 'delivering');
create index if not exists webhook_deliveries_endpoint_idx on ${n.table("deliveries")} (${v("endpoint")}, ${v("createdAt")} desc);
create index if not exists webhook_deliveries_open_idx on ${n.table("deliveries")} (${v("endpoint")}) where ${v("status")} in ('pending', 'retrying');
create index if not exists webhook_deliveries_finished_idx on ${n.table("deliveries")} (${v("createdAt")}) where ${v("status")} in (${n.status("succeeded")}, ${n.status("canceled")}, ${n.status("dead")});${
    n.has("deliveries", "tenant")
      ? `
create index if not exists webhook_deliveries_tenant_created_idx on ${n.table("deliveries")} (${v("tenant")}, ${v("createdAt")} desc);`
      : ""
  }${
    n.has("deliveries", "event")
      ? `
create ${n.partitioned ? "" : "unique "}index if not exists webhook_deliveries_endpoint_event_idx on ${n.table("deliveries")} (${v("endpoint")}, ${v("event")}) where ${v("event")} is not null;`
      : ""
  }
${lockTable(n.table("deliveries"))}${
    scoped
      ? `
grant select on ${n.table("deliveries")} to authenticated;${policy(
          "deliveries",
          "bsb_webhook_deliveries_read",
          `for select to authenticated using (${n.member(v("tenant"), "view")})`,
        )}`
      : ""
  }${n.partitioned ? `\n\n${MONTHLY_PARTITIONS}\n${registerPartitions(n.table("deliveries"))}` : ""}`;

  return [endpoints, secrets, deliveries].join("\n");
}

/** Re-enabling an endpoint clears its failure streak. */
function reenable(ctx: ModuleContext, n: HookNames): string {
  const d = (logical: string) => n.col("endpoints", logical);

  const resets = [
    n.has("endpoints", "failingSince")
      ? `new.${d("failingSince")} := null;`
      : "",
    n.has("endpoints", "disabledAt") ? `new.${d("disabledAt")} := null;` : "",
    n.has("endpoints", "disabledReason")
      ? `new.${d("disabledReason")} := null;`
      : "",
  ].filter(Boolean);

  const trigger = ctx.trigger("webhook_endpoint_reenable");

  if (resets.length === 0) {
    return `drop trigger if exists ${trigger} on ${n.table("endpoints")};`;
  }

  return `
create or replace function ${ctx.fn("reset_webhook_endpoint")}()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.${d("enabled")} and not old.${d("enabled")} then
    ${resets.join("\n    ")}
  end if;
  return new;
end;
$$;
revoke execute on function ${ctx.fn("reset_webhook_endpoint")}() from public, anon, authenticated;
drop trigger if exists ${trigger} on ${n.table("endpoints")};
create trigger ${trigger} before update of ${d("enabled")} on ${n.table("endpoints")}
  for each row execute function ${ctx.fn("reset_webhook_endpoint")}();`;
}

/** Deleting a secret row (or its endpoint) deletes its Vault secret. */
function vaultCleanup(ctx: ModuleContext, n: HookNames): string {
  const t = n.table("secrets");
  const trigger = ctx.trigger("webhook_secret_vault");

  if (!n.vault) {
    return `drop trigger if exists ${trigger} on ${t};`;
  }

  return `
create or replace function ${ctx.fn("drop_webhook_vault_secret")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from vault.secrets vs where vs.id = old.${n.col("secrets", "vaultId")};
  return null;
end;
$$;
revoke execute on function ${ctx.fn("drop_webhook_vault_secret")}() from public, anon, authenticated;
drop trigger if exists ${trigger} on ${t};
create trigger ${trigger} after delete on ${t}
  for each row execute function ${ctx.fn("drop_webhook_vault_secret")}();`;
}

function build(ctx: ModuleContext, layout: ModuleLayout): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const n = hookNames(ctx, layout);

  requireAdoptedFormat(ctx, n);

  return [
    `${schemaPreamble(ctx)}${tables(ctx, n)}${ctx.manages ? "" : formatDefault(ctx, n)}`,
    reenable(ctx, n),
    vaultCleanup(ctx, n),
    functions(ctx, n),
  ].join("\n");
}

function contract(): readonly ModuleContractFunction[] {
  return [
    {
      name: "publish_webhook_event",
      args: ["text", "jsonb", "{id}", "text", "text", "text"],
      returns: "integer",
    },
    { name: "publish_webhook_events", args: ["jsonb"], returns: "jsonb" },
    {
      name: "dispatch_webhook",
      args: ["uuid", "text", "jsonb", "text", "text"],
      returns: "uuid",
    },
    {
      name: "claim_webhook_deliveries",
      args: ["integer", "interval", "integer"],
      returns: "jsonb",
    },
    {
      name: "complete_webhook_delivery",
      args: ["uuid", "jsonb"],
      returns: "text",
    },
    { name: "redeliver_webhook", args: ["uuid"], returns: "uuid" },
    {
      name: "purge_webhook_deliveries",
      args: ["interval", "boolean", "integer"],
      returns: "integer",
    },
    {
      name: "rotate_webhook_secret",
      args: ["uuid", "interval", "text"],
      returns: "text",
    },
    { name: "webhook_secrets", args: ["uuid"], returns: "text[]" },
  ];
}

export const WEBHOOKS_OUT: ModuleDefinition = {
  name: "webhooks-out",
  title: "Outgoing webhooks",
  description:
    "Outgoing webhooks: endpoints subscribed to event types, a delivery log unique per endpoint and event with leases and retries, direct dispatch, secrets in Vault with overlap while rotating, auto-disable after an endpoint keeps failing and redelivery.",
  requires: ["updated-at"],
  integrates: ["access", "service-principals", "data-lifecycle"],
  providerFunctions: ["idsWithFor"],
  target: "schema",
  modes: ["managed", "adopt", "custom"],
  version: 5,
  names: NAMES,
  adoptOptional: (ctx) => ({
    ...ADDED_COLUMNS,
    secrets: [
      ctx.text("secretStorage", "vault") === "column" ? "vaultId" : "secret",
    ],
  }),
  contract,
  upgrades: [
    {
      from: 1,
      description:
        "Endpoint writes have one policy per command, so reads check one policy; an index finds an endpoint's open deliveries.",
      sql: () => "",
    },
    {
      from: 2,
      description:
        "publish_webhook_event takes a subject and a read permission and queues an event only for endpoints whose owner may read it; endpoints get permissions and batch, deliveries a subject.",
      sql: () => "",
    },
    {
      from: 3,
      description:
        "Endpoints get signing (v1 HMAC or v1a Ed25519), format (the encoder that writes the body) and credential_ref (the credential whose token authenticates the request), and claim_webhook_deliveries returns them. Existing endpoints get format 'standard', the 0.8 body, and new ones defaultFormat. purge_webhook_deliveries keeps deliveries for the data-lifecycle retention policy and skips those under a legal hold.",
      sql: (ctx) => {
        const n = hookNames(ctx);

        return ctx.manages && n.has("endpoints", "format")
          ? `alter table ${n.table("endpoints")} add column if not exists ${n.col("endpoints", "format")} ${formatColumn(n.col("endpoints", "format"), "standard")};`
          : "";
      },
    },
    {
      from: 4,
      description:
        "publish_webhook_events(events) queues a batch of events in one call, with publish_webhook_event's checks per event and a {count} or {error} result each. options.partitioned partitions a new deliveries table by month on created_at and applies to new tables only.",
      sql: () => "",
    },
  ],
  build,
};
