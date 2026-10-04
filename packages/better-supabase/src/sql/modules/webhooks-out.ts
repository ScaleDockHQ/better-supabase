import type { KitContext, KitContractFunction, KitNames } from "../context.ts";
import type { KitModuleDefinition } from "../kit.ts";

import { sqlIdent } from "../../core/template.ts";
import { schemaPreamble } from "../shared.ts";
import { functions, type HookNames, hookNames } from "./webhooks-out-sql.ts";

const NAMES: KitNames = {
  tables: {
    destinations: {
      name: "webhook_destinations",
      columns: {
        id: "id",
        tenant: "organization_id",
        name: "name",
        url: "url",
        enabled: "enabled",
        eventTypes: "event_kinds",
        failureCount: "consecutive_failures",
        disabledAt: "disabled_at",
        disabledReason: "disabled_reason",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: [
        "tenant",
        "name",
        "failureCount",
        "disabledAt",
        "disabledReason",
        "createdBy",
        "updatedAt",
      ],
    },
    secrets: {
      name: "webhook_destination_secrets",
      columns: {
        id: "id",
        destination: "destination_id",
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
      columns: {
        id: "id",
        tenant: "organization_id",
        destination: "destination_id",
        event: "event_id",
        run: "run_id",
        type: "event_kind",
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

function tables(ctx: KitContext, n: HookNames): string {
  if (!ctx.manages) return "";
  const id = ctx.idType;
  const d = (logical: string) => n.col("destinations", logical);
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

  const destinations = `
create table if not exists ${n.table("destinations")} (
  ${[
    `${d("id")} uuid primary key default gen_random_uuid()`,
    ...opt("destinations", "tenant", `${id} not null`),
    ...opt(
      "destinations",
      "name",
      `text not null check (length(trim(${d("name")})) > 0)`,
    ),
    `${d("url")} text not null ${urlCheck}`,
    `${d("enabled")} boolean not null default true`,
    `${d("eventTypes")} text[] not null default '{}'`,
    ...opt("destinations", "failureCount", "integer not null default 0"),
    ...opt("destinations", "disabledAt", "timestamptz"),
    ...opt("destinations", "disabledReason", "text"),
    ...opt(
      "destinations",
      "createdBy",
      "uuid references auth.users (id) on delete set null default auth.uid()",
    ),
    `${d("createdAt")} timestamptz not null default now()`,
    ...opt("destinations", "updatedAt", "timestamptz not null default now()"),
  ].join(",\n  ")}
);
create index if not exists webhook_destinations_types_idx on ${n.table("destinations")} using gin (${d("eventTypes")});
alter table ${n.table("destinations")} enable row level security;
revoke all on ${n.table("destinations")} from anon, authenticated;
grant all on ${n.table("destinations")} to service_role;${
    scoped
      ? `
grant select, insert, update, delete on ${n.table("destinations")} to authenticated;${policy(
          "destinations",
          "bs_webhook_destinations_read",
          `for select to authenticated using (${n.can(d("tenant"), "view")})`,
        )}${policy(
          "destinations",
          "bs_webhook_destinations_write",
          `for all to authenticated using (${n.can(d("tenant"), "manage")}) with check (${n.can(d("tenant"), "manage")})`,
        )}`
      : ""
  }`;

  const secrets = `
create table if not exists ${n.table("secrets")} (
  ${[
    `${s("id")} uuid primary key default gen_random_uuid()`,
    `${s("destination")} uuid not null references ${n.table("destinations")} (${d("id")}) on delete cascade`,
    ...opt("secrets", "tenant", id),
    ...(n.vault
      ? [`${s("vaultId")} uuid not null`]
      : [
          `${s("secret")} text not null check (length(${s("secret")}) between 16 and 200)`,
        ]),
    ...opt("secrets", "expiresAt", "timestamptz"),
    `${s("createdAt")} timestamptz not null default now()`,
  ].join(",\n  ")}
);
create index if not exists webhook_destination_secrets_destination_idx on ${n.table("secrets")} (${s("destination")});
alter table ${n.table("secrets")} enable row level security;
revoke all on ${n.table("secrets")} from anon, authenticated;
grant all on ${n.table("secrets")} to service_role;`;

  const deliveries = `
create table if not exists ${n.table("deliveries")} (
  ${[
    `${v("id")} uuid primary key default gen_random_uuid()`,
    ...opt("deliveries", "tenant", id),
    `${v("destination")} uuid not null references ${n.table("destinations")} (${d("id")}) on delete cascade`,
    ...opt("deliveries", "event", n.eventIdType),
    ...opt("deliveries", "run", n.runIdType),
    `${v("type")} text not null`,
    `${v("payload")} jsonb not null default '{}'`,
    `${v("status")} text not null default 'pending' check (${v("status")} in ('pending', 'processing', 'completed', 'failed', 'dead_lettered', 'canceled'))`,
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
create index if not exists webhook_deliveries_due_idx on ${n.table("deliveries")} (${v("availableAt")}, ${v("leasedUntil")}) where ${v("status")} in ('pending', 'failed', 'processing');
create index if not exists webhook_deliveries_destination_idx on ${n.table("deliveries")} (${v("destination")}, ${v("createdAt")} desc);${
    n.has("deliveries", "event")
      ? `
create unique index if not exists webhook_deliveries_destination_event_idx on ${n.table("deliveries")} (${v("destination")}, ${v("event")}) where ${v("event")} is not null;`
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
          `for select to authenticated using (${n.can(v("tenant"), "view")})`,
        )}`
      : ""
  }`;

  return [destinations, secrets, deliveries].join("\n");
}

/** Re-enabling a destination clears its failure streak. */
function reenable(ctx: KitContext, n: HookNames): string {
  const d = (logical: string) => n.col("destinations", logical);
  const resets = [
    n.has("destinations", "failureCount")
      ? `new.${d("failureCount")} := 0;`
      : "",
    n.has("destinations", "disabledAt")
      ? `new.${d("disabledAt")} := null;`
      : "",
    n.has("destinations", "disabledReason")
      ? `new.${d("disabledReason")} := null;`
      : "",
  ].filter(Boolean);
  const trigger = ctx.trigger("webhook_destination_reenable");
  if (resets.length === 0)
    return `drop trigger if exists ${trigger} on ${n.table("destinations")};`;
  return `
create or replace function ${ctx.fn("reset_webhook_destination")}()
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
revoke execute on function ${ctx.fn("reset_webhook_destination")}() from public, anon, authenticated;
drop trigger if exists ${trigger} on ${n.table("destinations")};
create trigger ${trigger} before update of ${d("enabled")} on ${n.table("destinations")}
  for each row execute function ${ctx.fn("reset_webhook_destination")}();`;
}

/** Deleting a secret row (or its destination) deletes its Vault secret. */
function vaultCleanup(ctx: KitContext, n: HookNames): string {
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

function build(ctx: KitContext): string {
  if (ctx.mode === "custom") return "";
  const n = hookNames(ctx);
  return [
    `${schemaPreamble(ctx)}${tables(ctx, n)}`,
    reenable(ctx, n),
    vaultCleanup(ctx, n),
    functions(ctx, n),
  ].join("\n");
}

function contract(): readonly KitContractFunction[] {
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
      args: ["integer", "interval"],
      returns: "jsonb",
    },
    {
      name: "complete_webhook_delivery",
      args: ["uuid", "jsonb"],
      returns: "text",
    },
    { name: "redeliver_webhook", args: ["uuid"], returns: "uuid" },
    {
      name: "rotate_webhook_secret",
      args: ["uuid", "interval", "text"],
      returns: "text",
    },
    { name: "webhook_secrets", args: ["uuid"], returns: "text[]" },
  ];
}

export const WEBHOOKS_OUT: KitModuleDefinition = {
  name: "webhooks-out",
  title: "Outgoing webhooks",
  description:
    "Outgoing webhooks: destinations subscribed to event types, a delivery log unique per destination and event with leases and retries, direct dispatch, secrets in Vault with overlap while rotating, auto-disable after repeated failures and redelivery.",
  requires: [],
  target: "schema",
  modes: ["managed", "adopt", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
