import type { BlockSqlContext, BlockSqlTableSpec } from "../context.ts";

import { lockTable } from "../shared.ts";
import { appUniqueIndex } from "./over-app.ts";

/** `names.tables.leases`: one row per (scope, key) that was claimed. */
export const LEASES_TABLE: BlockSqlTableSpec = {
  name: "job_leases",
  app: { writes: false },
  columns: {
    scope: "scope",
    key: "key",
    holder: "holder",
    state: "state",
    expiresAt: "expires_at",
  },
};

/** The function signatures `serviceOnly` grants for the leases. */
export const LEASE_FUNCTIONS: readonly string[] = [
  "claim_lease(text, text, integer)",
  "extend_lease_claim(text, text, uuid, integer)",
  "complete_lease(text, text, uuid, integer)",
  "release_lease_claim(text, text, uuid)",
];

/**
 * Leases on any (scope, key), for work that must run once at a time and can
 * finish for good, such as one drain per tenant or one import per file. The
 * `idempotency` module's `acquire_lease` family stays as it was; these are
 * named apart so the two never overload.
 */
export function leasesSql(ctx: BlockSqlContext): string {
  const leases = ctx.table("leases");
  const l = (column: string): string => ctx.col("leases", column);

  return `-- Leases: claim_lease answers claimed (the caller holds it until expires_at),
-- busy (another holder does; retry_after_ms says when it ends) or completed
-- (a holder finished it, and it stays finished until its keep time ends).
create table if not exists ${leases} (
  ${l("scope")} text not null default '',
  ${l("key")} text not null,
  ${l("holder")} uuid not null,
  ${l("state")} text not null default 'held' check (${l("state")} in ('held', 'completed')),
  ${l("expiresAt")} timestamptz not null,
  primary key (${l("scope")}, ${l("key")})
);
${lockTable(leases)}${appUniqueIndex(ctx, "leases", ["scope", "key"])}

create or replace function better_supabase.claim_lease(scope text, key text, lease_seconds integer default 60)
returns table (lease_state text, lease_holder uuid, lease_expires_at timestamptz, retry_after_ms integer)
language plpgsql
set search_path = ''
as $$
#variable_conflict use_column
declare
  token uuid := gen_random_uuid();
  lease_expires_at timestamptz := now() + make_interval(secs => greatest(coalesce(lease_seconds, 60), 1));
  taken ${leases}%rowtype;
begin
  -- A held lease that ran out, or a completed one past its keep time, is taken
  -- over; the new holder token makes the former holder's calls return false.
  insert into ${leases} as l (${l("scope")}, ${l("key")}, ${l("holder")}, ${l("state")}, ${l("expiresAt")})
  values (scope, key, token, 'held', lease_expires_at)
  on conflict (${l("scope")}, ${l("key")}) do update
    set ${l("holder")} = excluded.${l("holder")}, ${l("state")} = 'held', ${l("expiresAt")} = excluded.${l("expiresAt")}
    where l.${l("expiresAt")} <= now()
  returning * into taken;
  if found then
    return query select 'claimed'::text, token, lease_expires_at, 0;
    return;
  end if;

  select * into taken from ${leases} l
  where l.${l("scope")} = claim_lease.scope and l.${l("key")} = claim_lease.key;
  if not found then
    -- Released between the insert and the read: the caller can retry at once.
    return query select 'busy'::text, null::uuid, null::timestamptz, 0;
    return;
  end if;
  return query select
    case when taken.${l("state")} = 'completed' then 'completed' else 'busy' end,
    null::uuid,
    taken.${l("expiresAt")},
    greatest(ceil(extract(epoch from taken.${l("expiresAt")} - now()) * 1000)::integer, 0);
end;
$$;

-- Moves the expiry of a held lease the holder still has; false once it ran out
-- or another holder took it over.
create or replace function better_supabase.extend_lease_claim(scope text, key text, holder uuid, lease_seconds integer default 60)
returns boolean
language sql
set search_path = ''
as $$
  with extended as (
    update ${leases} l
    set ${l("expiresAt")} = now() + make_interval(secs => greatest(coalesce(extend_lease_claim.lease_seconds, 60), 1))
    where l.${l("scope")} = extend_lease_claim.scope and l.${l("key")} = extend_lease_claim.key
      and l.${l("holder")} = extend_lease_claim.holder and l.${l("state")} = 'held'
      and l.${l("expiresAt")} > now()
    returning 1
  )
  select exists (select 1 from extended)
$$;

-- Marks the work done: later claims answer completed for keep_seconds (a day by
-- default), then the key can be claimed again. False when another holder took
-- the lease over.
create or replace function better_supabase.complete_lease(scope text, key text, holder uuid, keep_seconds integer default 86400)
returns boolean
language sql
set search_path = ''
as $$
  with done as (
    update ${leases} l
    set ${l("state")} = 'completed',
        ${l("expiresAt")} = now() + make_interval(secs => greatest(coalesce(complete_lease.keep_seconds, 86400), 1))
    where l.${l("scope")} = complete_lease.scope and l.${l("key")} = complete_lease.key
      and l.${l("holder")} = complete_lease.holder and l.${l("state")} = 'held'
    returning 1
  )
  select exists (select 1 from done)
$$;

-- On failure: gives the lease up so the next claim succeeds at once. False when
-- another holder has it now, or it was completed.
create or replace function better_supabase.release_lease_claim(scope text, key text, holder uuid)
returns boolean
language sql
set search_path = ''
as $$
  with released as (
    delete from ${leases} l
    where l.${l("scope")} = release_lease_claim.scope and l.${l("key")} = release_lease_claim.key
      and l.${l("holder")} = release_lease_claim.holder and l.${l("state")} = 'held'
    returning 1
  )
  select exists (select 1 from released)
$$;`;
}
