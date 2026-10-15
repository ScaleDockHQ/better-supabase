-- ==== alone: schema supabase/schemas/900_better_supabase_08_idempotency.sql
-- better-supabase module: idempotency
-- @bs-module idempotency@1 managed
-- Stores responses by Idempotency-Key so retried requests replay the first result instead of running twice.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

create table if not exists better_supabase.idempotency_keys (
  scope text not null default '',
  key text not null,
  request_hash text not null,
  status text not null default 'running' check (status in ('running', 'completed')),
  status_code integer,
  response jsonb,
  locked_until timestamptz,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  primary key (scope, key)
);
create index if not exists idempotency_keys_expiry_idx on better_supabase.idempotency_keys (expires_at);
-- The token of the request that holds the key while it runs.
alter table better_supabase.idempotency_keys add column if not exists holder uuid;

alter table better_supabase.idempotency_keys enable row level security;
revoke all on better_supabase.idempotency_keys from anon, authenticated;
grant all on better_supabase.idempotency_keys to service_role;

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
  existing better_supabase.idempotency_keys;
  token uuid := gen_random_uuid();
begin
  delete from better_supabase.idempotency_keys k
  where k.scope = begin_idempotent.scope and k.key = begin_idempotent.key and k.expires_at < now();

  insert into better_supabase.idempotency_keys (scope, key, request_hash, locked_until, expires_at, holder)
  values (scope, key, request_hash, now() + lock, now() + ttl, token)
  on conflict on constraint idempotency_keys_pkey do nothing;
  if found then
    return query select 'started'::text, null::integer, null::jsonb, token;
    return;
  end if;

  select * into existing from better_supabase.idempotency_keys k
  where k.scope = begin_idempotent.scope and k.key = begin_idempotent.key
  for update;
  if existing.request_hash <> request_hash then
    return query select 'mismatch'::text, null::integer, null::jsonb, null::uuid;
  elsif existing.status = 'completed' then
    return query select 'replay'::text, existing.status_code, existing.response, null::uuid;
  elsif existing.locked_until < now() then
    -- The holder's lock ran out: this request takes the key over, and the
    -- former holder's complete and release now return false.
    update better_supabase.idempotency_keys k set locked_until = now() + lock, holder = token
    where k.scope = begin_idempotent.scope and k.key = begin_idempotent.key;
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
    update better_supabase.idempotency_keys k
    set status = 'completed', status_code = complete_idempotent.status_code,
        response = complete_idempotent.response, locked_until = null, holder = null
    where k.scope = complete_idempotent.scope and k.key = complete_idempotent.key
      and k.status = 'running' and k.holder = complete_idempotent.holder
    returning 1
  )
  select exists (select 1 from done)
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
    delete from better_supabase.idempotency_keys k
    where k.scope = release_idempotent.scope and k.key = release_idempotent.key
      and k.status = 'running' and k.holder = release_idempotent.holder
    returning 1
  )
  select exists (select 1 from released)
$$;

-- Leases: one holder per (scope, key) until it expires, for work that must
-- not run twice at once (one automation per conversation). acquire_lease
-- returns the holder token, or null while someone else holds the lease.
create table if not exists better_supabase.leases (
  scope text not null default '',
  key text not null,
  holder uuid not null,
  expires_at timestamptz not null,
  primary key (scope, key)
);
alter table better_supabase.leases enable row level security;
revoke all on better_supabase.leases from anon, authenticated;
grant all on better_supabase.leases to service_role;

create or replace function better_supabase.acquire_lease(key text, seconds integer default 60, scope text default '')
returns uuid
language plpgsql
set search_path = ''
as $$
#variable_conflict use_variable
declare
  token uuid := gen_random_uuid();
  taken uuid;
begin
  insert into better_supabase.leases as l (scope, key, holder, expires_at)
  values (scope, key, token, now() + make_interval(secs => greatest(seconds, 1)))
  on conflict on constraint leases_pkey do update
    set holder = excluded.holder, expires_at = excluded.expires_at
    where l.expires_at <= now()
  returning l.holder into taken;
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
    update better_supabase.leases l
    set expires_at = now() + make_interval(secs => greatest(extend_lease.seconds, 1))
    where l.scope = extend_lease.scope and l.key = extend_lease.key
      and l.holder = extend_lease.holder and l.expires_at > now()
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
    delete from better_supabase.leases l
    where l.scope = release_lease.scope and l.key = release_lease.key and l.holder = release_lease.holder
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
    delete from better_supabase.idempotency_keys where expires_at < now() returning 1
  )
  select count(*)::integer from purged
