import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";
import type { NotifyNames } from "./notifications-sql.ts";

import { fail, revokeTable } from "../shared.ts";
import { addressSql } from "./notifications-address.ts";
import { itemJson } from "./notifications-items.ts";

/** How often a digest of held notifications goes out, per cadence. */
const INTERVALS = { daily: "1 day", weekly: "7 days" } as const;

/** The `digests` table of the module's names, rendered only in managed mode. */
export const DIGEST_TABLE = {
  name: "notification_digests",
  lifecycle: { user: "user", tenant: "tenant" },
  columns: {
    id: "id",
    user: "user_id",
    tenant: "tenant_id",
    channel: "channel",
    cadence: "cadence",
    items: "items",
    itemCount: "item_count",
    status: "status",
    attempts: "attempts",
    attemptedAt: "attempted_at",
    error: "error",
    providerMessageId: "provider_message_id",
    sentAt: "sent_at",
    createdAt: "created_at",
  },
  optional: ["tenant"],
  optionalTable: true,
  app: { onlyWhenMapped: true },
} as const;

/**
 * Whether the digest engine renders: managed tables for the preferences with a
 * cadence column, the deliveries and the digests.
 */
function digesting(ctx: BlockSqlContext, n: NotifyNames): boolean {
  return (
    ctx.manages &&
    ctx.hasTable("deliveries") &&
    ctx.hasTable("preferences") &&
    ctx.hasTable("digests") &&
    n.has("preferences", "cadence")
  );
}

/**
 * The cadence column on the preferences, for a managed table created before it
 * existed, and the delivery statuses a held and a folded delivery use.
 */
export function digestUpgrade(ctx: BlockSqlContext): string {
  if (
    !ctx.manages ||
    !ctx.hasTable("preferences") ||
    !ctx.hasTable("deliveries")
  ) {
    return "";
  }

  const preferences = ctx.table("preferences");
  const deliveries = ctx.table("deliveries");
  const status = ctx.col("deliveries", "status");

  return `alter table ${preferences} add column if not exists ${ctx.col("preferences", "cadence")} text not null default 'immediate' check (${ctx.col("preferences", "cadence")} in ('immediate', 'daily', 'weekly', 'off'));
do $digest$
declare c record;
begin
  for c in
    select conname from pg_constraint
    where conrelid = '${deliveries}'::regclass and contype = 'c'
      and pg_get_constraintdef(oid) like '%''skipped''%' and pg_get_constraintdef(oid) not like '%''held''%'
  loop
    execute format('alter table ${deliveries} drop constraint %I', c.conname);
  end loop;
  alter table ${deliveries} add constraint notification_deliveries_status_held_check
    check (${status} in ('pending', 'sent', 'failed', 'skipped', 'held', 'digested'));
exception when duplicate_object then null;
end
$digest$;`;
}

/** The digests table: service-only writes, and each user reads their own. */
export function digestTable(ctx: BlockSqlContext, n: NotifyNames): string {
  if (!digesting(ctx, n)) {
    return "";
  }

  const t = n.table("digests");
  const c = (logical: string) => n.col("digests", logical);

  return `
-- One email of the notifications a member held back: what was folded, and how
-- sending it went.
create table if not exists ${t} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("user")} uuid not null references auth.users (id) on delete cascade,
  ${n.has("digests", "tenant") ? `${c("tenant")} ${ctx.idType},` : ""}
  ${c("channel")} text not null,
  ${c("cadence")} text not null check (${c("cadence")} in ('daily', 'weekly')),
  ${c("items")} jsonb not null,
  ${c("itemCount")} integer not null,
  ${c("status")} text not null default 'pending' check (${c("status")} in ('pending', 'sent', 'failed', 'skipped')),
  ${c("attempts")} integer not null default 0,
  ${c("attemptedAt")} timestamptz,
  ${c("error")} text,
  ${c("providerMessageId")} text,
  ${c("sentAt")} timestamptz,
  ${c("createdAt")} timestamptz not null default now()
);
create index if not exists notification_digests_user_idx on ${t} (${c("user")});
create index if not exists notification_digests_pending_idx on ${t} (${c("createdAt")}) where ${c("status")} = 'pending';
alter table ${t} enable row level security;
${revokeTable(t)}
grant all on ${t} to service_role;`;
}

