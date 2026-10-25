import type { BlockSqlContext, BlockSqlNames } from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { lockTable, schemaPreamble, serviceOnly } from "../shared.ts";

const NAMES: BlockSqlNames = {
  tables: {
    keys: {
      name: "idempotency_keys",
      app: { writes: false },
      columns: {
        scope: "scope",
        key: "key",
        requestHash: "request_hash",
        status: "status",
        statusCode: "status_code",
        response: "response",
        lockedUntil: "locked_until",
        createdAt: "created_at",
        expiresAt: "expires_at",
        holder: "holder",
      },
      optional: ["createdAt"],
      typed: ["status"],
    },
    leases: {
      name: "leases",
      app: { writes: false },
      columns: {
        scope: "scope",
        key: "key",
        holder: "holder",
        expiresAt: "expires_at",
      },
    },
  },
};

/**
 * The unique index an `on conflict (scope, key)` into `table` needs over the
 * app's table, where the module's primary key isn't there.
 */
function scopeKeyIndex(ctx: BlockSqlContext, table: string): string {
  if (ctx.owns(table)) {
    return "";
  }

  const name = sqlIdent(`bsb_${ctx.tableName(table).name}_scope_key_key`);

  return `\ncreate unique index if not exists ${name} on ${ctx.table(table)} (${ctx.col(table, "scope")}, ${ctx.col(table, "key")});`;
}