$$;

revoke execute on function better_supabase.begin_idempotent(text, text, text, interval, interval) from public, anon, authenticated;
grant execute on function better_supabase.begin_idempotent(text, text, text, interval, interval) to service_role;
revoke execute on function better_supabase.complete_idempotent(text, text, uuid, integer, jsonb) from public, anon, authenticated;
grant execute on function better_supabase.complete_idempotent(text, text, uuid, integer, jsonb) to service_role;
revoke execute on function better_supabase.release_idempotent(text, text, uuid) from public, anon, authenticated;
grant execute on function better_supabase.release_idempotent(text, text, uuid) to service_role;
revoke execute on function better_supabase.purge_idempotency_keys() from public, anon, authenticated;
grant execute on function better_supabase.purge_idempotency_keys() to service_role;
revoke execute on function better_supabase.acquire_lease(text, integer, text) from public, anon, authenticated;
grant execute on function better_supabase.acquire_lease(text, integer, text) to service_role;
revoke execute on function better_supabase.extend_lease(text, uuid, integer, text) from public, anon, authenticated;
grant execute on function better_supabase.extend_lease(text, uuid, integer, text) to service_role;
revoke execute on function better_supabase.release_lease(text, uuid, text) from public, anon, authenticated;
grant execute on function better_supabase.release_lease(text, uuid, text) to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_08_idempotency.sql
-- better-supabase module: idempotency
-- @bs-module-data idempotency
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('idempotency', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_08_idempotency.sql
-- better-supabase module: idempotency
-- @bs-module idempotency@1 managed
-- Stores responses by Idempotency-Key so retried requests replay the first result instead of running twice.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

create table if not exists better_supabase.idempotency_keys (
  scope text not null default '',
  key text not null,
  request_hash text not null,
  status text not null default 'running' check (status in ('running', 'completed')),
  status_code integer,
  response jsonb,
  locked_until timestamptz,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  primary key (scope, key)
);
create index if not exists idempotency_keys_expiry_idx on better_supabase.idempotency_keys (expires_at);
-- The token of the request that holds the key while it runs.
alter table better_supabase.idempotency_keys add column if not exists holder uuid;

alter table better_supabase.idempotency_keys enable row level security;
revoke all on better_supabase.idempotency_keys from anon, authenticated;
grant all on better_supabase.idempotency_keys to service_role;

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
  existing better_supabase.idempotency_keys;
  token uuid := gen_random_uuid();
begin
  delete from better_supabase.idempotency_keys k
  where k.scope = begin_idempotent.scope and k.key = begin_idempotent.key and k.expires_at < now();

  insert into better_supabase.idempotency_keys (scope, key, request_hash, locked_until, expires_at, holder)
  values (scope, key, request_hash, now() + lock, now() + ttl, token)
  on conflict on constraint idempotency_keys_pkey do nothing;
  if found then
    return query select 'started'::text, null::integer, null::jsonb, token;
    return;
  end if;

  select * into existing from better_supabase.idempotency_keys k
  where k.scope = begin_idempotent.scope and k.key = begin_idempotent.key
  for update;
  if existing.request_hash <> request_hash then
    return query select 'mismatch'::text, null::integer, null::jsonb, null::uuid;
  elsif existing.status = 'completed' then
    return query select 'replay'::text, existing.status_code, existing.response, null::uuid;
  elsif existing.locked_until < now() then
    -- The holder's lock ran out: this request takes the key over, and the
    -- former holder's complete and release now return false.
    update better_supabase.idempotency_keys k set locked_until = now() + lock, holder = token
    where k.scope = begin_idempotent.scope and k.key = begin_idempotent.key;
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
    update better_supabase.idempotency_keys k
    set status = 'completed', status_code = complete_idempotent.status_code,
        response = complete_idempotent.response, locked_until = null, holder = null
    where k.scope = complete_idempotent.scope and k.key = complete_idempotent.key
      and k.status = 'running' and k.holder = complete_idempotent.holder
    returning 1
  )
  select exists (select 1 from done)
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
    delete from better_supabase.idempotency_keys k
    where k.scope = release_idempotent.scope and k.key = release_idempotent.key
      and k.status = 'running' and k.holder = release_idempotent.holder
    returning 1
  )
  select exists (select 1 from released)
