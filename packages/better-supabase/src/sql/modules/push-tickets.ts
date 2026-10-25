import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";

import { fail, revokeTable, SERVICE_CALLER } from "../shared.ts";

/**
 * `push_tickets` needs the notifications block's deliveries: each ticket
 * belongs to one delivery, which keeps Expo's first ticket id as its provider
 * message id.
 */
function storesTickets(ctx: BlockSqlContext): boolean {
  if (!ctx.installed("notifications")) {
    return false;
  }

  const notifications = ctx.of("notifications");

  return (
    notifications.hasTable("deliveries") &&
    notifications.has("deliveries", "providerMessageId")
  );
}

/** Whether a receipt also writes `notification.delivered` or `bounced`. */
function recordsEvents(ctx: BlockSqlContext): boolean {
  return ctx.of("notifications").hasTable("deliveryEvents");
}

const TICKET_FUNCTIONS = [
  ["record_push_tickets", "uuid, jsonb"],
  ["push_tickets_for", "uuid"],
  ["unchecked_push_tickets", "integer, interval"],
  ["complete_push_receipts", "jsonb"],
] as const;

/**
 * The tickets Expo returned per delivery and device, which the receipt check
 * reads about 15 minutes later. Service role only.
 */
export function pushTickets(ctx: BlockSqlContext): string {
  if (!storesTickets(ctx)) {
    return "";
  }

  const notifications = ctx.of("notifications");
  const d = (logical: string) => notifications.col("deliveries", logical);
  const t = ctx.table("tickets");
  const c = (logical: string): string => ctx.col("tickets", logical);
  const fn = (name: string): string => ctx.fn(name);

  const serviceOnly = `
  if not (${SERVICE_CALLER}) then
    ${fail("PUSH_FORBIDDEN", "only the service role reads push tickets")}
  end if;`;

  const events = recordsEvents(ctx)
    ? `
  -- The delivery's provider message id is Expo's first ticket id, so every
  -- receipt of the delivery records its event on that message, once per
  -- ticket.
  perform ${notifications.fn("record_delivery_event")}(
    'expo',
    d.${d("providerMessageId")},
    case when r ->> 'status' = 'ok' then 'delivered' else 'bounced' end,
    'expo-receipt:' || (r ->> 'id'),
    now(),
    jsonb_strip_nulls(jsonb_build_object('token', x.${c("token")}, 'error', r ->> 'error', 'message', r ->> 'message')),
    false
  )
  from ${t} x
  join ${notifications.table("deliveries")} d on d.${d("id")} = x.${c("delivery")}
  cross join jsonb_array_elements(complete_push_receipts.receipts) r
  where x.${c("ticket")} = r ->> 'id'
    and x.${c("checkedAt")} is null
    and d.${d("providerMessageId")} is not null;`
    : "";

  return `
-- One row per delivery and device: the Expo ticket id, or the error Expo
-- answered. A retried delivery skips the devices that already have a ticket.
create table if not exists ${t} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("delivery")} uuid not null references ${notifications.table("deliveries")} (${d("id")}) on delete cascade,
  ${c("token")} text not null,
  ${c("ticket")} text,
  ${c("status")} text not null default 'pending' check (${c("status")} in ('pending', 'ok', 'error')),
  ${c("error")} text,
  ${c("createdAt")} timestamptz not null default now(),
  ${c("checkedAt")} timestamptz,
  unique (${c("delivery")}, ${c("token")})
);
create index if not exists push_tickets_unchecked_idx on ${t} (${c("createdAt")}) where ${c("checkedAt")} is null and ${c("ticket")} is not null;
alter table ${t} enable row level security;
${revokeTable(t)}
grant all on ${t} to service_role;

-- Stores the tickets of one delivery: [{ token, id } | { token, error }].
-- A ticket with an id replaces an earlier error for the same device and is
-- never replaced itself.
create or replace function ${fn("record_push_tickets")}(delivery uuid, tickets jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin${serviceOnly}
  if jsonb_typeof(record_push_tickets.tickets) <> 'array' or jsonb_array_length(record_push_tickets.tickets) > 1000 then
    ${fail("PUSH_TOO_MANY", "pass at most 1000 tickets", "22023")}
  end if;
  insert into ${t} as x (${c("delivery")}, ${c("token")}, ${c("ticket")}, ${c("status")}, ${c("error")})
  select record_push_tickets.delivery, e ->> 'token', e ->> 'id',
    case when e ->> 'id' is null then 'error' else 'pending' end,
    e ->> 'error'
  from jsonb_array_elements(record_push_tickets.tickets) e
  where e ->> 'token' is not null
  on conflict (${c("delivery")}, ${c("token")}) do update set
    ${c("ticket")} = coalesce(excluded.${c("ticket")}, x.${c("ticket")}),
    ${c("status")} = case when x.${c("ticket")} is not null then x.${c("status")} else excluded.${c("status")} end,
    ${c("error")} = case
      when x.${c("ticket")} is not null then x.${c("error")}
      when excluded.${c("ticket")} is not null then null
      else excluded.${c("error")}
    end;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- [{ token, id, error }] already stored for a delivery, in insert order.
create or replace function ${fn("push_tickets_for")}(delivery uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin${serviceOnly}
  return (
    select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'token', x.${c("token")},
      'id', x.${c("ticket")},
      'error', x.${c("error")}
    )) order by x.${c("createdAt")}, x.${c("token")}), '[]'::jsonb)
    from ${t} x
    where x.${c("delivery")} = push_tickets_for.delivery
  );
end;
$$;

-- [{ id, token, deliveryId }] for tickets older than older_than whose
-- receipt nobody read yet, oldest first.
create or replace function ${fn("unchecked_push_tickets")}(max_items integer default 1000, older_than interval default '15 minutes')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin${serviceOnly}
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', x.${c("ticket")},
      'token', x.${c("token")},
      'deliveryId', x.${c("delivery")}
    ) order by x.${c("createdAt")}), '[]'::jsonb)
    from (
      select * from ${t} y
      where y.${c("checkedAt")} is null
        and y.${c("ticket")} is not null
        and y.${c("createdAt")} <= now() - unchecked_push_tickets.older_than
      order by y.${c("createdAt")}
      limit least(greatest(coalesce(unchecked_push_tickets.max_items, 1000), 1), 1000)
    ) x
  );
end;
$$;

-- Stores what Expo answered for each ticket, [{ id, status: ok | error,
-- error, message }], and records notification.delivered or bounced on the
-- delivery when the notifications block tracks provider events. A ticket
-- Expo has no receipt for yet stays unchecked. Returns how many it stored.
create or replace function ${fn("complete_push_receipts")}(receipts jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin${serviceOnly}
  if jsonb_typeof(complete_push_receipts.receipts) <> 'array' or jsonb_array_length(complete_push_receipts.receipts) > 1000 then
    ${fail("PUSH_TOO_MANY", "pass at most 1000 receipts", "22023")}
  end if;${events}
  update ${t} x set
    ${c("status")} = case when r ->> 'status' = 'ok' then 'ok' else 'error' end,
    ${c("error")} = case when r ->> 'status' = 'ok' then null else coalesce(r ->> 'error', 'Unknown') end,
    ${c("checkedAt")} = now()
  from jsonb_array_elements(complete_push_receipts.receipts) r
  where x.${c("ticket")} = r ->> 'id'
    and x.${c("checkedAt")} is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
${TICKET_FUNCTIONS.map(
  ([
    name,
    args,
  ]) => `revoke execute on function ${fn(name)}(${args}) from public, anon, authenticated;
grant execute on function ${fn(name)}(${args}) to service_role;`,
).join("\n")}`;
}

export function ticketsContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  if (!storesTickets(ctx)) {
    return [];
  }

  return [
    {
      name: "record_push_tickets",
      args: ["uuid", "jsonb"],
      returns: "integer",
    },
    { name: "push_tickets_for", args: ["uuid"], returns: "jsonb" },
    {
      name: "unchecked_push_tickets",
      args: ["integer", "interval"],
      returns: "jsonb",
    },
    { name: "complete_push_receipts", args: ["jsonb"], returns: "integer" },
  ];
}
