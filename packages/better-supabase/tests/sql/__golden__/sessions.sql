-- ==== alone: schema supabase/schemas/900_better_supabase_26_sessions.sql
-- better-supabase module: sessions
-- @bsb-block sessions@1 managed
-- session_active() for restrictive policies: false once the caller's session was signed out or expired, or the user was banned or deleted, so revoked access tokens stop working before they expire. options.policies writes the policy on every table.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- An access token stays valid until it expires, even after its session is
-- signed out or its user is deleted. This checks the session behind it.
-- Tokens without a session_id claim (signed by the app) and support tokens
-- (with an act claim, whose session the support module ends) pass.
-- authenticated can't read auth.sessions, so the check runs as the owner.
create or replace function better_supabase.session_active()
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  claims jsonb := auth.jwt();
  session text := claims ->> 'session_id';
begin
  if claims -> 'act' is not null or session is null then
    return true;
  end if;
  if session !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return false;
  end if;
  return exists (
    select 1
    from auth.sessions s
    join auth.users u on u.id = s.user_id
    where s.id = session::uuid
      and s.user_id = auth.uid()
      and (s.not_after is null or s.not_after > now())
      and (u.banned_until is null or u.banned_until <= now())
      and u.deleted_at is null
  );
end;
$$;

revoke execute on function better_supabase.session_active() from public, anon;
grant execute on function better_supabase.session_active() to authenticated;

-- The last sign-in of many users in one query, for admin lists. auth.users
-- isn't readable through the Data API, so only the service role calls this.
create or replace function better_supabase.last_sign_ins(p_users uuid[])
returns table (user_id uuid, last_sign_in_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select u.id, u.last_sign_in_at
  from auth.users u
  where u.id = any(p_users)
$$;

revoke execute on function better_supabase.last_sign_ins(uuid[]) from public, anon, authenticated;
grant execute on function better_supabase.last_sign_ins(uuid[]) to service_role;

-- The caller's own unexpired sessions, most recently active first, with the
-- one behind the current token marked.
create or replace function better_supabase.list_my_sessions()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id,
    'createdAt', s.created_at,
    'lastActiveAt', coalesce(s.updated_at, s.created_at),
    'userAgent', s.user_agent,
    'ip', host(s.ip),
    'aal', s.aal,
    'current', s.id::text = auth.jwt() ->> 'session_id'
  ) order by coalesce(s.updated_at, s.created_at) desc), '[]'::jsonb)
  from auth.sessions s
  where s.user_id = (select auth.uid())
    and (s.not_after is null or s.not_after > now())
$$;

revoke execute on function better_supabase.list_my_sessions() from public, anon;
grant execute on function better_supabase.list_my_sessions() to authenticated;

-- Ends one of the caller's sessions: its refresh tokens go with it, and
-- session_active() turns false for its access tokens.
create or replace function better_supabase.end_my_session(session uuid)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from auth.sessions s
  where s.id = end_my_session.session
    and s.user_id = (select auth.uid());
  return found;
end;
$$;

revoke execute on function better_supabase.end_my_session(uuid) from public, anon;
grant execute on function better_supabase.end_my_session(uuid) to authenticated;

-- Restrictive, so it applies on top of the table's other policies. Wrapped in
-- a select, it runs one indexed lookup per statement:
-- create policy session_required on public.invoices as restrictive
--   for all to authenticated
--   using ((select better_supabase.session_active()))
--   with check ((select better_supabase.session_active()));

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_26_sessions.sql
-- better-supabase module: sessions
-- @bsb-block-data sessions
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('sessions', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_26_sessions.sql
-- better-supabase module: sessions
-- @bsb-block sessions@1 managed
-- session_active() for restrictive policies: false once the caller's session was signed out or expired, or the user was banned or deleted, so revoked access tokens stop working before they expire. options.policies writes the policy on every table.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- An access token stays valid until it expires, even after its session is
-- signed out or its user is deleted. This checks the session behind it.
-- Tokens without a session_id claim (signed by the app) and support tokens
-- (with an act claim, whose session the support module ends) pass.
-- authenticated can't read auth.sessions, so the check runs as the owner.
create or replace function better_supabase.session_active()
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  claims jsonb := auth.jwt();
  session text := claims ->> 'session_id';
begin
  if claims -> 'act' is not null or session is null then
    return true;
  end if;
  if session !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return false;
  end if;
  return exists (
    select 1
    from auth.sessions s
    join auth.users u on u.id = s.user_id
    where s.id = session::uuid
      and s.user_id = auth.uid()
      and (s.not_after is null or s.not_after > now())
      and (u.banned_until is null or u.banned_until <= now())
      and u.deleted_at is null
  );
end;
$$;

revoke execute on function better_supabase.session_active() from public, anon;
grant execute on function better_supabase.session_active() to authenticated;

-- The last sign-in of many users in one query, for admin lists. auth.users
-- isn't readable through the Data API, so only the service role calls this.
create or replace function better_supabase.last_sign_ins(p_users uuid[])
returns table (user_id uuid, last_sign_in_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select u.id, u.last_sign_in_at
  from auth.users u
  where u.id = any(p_users)
$$;

revoke execute on function better_supabase.last_sign_ins(uuid[]) from public, anon, authenticated;
grant execute on function better_supabase.last_sign_ins(uuid[]) to service_role;

-- The caller's own unexpired sessions, most recently active first, with the
-- one behind the current token marked.
create or replace function better_supabase.list_my_sessions()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id,
    'createdAt', s.created_at,
    'lastActiveAt', coalesce(s.updated_at, s.created_at),
    'userAgent', s.user_agent,
    'ip', host(s.ip),
    'aal', s.aal,
    'current', s.id::text = auth.jwt() ->> 'session_id'
  ) order by coalesce(s.updated_at, s.created_at) desc), '[]'::jsonb)
  from auth.sessions s
  where s.user_id = (select auth.uid())
    and (s.not_after is null or s.not_after > now())