$$;

-- Leases: one holder per (scope, key) until it expires, for work that must
-- not run twice at once (one automation per conversation). acquire_lease
-- returns the holder token, or null while someone else holds the lease.
create table if not exists better_supabase.leases (
  scope text not null default '',
  key text not null,
  holder uuid not null,
  expires_at timestamptz not null,
  primary key (scope, key)
);
alter table better_supabase.leases enable row level security;
revoke all on better_supabase.leases from anon, authenticated;
grant all on better_supabase.leases to service_role;

create or replace function better_supabase.acquire_lease(key text, seconds integer default 60, scope text default '')
returns uuid
language plpgsql
set search_path = ''
as $$
#variable_conflict use_variable
declare
  token uuid := gen_random_uuid();
  taken uuid;
begin
  insert into better_supabase.leases as l (scope, key, holder, expires_at)
  values (scope, key, token, now() + make_interval(secs => greatest(seconds, 1)))
  on conflict on constraint leases_pkey do update
    set holder = excluded.holder, expires_at = excluded.expires_at
    where l.expires_at <= now()
  returning l.holder into taken;
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
    update better_supabase.leases l
    set expires_at = now() + make_interval(secs => greatest(extend_lease.seconds, 1))
    where l.scope = extend_lease.scope and l.key = extend_lease.key
      and l.holder = extend_lease.holder and l.expires_at > now()
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
    delete from better_supabase.leases l
    where l.scope = release_lease.scope and l.key = release_lease.key and l.holder = release_lease.holder
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
    delete from better_supabase.idempotency_keys where expires_at < now() returning 1
  )
  select count(*)::integer from purged
$$;

revoke execute on function better_supabase.begin_idempotent(text, text, text, interval, interval) from public, anon, authenticated;
grant execute on function better_supabase.begin_idempotent(text, text, text, interval, interval) to service_role;
revoke execute on function better_supabase.complete_idempotent(text, text, uuid, integer, jsonb) from public, anon, authenticated;
grant execute on function better_supabase.complete_idempotent(text, text, uuid, integer, jsonb) to service_role;
revoke execute on function better_supabase.release_idempotent(text, text, uuid) from public, anon, authenticated;
grant execute on function better_supabase.release_idempotent(text, text, uuid) to service_role;
revoke execute on function better_supabase.purge_idempotency_keys() from public, anon, authenticated;
grant execute on function better_supabase.purge_idempotency_keys() to service_role;
revoke execute on function better_supabase.acquire_lease(text, integer, text) from public, anon, authenticated;
grant execute on function better_supabase.acquire_lease(text, integer, text) to service_role;
revoke execute on function better_supabase.extend_lease(text, uuid, integer, text) from public, anon, authenticated;
grant execute on function better_supabase.extend_lease(text, uuid, integer, text) to service_role;
revoke execute on function better_supabase.release_lease(text, uuid, text) from public, anon, authenticated;
grant execute on function better_supabase.release_lease(text, uuid, text) to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_08_idempotency.sql
-- better-supabase module: idempotency
-- @bs-module-data idempotency
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('idempotency', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_08_idempotency.sql
-- better-supabase module: idempotency
-- @bs-module idempotency@1 managed
-- Stores responses by Idempotency-Key so retried requests replay the first result instead of running twice.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

create table if not exists better_supabase.idempotency_keys (
  scope text not null default '',
  key text not null,
  request_hash text not null,
  status text not null default 'running' check (status in ('running', 'completed')),
  status_code integer,
  response jsonb,
  locked_until timestamptz,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  primary key (scope, key)
);
create index if not exists idempotency_keys_expiry_idx on better_supabase.idempotency_keys (expires_at);
-- The token of the request that holds the key while it runs.
alter table better_supabase.idempotency_keys add column if not exists holder uuid;

alter table better_supabase.idempotency_keys enable row level security;
revoke all on better_supabase.idempotency_keys from anon, authenticated;
grant all on better_supabase.idempotency_keys to service_role;

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
  existing better_supabase.idempotency_keys;
  token uuid := gen_random_uuid();
begin
  delete from better_supabase.idempotency_keys k
  where k.scope = begin_idempotent.scope and k.key = begin_idempotent.key and k.expires_at < now();

  insert into better_supabase.idempotency_keys (scope, key, request_hash, locked_until, expires_at, holder)
  values (scope, key, request_hash, now() + lock, now() + ttl, token)
  on conflict on constraint idempotency_keys_pkey do nothing;
  if found then
    return query select 'started'::text, null::integer, null::jsonb, token;
    return;
  end if;

  select * into existing from better_supabase.idempotency_keys k
  where k.scope = begin_idempotent.scope and k.key = begin_idempotent.key
  for update;
  if existing.request_hash <> request_hash then
    return query select 'mismatch'::text, null::integer, null::jsonb, null::uuid;
  elsif existing.status = 'completed' then
    return query select 'replay'::text, existing.status_code, existing.response, null::uuid;
  elsif existing.locked_until < now() then
    -- The holder's lock ran out: this request takes the key over, and the
    -- former holder's complete and release now return false.
    update better_supabase.idempotency_keys k set locked_until = now() + lock, holder = token
    where k.scope = begin_idempotent.scope and k.key = begin_idempotent.key;
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
    update better_supabase.idempotency_keys k
    set status = 'completed', status_code = complete_idempotent.status_code,
        response = complete_idempotent.response, locked_until = null, holder = null
    where k.scope = complete_idempotent.scope and k.key = complete_idempotent.key
      and k.status = 'running' and k.holder = complete_idempotent.holder
    returning 1
  )
  select exists (select 1 from done)
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
    delete from better_supabase.idempotency_keys k
    where k.scope = release_idempotent.scope and k.key = release_idempotent.key
      and k.status = 'running' and k.holder = release_idempotent.holder
    returning 1
  )
  select exists (select 1 from released)
