import type { KitContext } from "../context.ts";

import { SERVICE_CALLER } from "../shared.ts";
import { KIT_PERMISSIONS } from "./access-model.ts";

export interface HookNames {
  readonly table: (table: string) => string;
  readonly col: (table: string, logical: string) => string;
  readonly has: (table: string, logical: string) => boolean;
  /** A member check on `tenant` (a SQL expression) for a kit action. */
  readonly can: (tenant: string, action: "manage" | "view") => string;
  /** Clients read and manage destinations through RLS. */
  readonly clientAccess: boolean;
  readonly vault: boolean;
  readonly allowHttp: boolean;
  readonly eventIdType: string;
  readonly runIdType: string;
}

const TYPE = /^[a-z][a-z0-9_ ]*$/;

function typeOption(ctx: KitContext, name: string): string {
  const type = ctx.text(name, "text");
  if (!TYPE.test(type)) {
    throw new TypeError(
      `kits.webhooks-out.options.${name} must be a type name such as "uuid", not "${type}"`,
    );
  }
  return type;
}

export function hookNames(ctx: KitContext): HookNames {
  const has = (table: string, logical: string) => ctx.has(table, logical);
  const storage = ctx.text("secretStorage", "vault");
  if (storage !== "vault" && storage !== "column") {
    throw new TypeError(
      `kits.webhooks-out.options.secretStorage must be "vault" or "column", not "${storage}"`,
    );
  }
  const vault = storage === "vault";
  if (!has("secrets", vault ? "vaultId" : "secret")) {
    throw new TypeError(
      `kits.webhooks-out: secretStorage "${storage}" needs the secrets table's ${vault ? "vaultId" : "secret"} column`,
    );
  }
  const access = ctx.installed("access");
  const permissions = KIT_PERMISSIONS["webhooks-out"];
  return {
    table: (table) => ctx.table(table),
    col: (table, logical) => ctx.col(table, logical),
    has,
    can: (tenant, action) =>
      access
        ? `coalesce(better_supabase.can('tenant', ${tenant}, ${ctx.permission(action, permissions[action])}), false)`
        : "false",
    clientAccess:
      access && has("destinations", "tenant") && has("deliveries", "tenant"),
    vault,
    allowHttp: ctx.flag("allowHttp", false),
    eventIdType: typeOption(ctx, "eventIdType"),
    runIdType: typeOption(ctx, "runIdType"),
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
  const member = n.has("destinations", "tenant")
    ? n.can(tenant, action)
    : "false";
  return `if not (${SERVICE_CALLER}) and not ${member} then
    ${fail("WEBHOOK_FORBIDDEN", "Not allowed to manage this webhook destination")}
  end if;`;
}

function destinationTenant(n: HookNames, id: string): string {
  return n.has("destinations", "tenant")
    ? `select d.${n.col("destinations", "tenant")}, d.${n.col("destinations", "enabled")} into v_tenant, v_enabled
  from ${n.table("destinations")} d where d.${n.col("destinations", "id")} = ${id};`
    : `select null, d.${n.col("destinations", "enabled")} into v_tenant, v_enabled
  from ${n.table("destinations")} d where d.${n.col("destinations", "id")} = ${id};`;
}

const touched = (n: HookNames, table: string, alias = ""): string =>
  n.has(table, "updatedAt")
    ? `, ${alias}${n.col(table, "updatedAt")} = now()`
    : "";

function publish(ctx: KitContext, n: HookNames): string {
  const fn = ctx.fn("publish_webhook_event");
  const id = ctx.idType;
  const d = (logical: string) => n.col("destinations", logical);
  const v = (logical: string) => n.col("deliveries", logical);
  const columns: [string, string][] = [
    [v("destination"), `d.${d("id")}`],
    [v("type"), "publish_webhook_event.event_type"],
    [v("payload"), "coalesce(publish_webhook_event.payload, '{}')"],
  ];
  if (n.has("deliveries", "tenant"))
    columns.push([
      v("tenant"),
      n.has("destinations", "tenant")
        ? `d.${d("tenant")}`
        : "publish_webhook_event.tenant",
    ]);
  if (n.has("deliveries", "event"))
    columns.push([
      v("event"),
      `publish_webhook_event.event_id::${n.eventIdType}`,
    ]);
  const tenant = n.has("destinations", "tenant")
    ? `\n    and d.${d("tenant")} is not distinct from publish_webhook_event.tenant`
    : "";
  const conflict = n.has("deliveries", "event")
    ? `\n  on conflict (${v("destination")}, ${v("event")}) where ${v("event")} is not null do nothing`
    : "";
  return `
-- Queues the event for every enabled destination subscribed to its type:
-- the exact type, '*', or a prefix pattern such as 'invoice.*'. The same
-- event id never queues twice for one destination.
create or replace function ${fn}(event_type text, payload jsonb, tenant ${id} default null, event_id text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
${VARIABLES}
declare
  inserted integer;
begin
  if coalesce(publish_webhook_event.event_type, '') = '' then
    ${fail("WEBHOOK_TYPE_REQUIRED", "An event type is required", "22023")}
  end if;
  insert into ${n.table("deliveries")} (${columns.map(([column]) => column).join(", ")})
  select ${columns.map(([, value]) => value).join(", ")}
  from ${n.table("destinations")} d
  where d.${d("enabled")}${tenant}
    and exists (
      select 1 from unnest(d.${d("eventTypes")}) t(pattern)
      where t.pattern = publish_webhook_event.event_type
        or t.pattern = '*'
        or (right(t.pattern, 2) = '.*' and starts_with(publish_webhook_event.event_type, left(t.pattern, -1)))
    )${conflict};
  get diagnostics inserted = row_count;
  return inserted;
end;
$$;
${grants(fn, `text, jsonb, ${id}, text`, false)}`;
}

function dispatch(ctx: KitContext, n: HookNames): string {
  const fn = ctx.fn("dispatch_webhook");
  const v = (logical: string) => n.col("deliveries", logical);
  const columns: [string, string][] = [
    [v("destination"), "dispatch_webhook.destination"],
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
    where v.${v("destination")} = dispatch_webhook.destination and v.${v("event")} = dispatch_webhook.event_id::${n.eventIdType};`;
  return `
-- Sends one event to one destination, outside its subscriptions, e.g. from a
-- workflow step. With an event id, dispatching it again returns the first delivery.
create or replace function ${fn}(destination uuid, event_type text, payload jsonb, run_id text default null, event_id text default null)
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
  ${destinationTenant(n, "dispatch_webhook.destination")}
  if not found then
    ${fail("WEBHOOK_DESTINATION_NOT_FOUND", "Webhook destination not found", "P0002")}
  end if;
  ${guard(n, "v_tenant", "manage")}
  if not v_enabled then
    ${fail("WEBHOOK_DESTINATION_DISABLED", "Webhook destination is disabled", "55000")}
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
  on conflict (${v("destination")}, ${v("event")}) where ${v("event")} is not null do nothing`
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

function claim(ctx: KitContext, n: HookNames): string {
  const fn = ctx.fn("claim_webhook_deliveries");
  const d = (logical: string) => n.col("destinations", logical);
  const v = (logical: string) => n.col("deliveries", logical);
  const optional = (logical: string, key: string) =>
    n.has("deliveries", logical) ? `, '${key}', c.${v(logical)}` : "";
  return `
-- Leases due deliveries to one worker. Deliveries of disabled destinations
-- are canceled instead, and a lease that ran out is claimed again.
create or replace function ${fn}(max_items integer default 25, lease interval default '2 minutes')
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
  set ${v("status")} = 'canceled', ${v("leasedUntil")} = null${
    n.has("deliveries", "lastError")
      ? `, ${v("lastError")} = 'Destination is disabled'`
      : ""
  }${n.has("deliveries", "processedAt") ? `, ${v("processedAt")} = now()` : ""}${touched(n, "deliveries")}
  from ${n.table("destinations")} d
  where d.${d("id")} = v.${v("destination")}
    and not d.${d("enabled")}
    and v.${v("status")} in ('pending', 'failed');

  with due as (
    select v.${v("id")} as id
    from ${n.table("deliveries")} v
    where v.${v("status")} in ('pending', 'failed', 'processing')
      and v.${v("availableAt")} <= now()
      and (v.${v("leasedUntil")} is null or v.${v("leasedUntil")} <= now())
    order by v.${v("availableAt")}, v.${v("createdAt")}
    for update skip locked
    limit greatest(1, least(coalesce(claim_webhook_deliveries.max_items, 25), 100))
  ),
  claimed as (
    update ${n.table("deliveries")} v
    set ${v("status")} = 'processing',
      ${v("leasedUntil")} = now() + coalesce(claim_webhook_deliveries.lease, '2 minutes')${touched(n, "deliveries")}
    from due
    where v.${v("id")} = due.id
    returning v.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', c.${v("id")},
    'destination_id', c.${v("destination")},
    'type', c.${v("type")},
    'payload', c.${v("payload")},
    'attempt', c.${v("attempt")},
    'url', d.${d("url")},
    'created_at', c.${v("createdAt")}${optional("tenant", "tenant")}${optional("event", "event_id")}${optional("run", "run_id")}
  ) order by c.${v("availableAt")}), '[]')
  into result
  from claimed c
  join ${n.table("destinations")} d on d.${d("id")} = c.${v("destination")};
  return result;
end;
$$;
${grants(fn, "integer, interval", false)}`;
}

function complete(ctx: KitContext, n: HookNames): string {
  const fn = ctx.fn("complete_webhook_delivery");
  const d = (logical: string) => n.col("destinations", logical);
  const v = (logical: string) => n.col("deliveries", logical);
  const disableAfter = ctx.number("disableAfter", 10);
  if (!Number.isInteger(disableAfter) || disableAfter < 0) {
    throw new TypeError(
      "kits.webhooks-out.options.disableAfter must be a whole number (0 never disables)",
    );
  }
  const sets = [
    `${v("status")} = v_status`,
    `${v("attempt")} = coalesce((complete_webhook_delivery.outcome ->> 'attempt')::integer, v.${v("attempt")} + 1)`,
    `${v("availableAt")} = case when v_status = 'failed' then coalesce((complete_webhook_delivery.outcome ->> 'retry_at')::timestamptz, now()) else v.${v("availableAt")} end`,
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
    ["processedAt", "case when v_status = 'failed' then null else now() end"],
    ["updatedAt", "now()"],
  ];
  for (const [logical, value] of optional)
    if (n.has("deliveries", logical)) sets.push(`${v(logical)} = ${value}`);
  const tenantSelect = n.has("destinations", "tenant")
    ? `, d.${d("tenant")}`
    : ", null";
  const disable = [
    n.has("destinations", "disabledAt") ? `, ${d("disabledAt")} = now()` : "",
    n.has("destinations", "disabledReason")
      ? `, ${d("disabledReason")} = format('%s deliveries in a row failed', v_count)`
      : "",
    touched(n, "destinations"),
  ].join("");
  const streak =
    n.has("destinations", "failureCount") && disableAfter > 0
      ? `
  if v_status = 'completed' then
    update ${n.table("destinations")} d set ${d("failureCount")} = 0
    where d.${d("id")} = v_destination and d.${d("failureCount")} <> 0;
  elsif v_status = 'dead_lettered' then
    update ${n.table("destinations")} d set ${d("failureCount")} = d.${d("failureCount")} + 1
    where d.${d("id")} = v_destination
    returning d.${d("failureCount")}${tenantSelect} into v_count, v_tenant;
    if v_count >= ${String(disableAfter)} then
      update ${n.table("destinations")} d set ${d("enabled")} = false${disable}
      where d.${d("id")} = v_destination and d.${d("enabled")};
      if found then
        v_result := 'disabled';
        ${ctx.emit({
          type: "webhook.disabled",
          payload:
            "jsonb_build_object('endpointId', v_destination, 'failures', v_count)",
          subject: "'webhooks/' || v_destination::text",
          tenant: "v_tenant::text",
        })}
      end if;
    end if;
  end if;`
      : "";
  return `
-- Records an attempt. 'failed' retries at retry_at; 'dead_lettered' counts
-- toward disabling the destination; 'completed' resets the count.
create or replace function ${fn}(delivery uuid, outcome jsonb)
returns text
language plpgsql
security definer
set search_path = ''
as $$
${VARIABLES}
declare
  v_status text := complete_webhook_delivery.outcome ->> 'status';
  v_destination uuid;
  v_tenant ${ctx.idType};
  v_count integer;
  v_result text := 'ok';
begin
  if v_status is null or v_status not in ('completed', 'failed', 'dead_lettered', 'canceled') then
    ${fail("WEBHOOK_STATUS_UNKNOWN", "status must be completed, failed, dead_lettered or canceled", "22023")}
  end if;
  update ${n.table("deliveries")} v
  set ${sets.join(",\n    ")}
  where v.${v("id")} = complete_webhook_delivery.delivery
  returning v.${v("destination")} into v_destination;
  if not found then
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

function redeliver(ctx: KitContext, n: HookNames): string {
  const fn = ctx.fn("redeliver_webhook");
  const v = (logical: string) => n.col("deliveries", logical);
  const resets = [
    `${v("status")} = 'pending'`,
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
  v_destination uuid;
  v_status text;
  v_tenant ${ctx.idType};
  v_enabled boolean;
begin
  select v.${v("destination")}, v.${v("status")} into v_destination, v_status
  from ${n.table("deliveries")} v where v.${v("id")} = redeliver_webhook.delivery;
  if not found then
    ${fail("WEBHOOK_DELIVERY_NOT_FOUND", "Webhook delivery not found", "P0002")}
  end if;
  ${destinationTenant(n, "v_destination")}
  ${guard(n, "v_tenant", "manage")}
  if v_status in ('pending', 'processing') then
    ${fail("WEBHOOK_DELIVERY_IN_PROGRESS", "The delivery is still in progress", "55000")}
  end if;
  if not v_enabled then
    ${fail("WEBHOOK_DESTINATION_DISABLED", "Webhook destination is disabled", "55000")}
  end if;
  update ${n.table("deliveries")} v
  set ${resets.join(", ")}
  where v.${v("id")} = redeliver_webhook.delivery;
  return redeliver_webhook.delivery;
end;
$$;
${grants(fn, "uuid", true)}`;
}

function secrets(ctx: KitContext, n: HookNames): string {
  const rotate = ctx.fn("rotate_webhook_secret");
  const read = ctx.fn("webhook_secrets");
  const s = (logical: string) => n.col("secrets", logical);
  const t = n.table("secrets");
  const expires = n.has("secrets", "expiresAt");
  const ofDestination = `s.${s("destination")} = rotate_webhook_secret.destination`;
  const dropVault = (where: string) =>
    n.vault
      ? `delete from vault.secrets vs using ${t} s where vs.id = s.${s("vaultId")} and ${where};
  `
      : "";
  const retire = expires
    ? `${dropVault(`${ofDestination} and s.${s("expiresAt")} <= now()`)}delete from ${t} s where ${ofDestination} and s.${s("expiresAt")} <= now();
  update ${t} s set ${s("expiresAt")} = now() + coalesce(rotate_webhook_secret.overlap, '24 hours')
  where ${ofDestination} and s.${s("expiresAt")} is null;`
    : `${dropVault(ofDestination)}delete from ${t} s where ${ofDestination};`;
  const columns: [string, string][] = [
    [s("destination"), "rotate_webhook_secret.destination"],
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
create or replace function ${rotate}(destination uuid, overlap interval default '24 hours', secret text default null)
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
  ${destinationTenant(n, "rotate_webhook_secret.destination")}
  if not found then
    ${fail("WEBHOOK_DESTINATION_NOT_FOUND", "Webhook destination not found", "P0002")}
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
    'webhook:' || rotate_webhook_secret.destination::text || ':' || gen_random_uuid()::text,
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

-- The secrets that sign a destination's deliveries: the current one first, then by age.
create or replace function ${read}(destination uuid)
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
    where s.${s("destination")} = webhook_secrets.destination${
      expires
        ? `
      and (s.${s("expiresAt")} is null or s.${s("expiresAt")} > now())`
        : ""
    }
  ) x
$$;
${grants(read, "uuid", false)}`;
}

export function functions(ctx: KitContext, n: HookNames): string {
  return [
    publish(ctx, n),
    dispatch(ctx, n),
    claim(ctx, n),
    complete(ctx, n),
    redeliver(ctx, n),
    secrets(ctx, n),
  ].join("\n");
}