function build(ctx: BlockSqlContext): string {
  const keys = ctx.table("keys");
  const leases = ctx.table("leases");
  const k = (column: string): string => ctx.col("keys", column);
  const l = (column: string): string => ctx.col("leases", column);
  const keysName = ctx.tableName("keys").name;

  return `${schemaPreamble(ctx)}

create table if not exists ${keys} (
  ${k("scope")} text not null default '',
  ${k("key")} text not null,
  ${k("requestHash")} text not null,
  ${k("status")} text not null default 'running' check (${k("status")} in ('running', 'completed')),
  ${k("statusCode")} integer,
  ${k("response")} jsonb,
  ${k("lockedUntil")} timestamptz,${ctx.has("keys", "createdAt") ? `\n  ${k("createdAt")} timestamptz not null default now(),` : ""}
  ${k("expiresAt")} timestamptz not null,
  primary key (${k("scope")}, ${k("key")})
);
create index if not exists ${sqlIdent(`${keysName}_expiry_idx`)} on ${keys} (${k("expiresAt")});
-- The token of the request that holds the key while it runs.
alter table ${keys} add column if not exists ${k("holder")} uuid;${scopeKeyIndex(ctx, "keys")}

${lockTable(keys)}

-- state: 'started' (run it, with holder as the token complete and release
-- need), 'replay' (send the stored response), 'running' (another request
-- holds the key) or 'mismatch' (same key, different request).
drop function if exists better_supabase.begin_idempotent(text, text, text, interval, interval);
create or replace function better_supabase.begin_idempotent(
  scope text,
  key text,
  request_hash text,
  ttl interval default '24 hours',
  lock interval default '1 minute'
)
returns table (state text, status_code integer, response jsonb, holder uuid)
language plpgsql
set search_path = ''
as $$
#variable_conflict use_column
declare
  existing ${keys};
  token uuid := gen_random_uuid();
begin
  delete from ${keys} k
  where k.${k("scope")} = begin_idempotent.scope and k.${k("key")} = begin_idempotent.key and k.${k("expiresAt")} < now();

  insert into ${keys} (${k("scope")}, ${k("key")}, ${k("requestHash")}, ${k("status")}, ${k("lockedUntil")}, ${k("expiresAt")}, ${k("holder")})
  values (scope, key, request_hash, ${ctx.cast("keys", "status", "'running'")}, now() + lock, now() + ttl, token)
  on conflict (${k("scope")}, ${k("key")}) do nothing;
  if found then
    return query select 'started'::text, null::integer, null::jsonb, token;
    return;
  end if;

  select * into existing from ${keys} k
  where k.${k("scope")} = begin_idempotent.scope and k.${k("key")} = begin_idempotent.key
  for update;
  if existing.${k("requestHash")} <> request_hash then
    return query select 'mismatch'::text, null::integer, null::jsonb, null::uuid;
  elsif existing.${k("status")} = 'completed' then
    return query select 'replay'::text, existing.${k("statusCode")}, existing.${k("response")}, null::uuid;
  elsif existing.${k("lockedUntil")} < now() then
    -- The holder's lock ran out: this request takes the key over, and the
    -- former holder's complete and release now return false.
    update ${keys} k set ${k("lockedUntil")} = now() + lock, ${k("holder")} = token
    where k.${k("scope")} = begin_idempotent.scope and k.${k("key")} = begin_idempotent.key;
    return query select 'started'::text, null::integer, null::jsonb, token;
  else
    return query select 'running'::text, null::integer, null::jsonb, null::uuid;
  end if;
end;
$$;

-- Stores the response for the holder that begin_idempotent returned; false
-- when another request has taken the key over since.
drop function if exists better_supabase.complete_idempotent(text, text, integer, jsonb);
create or replace function better_supabase.complete_idempotent(
  scope text,
  key text,
  holder uuid,
  status_code integer,
  response jsonb
)
returns boolean
language sql
set search_path = ''
as $$
  with done as (
    update ${keys} k
    set ${k("status")} = ${ctx.cast("keys", "status", "'completed'")}, ${k("statusCode")} = complete_idempotent.status_code,
        ${k("response")} = complete_idempotent.response, ${k("lockedUntil")} = null, ${k("holder")} = null
    where k.${k("scope")} = complete_idempotent.scope and k.${k("key")} = complete_idempotent.key
      and k.${k("status")} = 'running' and k.${k("holder")} = complete_idempotent.holder
    returning 1
  )
  select exists (select 1 from done)
$$;

-- Moves the lock of a running key the holder still has, for a request that
-- runs longer than lock; false once the lock ran out or another request took
-- the key over.
create or replace function better_supabase.extend_idempotent(
  scope text,
  key text,
  holder uuid,
  lock interval default '1 minute'
)
returns boolean
language sql
set search_path = ''
as $$
  with extended as (
    update ${keys} k
    set ${k("lockedUntil")} = now() + extend_idempotent.lock
    where k.${k("scope")} = extend_idempotent.scope and k.${k("key")} = extend_idempotent.key
      and k.${k("status")} = 'running' and k.${k("holder")} = extend_idempotent.holder
      and k.${k("lockedUntil")} > now()
    returning 1
  )
  select exists (select 1 from extended)
$$;

-- On failure: forget the key so the client can retry. False when another
-- request holds it now.
drop function if exists better_supabase.release_idempotent(text, text);
create or replace function better_supabase.release_idempotent(scope text, key text, holder uuid)
returns boolean
language sql
set search_path = ''
as $$
  with released as (
    delete from ${keys} k
    where k.${k("scope")} = release_idempotent.scope and k.${k("key")} = release_idempotent.key
      and k.${k("status")} = 'running' and k.${k("holder")} = release_idempotent.holder
    returning 1
  )
  select exists (select 1 from released)
$$;

-- Leases: one holder per (scope, key) until it expires, for work that must
-- not run twice at once (one automation per conversation). acquire_lease
-- returns the holder token, or null while someone else holds the lease.
create table if not exists ${leases} (
  ${l("scope")} text not null default '',
  ${l("key")} text not null,
  ${l("holder")} uuid not null,
  ${l("expiresAt")} timestamptz not null,
  primary key (${l("scope")}, ${l("key")})
);${scopeKeyIndex(ctx, "leases")}
${lockTable(leases)}

create or replace function better_supabase.acquire_lease(key text, seconds integer default 60, scope text default '')
returns uuid
language plpgsql
set search_path = ''
as $$
#variable_conflict use_column
declare
  token uuid := gen_random_uuid();
  taken uuid;
begin
  insert into ${leases} as l (${l("scope")}, ${l("key")}, ${l("holder")}, ${l("expiresAt")})
  values (scope, key, token, now() + make_interval(secs => greatest(seconds, 1)))
  on conflict (${l("scope")}, ${l("key")}) do update
    set ${l("holder")} = excluded.${l("holder")}, ${l("expiresAt")} = excluded.${l("expiresAt")}
    where l.${l("expiresAt")} <= now()
  returning l.${l("holder")} into taken;
  return taken;
end;
$$;

-- Moves the expiry of a lease the holder still has; false once it is lost.
create or replace function better_supabase.extend_lease(key text, holder uuid, seconds integer default 60, scope text default '')
returns boolean
language sql
set search_path = ''
as $$
  with extended as (
    update ${leases} l
    set ${l("expiresAt")} = now() + make_interval(secs => greatest(extend_lease.seconds, 1))
    where l.${l("scope")} = extend_lease.scope and l.${l("key")} = extend_lease.key
      and l.${l("holder")} = extend_lease.holder and l.${l("expiresAt")} > now()
    returning 1
  )
  select exists (select 1 from extended)
$$;

create or replace function better_supabase.release_lease(key text, holder uuid, scope text default '')
returns boolean
language sql
set search_path = ''
as $$
  with released as (
    delete from ${leases} l
    where l.${l("scope")} = release_lease.scope and l.${l("key")} = release_lease.key and l.${l("holder")} = release_lease.holder
    returning 1
  )
  select exists (select 1 from released)
$$;

create or replace function better_supabase.purge_idempotency_keys()
returns integer
language sql
set search_path = ''
as $$
  with purged as (
    delete from ${keys} k where k.${k("expiresAt")} < now() returning 1
  )
  select count(*)::integer from purged
$$;

${serviceOnly([
  "begin_idempotent(text, text, text, interval, interval)",
  "complete_idempotent(text, text, uuid, integer, jsonb)",
  "extend_idempotent(text, text, uuid, interval)",
  "release_idempotent(text, text, uuid)",
  "purge_idempotency_keys()",
  "acquire_lease(text, integer, text)",
  "extend_lease(text, uuid, integer, text)",
  "release_lease(text, uuid, text)",
])}`;
}

export const IDEMPOTENCY: BlockSqlDefinition = {
  name: "idempotency",
  names: NAMES,
  title: "Idempotency keys",
  description:
    "Stores responses by Idempotency-Key so retried requests replay the first result instead of running twice.",
  requires: [],
  target: "schema",
  build,
};