$$;

-- Leases: one holder per (scope, key) until it expires, for work that must
-- not run twice at once (one automation per conversation). acquire_lease
-- returns the holder token, or null while someone else holds the lease.
create table if not exists better_supabase.leases (
  scope text not null default '',
  key text not null,
  holder uuid not null,
  expires_at timestamptz not null,
  primary key (scope, key)
);
alter table better_supabase.leases enable row level security;
revoke all on better_supabase.leases from anon, authenticated;
grant all on better_supabase.leases to service_role;

create or replace function better_supabase.acquire_lease(key text, seconds integer default 60, scope text default '')
returns uuid
language plpgsql
set search_path = ''
as $$
#variable_conflict use_variable
declare
  token uuid := gen_random_uuid();
  taken uuid;
begin
  insert into better_supabase.leases as l (scope, key, holder, expires_at)
  values (scope, key, token, now() + make_interval(secs => greatest(seconds, 1)))
  on conflict on constraint leases_pkey do update
    set holder = excluded.holder, expires_at = excluded.expires_at
    where l.expires_at <= now()
  returning l.holder into taken;
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
    update better_supabase.leases l
    set expires_at = now() + make_interval(secs => greatest(extend_lease.seconds, 1))
    where l.scope = extend_lease.scope and l.key = extend_lease.key
      and l.holder = extend_lease.holder and l.expires_at > now()
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
    delete from better_supabase.leases l
    where l.scope = release_lease.scope and l.key = release_lease.key and l.holder = release_lease.holder
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
    delete from better_supabase.idempotency_keys where expires_at < now() returning 1
  )
  select count(*)::integer from purged
$$;

