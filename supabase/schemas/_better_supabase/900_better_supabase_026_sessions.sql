-- better-supabase module: sessions
-- @bsb-block sessions@1 managed
-- @bsb-hash sha256:7aa40e40b10f5a9ed7478cef83aea7c28b1b156b2417fbe5ba400e8cd0ed788d
-- session_active() for restrictive policies: false once the caller's session was signed out or expired, or the user was banned or deleted, so revoked access tokens stop working before they expire. options.policies writes the policy on every table.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

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

-- Why session_active() is false: user_banned while the caller's user is banned,
-- else session_not_found. The bootstrap wrappers return it as end_reason.
create or replace function better_supabase.session_end_reason()
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from auth.users u
    where u.id = auth.uid() and u.banned_until is not null and u.banned_until > now()
  ) then
    return 'user_banned';
  end if;
  return 'session_not_found';
end;
$$;

revoke execute on function better_supabase.session_end_reason() from public, anon;
grant execute on function better_supabase.session_end_reason() to authenticated;

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

-- Deletes every session and refresh token of a user and returns how many
-- sessions went. Only the service role calls this, over SQL or the Data API.
create or replace function better_supabase.end_sessions(p_user uuid)
returns int
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  ended int;
begin
  with gone as (
    delete from auth.sessions s where s.user_id = end_sessions.p_user returning s.id
  )
  select count(*)::int into ended from gone;
  delete from auth.refresh_tokens t where t.user_id = end_sessions.p_user::text;
  return ended;
end;
$$;

revoke execute on function better_supabase.end_sessions(uuid) from public, anon, authenticated;
grant execute on function better_supabase.end_sessions(uuid) to service_role;

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


-- The caller's security page in one call: the sessions from
-- list_my_sessions(), the count and the current session's id.
create or replace function better_supabase.sessions_overview()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'count', jsonb_array_length(s.payload),
    'currentId', (select x ->> 'id' from jsonb_array_elements(s.payload) x where (x ->> 'current')::boolean limit 1),
    'sessions', s.payload)
  from (select better_supabase.list_my_sessions() as payload) s
$$;

revoke execute on function better_supabase.sessions_overview() from public, anon;
grant execute on function better_supabase.sessions_overview() to authenticated;

-- Restrictive, so it applies on top of the table's other policies. Wrapped in
-- a select, it runs one indexed lookup per statement:
-- create policy session_required on public.invoices as restrictive
--   for all to authenticated
--   using ((select better_supabase.session_active()))
--   with check ((select better_supabase.session_active()));

-- blocks['sessions'].options.policies: every table in the schema files,
-- except blocks['sessions'].options.exclude. `upgrade` rewrites these.
create policy bsb_session_active on "public"."change_requests" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
create policy bsb_session_active on "public"."client_notes" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
create policy bsb_session_active on "public"."contacts" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
create policy bsb_session_active on "public"."customer_tags" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
create policy bsb_session_active on "public"."customers" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
create policy bsb_session_active on "public"."locations" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
create policy bsb_session_active on "public"."memberships" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
create policy bsb_session_active on "public"."notes" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
create policy bsb_session_active on "public"."organizations" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
create policy bsb_session_active on "public"."plan_features" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
create policy bsb_session_active on "public"."plans" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
create policy bsb_session_active on "public"."projects" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
create policy bsb_session_active on "public"."saved_views" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
create policy bsb_session_active on "public"."subscriptions" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
create policy bsb_session_active on "public"."tags" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
create policy bsb_session_active on "public"."tasks" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));

-- blocks['sessions'].options.authzVersions: one authorization version per
-- user. Attach better_supabase.bump_authz_version() to the tables a user's
-- access comes from; the access token hook reads better_supabase.authz_version().
create table better_supabase.user_authz_versions (
  user_id uuid primary key references auth.users on delete cascade,
  version bigint not null default 1,
  updated_at timestamptz not null default now()
);

alter table better_supabase.user_authz_versions enable row level security;

revoke all on better_supabase.user_authz_versions from public, anon, authenticated;
grant select on better_supabase.user_authz_versions to supabase_auth_admin;
grant all on better_supabase.user_authz_versions to service_role;

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
  select distinct u from unnest(p_users) u
  where u is not null and exists (select 1 from auth.users x where x.id = u)
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
create trigger bsb_authz_versions_broadcast
  after insert or update on better_supabase.user_authz_versions
  for each row execute function better_supabase.broadcast_authz_version();

create policy bsb_authz_versions_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension = 'broadcast' and (select realtime.topic()) = 'authz:' || (select auth.uid())::text);