/** `notification_cadence`: the preference order of `notification_enabled`. */
function cadenceFunction(ctx: BlockSqlContext, n: NotifyNames): string {
  const p = (logical: string) => n.col("preferences", logical);
  const tenant = n.has("preferences", "tenant");
  const fn = ctx.fn("notification_cadence");
  const id = ctx.idType;

  return `
-- How a member wants a type on a channel: immediate, daily, weekly or off,
-- chosen the way notification_enabled chooses, immediate when nothing is set.
create or replace function ${fn}(member uuid, tenant ${id}, type text, channel text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select p.${p("cadence")} from ${n.table("preferences")} p
    where p.${p("user")} = notification_cadence.member
      and p.${p("channel")} = notification_cadence.channel
      and (p.${p("type")} = notification_cadence.type or p.${p("type")} = '*')${
        tenant
          ? `
      and (p.${p("tenant")} is null or p.${p("tenant")} = notification_cadence.tenant)
    order by p.${p("tenant")} is null, p.${p("type")} = '*'`
          : `
    order by p.${p("type")} = '*'`
      }
    limit 1
  ), 'immediate')
$$;
revoke execute on function ${fn}(uuid, ${id}, text, text) from public, anon, authenticated;
grant execute on function ${fn}(uuid, ${id}, text, text) to service_role;`;
}

/**
 * `set_notification_cadence` for the member, `run_notification_digests` (the
 * `digest_run` job) that folds due held deliveries into digests, and the claim
 * and complete pair a sender uses.
 */