revoke execute on function better_supabase.begin_idempotent(text, text, text, interval, interval) from public, anon, authenticated;
grant execute on function better_supabase.begin_idempotent(text, text, text, interval, interval) to service_role;
revoke execute on function better_supabase.complete_idempotent(text, text, uuid, integer, jsonb) from public, anon, authenticated;
grant execute on function better_supabase.complete_idempotent(text, text, uuid, integer, jsonb) to service_role;
revoke execute on function better_supabase.release_idempotent(text, text, uuid) from public, anon, authenticated;
grant execute on function better_supabase.release_idempotent(text, text, uuid) to service_role;
revoke execute on function better_supabase.purge_idempotency_keys() from public, anon, authenticated;
grant execute on function better_supabase.purge_idempotency_keys() to service_role;
revoke execute on function better_supabase.acquire_lease(text, integer, text) from public, anon, authenticated;
grant execute on function better_supabase.acquire_lease(text, integer, text) to service_role;
revoke execute on function better_supabase.extend_lease(text, uuid, integer, text) from public, anon, authenticated;
grant execute on function better_supabase.extend_lease(text, uuid, integer, text) to service_role;
revoke execute on function better_supabase.release_lease(text, uuid, text) from public, anon, authenticated;
grant execute on function better_supabase.release_lease(text, uuid, text) to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_08_idempotency.sql
-- better-supabase module: idempotency
-- @bs-module-data idempotency
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('idempotency', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_08_idempotency.sql
-- better-supabase module: idempotency
-- @bs-module idempotency@1 managed
-- Stores responses by Idempotency-Key so retried requests replay the first result instead of running twice.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

create table if not exists better_supabase.idempotency_keys (
  scope text not null default '',
  key text not null,
  request_hash text not null,
  status text not null default 'running' check (status in ('running', 'completed')),
  status_code integer,
  response jsonb,
  locked_until timestamptz,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  primary key (scope, key)
);
create index if not exists idempotency_keys_expiry_idx on better_supabase.idempotency_keys (expires_at);
-- The token of the request that holds the key while it runs.
alter table better_supabase.idempotency_keys add column if not exists holder uuid;

alter table better_supabase.idempotency_keys enable row level security;
revoke all on better_supabase.idempotency_keys from anon, authenticated;
grant all on better_supabase.idempotency_keys to service_role;

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
  existing better_supabase.idempotency_keys;
  token uuid := gen_random_uuid();
begin
  delete from better_supabase.idempotency_keys k
  where k.scope = begin_idempotent.scope and k.key = begin_idempotent.key and k.expires_at < now();

  insert into better_supabase.idempotency_keys (scope, key, request_hash, locked_until, expires_at, holder)
  values (scope, key, request_hash, now() + lock, now() + ttl, token)
  on conflict on constraint idempotency_keys_pkey do nothing;
  if found then
    return query select 'started'::text, null::integer, null::jsonb, token;
    return;
  end if;

  select * into existing from better_supabase.idempotency_keys k
  where k.scope = begin_idempotent.scope and k.key = begin_idempotent.key
  for update;
  if existing.request_hash <> request_hash then
    return query select 'mismatch'::text, null::integer, null::jsonb, null::uuid;
  elsif existing.status = 'completed' then
    return query select 'replay'::text, existing.status_code, existing.response, null::uuid;
  elsif existing.locked_until < now() then
    -- The holder's lock ran out: this request takes the key over, and the
    -- former holder's complete and release now return false.
    update better_supabase.idempotency_keys k set locked_until = now() + lock, holder = token
    where k.scope = begin_idempotent.scope and k.key = begin_idempotent.key;
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
    update better_supabase.idempotency_keys k
    set status = 'completed', status_code = complete_idempotent.status_code,
        response = complete_idempotent.response, locked_until = null, holder = null
    where k.scope = complete_idempotent.scope and k.key = complete_idempotent.key
      and k.status = 'running' and k.holder = complete_idempotent.holder
    returning 1
  )
  select exists (select 1 from done)
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
    delete from better_supabase.idempotency_keys k
    where k.scope = release_idempotent.scope and k.key = release_idempotent.key
      and k.status = 'running' and k.holder = release_idempotent.holder
    returning 1
  )
  select exists (select 1 from released)
$$;

-- Leases: one holder per (scope, key) until it expires, for work that must
-- not run twice at once (one automation per conversation). acquire_lease
-- returns the holder token, or null while someone else holds the lease.
create table if not exists better_supabase.leases (
  scope text not null default '',
  key text not null,
  holder uuid not null,
  expires_at timestamptz not null,
  primary key (scope, key)
);
alter table better_supabase.leases enable row level security;
revoke all on better_supabase.leases from anon, authenticated;
grant all on better_supabase.leases to service_role;

create or replace function better_supabase.acquire_lease(key text, seconds integer default 60, scope text default '')
returns uuid
language plpgsql
set search_path = ''
as $$
#variable_conflict use_variable
declare
  token uuid := gen_random_uuid();
  taken uuid;
begin
  insert into better_supabase.leases as l (scope, key, holder, expires_at)
  values (scope, key, token, now() + make_interval(secs => greatest(seconds, 1)))
  on conflict on constraint leases_pkey do update
    set holder = excluded.holder, expires_at = excluded.expires_at
    where l.expires_at <= now()
  returning l.holder into taken;
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
    update better_supabase.leases l
    set expires_at = now() + make_interval(secs => greatest(extend_lease.seconds, 1))
    where l.scope = extend_lease.scope and l.key = extend_lease.key
      and l.holder = extend_lease.holder and l.expires_at > now()
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
    delete from better_supabase.leases l
    where l.scope = release_lease.scope and l.key = release_lease.key and l.holder = release_lease.holder
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
    delete from better_supabase.idempotency_keys where expires_at < now() returning 1
  )
  select count(*)::integer from purged