create or replace function better_supabase.bump_inserted_role_members()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform better_supabase.bump_authz_versions(array(
    select m."user_id"
    from "public"."memberships" m
    where m."role" in (select "role_id" from changed)
  ));
  return null;
end;
$$;

revoke execute on function better_supabase.bump_inserted_role_members() from public, anon, authenticated;
create trigger bsb_bump_inserted_role_members
  after insert on "better_supabase"."role_permissions"
  referencing new table as changed
  for each statement execute function better_supabase.bump_inserted_role_members();

create or replace function better_supabase.bump_deleted_role_members()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform better_supabase.bump_authz_versions(array(
    select m."user_id"
    from "public"."memberships" m
    where m."role" in (select "role_id" from changed)
  ));
  return null;
end;
$$;

revoke execute on function better_supabase.bump_deleted_role_members() from public, anon, authenticated;
create trigger bsb_bump_deleted_role_members
  after delete on "better_supabase"."role_permissions"
  referencing old table as changed
  for each statement execute function better_supabase.bump_deleted_role_members();

create or replace function better_supabase.bump_updated_role_members()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform better_supabase.bump_authz_versions(array(
    select m."user_id"
    from "public"."memberships" m
    where m."role" in (
      select "role_id" from changed
      union
      select "role_id" from previous
    )
  ));
  return null;
end;
$$;

revoke execute on function better_supabase.bump_updated_role_members() from public, anon, authenticated;
create trigger bsb_bump_updated_role_members
  after update on "better_supabase"."role_permissions"
  referencing new table as changed old table as previous
  for each statement execute function better_supabase.bump_updated_role_members();

create or replace function better_supabase.bump_inserted_platform_roles()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform better_supabase.bump_authz_versions(array(select "user_id" from changed));
  return null;
end;
$$;

revoke execute on function better_supabase.bump_inserted_platform_roles() from public, anon, authenticated;
create trigger bsb_bump_inserted_platform_roles
  after insert on "better_supabase"."platform_roles"
  referencing new table as changed
  for each statement execute function better_supabase.bump_inserted_platform_roles();

create or replace function better_supabase.bump_deleted_platform_roles()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform better_supabase.bump_authz_versions(array(select "user_id" from changed));
  return null;
end;
$$;

revoke execute on function better_supabase.bump_deleted_platform_roles() from public, anon, authenticated;
create trigger bsb_bump_deleted_platform_roles
  after delete on "better_supabase"."platform_roles"
  referencing old table as changed
  for each statement execute function better_supabase.bump_deleted_platform_roles();
create or replace function better_supabase.bump_override_members()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform better_supabase.bump_authz_versions(array(
    select m."user_id"
    from "public"."memberships" m
    where (m."organization_id", m."role") in (
      select "tenant_id", "role_id" from changed
    )
  ));
  return null;
end;
$$;

revoke execute on function better_supabase.bump_override_members() from public, anon, authenticated;
create trigger bsb_bump_override_members_insert
  after insert on "better_supabase"."permission_overrides"
  referencing new table as changed
  for each statement execute function better_supabase.bump_override_members();
create trigger bsb_bump_override_members_update
  after update on "better_supabase"."permission_overrides"
  referencing new table as changed
  for each statement execute function better_supabase.bump_override_members();
create trigger bsb_bump_override_members_delete
  after delete on "better_supabase"."permission_overrides"
  referencing old table as changed
  for each statement execute function better_supabase.bump_override_members();

-- blocks['sessions'].options.hook: how much the access token hook reads for
-- this event, as 'slim' (an OAuth client token: leave out memberships,
-- permissions, team_ids and authz_ver), 'reuse' (a refresh whose authz_ver is
-- still current: return the event unchanged, no membership reads) or 'full'.
-- Call it first in the hook:
--   plan := better_supabase.hook_plan(event);
create or replace function better_supabase.hook_plan(event jsonb)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_claims jsonb := coalesce(event -> 'claims', '{}'::jsonb);
  v_user uuid := nullif(event ->> 'user_id', '')::uuid;