export function digestFunctions(ctx: BlockSqlContext, n: NotifyNames): string {
  if (!digesting(ctx, n)) {
    return "";
  }

  const id = ctx.idType;
  const p = (logical: string) => n.col("preferences", logical);
  const d = (logical: string) => n.col("deliveries", logical);
  const r = (logical: string) => n.col("recipients", logical);
  const e = (logical: string) => n.col("events", logical);
  const g = (logical: string) => n.col("digests", logical);
  const tenant = n.has("preferences", "tenant");

  const eventTenant = n.has("events", "tenant")
    ? `ev.${e("tenant")}`
    : `null::${id}`;

  const digestTenant = n.has("digests", "tenant");

  const set = ctx.fn("set_notification_cadence");
  const run = ctx.fn("run_notification_digests");
  const claim = ctx.fn("claim_notification_digests");
  const complete = ctx.fn("complete_notification_digest");

  return `${cadenceFunction(ctx, n)}

-- Sets how often a type on a channel reaches the caller: immediate, daily,
-- weekly or off, for one organization or everywhere (tenant null).
create or replace function ${set}(type text, channel text, cadence text, tenant ${id} default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    ${fail("NOTIFICATION_FORBIDDEN", "Sign in to change notification preferences")}
  end if;
  if set_notification_cadence.cadence is null or set_notification_cadence.cadence not in ('immediate', 'daily', 'weekly', 'off') then
    ${fail("NOTIFICATION_CADENCE_UNKNOWN", "cadence must be immediate, daily, weekly or off", "22023")}
  end if;
  update ${n.table("preferences")} x set ${p("cadence")} = set_notification_cadence.cadence
  where x.${p("user")} = auth.uid() and x.${p("type")} = set_notification_cadence.type
    and x.${p("channel")} = set_notification_cadence.channel${tenant ? `\n    and x.${p("tenant")} is not distinct from set_notification_cadence.tenant` : ""};
  if not found then
    insert into ${n.table("preferences")} (${[p("user"), ...(tenant ? [p("tenant")] : []), p("type"), p("channel"), p("cadence")].join(", ")})
    values (${["auth.uid()", ...(tenant ? ["set_notification_cadence.tenant"] : []), "set_notification_cadence.type", "set_notification_cadence.channel", "set_notification_cadence.cadence"].join(", ")});
  end if;
end;
$$;
revoke execute on function ${set}(text, text, text, ${id}) from public, anon;
grant execute on function ${set}(text, text, text, ${id}) to authenticated, service_role;

-- Folds each member's held deliveries into one pending digest per channel once
-- the oldest of them is a day (daily) or a week (weekly) old. Returns how many
-- digests and deliveries it folded. The 'digest_run' housekeeping job.
create or replace function ${run}(max_digests integer default 100)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group record;
  v_ids uuid[];
  v_digests integer := 0;
  v_items integer := 0;
  v_count integer;
begin
  for v_group in
    select rc.${r("user")} as member, ${eventTenant} as tenant, d.${d("channel")} as channel,
      min(case ${ctx.fn("notification_cadence")}(rc.${r("user")}, ${eventTenant}, ev.${e("type")}, d.${d("channel")}) when 'weekly' then 'weekly' else 'daily' end) as cadence
    from ${n.table("deliveries")} d
    join ${n.table("recipients")} rc on rc.${r("id")} = d.${d("recipient")}
    join ${n.table("events")} ev on ev.${e("id")} = rc.${r("event")}
    where d.${d("status")} = 'held'
      and d.${d("createdAt")} <= now() - case ${ctx.fn("notification_cadence")}(rc.${r("user")}, ${eventTenant}, ev.${e("type")}, d.${d("channel")}) when 'weekly' then interval '${INTERVALS.weekly}' else interval '${INTERVALS.daily}' end
    group by 1, 2, 3
    limit greatest(1, coalesce(run_notification_digests.max_digests, 100))
  loop
    select coalesce(array_agg(d.${d("id")}), '{}') into v_ids
    from (
      select d.${d("id")} from ${n.table("deliveries")} d
      join ${n.table("recipients")} rc on rc.${r("id")} = d.${d("recipient")}
      join ${n.table("events")} ev on ev.${e("id")} = rc.${r("event")}
      where d.${d("status")} = 'held' and d.${d("channel")} = v_group.channel
        and rc.${r("user")} = v_group.member and ${eventTenant} is not distinct from v_group.tenant
      for update of d skip locked
    ) d;
    if cardinality(v_ids) = 0 then
      continue;
    end if;
    insert into ${n.table("digests")} (${[g("user"), ...(digestTenant ? [g("tenant")] : []), g("channel"), g("cadence"), g("items"), g("itemCount")].join(", ")})
    select v_group.member, ${digestTenant ? "v_group.tenant, " : ""}v_group.channel, v_group.cadence,
      coalesce(jsonb_agg(${itemJson(n)} order by rc.${r("createdAt")}, rc.${r("id")}), '[]'), count(*)
    from ${n.table("deliveries")} d
    join ${n.table("recipients")} rc on rc.${r("id")} = d.${d("recipient")}
    join ${n.table("events")} ev on ev.${e("id")} = rc.${r("event")}
    where d.${d("id")} = any(v_ids);
    update ${n.table("deliveries")} d set ${d("status")} = 'digested' where d.${d("id")} = any(v_ids);
    get diagnostics v_count = row_count;
    v_digests := v_digests + 1;
    v_items := v_items + v_count;
  end loop;
  return jsonb_build_object('digests', v_digests, 'items', v_items);
end;
$$;
revoke execute on function ${run}(integer) from public, anon, authenticated;
grant execute on function ${run}(integer) to service_role;

-- Leases up to max_items pending digests with the recipient's email, for a
-- sender that mails each one.
create or replace function ${claim}(max_items integer default 50, lease interval default '5 minutes', max_attempts integer default 5)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  claimed jsonb;
begin
  update ${n.table("digests")} x set ${g("status")} = 'failed', ${g("error")} = 'The lease ran out on the last attempt'
  where x.${g("status")} = 'pending' and x.${g("attempts")} >= greatest(1, coalesce(claim_notification_digests.max_attempts, 5))
    and x.${g("attemptedAt")} < now() - claim_notification_digests.lease;
  with picked as (
    select x.${g("id")} as id from ${n.table("digests")} x
    where x.${g("status")} = 'pending'
      and (x.${g("attemptedAt")} is null or x.${g("attemptedAt")} < now() - claim_notification_digests.lease)
    order by x.${g("createdAt")}
    limit claim_notification_digests.max_items
    for update skip locked
  ), leased as (
    update ${n.table("digests")} x set ${g("attemptedAt")} = now(), ${g("attempts")} = x.${g("attempts")} + 1
    from picked where x.${g("id")} = picked.id
    returning x.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'digest_id', l.${g("id")},
    'user_id', l.${g("user")},
    'email', ${addressSql(ctx, `l.${g("user")}`, `l.${g("channel")}`, "u.email")},
    'channel', l.${g("channel")},
    'cadence', l.${g("cadence")},${digestTenant ? `\n    'tenant', l.${g("tenant")},` : ""}
    'item_count', l.${g("itemCount")},
    'items', l.${g("items")}
  )), '[]') into claimed
  from leased l left join auth.users u on u.id = l.${g("user")};
  return claimed;
end;
$$;

-- Records how sending a digest went: sent, failed, skipped, or pending to retry.
create or replace function ${complete}(digest uuid, status text, provider_message_id text default null, error text default null, max_attempts integer default 5)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_outcome text := complete_notification_digest.status;
begin
  if v_outcome is null or v_outcome not in ('sent', 'failed', 'skipped', 'pending') then
    ${fail("NOTIFICATION_STATUS_UNKNOWN", "status must be sent, failed, skipped or pending", "22023")}
  end if;
  if v_outcome = 'pending' and exists (
    select 1 from ${n.table("digests")} x
    where x.${g("id")} = complete_notification_digest.digest
      and x.${g("attempts")} >= greatest(1, coalesce(complete_notification_digest.max_attempts, 5))
  ) then
    v_outcome := 'failed';
  end if;
  update ${n.table("digests")} x set ${g("status")} = v_outcome,
    ${g("providerMessageId")} = coalesce(complete_notification_digest.provider_message_id, x.${g("providerMessageId")}),
    ${g("error")} = complete_notification_digest.error,
    ${g("sentAt")} = case when v_outcome = 'sent' then now() else x.${g("sentAt")} end,
    ${g("attemptedAt")} = case when v_outcome = 'pending' then null else x.${g("attemptedAt")} end
  where x.${g("id")} = complete_notification_digest.digest;
  return v_outcome;
end;
$$;
revoke execute on function ${claim}(integer, interval, integer) from public, anon, authenticated;
grant execute on function ${claim}(integer, interval, integer) to service_role;
revoke execute on function ${complete}(uuid, text, text, text, integer) from public, anon, authenticated;
grant execute on function ${complete}(uuid, text, text, text, integer) to service_role;`;
}