$$;

revoke execute on function better_supabase.begin_idempotent(text, text, text, interval, interval) from public, anon, authenticated;
grant execute on function better_supabase.begin_idempotent(text, text, text, interval, interval) to service_role;
revoke execute on function better_supabase.complete_idempotent(text, text, uuid, integer, jsonb) from public, anon, authenticated;
grant execute on function better_supabase.complete_idempotent(text, text, uuid, integer, jsonb) to service_role;
revoke execute on function better_supabase.release_idempotent(text, text, uuid) from public, anon, authenticated;
grant execute on function better_supabase.release_idempotent(text, text, uuid) to service_role;
revoke execute on function better_supabase.purge_idempotency_keys() from public, anon, authenticated;
grant execute on function better_supabase.purge_idempotency_keys() to service_role;
revoke execute on function better_supabase.acquire_lease(text, integer, text) from public, anon, authenticated;
grant execute on function better_supabase.acquire_lease(text, integer, text) to service_role;
revoke execute on function better_supabase.extend_lease(text, uuid, integer, text) from public, anon, authenticated;
grant execute on function better_supabase.extend_lease(text, uuid, integer, text) to service_role;
revoke execute on function better_supabase.release_lease(text, uuid, text) from public, anon, authenticated;
grant execute on function better_supabase.release_lease(text, uuid, text) to service_role;

-- blocks.idempotency.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."begin_idempotent"(text, text, text, interval, interval);
drop function if exists "api"."complete_idempotent"(text, text, integer, jsonb);
drop function if exists "api"."release_idempotent"(text, text);

create or replace function "api"."begin_idempotent"(scope text, key text, request_hash text, ttl interval default '24 hours', lock interval default '1 minute')
returns table (state text, status_code integer, response jsonb, holder uuid)
language sql
security invoker
set search_path = ''
as $$ select * from "better_supabase"."begin_idempotent"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."begin_idempotent"(text, text, text, interval, interval) from public, anon, authenticated;
grant execute on function "api"."begin_idempotent"(text, text, text, interval, interval) to service_role;

create or replace function "api"."complete_idempotent"(scope text, key text, holder uuid, status_code integer, response jsonb)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."complete_idempotent"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."complete_idempotent"(text, text, uuid, integer, jsonb) from public, anon, authenticated;
grant execute on function "api"."complete_idempotent"(text, text, uuid, integer, jsonb) to service_role;

create or replace function "api"."release_idempotent"(scope text, key text, holder uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."release_idempotent"($1, $2, $3) $$;
revoke execute on function "api"."release_idempotent"(text, text, uuid) from public, anon, authenticated;
grant execute on function "api"."release_idempotent"(text, text, uuid) to service_role;

create or replace function "api"."purge_idempotency_keys"()
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."purge_idempotency_keys"() $$;
revoke execute on function "api"."purge_idempotency_keys"() from public, anon, authenticated;
grant execute on function "api"."purge_idempotency_keys"() to service_role;

create or replace function "api"."acquire_lease"(key text, seconds integer default 60, scope text default '')
returns uuid
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."acquire_lease"($1, $2, $3) $$;
revoke execute on function "api"."acquire_lease"(text, integer, text) from public, anon, authenticated;
grant execute on function "api"."acquire_lease"(text, integer, text) to service_role;

create or replace function "api"."extend_lease"(key text, holder uuid, seconds integer default 60, scope text default '')
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."extend_lease"($1, $2, $3, $4) $$;
revoke execute on function "api"."extend_lease"(text, uuid, integer, text) from public, anon, authenticated;
grant execute on function "api"."extend_lease"(text, uuid, integer, text) to service_role;

create or replace function "api"."release_lease"(key text, holder uuid, scope text default '')
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."release_lease"($1, $2, $3) $$;
revoke execute on function "api"."release_lease"(text, uuid, text) from public, anon, authenticated;
grant execute on function "api"."release_lease"(text, uuid, text) to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_08_idempotency.sql
-- better-supabase module: idempotency
-- @bs-module-data idempotency
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('idempotency', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
