import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../registry.ts";

import { sqlIdent } from "../../core/template.ts";
import { schemaPreamble, updatedAt } from "../shared.ts";
import {
  functions,
  type HookNames,
  hookNames,
  WEBHOOK_STATUSES,
} from "./webhooks-out-sql.ts";

const NAMES: ModuleNames = {
  options: [
    "allowHttp",
    "disableAfter",
    "eventIdType",
    "runIdType",
    "secretStorage",
    "statuses",
  ],
  tables: {
    endpoints: {
      name: "webhook_endpoints",
      lifecycle: { tenant: "tenant" },
      columns: {
        id: "id",
        tenant: "organization_id",
        name: "name",
        url: "url",
        enabled: "enabled",
        eventTypes: "event_types",
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
        "failingSince",
        "disabledAt",
        "disabledReason",
        "createdBy",
        "updatedAt",
      ],
    },
    secrets: {
      name: "webhook_endpoint_secrets",
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

function tables(ctx: ModuleContext, n: HookNames): string {
  if (!ctx.manages) return "";
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
create index if not exists webhook_endpoints_types_idx on ${n.table("endpoints")} using gin (${d("eventTypes")});
${n.has("endpoints", "tenant") ? `create index if not exists webhook_endpoints_tenant_idx on ${n.table("endpoints")} (${d("tenant")});\n` : ""}${n.has("endpoints", "createdBy") ? `create index if not exists webhook_endpoints_created_by_idx on ${n.table("endpoints")} (${d("createdBy")});\n` : ""}${n.has("endpoints", "updatedAt") ? `${updatedAt(n.table("endpoints"), d("updatedAt"))}\n` : ""}alter table ${n.table("endpoints")} enable row level security;
revoke all on ${n.table("endpoints")} from anon, authenticated;
grant all on ${n.table("endpoints")} to service_role;${
    scoped
      ? `
grant select, insert, update, delete on ${n.table("endpoints")} to authenticated;${policy(
          "endpoints",
          "bs_webhook_endpoints_read",
          `for select to authenticated using (${n.member(d("tenant"), "view")})`,
        )}
drop policy if exists bs_webhook_endpoints_write on ${n.table("endpoints")};${policy(
          "endpoints",
          "bs_webhook_endpoints_insert",
          `for insert to authenticated with check (${n.member(d("tenant"), "manage")})`,
        )}${policy(
          "endpoints",
          "bs_webhook_endpoints_update",
          `for update to authenticated using (${n.member(d("tenant"), "manage")}) with check (${n.member(d("tenant"), "manage")})`,
        )}${policy(
          "endpoints",
          "bs_webhook_endpoints_delete",
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
alter table ${n.table("secrets")} enable row level security;
revoke all on ${n.table("secrets")} from anon, authenticated;
grant all on ${n.table("secrets")} to service_role;`;

  const deliveries = `
create table if not exists ${n.table("deliveries")} (
  ${[
    `${v("id")} uuid primary key default gen_random_uuid()`,
    ...opt("deliveries", "tenant", id),
    `${v("endpoint")} uuid not null references ${n.table("endpoints")} (${d("id")}) on delete cascade`,
    ...opt("deliveries", "event", n.eventIdType),
    ...opt("deliveries", "run", n.runIdType),
    `${v("type")} text not null`,
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
  ].join(",\n  ")}
);
create index if not exists webhook_deliveries_due_idx on ${n.table("deliveries")} (${v("availableAt")}, ${v("leasedUntil")}) where ${v("status")} in ('pending', 'retrying', 'delivering');
create index if not exists webhook_deliveries_endpoint_idx on ${n.table("deliveries")} (${v("endpoint")}, ${v("createdAt")} desc);
create index if not exists webhook_deliveries_open_idx on ${n.table("deliveries")} (${v("endpoint")}) where ${v("status")} in ('pending', 'retrying');${
    n.has("deliveries", "tenant")
      ? `
create index if not exists webhook_deliveries_tenant_created_idx on ${n.table("deliveries")} (${v("tenant")}, ${v("createdAt")} desc);`
      : ""
  }${
    n.has("deliveries", "event")
      ? `
create unique index if not exists webhook_deliveries_endpoint_event_idx on ${n.table("deliveries")} (${v("endpoint")}, ${v("event")}) where ${v("event")} is not null;`
      : ""
  }
alter table ${n.table("deliveries")} enable row level security;
revoke all on ${n.table("deliveries")} from anon, authenticated;
grant all on ${n.table("deliveries")} to service_role;${
    scoped
      ? `
grant select on ${n.table("deliveries")} to authenticated;${policy(
          "deliveries",
          "bs_webhook_deliveries_read",
          `for select to authenticated using (${n.member(v("tenant"), "view")})`,
        )}`
      : ""
  }`;

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
  if (resets.length === 0)
    return `drop trigger if exists ${trigger} on ${n.table("endpoints")};`;
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
  if (!n.vault) return `drop trigger if exists ${trigger} on ${t};`;
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

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const n = hookNames(ctx);
  return [
    `${schemaPreamble(ctx)}${tables(ctx, n)}`,
    reenable(ctx, n),
    vaultCleanup(ctx, n),
    functions(ctx, n),
  ].join("\n");
}

function contract(): readonly ModuleContractFunction[] {
  return [
    {
      name: "publish_webhook_event",
      args: ["text", "jsonb", "{id}", "text"],
      returns: "integer",
    },
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
  target: "schema",
  modes: ["managed", "adopt", "custom"],
  version: 2,
  names: NAMES,
  contract,
  upgrades: [
    {
      from: 1,
      description:
        "Endpoint writes have one policy per command, so reads check one policy; an index finds an endpoint's open deliveries.",
      sql: () => "",
    },
  ],
  build,
};