$$;

revoke execute on function better_supabase.list_my_sessions() from public, anon;
grant execute on function better_supabase.list_my_sessions() to authenticated;

-- Ends one of the caller's sessions: its refresh tokens go with it, and
-- session_active() turns false for its access tokens.
create or replace function better_supabase.end_my_session(session uuid)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from auth.sessions s
  where s.id = end_my_session.session
    and s.user_id = (select auth.uid());
  return found;
end;
$$;

revoke execute on function better_supabase.end_my_session(uuid) from public, anon;
grant execute on function better_supabase.end_my_session(uuid) to authenticated;

-- Restrictive, so it applies on top of the table's other policies. Wrapped in
-- a select, it runs one indexed lookup per statement:
-- create policy session_required on public.invoices as restrictive
--   for all to authenticated
--   using ((select better_supabase.session_active()))
--   with check ((select better_supabase.session_active()));

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_26_sessions.sql
-- better-supabase module: sessions
-- @bsb-block-data sessions
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('sessions', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_26_sessions.sql
-- better-supabase module: sessions
-- @bsb-block sessions@1 managed
-- session_active() for restrictive policies: false once the caller's session was signed out or expired, or the user was banned or deleted, so revoked access tokens stop working before they expire. options.policies writes the policy on every table.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- An access token stays valid until it expires, even after its session is
-- signed out or its user is deleted. This checks the session behind it.
-- Tokens without a session_id claim (signed by the app) and support tokens
-- (with an act claim, whose session the support module ends) pass.
-- authenticated can't read auth.sessions, so the check runs as the owner.
create or replace function better_supabase.session_active()
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  claims jsonb := auth.jwt();
  session text := claims ->> 'session_id';
begin
  if claims -> 'act' is not null or session is null then
    return true;
  end if;
  if session !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return false;
  end if;
  return exists (
    select 1
    from auth.sessions s
    join auth.users u on u.id = s.user_id
    where s.id = session::uuid
      and s.user_id = auth.uid()
      and (s.not_after is null or s.not_after > now())
      and (u.banned_until is null or u.banned_until <= now())
      and u.deleted_at is null
  );
end;
$$;

revoke execute on function better_supabase.session_active() from public, anon;
grant execute on function better_supabase.session_active() to authenticated;

-- The last sign-in of many users in one query, for admin lists. auth.users
-- isn't readable through the Data API, so only the service role calls this.
create or replace function better_supabase.last_sign_ins(p_users uuid[])
returns table (user_id uuid, last_sign_in_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select u.id, u.last_sign_in_at
  from auth.users u
  where u.id = any(p_users)
$$;

revoke execute on function better_supabase.last_sign_ins(uuid[]) from public, anon, authenticated;
grant execute on function better_supabase.last_sign_ins(uuid[]) to service_role;

-- The caller's own unexpired sessions, most recently active first, with the
-- one behind the current token marked.
create or replace function better_supabase.list_my_sessions()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id,
    'createdAt', s.created_at,
    'lastActiveAt', coalesce(s.updated_at, s.created_at),
    'userAgent', s.user_agent,
    'ip', host(s.ip),
    'aal', s.aal,
    'current', s.id::text = auth.jwt() ->> 'session_id'
  ) order by coalesce(s.updated_at, s.created_at) desc), '[]'::jsonb)
  from auth.sessions s
  where s.user_id = (select auth.uid())
    and (s.not_after is null or s.not_after > now())
$$;

revoke execute on function better_supabase.list_my_sessions() from public, anon;
grant execute on function better_supabase.list_my_sessions() to authenticated;

-- Ends one of the caller's sessions: its refresh tokens go with it, and
-- session_active() turns false for its access tokens.
create or replace function better_supabase.end_my_session(session uuid)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from auth.sessions s
  where s.id = end_my_session.session
    and s.user_id = (select auth.uid());
  return found;
end;
$$;

revoke execute on function better_supabase.end_my_session(uuid) from public, anon;
grant execute on function better_supabase.end_my_session(uuid) to authenticated;