/** The functions of the digest engine, for the module's contract. */
export function digestContract(
  ctx: BlockSqlContext,
  n: NotifyNames,
): readonly BlockSqlContractFunction[] {
  if (!digesting(ctx, n)) {
    return [];
  }

  return [
    {
      name: "set_notification_cadence",
      args: ["text", "text", "text", "{id}"],
      returns: "void",
    },
    { name: "run_notification_digests", args: ["integer"], returns: "jsonb" },
    {
      name: "claim_notification_digests",
      args: ["integer", "interval", "integer"],
      returns: "jsonb",
    },
    {
      name: "complete_notification_digest",
      args: ["uuid", "text", "text", "text", "integer"],
      returns: "text",
    },
  ];
}

/**
 * The status a new delivery of a non-in-app channel starts in: held for a daily
 * or weekly cadence, pending otherwise.
 */
export function heldStatus(
  ctx: BlockSqlContext,
  n: NotifyNames,
  member: string,
): string {
  if (!digesting(ctx, n)) {
    return "'pending'";
  }

  return `case when ${ctx.fn("notification_cadence")}(${member}, v_tenant, v_type, c) in ('daily', 'weekly') then 'held' else 'pending' end`;
}

/** Excludes a preference whose cadence is off, for `alias` the preferences row. */
export function notOff(n: NotifyNames, alias: string): string {
  return n.has("preferences", "cadence")
    ? ` and ${alias}.${n.col("preferences", "cadence")} is distinct from 'off'`
    : "";
}
