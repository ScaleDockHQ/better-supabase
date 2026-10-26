import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";
import type { NotifyNames } from "./notifications-sql.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { fail, pageSize, revokeTable, serviceGrant } from "../shared.ts";

/**
 * Whether the module writes and honours suppressions. A module over the app's
 * tables needs the table mapped explicitly, so an adopter that predates it
 * keeps installing.
 */
export const suppressing = (ctx: BlockSqlContext): boolean =>
  ctx.hasTable("deliveries") &&
  ctx.hasTable("suppressions") &&
  (ctx.manages || ctx.config.tables["suppressions"] !== undefined);

/** The table, its RLS (users read their own rows) and the service-only grants. */
export function suppressionsTable(
  ctx: BlockSqlContext,
  n: NotifyNames,
): string {
  if (!ctx.manages || !suppressing(ctx)) {
    return "";
  }

  const t = n.table("suppressions");
  const c = (logical: string) => n.col("suppressions", logical);
  const policy = sqlIdent("bsb_notification_suppressions_read");

  return `
create table if not exists ${t} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("channel")} text not null default 'email',
  ${c("address")} text not null check (${c("address")} = lower(${c("address")})),
  ${c("user")} uuid references auth.users (id) on delete cascade,
  ${c("reason")} text not null check (${c("reason")} in ('bounce', 'complaint', 'manual')),
  ${c("provider")} text,
  ${c("providerEventId")} text,
  ${c("detail")} jsonb not null default '{}',
  ${c("createdAt")} timestamptz not null default now(),
  unique (${c("channel")}, ${c("address")})
);
create index if not exists notification_suppressions_user_idx on ${t} (${c("user")});
alter table ${t} enable row level security;
${revokeTable(t)}
grant select on ${t} to authenticated;
grant all on ${t} to service_role;
${renderPolicy(makePolicy({ table: t, name: policy, command: "select", roles: ["authenticated"], using: `${c("user")} = (select auth.uid())` }), { drop: true, target: t })}`;
}

/**
 * The suppression's reason for the claimed delivery `l`, joined through `u`
 * (auth.users).
 */
export function claimSuppression(
  ctx: BlockSqlContext,
  n: NotifyNames,
): { readonly join: string; readonly field: string } {
  if (!suppressing(ctx)) {
    return { join: "", field: "" };
  }

  const c = (logical: string) => n.col("suppressions", logical);

  return {
    join: `
  left join ${n.table("suppressions")} s on s.${c("channel")} = l.${n.col("deliveries", "channel")} and s.${c("address")} = lower(u.email)`,
    field: `,
    'suppressed', s.${c("reason")}`,
  };
}

/**
 * `suppress_notification_address` and `unsuppress_notification_address` for the
 * service (bounce and complaint webhooks), and
 * `list_notification_suppressions`, which reads through RLS.
 */
export function suppressionFunctions(
  ctx: BlockSqlContext,
  n: NotifyNames,
): string {
  if (!suppressing(ctx)) {
    return "";
  }

  const t = n.table("suppressions");
  const c = (logical: string) => n.col("suppressions", logical);
  const suppress = ctx.fn("suppress_notification_address");
  const unsuppress = ctx.fn("unsuppress_notification_address");
  const list = ctx.fn("list_notification_suppressions");

  return `
-- Stops a channel from sending to an address after a bounce, a complaint
-- or by hand. The first suppression wins; returns whether it is new.
create or replace function ${suppress}(address text, reason text, channel text default 'email', provider text default null, provider_event_id text default null, detail jsonb default '{}')
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_address text := lower(btrim(suppress_notification_address.address));
begin
  if v_address is null or v_address = '' then
    ${fail("NOTIFICATION_SUPPRESSION_ADDRESS", "address is required", "22023")}
  end if;
  if suppress_notification_address.reason is null or suppress_notification_address.reason not in ('bounce', 'complaint', 'manual') then
    ${fail("NOTIFICATION_SUPPRESSION_REASON", "reason must be bounce, complaint or manual", "22023")}
  end if;
  insert into ${t} (${c("channel")}, ${c("address")}, ${c("user")}, ${c("reason")}, ${c("provider")}, ${c("providerEventId")}, ${c("detail")})
  values (
    coalesce(suppress_notification_address.channel, 'email'),
    v_address,
    (select u.id from auth.users u where lower(u.email) = v_address order by u.created_at limit 1),
    suppress_notification_address.reason,
    suppress_notification_address.provider,
    suppress_notification_address.provider_event_id,
    coalesce(suppress_notification_address.detail, '{}')
  )
  on conflict (${c("channel")}, ${c("address")}) do nothing;
  return found;
end;
$$;
${serviceGrant(`${suppress}(text, text, text, text, text, jsonb)`)}

create or replace function ${unsuppress}(address text, channel text default 'email')
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from ${t} s
  where s.${c("channel")} = coalesce(unsuppress_notification_address.channel, 'email')
    and s.${c("address")} = lower(btrim(unsuppress_notification_address.address));
  return found;
end;
$$;
${serviceGrant(`${unsuppress}(text, text)`)}

-- The caller's suppressions, newest first; the service sees every row.
create or replace function ${list}(max_items integer default 50)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'channel', s.${c("channel")},
    'address', s.${c("address")},
    'user_id', s.${c("user")},
    'reason', s.${c("reason")},
    'provider', s.${c("provider")},
    'created_at', s.${c("createdAt")}
  ) order by s.${c("createdAt")} desc), '[]')
  from (
    select * from ${t} s
    where s.${c("user")} = (select auth.uid()) or (select auth.role()) = 'service_role'
    order by s.${c("createdAt")} desc
    limit ${pageSize("max_items", 50, 200)}
  ) s
$$;
revoke execute on function ${list}(integer) from public, anon;
grant execute on function ${list}(integer) to authenticated, service_role;`;
}

export function suppressionContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  if (!suppressing(ctx)) {
    return [];
  }

  return [
    {
      name: "suppress_notification_address",
      args: ["text", "text", "text", "text", "text", "jsonb"],
      returns: "boolean",
    },
    {
      name: "unsuppress_notification_address",
      args: ["text", "text"],
      returns: "boolean",
    },
    {
      name: "list_notification_suppressions",
      args: ["integer"],
      returns: "jsonb",
    },
  ];
}
