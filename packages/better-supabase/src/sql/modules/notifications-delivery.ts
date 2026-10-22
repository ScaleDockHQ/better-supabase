import type { BlockSqlContext } from "../context.ts";
import type { NotifyNames } from "./notifications-sql.ts";

import { PARTITION_VARIABLES, dropExpiredPartitions, fail } from "../shared.ts";
import { itemJson } from "./notifications-items.ts";
import { claimSuppression } from "./notifications-suppressions.ts";
import {
  eventsPartitioned,
  keepsTemplateKey,
} from "./notifications-tracking.ts";

/** The worker side: claim pending deliveries of a channel, then complete them. */
export function delivery(ctx: BlockSqlContext, n: NotifyNames): string {
  if (!ctx.hasTable("deliveries")) {
    return "";
  }

  const d = (logical: string) => n.col("deliveries", logical);
  const r = (logical: string) => n.col("recipients", logical);

  const attempts = n.has("deliveries", "attempts")
    ? `, ${d("attempts")} = d.${d("attempts")} + 1`
    : "";

  const set: string[] = [`${d("status")} = v_status`];

  if (n.has("deliveries", "provider")) {
    set.push(
      `${d("provider")} = coalesce(complete_notification_delivery.provider, d.${d("provider")})`,
    );
  }

  if (n.has("deliveries", "providerMessageId")) {
    set.push(
      `${d("providerMessageId")} = coalesce(complete_notification_delivery.provider_message_id, d.${d("providerMessageId")})`,
    );
  }

  if (n.has("deliveries", "error")) {
    set.push(`${d("error")} = complete_notification_delivery.error`);
  }

  const templateKey = keepsTemplateKey(ctx);

  if (templateKey) {
    set.push(
      `${d("templateKey")} = coalesce(complete_notification_delivery.template_key, d.${d("templateKey")})`,
    );
  }

  const completeArgs = `uuid, text, text, text, text, integer${templateKey ? ", text" : ""}`;

  if (n.has("deliveries", "deliveredAt")) {
    set.push(
      `${d("deliveredAt")} = case when v_status = 'sent' then now() else d.${d("deliveredAt")} end`,
    );
  }

  set.push(
    `${d("attemptedAt")} = case when v_status = 'pending' then null else d.${d("attemptedAt")} end`,
  );
  const retries = n.has("deliveries", "attempts");
  const backoff = n.has("deliveries", "nextAttemptAt");
  const suppression = claimSuppression(ctx, n);

  if (backoff) {
    set.push(
      `${d("nextAttemptAt")} = case when v_status = 'pending' then now() + make_interval(secs => 1 + floor(random() * least(3600, 30 * power(2, ${retries ? `greatest(d.${d("attempts")}, 1) - 1` : "0"})))) else d.${d("nextAttemptAt")} end`,
    );
  }

  const lostLease = retries
    ? `
  -- A delivery whose lease ran out on its last attempt lost its worker.
  update ${n.table("deliveries")} d
  set ${d("status")} = 'failed'${n.has("deliveries", "error") ? `, ${d("error")} = 'The lease ran out on the last attempt'` : ""}
  where d.${d("channel")} = claim_notification_deliveries.channel
    and d.${d("status")} = 'pending'
    and d.${d("attempts")} >= greatest(1, coalesce(claim_notification_deliveries.max_attempts, 5))
    and d.${d("attemptedAt")} < now() - claim_notification_deliveries.lease;
`
    : "";

  const giveUp = retries
    ? `
  if v_status = 'pending' and exists (
    select 1 from ${n.table("deliveries")} d
    where d.${d("id")} = complete_notification_delivery.delivery
      and d.${d("attempts")} >= greatest(1, coalesce(complete_notification_delivery.max_attempts, 5))
  ) then
    v_status := 'failed';
  end if;`
    : "";

  return `
drop function if exists ${ctx.fn("claim_notification_deliveries")}(text, integer, interval);
drop function if exists ${ctx.fn("complete_notification_delivery")}(uuid, text, text, text, text);
drop function if exists ${ctx.fn("complete_notification_delivery")}(uuid, text, text, text, text, integer${templateKey ? "" : ", text"});
-- Leases up to max_items due deliveries of one channel and returns them
-- with the notification and the recipient's email, for a NotificationChannel.
create or replace function ${ctx.fn("claim_notification_deliveries")}(channel text, max_items integer default 50, lease interval default '5 minutes', max_attempts integer default 5)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  claimed jsonb;
begin${lostLease}
  with picked as (
    select d.${d("id")} as id from ${n.table("deliveries")} d
    where d.${d("channel")} = claim_notification_deliveries.channel
      and d.${d("status")} = 'pending'${
        backoff
          ? `
      and d.${d("nextAttemptAt")} <= now()`
          : ""
      }
      and (d.${d("attemptedAt")} is null or d.${d("attemptedAt")} < now() - claim_notification_deliveries.lease)
    order by d.${d("createdAt")}
    limit claim_notification_deliveries.max_items
    for update skip locked
  ), leased as (
    update ${n.table("deliveries")} d set ${d("attemptedAt")} = now()${attempts}
    from picked where d.${d("id")} = picked.id
    returning d.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'delivery_id', l.${d("id")},
    'channel', l.${d("channel")},
    'attempts', ${retries ? `l.${d("attempts")}` : "1"},
    'user_id', rc.${r("user")},
    'email', u.email,
    'notification', ${itemJson(n)}${suppression.field}
  )), '[]') into claimed
  from leased l
  join ${n.table("recipients")} rc on rc.${r("id")} = l.${d("recipient")}
  join ${n.table("events")} ev on ev.${n.col("events", "id")} = rc.${r("event")}
  left join auth.users u on u.id = rc.${r("user")}${suppression.join};
  return claimed;
end;
$$;

-- Records the outcome: sent, failed, skipped, or pending to retry. A retry
-- waits a random time up to 30 seconds, doubling per attempt to an hour,
-- and after max_attempts the delivery is failed instead.${templateKey ? " template_key\n-- names the template the channel composed, for list_subject_deliveries." : ""}
create or replace function ${ctx.fn("complete_notification_delivery")}(delivery uuid, status text, provider text default null, provider_message_id text default null, error text default null, max_attempts integer default 5${templateKey ? ", template_key text default null" : ""})
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text := complete_notification_delivery.status;
begin
  if v_status is null or v_status not in ('sent', 'failed', 'skipped', 'pending') then
    ${fail("NOTIFICATION_STATUS_UNKNOWN", "status must be sent, failed, skipped or pending", "22023")}
  end if;${giveUp}
  update ${n.table("deliveries")} d
  set ${set.join(",\n    ")}
  where d.${d("id")} = complete_notification_delivery.delivery;
  return v_status;
end;
$$;
revoke execute on function ${ctx.fn("claim_notification_deliveries")}(text, integer, interval, integer) from public, anon, authenticated;
grant execute on function ${ctx.fn("claim_notification_deliveries")}(text, integer, interval, integer) to service_role;
revoke execute on function ${ctx.fn("complete_notification_delivery")}(${completeArgs}) from public, anon, authenticated;
grant execute on function ${ctx.fn("complete_notification_delivery")}(${completeArgs}) to service_role;`;
}