-- Restrictive, so it applies on top of the table's other policies. Wrapped in
-- a select, it runs one indexed lookup per statement:
-- create policy session_required on public.invoices as restrictive
--   for all to authenticated
--   using ((select better_supabase.session_active()))
--   with check ((select better_supabase.session_active()));

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_26_sessions.sql
-- better-supabase module: sessions
-- @bsb-block-data sessions
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('sessions', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_26_sessions.sql
-- better-supabase module: sessions
-- @bsb-block sessions@1 managed
-- session_active() for restrictive policies: false once the caller's session was signed out or expired, or the user was banned or deleted, so revoked access tokens stop working before they expire. options.policies writes the policy on every table.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- An access token stays valid until it expires, even after its session is
-- signed out or its user is deleted. This checks the session behind it.
-- Tokens without a session_id claim (signed by the app) and support tokens
-- (with an act claim, whose session the support module ends) pass.
-- authenticated can't read auth.sessions, so the check runs as the owner.
create or replace function better_supabase.session_active()
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  claims jsonb := auth.jwt();
  session text := claims ->> 'session_id';
begin
  if claims -> 'act' is not null or session is null then
    return true;
  end if;
  if session !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return false;
  end if;
  return exists (
    select 1
    from auth.sessions s
    join auth.users u on u.id = s.user_id
    where s.id = session::uuid
      and s.user_id = auth.uid()
      and (s.not_after is null or s.not_after > now())
      and (u.banned_until is null or u.banned_until <= now())
      and u.deleted_at is null
  );
end;
$$;

revoke execute on function better_supabase.session_active() from public, anon;
grant execute on function better_supabase.session_active() to authenticated;

-- The last sign-in of many users in one query, for admin lists. auth.users
-- isn't readable through the Data API, so only the service role calls this.
create or replace function better_supabase.last_sign_ins(p_users uuid[])
returns table (user_id uuid, last_sign_in_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select u.id, u.last_sign_in_at
  from auth.users u
  where u.id = any(p_users)
$$;

revoke execute on function better_supabase.last_sign_ins(uuid[]) from public, anon, authenticated;
grant execute on function better_supabase.last_sign_ins(uuid[]) to service_role;

-- The caller's own unexpired sessions, most recently active first, with the
-- one behind the current token marked.
create or replace function better_supabase.list_my_sessions()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id,
    'createdAt', s.created_at,
    'lastActiveAt', coalesce(s.updated_at, s.created_at),
    'userAgent', s.user_agent,
    'ip', host(s.ip),
    'aal', s.aal,
    'current', s.id::text = auth.jwt() ->> 'session_id'
  ) order by coalesce(s.updated_at, s.created_at) desc), '[]'::jsonb)
  from auth.sessions s
  where s.user_id = (select auth.uid())
    and (s.not_after is null or s.not_after > now())
$$;

revoke execute on function better_supabase.list_my_sessions() from public, anon;
grant execute on function better_supabase.list_my_sessions() to authenticated;

-- Ends one of the caller's sessions: its refresh tokens go with it, and
-- session_active() turns false for its access tokens.
create or replace function better_supabase.end_my_session(session uuid)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from auth.sessions s
  where s.id = end_my_session.session
    and s.user_id = (select auth.uid());
  return found;
end;
$$;

revoke execute on function better_supabase.end_my_session(uuid) from public, anon;
grant execute on function better_supabase.end_my_session(uuid) to authenticated;

-- Restrictive, so it applies on top of the table's other policies. Wrapped in
-- a select, it runs one indexed lookup per statement:
-- create policy session_required on public.invoices as restrictive
--   for all to authenticated
--   using ((select better_supabase.session_active()))
--   with check ((select better_supabase.session_active()));

-- blocks.sessions.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

-- Helpers for the module's policies and triggers have no entry point.
drop function if exists "api"."session_active"();

create or replace function "api"."actor_may_write"()
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."actor_may_write"() $$;
revoke execute on function "api"."actor_may_write"() from public;
grant execute on function "api"."actor_may_write"() to anon, authenticated, service_role;

create or replace function "api"."raise_actor_readonly"()
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."raise_actor_readonly"() $$;
revoke execute on function "api"."raise_actor_readonly"() from public;
grant execute on function "api"."raise_actor_readonly"() to anon, authenticated, service_role;

create or replace function "api"."last_sign_ins"(p_users uuid[])
returns table (user_id uuid, last_sign_in_at timestamptz)
language sql
security invoker
set search_path = ''
as $$ select * from "better_supabase"."last_sign_ins"($1) $$;
revoke execute on function "api"."last_sign_ins"(uuid[]) from public, anon, authenticated;
grant execute on function "api"."last_sign_ins"(uuid[]) to service_role;

create or replace function "api"."list_my_sessions"()
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_my_sessions"() $$;
revoke execute on function "api"."list_my_sessions"() from public, anon, service_role;
grant execute on function "api"."list_my_sessions"() to authenticated;

create or replace function "api"."end_my_session"(session uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."end_my_session"($1) $$;
revoke execute on function "api"."end_my_session"(uuid) from public, anon, service_role;
grant execute on function "api"."end_my_session"(uuid) to authenticated;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_26_sessions.sql
-- better-supabase module: sessions
-- @bsb-block-data sessions
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('sessions', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
