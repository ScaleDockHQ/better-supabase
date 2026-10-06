import type { BlockContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { SERVICE_CALLER } from "../shared.ts";
import { BLOCK_PERMISSIONS } from "./access-model.ts";

export interface HookNames {
  readonly table: (table: string) => string;
  readonly col: (table: string, logical: string) => string;
  readonly has: (table: string, logical: string) => boolean;
  /** A member check on `tenant` (a SQL expression) for a block action. */
  readonly can: (tenant: string, action: "manage" | "view") => string;
  /**
   * `tenant in (select tenant_ids_with(...))` for policies: the set is
   * computed once per query instead of a `can()` call per row.
   */
  readonly member: (tenant: string, action: "manage" | "view") => string;
  /** Clients read and manage endpoints through RLS. */
  readonly clientAccess: boolean;
  readonly vault: boolean;
  readonly allowHttp: boolean;
  readonly eventIdType: string;
  readonly runIdType: string;
  /** A delivery status as the deliveries table stores it, quoted. */
  readonly status: (status: WebhookStatus) => string;
  /** `expression` (a status name) as the stored value. */
  readonly stored: (expression: string) => string;
}

export const WEBHOOK_STATUSES = [
  "pending",
  "delivering",
  "succeeded",
  "retrying",
  "dead",
  "canceled",
] as const;

export type WebhookStatus = (typeof WEBHOOK_STATUSES)[number];

const isStatus = (value: string): value is WebhookStatus =>
  WEBHOOK_STATUSES.some((status) => status === value);

/** `blocks.webhooks-out.options.statuses`: the values an adopted table stores. */
function statusValues(
  ctx: BlockContext,
): Readonly<Record<WebhookStatus, string>> {
  const configured = ctx.option("statuses") ?? {};
  if (typeof configured !== "object" || Array.isArray(configured)) {
    throw new TypeError(
      "blocks.webhooks-out.options.statuses must map status names to the stored values",
    );
  }
  const values: Record<WebhookStatus, string> = {
    pending: "pending",
    delivering: "delivering",
    succeeded: "succeeded",
    retrying: "retrying",
    dead: "dead",
    canceled: "canceled",
  };
  for (const [name, value] of Object.entries(configured)) {
    if (!isStatus(name)) {
      throw new TypeError(
        `blocks.webhooks-out.options.statuses: unknown status "${name}". Statuses: ${WEBHOOK_STATUSES.join(", ")}`,
      );
    }
    if (typeof value !== "string" || value.length === 0) {
      throw new TypeError(
        `blocks.webhooks-out.options.statuses.${name} must be a non-empty string`,
      );
    }
    if (ctx.manages) {
      throw new TypeError(
        "blocks.webhooks-out.options.statuses maps an adopted table's values; managed tables use the default statuses",
      );
    }
    values[name] = value;
  }
  return values;
}

const TYPE = /^[a-z][a-z0-9_ ]*$/;

function typeOption(ctx: BlockContext, name: string): string {
  const type = ctx.text(name, "text");
  if (!TYPE.test(type)) {
    throw new TypeError(
      `blocks.webhooks-out.options.${name} must be a type name such as "uuid", not "${type}"`,
    );
  }
  return type;
}

export function hookNames(ctx: BlockContext): HookNames {
  const has = (table: string, logical: string) => ctx.has(table, logical);
  const storage = ctx.text("secretStorage", "vault");
  if (storage !== "vault" && storage !== "column") {
    throw new TypeError(
      `blocks.webhooks-out.options.secretStorage must be "vault" or "column", not "${storage}"`,
    );
  }
  const vault = storage === "vault";
  if (!has("secrets", vault ? "vaultId" : "secret")) {
    throw new TypeError(
      `blocks.webhooks-out: secretStorage "${storage}" needs the secrets table's ${vault ? "vaultId" : "secret"} column`,
    );
  }
  const access = ctx.installed("access");
  const permissions = BLOCK_PERMISSIONS["webhooks-out"];
  const values = statusValues(ctx);
  return {
    table: (table) => ctx.table(table),
    col: (table, logical) => ctx.col(table, logical),
    has,
    can: (tenant, action) =>
      access
        ? `coalesce(better_supabase.can('tenant', ${tenant}, ${ctx.permission(action, permissions[action])}), false)`
        : "false",
    member: (tenant, action) =>
      access
        ? `${tenant} in (select better_supabase.tenant_ids_with(${ctx.permission(action, permissions[action])}))`
        : "false",
    clientAccess:
      access && has("endpoints", "tenant") && has("deliveries", "tenant"),
    vault,
    allowHttp: ctx.flag("allowHttp", false),
    eventIdType: typeOption(ctx, "eventIdType"),
    runIdType: typeOption(ctx, "runIdType"),
    status: (status) => sqlString(values[status]),
    stored: (expression) =>
      WEBHOOK_STATUSES.every((status) => values[status] === status)
        ? expression
        : `case ${expression} ${WEBHOOK_STATUSES.map((status) => `when '${status}' then ${sqlString(values[status])}`).join(" ")} end`,
  };
}

const fail = (code: string, message: string, errcode = "42501"): string =>
  `raise exception '${message}' using errcode = '${errcode}', hint = '${code}';`;

const VARIABLES = "#variable_conflict use_column";

function grants(fn: string, args: string, clients: boolean): string {
  return `revoke execute on function ${fn}(${args}) from public, anon, authenticated;
grant execute on function ${fn}(${args}) to ${clients ? "authenticated, service_role" : "service_role"};`;
}

/** Raises unless the caller is the service or may `action` in `tenant`. */
function guard(
  n: HookNames,
  tenant: string,
  action: "manage" | "view",
): string {
  const member = n.has("endpoints", "tenant") ? n.can(tenant, action) : "false";
  return `if not (${SERVICE_CALLER}) and not ${member} then
    ${fail("WEBHOOK_FORBIDDEN", "Not allowed to manage this webhook endpoint")}
  end if;`;
}

function endpointTenant(n: HookNames, id: string): string {
  return n.has("endpoints", "tenant")
    ? `select d.${n.col("endpoints", "tenant")}, d.${n.col("endpoints", "enabled")} into v_tenant, v_enabled
  from ${n.table("endpoints")} d where d.${n.col("endpoints", "id")} = ${id};`
    : `select null, d.${n.col("endpoints", "enabled")} into v_tenant, v_enabled
  from ${n.table("endpoints")} d where d.${n.col("endpoints", "id")} = ${id};`;
}

const touched = (n: HookNames, table: string, alias = ""): string =>
  n.has(table, "updatedAt")
    ? `, ${alias}${n.col(table, "updatedAt")} = now()`
    : "";

function publish(ctx: BlockContext, n: HookNames): string {
  const fn = ctx.fn("publish_webhook_event");
  const id = ctx.idType;
  const d = (logical: string) => n.col("endpoints", logical);
  const v = (logical: string) => n.col("deliveries", logical);
  const columns: [string, string][] = [
    [v("endpoint"), `d.${d("id")}`],
    [v("type"), "publish_webhook_event.event_type"],
    [v("payload"), "coalesce(publish_webhook_event.payload, '{}')"],
  ];
  if (n.has("deliveries", "tenant"))
    columns.push([
      v("tenant"),
      n.has("endpoints", "tenant")
        ? `d.${d("tenant")}`
        : "publish_webhook_event.tenant",
    ]);
  if (n.has("deliveries", "event"))
    columns.push([
      v("event"),
      `publish_webhook_event.event_id::${n.eventIdType}`,
    ]);
  const tenant = n.has("endpoints", "tenant")
    ? `\n    and d.${d("tenant")} is not distinct from publish_webhook_event.tenant`
    : "";
  const conflict = n.has("deliveries", "event")
    ? `\n  on conflict (${v("endpoint")}, ${v("event")}) where ${v("event")} is not null do nothing`
    : "";
  return `
-- Queues the event for every enabled endpoint subscribed to its type:
-- the exact type, '*', or a prefix pattern such as 'invoice.*'. The
-- patterns that can match are built from the type, so && uses the GIN
-- index on the subscriptions. The same event id never queues twice for one
-- endpoint.
create or replace function ${fn}(event_type text, payload jsonb, tenant ${id} default null, event_id text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
${VARIABLES}
declare
  inserted integer;
  segments text[] := string_to_array(publish_webhook_event.event_type, '.');
  patterns text[];
begin
  if coalesce(publish_webhook_event.event_type, '') = '' then
    ${fail("WEBHOOK_TYPE_REQUIRED", "An event type is required", "22023")}
  end if;
  patterns := array[publish_webhook_event.event_type, '*'] || array(
    select array_to_string(segments[1:i], '.') || '.*'
    from generate_series(1, cardinality(segments) - 1) i
  );
  insert into ${n.table("deliveries")} (${columns.map(([column]) => column).join(", ")})
  select ${columns.map(([, value]) => value).join(", ")}
  from ${n.table("endpoints")} d
  where d.${d("enabled")}${tenant}
    and d.${d("eventTypes")} && patterns${conflict};
  get diagnostics inserted = row_count;
  return inserted;
end;
$$;
${grants(fn, `text, jsonb, ${id}, text`, false)}`;
}

function dispatch(ctx: BlockContext, n: HookNames): string {
  const fn = ctx.fn("dispatch_webhook");
  const v = (logical: string) => n.col("deliveries", logical);
  const columns: [string, string][] = [
    [v("endpoint"), "dispatch_webhook.endpoint"],
    [v("type"), "dispatch_webhook.event_type"],
    [v("payload"), "coalesce(dispatch_webhook.payload, '{}')"],
  ];
  if (n.has("deliveries", "tenant")) columns.push([v("tenant"), "v_tenant"]);
  if (n.has("deliveries", "run"))
    columns.push([v("run"), `dispatch_webhook.run_id::${n.runIdType}`]);
  const event = n.has("deliveries", "event");
  if (event)
    columns.push([v("event"), `dispatch_webhook.event_id::${n.eventIdType}`]);
  const existing = `select v.${v("id")} into v_id from ${n.table("deliveries")} v
    where v.${v("endpoint")} = dispatch_webhook.endpoint and v.${v("event")} = dispatch_webhook.event_id::${n.eventIdType};`;
  return `
-- Sends one event to one endpoint, outside its subscriptions, e.g. from a
-- workflow step. With an event id, dispatching it again returns the first delivery.
create or replace function ${fn}(endpoint uuid, event_type text, payload jsonb, run_id text default null, event_id text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
${VARIABLES}
declare
  v_tenant ${ctx.idType};
  v_enabled boolean;
  v_id uuid;
begin
  if coalesce(dispatch_webhook.event_type, '') = '' then
    ${fail("WEBHOOK_TYPE_REQUIRED", "An event type is required", "22023")}
  end if;
  ${endpointTenant(n, "dispatch_webhook.endpoint")}
  if not found then
    ${fail("WEBHOOK_ENDPOINT_NOT_FOUND", "Webhook endpoint not found", "P0002")}
  end if;
  ${guard(n, "v_tenant", "manage")}
  if not v_enabled then
    ${fail("WEBHOOK_ENDPOINT_DISABLED", "Webhook endpoint is disabled", "55000")}
  end if;${
    event
      ? `
  if dispatch_webhook.event_id is not null then
    ${existing}
    if v_id is not null then
      return v_id;
    end if;
  end if;`
      : ""
  }
  insert into ${n.table("deliveries")} (${columns.map(([column]) => column).join(", ")})
  values (${columns.map(([, value]) => value).join(", ")})${
    event
      ? `
  on conflict (${v("endpoint")}, ${v("event")}) where ${v("event")} is not null do nothing`
      : ""
  }
  returning ${v("id")} into v_id;${
    event
      ? `
  if v_id is null then
    -- Another transaction dispatched the same event first.
    ${existing}
  end if;`
      : ""
  }
  return v_id;
end;
$$;
${grants(fn, "uuid, text, jsonb, text, text", true)}`;
}

function claim(ctx: BlockContext, n: HookNames): string {
  const fn = ctx.fn("claim_webhook_deliveries");
  const d = (logical: string) => n.col("endpoints", logical);
  const v = (logical: string) => n.col("deliveries", logical);
  const optional = (logical: string, key: string) =>
    n.has("deliveries", logical) ? `, '${key}', c.${v(logical)}` : "";
  const stamp = [
    n.has("deliveries", "lastError")
      ? `, ${v("lastError")} = 'The lease ran out on the last attempt'`
      : "",
    n.has("deliveries", "processedAt") ? `, ${v("processedAt")} = now()` : "",
    touched(n, "deliveries"),
  ].join("");
  return `
drop function if exists ${fn}(integer, interval);
-- Leases due deliveries to one worker and counts the attempt, so a worker
-- that dies mid-send still uses one up. The attempt is the lease token that
-- complete_webhook_delivery checks. Deliveries of disabled endpoints are
-- canceled instead, a lease that ran out is claimed again, and one that ran
-- out on the last attempt is dead-lettered.
create or replace function ${fn}(max_items integer default 25, lease interval default '2 minutes', max_attempts integer default 8)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
${VARIABLES}
declare
  result jsonb;
begin
  update ${n.table("deliveries")} v
  set ${v("status")} = ${n.status("canceled")}, ${v("leasedUntil")} = null${
    n.has("deliveries", "lastError")
      ? `, ${v("lastError")} = 'Endpoint is disabled'`
      : ""
  }${n.has("deliveries", "processedAt") ? `, ${v("processedAt")} = now()` : ""}${touched(n, "deliveries")}
  from ${n.table("endpoints")} d
  where d.${d("id")} = v.${v("endpoint")}
    and not d.${d("enabled")}
    and v.${v("status")} in (${n.status("pending")}, ${n.status("retrying")});

  update ${n.table("deliveries")} v
  set ${v("status")} = ${n.status("dead")}, ${v("leasedUntil")} = null${stamp}
  where v.${v("status")} = ${n.status("delivering")}
    and v.${v("leasedUntil")} <= now()
    and v.${v("attempt")} >= greatest(1, coalesce(claim_webhook_deliveries.max_attempts, 8));

  with due as (
    select v.${v("id")} as id
    from ${n.table("deliveries")} v
    where v.${v("status")} in (${n.status("pending")}, ${n.status("retrying")}, ${n.status("delivering")})
      and v.${v("availableAt")} <= now()
      and (v.${v("leasedUntil")} is null or v.${v("leasedUntil")} <= now())
    order by v.${v("availableAt")}, v.${v("createdAt")}
    for update skip locked
    limit greatest(1, least(coalesce(claim_webhook_deliveries.max_items, 25), 100))
  ),
  claimed as (
    update ${n.table("deliveries")} v
    set ${v("status")} = ${n.status("delivering")},
      ${v("attempt")} = v.${v("attempt")} + 1,
      ${v("leasedUntil")} = now() + coalesce(claim_webhook_deliveries.lease, '2 minutes')${touched(n, "deliveries")}
    from due
    where v.${v("id")} = due.id
    returning v.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', c.${v("id")},
    'endpoint_id', c.${v("endpoint")},
    'type', c.${v("type")},
    'payload', c.${v("payload")},
    'attempt', c.${v("attempt")},
    'url', d.${d("url")},
    'created_at', c.${v("createdAt")}${optional("tenant", "tenant")}${optional("event", "event_id")}${optional("run", "run_id")}
  ) order by c.${v("availableAt")}), '[]')
  into result
  from claimed c
  join ${n.table("endpoints")} d on d.${d("id")} = c.${v("endpoint")};
  return result;
end;
$$;
${grants(fn, "integer, interval, integer", false)}`;
}

function complete(ctx: BlockContext, n: HookNames): string {
  const fn = ctx.fn("complete_webhook_delivery");
  const d = (logical: string) => n.col("endpoints", logical);
  const v = (logical: string) => n.col("deliveries", logical);
  const window = ctx.text("disableAfter", "5 days");
  if (!/^\d+ (minute|hour|day|week)s?$/.test(window)) {
    throw new TypeError(
      `blocks.webhooks-out.options.disableAfter must be an interval such as "5 days", not "${window}"`,
    );
  }
  const disableAfter = sqlString(window);
  const sets = [
    `${v("status")} = ${n.stored("v_status")}`,
    `${v("attempt")} = case when v_status = 'canceled' then greatest(v.${v("attempt")} - 1, 0) else v.${v("attempt")} end`,
    `${v("availableAt")} = case when v_status = 'retrying' then coalesce((complete_webhook_delivery.outcome ->> 'retry_at')::timestamptz, now()) else v.${v("availableAt")} end`,
    `${v("leasedUntil")} = null`,
  ];
  const optional: [string, string][] = [
    [
      "responseStatus",
      "(complete_webhook_delivery.outcome ->> 'response_status')::integer",
    ],
    ["responseBody", "complete_webhook_delivery.outcome ->> 'response_body'"],
    [
      "durationMs",
      "(complete_webhook_delivery.outcome ->> 'duration_ms')::integer",
    ],
    ["lastError", "complete_webhook_delivery.outcome ->> 'error'"],
    ["processedAt", "case when v_status = 'retrying' then null else now() end"],
    ["updatedAt", "now()"],
  ];
  for (const [logical, value] of optional)
    if (n.has("deliveries", logical)) sets.push(`${v(logical)} = ${value}`);
  const tenantSelect = n.has("endpoints", "tenant")
    ? `, d.${d("tenant")}`
    : ", null";
  const disable = [
    n.has("endpoints", "disabledAt") ? `, ${d("disabledAt")} = now()` : "",
    n.has("endpoints", "disabledReason")
      ? `, ${d("disabledReason")} = format('Deliveries failed since %s', v_since)`
      : "",
    touched(n, "endpoints"),
  ].join("");
  const streak = n.has("endpoints", "failingSince")
    ? `
  if v_status = 'succeeded' then
    update ${n.table("endpoints")} d set ${d("failingSince")} = null
    where d.${d("id")} = v_endpoint and d.${d("failingSince")} is not null;
  elsif v_status in ('retrying', 'dead') then
    update ${n.table("endpoints")} d set ${d("failingSince")} = coalesce(d.${d("failingSince")}, now())
    where d.${d("id")} = v_endpoint
    returning d.${d("failingSince")}${tenantSelect} into v_since, v_tenant;
    if v_since <= now() - ${disableAfter}::interval then
      update ${n.table("endpoints")} d set ${d("enabled")} = false${disable}
      where d.${d("id")} = v_endpoint and d.${d("enabled")};
      if found then
        v_result := 'disabled';
        ${ctx.emit({
          type: "webhook.disabled",
          payload:
            "jsonb_build_object('endpointId', v_endpoint, 'failingSince', v_since)",
          subject: "'webhooks/' || v_endpoint::text",
          tenant: "v_tenant::text",
        })}
      end if;
    end if;
  end if;`
    : "";
  return `
-- Records an attempt for the worker that holds the lease: outcome.attempt
-- must be the attempt the claim returned, and a delivery claimed again in
-- the meantime returns 'stale' unchanged. 'retrying' retries at retry_at, and
-- an endpoint that keeps failing for disableAfter is disabled.
create or replace function ${fn}(delivery uuid, outcome jsonb)
returns text
language plpgsql
security definer
set search_path = ''
as $$
${VARIABLES}
declare
  v_status text := complete_webhook_delivery.outcome ->> 'status';
  v_attempt integer := (complete_webhook_delivery.outcome ->> 'attempt')::integer;
  v_endpoint uuid;
  v_tenant ${ctx.idType};
  v_since timestamptz;
  v_result text := 'ok';
begin
  if v_status is null or v_status not in ('succeeded', 'retrying', 'dead', 'canceled') then
    ${fail("WEBHOOK_STATUS_UNKNOWN", "status must be succeeded, retrying, dead or canceled", "22023")}
  end if;
  if v_attempt is null then
    ${fail("WEBHOOK_ATTEMPT_REQUIRED", "outcome.attempt must be the attempt the claim returned", "22023")}
  end if;
  update ${n.table("deliveries")} v
  set ${sets.join(",\n    ")}
  where v.${v("id")} = complete_webhook_delivery.delivery
    and v.${v("attempt")} = v_attempt
    and v.${v("status")} = ${n.status("delivering")}
  returning v.${v("endpoint")} into v_endpoint;
  if not found then
    if exists (select 1 from ${n.table("deliveries")} v where v.${v("id")} = complete_webhook_delivery.delivery) then
      return 'stale';
    end if;
    ${fail("WEBHOOK_DELIVERY_NOT_FOUND", "Webhook delivery not found", "P0002")}
  end if;${streak}
  ${ctx.hook("after_webhook_delivery", [
    ["uuid", "complete_webhook_delivery.delivery"],
    ["text", "v_status"],
  ])}
  return v_result;
end;
$$;
${grants(fn, "uuid, jsonb", false)}`;
}

function redeliver(ctx: BlockContext, n: HookNames): string {
  const fn = ctx.fn("redeliver_webhook");
  const v = (logical: string) => n.col("deliveries", logical);
  const resets = [
    `${v("status")} = ${n.status("pending")}`,
    `${v("attempt")} = 0`,
    `${v("availableAt")} = now()`,
    `${v("leasedUntil")} = null`,
    ...(n.has("deliveries", "processedAt")
      ? [`${v("processedAt")} = null`]
      : []),
    ...(n.has("deliveries", "lastError") ? [`${v("lastError")} = null`] : []),
    ...(n.has("deliveries", "updatedAt") ? [`${v("updatedAt")} = now()`] : []),
  ];
  return `
-- Queues a finished delivery again, e.g. after the receiver fixed a bug.
create or replace function ${fn}(delivery uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
${VARIABLES}
declare
  v_endpoint uuid;
  v_status text;
  v_tenant ${ctx.idType};
  v_enabled boolean;
begin
  select v.${v("endpoint")}, v.${v("status")} into v_endpoint, v_status
  from ${n.table("deliveries")} v where v.${v("id")} = redeliver_webhook.delivery;
  if not found then
    ${fail("WEBHOOK_DELIVERY_NOT_FOUND", "Webhook delivery not found", "P0002")}
  end if;
  ${endpointTenant(n, "v_endpoint")}
  ${guard(n, "v_tenant", "manage")}
  if v_status in (${n.status("pending")}, ${n.status("delivering")}) then
    ${fail("WEBHOOK_DELIVERY_IN_PROGRESS", "The delivery is still in progress", "55000")}
  end if;
  if not v_enabled then
    ${fail("WEBHOOK_ENDPOINT_DISABLED", "Webhook endpoint is disabled", "55000")}
  end if;
  update ${n.table("deliveries")} v
  set ${resets.join(", ")}
  where v.${v("id")} = redeliver_webhook.delivery;
  return redeliver_webhook.delivery;
end;
$$;
${grants(fn, "uuid", true)}`;
}

function purge(ctx: BlockContext, n: HookNames): string {
  const fn = ctx.fn("purge_webhook_deliveries");
  const v = (logical: string) => n.col("deliveries", logical);
  return `
-- Deletes up to batch finished deliveries (and dead ones with include_dead)
-- created before older_than. A purged event id can be queued again for the
-- same endpoint, so keep older_than above the window you republish in.
-- Nightly with pg_cron: select cron.schedule('purge-webhook-deliveries', '45 3 * * *', 'select ${fn}()');
create or replace function ${fn}(older_than interval default '30 days', include_dead boolean default false, batch integer default 10000)
returns integer
language sql
security definer
set search_path = ''
as $$
  with purged as (
    delete from ${n.table("deliveries")}
    where ${v("id")} in (
      select v.${v("id")} from ${n.table("deliveries")} v
      where v.${v("createdAt")} < now() - purge_webhook_deliveries.older_than
        and (
          v.${v("status")} in (${n.status("succeeded")}, ${n.status("canceled")})
          or (purge_webhook_deliveries.include_dead and v.${v("status")} = ${n.status("dead")})
        )
      limit purge_webhook_deliveries.batch
    )
    returning 1
  )
  select count(*)::integer from purged
$$;
${grants(fn, "interval, boolean, integer", false)}`;
}

function secrets(ctx: BlockContext, n: HookNames): string {
  const rotate = ctx.fn("rotate_webhook_secret");
  const read = ctx.fn("webhook_secrets");
  const s = (logical: string) => n.col("secrets", logical);
  const t = n.table("secrets");
  const expires = n.has("secrets", "expiresAt");
  const ofEndpoint = `s.${s("endpoint")} = rotate_webhook_secret.endpoint`;
  const dropVault = (where: string) =>
    n.vault
      ? `delete from vault.secrets vs using ${t} s where vs.id = s.${s("vaultId")} and ${where};
  `
      : "";
  const retire = expires
    ? `${dropVault(`${ofEndpoint} and s.${s("expiresAt")} <= now()`)}delete from ${t} s where ${ofEndpoint} and s.${s("expiresAt")} <= now();
  update ${t} s set ${s("expiresAt")} = now() + coalesce(rotate_webhook_secret.overlap, '24 hours')
  where ${ofEndpoint} and s.${s("expiresAt")} is null;`
    : `${dropVault(ofEndpoint)}delete from ${t} s where ${ofEndpoint};`;
  const columns: [string, string][] = [
    [s("endpoint"), "rotate_webhook_secret.endpoint"],
    n.vault ? [s("vaultId"), "v_vault"] : [s("secret"), "v_secret"],
  ];
  if (n.has("secrets", "tenant")) columns.push([s("tenant"), "v_tenant"]);
  const value = n.vault ? "ds.decrypted_secret" : `s.${s("secret")}`;
  const join = n.vault
    ? `\n    join vault.decrypted_secrets ds on ds.id = s.${s("vaultId")}`
    : "";
  return `
-- A new signing secret, returned once. Older secrets keep signing for
-- overlap, so receivers can switch without dropping deliveries.
create or replace function ${rotate}(endpoint uuid, overlap interval default '24 hours', secret text default null)
returns text
language plpgsql
security definer
set search_path = ''
as $$
${VARIABLES}
declare
  v_tenant ${ctx.idType};
  v_enabled boolean;
  v_secret text := coalesce(
    rotate_webhook_secret.secret,
    'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
  );${n.vault ? "\n  v_vault uuid;" : ""}
begin
  ${endpointTenant(n, "rotate_webhook_secret.endpoint")}
  if not found then
    ${fail("WEBHOOK_ENDPOINT_NOT_FOUND", "Webhook endpoint not found", "P0002")}
  end if;
  ${guard(n, "v_tenant", "manage")}
  if length(v_secret) < 16 then
    ${fail("WEBHOOK_SECRET_TOO_SHORT", "A webhook secret needs at least 16 characters", "22023")}
  end if;
  ${retire}${
    n.vault
      ? `
  v_vault := vault.create_secret(
    v_secret,
    'webhook:' || rotate_webhook_secret.endpoint::text || ':' || gen_random_uuid()::text,
    'better-supabase outgoing webhook signing secret'
  );`
      : ""
  }
  insert into ${t} (${columns.map(([column]) => column).join(", ")})
  values (${columns.map(([, expression]) => expression).join(", ")});
  return v_secret;
end;
$$;
${grants(rotate, "uuid, interval, text", true)}

-- The secrets that sign an endpoint's deliveries: the current one first, then by age.
create or replace function ${read}(endpoint uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(x.secret order by x.expires desc nulls first, x.created desc), '{}')
  from (
    select ${value} as secret, ${expires ? `s.${s("expiresAt")}` : "null::timestamptz"} as expires, s.${s("createdAt")} as created
    from ${t} s${join}
    where s.${s("endpoint")} = webhook_secrets.endpoint${
      expires
        ? `
      and (s.${s("expiresAt")} is null or s.${s("expiresAt")} > now())`
        : ""
    }
  ) x
$$;
${grants(read, "uuid", false)}`;
}

export function functions(ctx: BlockContext, n: HookNames): string {
  return [
    publish(ctx, n),
    dispatch(ctx, n),
    claim(ctx, n),
    complete(ctx, n),
    redeliver(ctx, n),
    purge(ctx, n),
    secrets(ctx, n),
  ].join("\n");
}
