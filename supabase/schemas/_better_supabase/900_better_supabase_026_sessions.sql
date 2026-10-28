-- better-supabase module: sessions
-- @bsb-block sessions@1 managed
-- @bsb-hash sha256:712c0ec39f6158d75b01bd1f8060f445a88f70622e8cf9300dbbd49b7ed559a8
-- session_active() for restrictive policies: false once the caller's session was signed out or expired, or the user was banned or deleted, so revoked access tokens stop working before they expire. options.policies writes the policy on every table.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
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

-- blocks['sessions'].options.policies: every table in the schema files,
-- except blocks['sessions'].options.exclude. `upgrade` rewrites these.
drop policy if exists bsb_session_active on "public"."client_notes";
create policy bsb_session_active on "public"."client_notes" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "public"."contacts";
create policy bsb_session_active on "public"."contacts" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "public"."customer_tags";
create policy bsb_session_active on "public"."customer_tags" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "public"."customers";
create policy bsb_session_active on "public"."customers" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "public"."locations";
create policy bsb_session_active on "public"."locations" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "public"."memberships";
create policy bsb_session_active on "public"."memberships" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "public"."notes";
create policy bsb_session_active on "public"."notes" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "public"."organizations";
create policy bsb_session_active on "public"."organizations" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "public"."plan_features";
create policy bsb_session_active on "public"."plan_features" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "public"."plans";
create policy bsb_session_active on "public"."plans" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "public"."projects";
create policy bsb_session_active on "public"."projects" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "public"."saved_views";
create policy bsb_session_active on "public"."saved_views" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "public"."subscriptions";
create policy bsb_session_active on "public"."subscriptions" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "public"."tags";
create policy bsb_session_active on "public"."tags" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "public"."tasks";
create policy bsb_session_active on "public"."tasks" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));

-- blocks['sessions'].options.authzVersions: one authorization version per
-- user. Attach better_supabase.bump_authz_version() to the tables a user's
-- access comes from; the access token hook reads better_supabase.authz_version().
create table if not exists better_supabase.user_authz_versions (
  user_id uuid primary key references auth.users on delete cascade,
  version bigint not null default 1,
  updated_at timestamptz not null default now()
);

alter table better_supabase.user_authz_versions enable row level security;

revoke all on better_supabase.user_authz_versions from public, anon, authenticated;
grant select on better_supabase.user_authz_versions to supabase_auth_admin;
grant all on better_supabase.user_authz_versions to service_role;

drop policy if exists bsb_authz_versions_auth_admin on better_supabase.user_authz_versions;
create policy bsb_authz_versions_auth_admin on better_supabase.user_authz_versions
  for select to supabase_auth_admin
  using (true);

-- The version the access token hook copies into authz_ver; 0 before the
-- first bump.
create or replace function better_supabase.authz_version(p_user uuid)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select v.version from better_supabase.user_authz_versions v where v.user_id = p_user),
    0
  )
$$;

revoke execute on function better_supabase.authz_version(uuid) from public, anon, authenticated;
grant execute on function better_supabase.authz_version(uuid) to supabase_auth_admin, service_role;

-- Bumps the versions of many users at once, for changes no trigger sees.
create or replace function better_supabase.bump_authz_versions(p_users uuid[])
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  insert into better_supabase.user_authz_versions as v (user_id)
  select distinct u from unnest(p_users) u where u is not null
  on conflict (user_id) do update
    set version = v.version + 1, updated_at = now()
$$;

revoke execute on function better_supabase.bump_authz_versions(uuid[]) from public, anon, authenticated;
grant execute on function better_supabase.bump_authz_versions(uuid[]) to service_role;

-- A row trigger: bumps the user in the row's user_id column, or in the column
-- named by the trigger's first argument, before and after an update.
create or replace function better_supabase.bump_authz_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  col text := coalesce(tg_argv[0], 'user_id');
begin
  perform better_supabase.bump_authz_versions(array[
    (to_jsonb(new) ->> col)::uuid,
    (to_jsonb(old) ->> col)::uuid
  ]);
  return null;
end;
$$;

revoke execute on function better_supabase.bump_authz_version() from public, anon, authenticated;

-- Sends { user_id, version } as the changed event on the server topic, which
-- no user may join, and on the user's own authz:<uid> topic.
create or replace function better_supabase.broadcast_authz_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(jsonb_build_object('user_id', new.user_id, 'version', new.version), 'changed', 'better_supabase:authz', true);
  end if;
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(jsonb_build_object('user_id', new.user_id, 'version', new.version), 'changed', 'authz:' || new.user_id::text, true);
  end if;
  return null;
end;
$$;

revoke execute on function better_supabase.broadcast_authz_version() from public, anon, authenticated;

drop trigger if exists bsb_authz_versions_broadcast on better_supabase.user_authz_versions;
create trigger bsb_authz_versions_broadcast
  after insert or update on better_supabase.user_authz_versions
  for each row execute function better_supabase.broadcast_authz_version();

do $$
begin
  if to_regclass('realtime.messages') is not null then
    drop policy if exists bsb_authz_versions_receive on realtime.messages;
create policy bsb_authz_versions_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension = 'broadcast' and (select realtime.topic()) = 'authz:' || (select auth.uid())::text);
  end if;
end;
$$;

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

create or replace function "api"."authz_version"(p_user uuid)
returns bigint
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."authz_version"($1) $$;
revoke execute on function "api"."authz_version"(uuid) from public, anon, authenticated;
grant execute on function "api"."authz_version"(uuid) to service_role;

create or replace function "api"."bump_authz_versions"(p_users uuid[])
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."bump_authz_versions"($1) $$;
revoke execute on function "api"."bump_authz_versions"(uuid[]) from public, anon, authenticated;
grant execute on function "api"."bump_authz_versions"(uuid[]) to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;