/**
 * Deletes up to batch notifications older than older_than, with their
 * recipients and deliveries.
 */
export function purge(ctx: BlockSqlContext, n: NotifyNames): string {
  const e = (logical: string) => n.col("events", logical);
  const fn = ctx.fn("purge_notifications");
  const partitioned = eventsPartitioned(ctx);

  return `
-- Deletes up to batch notifications past their retention, with their recipients
-- and deliveries, and returns how many. Run it until it returns less than batch.
create or replace function ${fn}(older_than interval default '90 days', batch integer default 10000)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare v_purged integer;${
    partitioned
      ? `
  v_dropped integer := 0;${PARTITION_VARIABLES}`
      : ""
  }
begin${
    partitioned
      ? `
  -- A delivery event comes after its notification, so a month of them
  -- past every tenant's retention belongs to notifications this deletes.
  ${dropExpiredPartitions({
    table: n.table("deliveryEvents"),
    cutoff: ctx.cutoff("notifications", "coalesce(older_than, '90 days')"),
    purged: "v_dropped",
  })}`
      : ""
  }
  delete from ${n.table("events")}
  where ${e("id")} in (
    select ev.${e("id")} from ${n.table("events")} ev
    where ${ctx.expired("notifications", { at: `ev.${e("createdAt")}`, tenant: n.has("events", "tenant") ? `ev.${e("tenant")}` : "null", fallback: "coalesce(older_than, '90 days')" })}
    order by ev.${e("createdAt")}
    limit coalesce(batch, 10000)
  );
  get diagnostics v_purged = row_count;
  return v_purged;
end;
$$;
revoke execute on function ${fn}(interval, integer) from public, anon, authenticated;
grant execute on function ${fn}(interval, integer) to service_role;`;
}