begin
  if coalesce(v_claims ->> 'client_id', '') <> '' then
    return 'slim';
  end if;

  -- A refresh whose permission claim was built for another tenant than
  -- app_metadata.tenant_id must read again. reuse would keep the old keys.
  if coalesce(v_claims -> 'app_metadata' ->> 'tenant_id', '') <> ''
    and jsonb_typeof(v_claims -> 'permissions') = 'object'
    and v_claims -> 'permissions' <> '{}'::jsonb
    and not (v_claims -> 'permissions' ? (v_claims -> 'app_metadata' ->> 'tenant_id'))
  then
    return 'full';
  end if;

  if event ->> 'authentication_method' = 'token_refresh'
    and jsonb_typeof(v_claims -> 'authz_ver') = 'number'
    and jsonb_typeof(v_claims -> 'memberships') = 'array'
    and coalesce(v_claims ->> 'permissions_truncated', 'false') <> 'true'
    and coalesce(v_claims ->> 'team_ids_truncated', 'false') <> 'true'
    and (v_claims ->> 'authz_ver')::bigint = better_supabase.authz_version(v_user)
  then
    return 'reuse';
  end if;

  return 'full';
end;
$$;

revoke execute on function better_supabase.hook_plan(jsonb) from public, anon, authenticated;
grant execute on function better_supabase.hook_plan(jsonb) to supabase_auth_admin, service_role;

-- The caller's own authorization version, null without a signed-in user.
-- Clients compare it with the token's authz_ver to catch up on a broadcast
-- they missed.
create or replace function better_supabase.caller_authz_version()
returns bigint
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    return null;
  end if;
  return better_supabase.authz_version(auth.uid());
end;
$$;

revoke execute on function better_supabase.caller_authz_version() from public, anon;
grant execute on function better_supabase.caller_authz_version() to authenticated;

-- blocks['sessions'].options.bootstrap: bsb.bootstrap({ rpc }) calls these.
-- Each checks the session and returns the caller's authorization version
-- (the live one when the database keeps it, and the token's) with the app
-- function's data, so a cache miss is one query.
create or replace function better_supabase.bootstrap_islands(args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not (select better_supabase.session_active()) then
    return jsonb_build_object(
      'session_active', false,
      'end_reason', better_supabase.session_end_reason(),
      'authz_version', auth.jwt() -> 'authz_ver',
      'token_authz_version', auth.jwt() -> 'authz_ver',
      'tenant', args ->> 'tenant',
      'data', null
    );
  end if;
  return jsonb_build_object(
    'session_active', true,
    'authz_version', to_jsonb(better_supabase.caller_authz_version()),
    'token_authz_version', auth.jwt() -> 'authz_ver',
    'tenant', args ->> 'tenant',
    'data', to_jsonb(public.island_counts(args))
  );
end;
$$;

revoke execute on function better_supabase.bootstrap_islands(jsonb) from public, anon;
grant execute on function better_supabase.bootstrap_islands(jsonb) to authenticated;

-- blocks.sessions.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

-- Helpers for the module's policies and triggers have no entry point.


create or replace function "api"."last_sign_ins"(p_users uuid[])
returns table (user_id uuid, last_sign_in_at timestamptz)
language sql
stable
security invoker
set search_path = ''
as $$ select * from "better_supabase"."last_sign_ins"($1) $$;
revoke execute on function "api"."last_sign_ins"(uuid[]) from public, anon, authenticated;
grant execute on function "api"."last_sign_ins"(uuid[]) to service_role;

create or replace function "api"."end_sessions"(p_user uuid)
returns int
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."end_sessions"($1) $$;
revoke execute on function "api"."end_sessions"(uuid) from public, anon, authenticated;
grant execute on function "api"."end_sessions"(uuid) to service_role;

create or replace function "api"."list_my_sessions"()
returns jsonb
language sql
stable
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

create or replace function "api"."sessions_overview"()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."sessions_overview"() $$;
revoke execute on function "api"."sessions_overview"() from public, anon, service_role;
grant execute on function "api"."sessions_overview"() to authenticated;

create or replace function "api"."authz_version"(p_user uuid)
returns bigint
language sql
stable
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

create or replace function "api"."hook_plan"(event jsonb)
returns text
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."hook_plan"($1) $$;
revoke execute on function "api"."hook_plan"(jsonb) from public, anon, authenticated;
grant execute on function "api"."hook_plan"(jsonb) to service_role;

create or replace function "api"."caller_authz_version"()
returns bigint
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."caller_authz_version"() $$;
revoke execute on function "api"."caller_authz_version"() from public, anon, service_role;
grant execute on function "api"."caller_authz_version"() to authenticated;

create or replace function "api"."bootstrap_islands"(args jsonb default '{}'::jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."bootstrap_islands"($1) $$;
revoke execute on function "api"."bootstrap_islands"(jsonb) from public, anon, service_role;
grant execute on function "api"."bootstrap_islands"(jsonb) to authenticated;
