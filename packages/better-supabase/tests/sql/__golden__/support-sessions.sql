-- ==== alone: schema supabase/schemas/900_better_supabase_20_support_sessions.sql
-- better-supabase module: support-sessions
-- @bs-module support-sessions@1 managed
-- Lets platform staff view the app as a user: time-limited, read-only by default, gated by is_platform(), recorded in the audit log, with the target's claims built by your access token hook.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."support_sessions" (
  "id" uuid primary key default gen_random_uuid(),
  -- Sessions outlive a deleted user, so the record of who viewed whom stays.
  "admin_id" uuid references auth.users (id) on delete set null,
  "target_user_id" uuid references auth.users (id) on delete set null,
  "reason" text not null,
  "organization_id" uuid,
  "read_only" boolean not null default true,
  "started_at" timestamptz not null default now(),
  "expires_at" timestamptz not null,
  "ended_at" timestamptz,
  "ended_by" text check ("ended_by" in ('admin', 'expired', 'revoked')),
  -- App data, such as a ticket id.
  "metadata" jsonb not null default '{}',
  check ("admin_id" <> "target_user_id"),
  check ("expires_at" > "started_at")
);
create index if not exists support_sessions_admin_idx on "better_supabase"."support_sessions" ("admin_id", "started_at" desc);
create index if not exists support_sessions_target_idx on "better_supabase"."support_sessions" ("target_user_id", "started_at" desc);
create unique index if not exists support_sessions_one_active_idx on "better_supabase"."support_sessions" ("admin_id") where "ended_at" is null;
alter table "better_supabase"."support_sessions" enable row level security;
revoke all on "better_supabase"."support_sessions" from anon, authenticated;
grant select on "better_supabase"."support_sessions" to service_role;
-- Platform staff read every session.
drop policy if exists bs_support_read on "better_supabase"."support_sessions";
create policy bs_support_read on "better_supabase"."support_sessions" for select to authenticated
  using ((select "better_supabase"."is_platform"('support.read')));
grant select on "better_supabase"."support_sessions" to authenticated;


-- Starts a support session: the admin sees the app as target until it expires
-- or ends. An admin has one active session; starting another ends the first.
-- Errors carry a code in the hint: SUPPORT_FORBIDDEN, SUPPORT_SELF,
-- SUPPORT_TARGET_MISSING, SUPPORT_TTL or SUPPORT_REASON_REQUIRED.
create or replace function "better_supabase"."start_support_session"(
  target uuid,
  reason text default null,
  ttl interval default '30 minutes',
  read_only boolean default true,
  metadata jsonb default '{}',
  tenant uuid default null,
  admin_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  admin uuid;
  session_id uuid;
  started jsonb;
begin
  if service then
    admin := admin_id;
    if admin is null then
      raise exception 'admin_id is required for the service role' using errcode = '22023', hint = 'SUPPORT_FORBIDDEN';
    end if;
  else
    admin := auth.uid();
    if admin is null or (admin_id is not null and admin_id <> admin)
      or not "better_supabase"."is_platform"('support.start') then
      raise exception 'Not allowed to start a support session' using errcode = '42501', hint = 'SUPPORT_FORBIDDEN';
    end if;
  end if;
  if target = admin then
    raise exception 'An admin cannot start a support session as themselves' using errcode = '22023', hint = 'SUPPORT_SELF';
  end if;
  if not exists (select 1 from auth.users u where u.id = target) then
    raise exception 'No user %', target using errcode = 'P0002', hint = 'SUPPORT_TARGET_MISSING';
  end if;
  if ttl <= interval '0' or ttl > '4 hours'::interval then
    raise exception 'ttl must be between 0 and %', '4 hours' using errcode = '22023', hint = 'SUPPORT_TTL';
  end if;
  -- Viewing the app as platform staff would hand the admin that staff's reach.
  if exists (
    select 1 from auth.users u
    where u.id = target and jsonb_typeof(u.raw_app_meta_data -> 'platform_permissions') = 'array'
      and jsonb_array_length(u.raw_app_meta_data -> 'platform_permissions') > 0
  ) then
    raise exception 'A support session cannot target platform staff' using errcode = '42501', hint = 'SUPPORT_TARGET_PLATFORM';
  end if;
  if not coalesce(read_only, true) then
    raise exception 'Support sessions are read-only (modules.support-sessions.options.allowWrites)' using errcode = '42501', hint = 'SUPPORT_WRITES_DISABLED';
  end if;
  if coalesce(btrim(reason), '') = '' then
    raise exception 'A reason is required' using errcode = '22023', hint = 'SUPPORT_REASON_REQUIRED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_support_start"(uuid, uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text, $4::jsonb)', v_hook::oid::regproc)
        using admin, target, reason, metadata;
    end if;
  end;
  update "better_supabase"."support_sessions" s set "ended_at" = now(), "ended_by" = 'admin'
  where s."admin_id" = admin and s."ended_at" is null;
  insert into "better_supabase"."support_sessions" ("admin_id", "target_user_id", "reason", "organization_id", "read_only", "expires_at", "metadata")
  values (admin, target, coalesce(reason, ''), tenant, read_only, now() + ttl, coalesce(metadata, '{}'))
  returning "id" into session_id;
  select jsonb_build_object(
    'id', s."id",
    'admin_id', s."admin_id",
    'target_user_id', s."target_user_id",
    'reason', s."reason",
    'tenant', s."organization_id",
    'read_only', s."read_only",
    'started_at', s."started_at",
    'expires_at', s."expires_at",
    'ended_at', s."ended_at",
    'ended_by', s."ended_by",
    'metadata', s."metadata"
  ) into started from "better_supabase"."support_sessions" s where s."id" = session_id;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_support_start"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using session_id;
    end if;
  end;
  perform better_supabase.audit_event(
    event_type => 'support.started',
    category => 'security',
    target_type => 'user',
    record_id => target::text,
    tenant => (tenant)::uuid,
    metadata => jsonb_build_object('session_id', session_id, 'reason', reason, 'read_only', read_only),
    idempotency_key => 'support.started:' || session_id,
    actor_id => admin,
    support_session => session_id,
    impersonated_by => admin,
    impersonation_reason => reason
  );
  return started;
end;
$$;

-- Ends a session. The admin who started it ends their own ('admin');
-- platform staff with the revoke permission end anyone's ('revoked'). Only
-- the service role chooses ended_by, for example 'expired' from a sweep.
create or replace function "better_supabase"."end_support_session"(
  session_id uuid,
  ended_by text default 'admin'
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  ended jsonb;
begin
  if service and ended_by not in ('admin', 'expired', 'revoked') then
    raise exception 'ended_by must be admin, expired or revoked' using errcode = '22023';
  end if;
  update "better_supabase"."support_sessions" s set "ended_at" = now(), "ended_by" = case
      when service then ended_by
      when s."admin_id" = auth.uid() then 'admin'
      else 'revoked'
    end
  where s."id" = session_id and s."ended_at" is null
    and (service or s."admin_id" = auth.uid()
      or "better_supabase"."is_platform"('support.revoke'))
  returning jsonb_build_object(
    'id', s."id",
    'admin_id', s."admin_id",
    'target_user_id', s."target_user_id",
    'reason', s."reason",
    'tenant', s."organization_id",
    'read_only', s."read_only",
    'started_at', s."started_at",
    'expires_at', s."expires_at",
    'ended_at', s."ended_at",
    'ended_by', s."ended_by",
    'metadata', s."metadata"
  ) into ended;
  if not service then
    ended_by := case when (ended ->> 'admin_id')::uuid = auth.uid() then 'admin' else 'revoked' end;
  end if;
  if ended is null then
    return false;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_support_end"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using session_id;
    end if;
  end;
  perform better_supabase.audit_event(
    event_type => 'support.ended',
    category => 'security',
    target_type => 'user',
    record_id => ended ->> 'target_user_id',
    tenant => ((ended ->> 'tenant')::uuid)::uuid,
    metadata => jsonb_build_object('session_id', session_id, 'ended_by', ended_by),
    idempotency_key => 'support.ended:' || session_id,
    actor_id => case when service then (ended ->> 'admin_id')::uuid else auth.uid() end,
    support_session => session_id,
    impersonated_by => (ended ->> 'admin_id')::uuid,
    impersonation_reason => ended ->> 'reason'
  );
  return true;
end;
$$;

-- Ends the sessions past their expiry, each with ended_by 'expired', and
-- returns them. Run it from a cron job as the service role.
create or replace function "better_supabase"."expire_support_sessions"()
returns setof jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  expired_id uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role expires support sessions' using errcode = '42501', hint = 'SUPPORT_FORBIDDEN';
  end if;
  for expired_id in
    select s."id" from "better_supabase"."support_sessions" s
    where s."ended_at" is null and s."expires_at" <= now()
    order by s."expires_at"
    for update skip locked
  loop
    if "better_supabase"."end_support_session"(expired_id, 'expired') then
      return next (select jsonb_build_object(
    'id', s."id",
    'admin_id', s."admin_id",
    'target_user_id', s."target_user_id",
    'reason', s."reason",
    'tenant', s."organization_id",
    'read_only', s."read_only",
    'started_at', s."started_at",
    'expires_at', s."expires_at",
    'ended_at', s."ended_at",
    'ended_by', s."ended_by",
    'metadata', s."metadata"
  ) from "better_supabase"."support_sessions" s where s."id" = expired_id);
    end if;
  end loop;
end;
$$;

-- Parameters are positional below: in SQL functions a column name wins over a
-- parameter of the same name.
-- The admin's session while it is active, or null. Read on every request
-- that carries the support cookie. Called as the admin, it also checks that
-- the admin may still start sessions.
create or replace function "better_supabase"."active_support_session"(
  session_id uuid,
  admin_id uuid default null
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', s."id",
    'admin_id', s."admin_id",
    'target_user_id', s."target_user_id",
    'reason', s."reason",
    'tenant', s."organization_id",
    'read_only', s."read_only",
    'started_at', s."started_at",
    'expires_at', s."expires_at",
    'ended_at', s."ended_at",
    'ended_by', s."ended_by",
    'metadata', s."metadata"
  )
  from "better_supabase"."support_sessions" s
  where s."id" = $1
    and s."ended_at" is null
    and s."expires_at" > now()
    and case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then s."admin_id" = $2
      else s."admin_id" = auth.uid() and "better_supabase"."is_platform"('support.start')
    end
$$;

-- Sessions, newest first, for platform staff with the view permission.
create or replace function "better_supabase"."list_support_sessions"(
  admin_id uuid default null,
  target uuid default null,
  active boolean default null,
  max_rows integer default 50
)
returns setof jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', s."id",
    'admin_id', s."admin_id",
    'target_user_id', s."target_user_id",
    'reason', s."reason",
    'tenant', s."organization_id",
    'read_only', s."read_only",
    'started_at', s."started_at",
    'expires_at', s."expires_at",
    'ended_at', s."ended_at",
    'ended_by', s."ended_by",
    'metadata', s."metadata"
  )
  from "better_supabase"."support_sessions" s
  where (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or "better_supabase"."is_platform"('support.read'))
    and ($1 is null or s."admin_id" = $1)
    and ($2 is null or s."target_user_id" = $2)
    and ($3 is null
      or $3 = (s."ended_at" is null and s."expires_at" > now()))
  order by s."started_at" desc
  limit $4
$$;

create or replace function "better_supabase"."support_target_claims"(target uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  base jsonb;
begin
  select jsonb_build_object(
    'user_id', u.id,
    'authentication_method', 'support',
    'claims', jsonb_strip_nulls(jsonb_build_object(
      'sub', u.id::text,
      'aud', 'authenticated',
      'role', coalesce(nullif(u.role, ''), 'authenticated'),
      'email', u.email,
      'phone', nullif(u.phone, ''),
      'app_metadata', coalesce(u.raw_app_meta_data, '{}'),
      'user_metadata', coalesce(u.raw_user_meta_data, '{}'),
      'is_anonymous', u.is_anonymous,
      'aal', 'aal1',
      'amr', '[]'::jsonb,
      'session_id', gen_random_uuid()
    ))
  ) into base
  from auth.users u where u.id = target;
  if base is null then
    raise exception 'No user %', target using errcode = 'P0002', hint = 'SUPPORT_TARGET_MISSING';
  end if;
  return base -> 'claims';
end;
$$;

revoke execute on function "better_supabase"."start_support_session"(uuid, text, interval, boolean, jsonb, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."start_support_session"(uuid, text, interval, boolean, jsonb, uuid, uuid) to authenticated, service_role;
revoke execute on function "better_supabase"."end_support_session"(uuid, text) from public, anon;
grant execute on function "better_supabase"."end_support_session"(uuid, text) to authenticated, service_role;
revoke execute on function "better_supabase"."active_support_session"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."active_support_session"(uuid, uuid) to authenticated, service_role;
revoke execute on function "better_supabase"."list_support_sessions"(uuid, uuid, boolean, integer) from public, anon;
grant execute on function "better_supabase"."list_support_sessions"(uuid, uuid, boolean, integer) to authenticated, service_role;
revoke execute on function "better_supabase"."support_target_claims"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."support_target_claims"(uuid) to service_role;
revoke execute on function "better_supabase"."expire_support_sessions"() from public, anon, authenticated;
grant execute on function "better_supabase"."expire_support_sessions"() to service_role;

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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_20_support_sessions.sql
-- better-supabase module: support-sessions
-- @bs-module-data support-sessions
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('support-sessions', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_20_support_sessions.sql
-- better-supabase module: support-sessions
-- @bs-module support-sessions@1 managed
-- Lets platform staff view the app as a user: time-limited, read-only by default, gated by is_platform(), recorded in the audit log, with the target's claims built by your access token hook.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."support_sessions" (
  "id" uuid primary key default gen_random_uuid(),
  -- Sessions outlive a deleted user, so the record of who viewed whom stays.
  "admin_id" uuid references auth.users (id) on delete set null,
  "target_user_id" uuid references auth.users (id) on delete set null,
  "reason" text not null,
  "organization_id" uuid,
  "read_only" boolean not null default true,
  "started_at" timestamptz not null default now(),
  "expires_at" timestamptz not null,
  "ended_at" timestamptz,
  "ended_by" text check ("ended_by" in ('admin', 'expired', 'revoked')),
  -- App data, such as a ticket id.
  "metadata" jsonb not null default '{}',
  check ("admin_id" <> "target_user_id"),
  check ("expires_at" > "started_at")
);
create index if not exists support_sessions_admin_idx on "better_supabase"."support_sessions" ("admin_id", "started_at" desc);
create index if not exists support_sessions_target_idx on "better_supabase"."support_sessions" ("target_user_id", "started_at" desc);
create unique index if not exists support_sessions_one_active_idx on "better_supabase"."support_sessions" ("admin_id") where "ended_at" is null;
alter table "better_supabase"."support_sessions" enable row level security;
revoke all on "better_supabase"."support_sessions" from anon, authenticated;
grant select on "better_supabase"."support_sessions" to service_role;
-- Platform staff read every session.
drop policy if exists bs_support_read on "better_supabase"."support_sessions";
create policy bs_support_read on "better_supabase"."support_sessions" for select to authenticated
  using ((select "better_supabase"."is_platform"('support.read')));
grant select on "better_supabase"."support_sessions" to authenticated;


-- Starts a support session: the admin sees the app as target until it expires
-- or ends. An admin has one active session; starting another ends the first.
-- Errors carry a code in the hint: SUPPORT_FORBIDDEN, SUPPORT_SELF,
-- SUPPORT_TARGET_MISSING, SUPPORT_TTL or SUPPORT_REASON_REQUIRED.
create or replace function "better_supabase"."start_support_session"(
  target uuid,
  reason text default null,
  ttl interval default '30 minutes',
  read_only boolean default true,
  metadata jsonb default '{}',
  tenant uuid default null,
  admin_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  admin uuid;
  session_id uuid;
  started jsonb;
begin
  if service then
    admin := admin_id;
    if admin is null then
      raise exception 'admin_id is required for the service role' using errcode = '22023', hint = 'SUPPORT_FORBIDDEN';
    end if;
  else
    admin := auth.uid();
    if admin is null or (admin_id is not null and admin_id <> admin)
      or not "better_supabase"."is_platform"('support.start') then
      raise exception 'Not allowed to start a support session' using errcode = '42501', hint = 'SUPPORT_FORBIDDEN';
    end if;
  end if;
  if target = admin then
    raise exception 'An admin cannot start a support session as themselves' using errcode = '22023', hint = 'SUPPORT_SELF';
  end if;
  if not exists (select 1 from auth.users u where u.id = target) then
    raise exception 'No user %', target using errcode = 'P0002', hint = 'SUPPORT_TARGET_MISSING';
  end if;
  if ttl <= interval '0' or ttl > '4 hours'::interval then
    raise exception 'ttl must be between 0 and %', '4 hours' using errcode = '22023', hint = 'SUPPORT_TTL';
  end if;
  -- Viewing the app as platform staff would hand the admin that staff's reach.
  if exists (
    select 1 from auth.users u
    where u.id = target and jsonb_typeof(u.raw_app_meta_data -> 'platform_permissions') = 'array'
      and jsonb_array_length(u.raw_app_meta_data -> 'platform_permissions') > 0
  ) then
    raise exception 'A support session cannot target platform staff' using errcode = '42501', hint = 'SUPPORT_TARGET_PLATFORM';
  end if;
  if not coalesce(read_only, true) then
    raise exception 'Support sessions are read-only (modules.support-sessions.options.allowWrites)' using errcode = '42501', hint = 'SUPPORT_WRITES_DISABLED';
  end if;
  if coalesce(btrim(reason), '') = '' then
    raise exception 'A reason is required' using errcode = '22023', hint = 'SUPPORT_REASON_REQUIRED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_support_start"(uuid, uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text, $4::jsonb)', v_hook::oid::regproc)
        using admin, target, reason, metadata;
    end if;
  end;
  update "better_supabase"."support_sessions" s set "ended_at" = now(), "ended_by" = 'admin'
  where s."admin_id" = admin and s."ended_at" is null;
  insert into "better_supabase"."support_sessions" ("admin_id", "target_user_id", "reason", "organization_id", "read_only", "expires_at", "metadata")
  values (admin, target, coalesce(reason, ''), tenant, read_only, now() + ttl, coalesce(metadata, '{}'))
  returning "id" into session_id;
  select jsonb_build_object(
    'id', s."id",
    'admin_id', s."admin_id",
    'target_user_id', s."target_user_id",
    'reason', s."reason",
    'tenant', s."organization_id",
    'read_only', s."read_only",
    'started_at', s."started_at",
    'expires_at', s."expires_at",
    'ended_at', s."ended_at",
    'ended_by', s."ended_by",
    'metadata', s."metadata"
  ) into started from "better_supabase"."support_sessions" s where s."id" = session_id;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_support_start"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using session_id;
    end if;
  end;
  perform "better_supabase".emit_event('support.started', jsonb_build_object('sessionId', started ->> 'id', 'adminId', started ->> 'admin_id', 'targetUserId', started ->> 'target_user_id', 'reason', started ->> 'reason', 'readOnly', (started ->> 'read_only')::boolean, 'expiresAt', started ->> 'expires_at', 'organizationId', started ->> 'tenant'), 'support-sessions/' || session_id, (tenant)::text, 'support.started:' || session_id, 'better-supabase/support-sessions');
  perform better_supabase.audit_event(
    event_type => 'support.started',
    category => 'security',
    target_type => 'user',
    record_id => target::text,
    tenant => (tenant)::uuid,
    metadata => jsonb_build_object('session_id', session_id, 'reason', reason, 'read_only', read_only),
    idempotency_key => 'support.started:' || session_id,
    actor_id => admin,
    support_session => session_id,
    impersonated_by => admin,
    impersonation_reason => reason
  );
  return started;
end;
$$;

-- Ends a session. The admin who started it ends their own ('admin');
-- platform staff with the revoke permission end anyone's ('revoked'). Only
-- the service role chooses ended_by, for example 'expired' from a sweep.
create or replace function "better_supabase"."end_support_session"(
  session_id uuid,
  ended_by text default 'admin'
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  ended jsonb;
begin
  if service and ended_by not in ('admin', 'expired', 'revoked') then
    raise exception 'ended_by must be admin, expired or revoked' using errcode = '22023';
  end if;
  update "better_supabase"."support_sessions" s set "ended_at" = now(), "ended_by" = case
      when service then ended_by
      when s."admin_id" = auth.uid() then 'admin'
      else 'revoked'
    end
  where s."id" = session_id and s."ended_at" is null
    and (service or s."admin_id" = auth.uid()
      or "better_supabase"."is_platform"('support.revoke'))
  returning jsonb_build_object(
    'id', s."id",
    'admin_id', s."admin_id",
    'target_user_id', s."target_user_id",
    'reason', s."reason",
    'tenant', s."organization_id",
    'read_only', s."read_only",
    'started_at', s."started_at",
    'expires_at', s."expires_at",
    'ended_at', s."ended_at",
    'ended_by', s."ended_by",
    'metadata', s."metadata"
  ) into ended;
  if not service then
    ended_by := case when (ended ->> 'admin_id')::uuid = auth.uid() then 'admin' else 'revoked' end;
  end if;
  if ended is null then
    return false;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_support_end"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using session_id;
    end if;
  end;
  perform "better_supabase".emit_event('support.ended', jsonb_build_object('sessionId', ended ->> 'id', 'adminId', ended ->> 'admin_id', 'targetUserId', ended ->> 'target_user_id', 'reason', ended ->> 'reason', 'readOnly', (ended ->> 'read_only')::boolean, 'expiresAt', ended ->> 'expires_at', 'organizationId', ended ->> 'tenant', 'endedBy', ended_by), 'support-sessions/' || session_id, ((ended ->> 'tenant')::uuid)::text, 'support.ended:' || session_id, 'better-supabase/support-sessions');
  perform better_supabase.audit_event(
    event_type => 'support.ended',
    category => 'security',
    target_type => 'user',
    record_id => ended ->> 'target_user_id',
    tenant => ((ended ->> 'tenant')::uuid)::uuid,
    metadata => jsonb_build_object('session_id', session_id, 'ended_by', ended_by),
    idempotency_key => 'support.ended:' || session_id,
    actor_id => case when service then (ended ->> 'admin_id')::uuid else auth.uid() end,
    support_session => session_id,
    impersonated_by => (ended ->> 'admin_id')::uuid,
    impersonation_reason => ended ->> 'reason'
  );
  return true;
end;
$$;

-- Ends the sessions past their expiry, each with ended_by 'expired', and
-- returns them. Run it from a cron job as the service role.
create or replace function "better_supabase"."expire_support_sessions"()
returns setof jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  expired_id uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role expires support sessions' using errcode = '42501', hint = 'SUPPORT_FORBIDDEN';
  end if;
  for expired_id in
    select s."id" from "better_supabase"."support_sessions" s
    where s."ended_at" is null and s."expires_at" <= now()
    order by s."expires_at"
    for update skip locked
  loop
    if "better_supabase"."end_support_session"(expired_id, 'expired') then
      return next (select jsonb_build_object(
    'id', s."id",
    'admin_id', s."admin_id",
    'target_user_id', s."target_user_id",
    'reason', s."reason",
    'tenant', s."organization_id",
    'read_only', s."read_only",
    'started_at', s."started_at",
    'expires_at', s."expires_at",
    'ended_at', s."ended_at",
    'ended_by', s."ended_by",
    'metadata', s."metadata"
  ) from "better_supabase"."support_sessions" s where s."id" = expired_id);
    end if;
  end loop;
end;
$$;

-- Parameters are positional below: in SQL functions a column name wins over a
-- parameter of the same name.
-- The admin's session while it is active, or null. Read on every request
-- that carries the support cookie. Called as the admin, it also checks that
-- the admin may still start sessions.
create or replace function "better_supabase"."active_support_session"(
  session_id uuid,
  admin_id uuid default null
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', s."id",
    'admin_id', s."admin_id",
    'target_user_id', s."target_user_id",
    'reason', s."reason",
    'tenant', s."organization_id",
    'read_only', s."read_only",
    'started_at', s."started_at",
    'expires_at', s."expires_at",
    'ended_at', s."ended_at",
    'ended_by', s."ended_by",
    'metadata', s."metadata"
  )
  from "better_supabase"."support_sessions" s
  where s."id" = $1
    and s."ended_at" is null
    and s."expires_at" > now()
    and case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then s."admin_id" = $2
      else s."admin_id" = auth.uid() and "better_supabase"."is_platform"('support.start')
    end
$$;

-- Sessions, newest first, for platform staff with the view permission.
create or replace function "better_supabase"."list_support_sessions"(
  admin_id uuid default null,
  target uuid default null,
  active boolean default null,
  max_rows integer default 50
)
returns setof jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', s."id",
    'admin_id', s."admin_id",
    'target_user_id', s."target_user_id",
    'reason', s."reason",
    'tenant', s."organization_id",
    'read_only', s."read_only",
    'started_at', s."started_at",
    'expires_at', s."expires_at",
    'ended_at', s."ended_at",
    'ended_by', s."ended_by",
    'metadata', s."metadata"
  )
  from "better_supabase"."support_sessions" s
  where (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or "better_supabase"."is_platform"('support.read'))
    and ($1 is null or s."admin_id" = $1)
    and ($2 is null or s."target_user_id" = $2)
    and ($3 is null
      or $3 = (s."ended_at" is null and s."expires_at" > now()))
  order by s."started_at" desc
  limit $4
$$;

create or replace function "better_supabase"."support_target_claims"(target uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  base jsonb;
begin
  select jsonb_build_object(
    'user_id', u.id,
    'authentication_method', 'support',
    'claims', jsonb_strip_nulls(jsonb_build_object(
      'sub', u.id::text,
      'aud', 'authenticated',
      'role', coalesce(nullif(u.role, ''), 'authenticated'),
      'email', u.email,
      'phone', nullif(u.phone, ''),
      'app_metadata', coalesce(u.raw_app_meta_data, '{}'),
      'user_metadata', coalesce(u.raw_user_meta_data, '{}'),
      'is_anonymous', u.is_anonymous,
      'aal', 'aal1',
      'amr', '[]'::jsonb,
      'session_id', gen_random_uuid()
    ))
  ) into base
  from auth.users u where u.id = target;
  if base is null then
    raise exception 'No user %', target using errcode = 'P0002', hint = 'SUPPORT_TARGET_MISSING';
  end if;
  return base -> 'claims';
end;
$$;

revoke execute on function "better_supabase"."start_support_session"(uuid, text, interval, boolean, jsonb, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."start_support_session"(uuid, text, interval, boolean, jsonb, uuid, uuid) to authenticated, service_role;
revoke execute on function "better_supabase"."end_support_session"(uuid, text) from public, anon;
grant execute on function "better_supabase"."end_support_session"(uuid, text) to authenticated, service_role;
revoke execute on function "better_supabase"."active_support_session"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."active_support_session"(uuid, uuid) to authenticated, service_role;
revoke execute on function "better_supabase"."list_support_sessions"(uuid, uuid, boolean, integer) from public, anon;
grant execute on function "better_supabase"."list_support_sessions"(uuid, uuid, boolean, integer) to authenticated, service_role;
revoke execute on function "better_supabase"."support_target_claims"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."support_target_claims"(uuid) to service_role;
revoke execute on function "better_supabase"."expire_support_sessions"() from public, anon, authenticated;
grant execute on function "better_supabase"."expire_support_sessions"() to service_role;

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_20_support_sessions.sql
-- better-supabase module: support-sessions
-- @bs-module-data support-sessions
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('support-sessions', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_20_support_sessions.sql
-- better-supabase module: support-sessions
-- @bs-module support-sessions@1 managed
-- Lets platform staff view the app as a user: time-limited, read-only by default, gated by is_platform(), recorded in the audit log, with the target's claims built by your access token hook.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "app_private"."support_sessions" (
  "id" uuid primary key default gen_random_uuid(),
  -- Sessions outlive a deleted user, so the record of who viewed whom stays.
  "admin_id" uuid references auth.users (id) on delete set null,
  "target_user_id" uuid references auth.users (id) on delete set null,
  "reason" text not null,
  "organization_id" uuid,
  "read_only" boolean not null default true,
  "started_at" timestamptz not null default now(),
  "expires_at" timestamptz not null,
  "ended_at" timestamptz,
  "ended_by" text check ("ended_by" in ('admin', 'expired', 'revoked')),
  -- App data, such as a ticket id.
  "metadata" jsonb not null default '{}',
  check ("admin_id" <> "target_user_id"),
  check ("expires_at" > "started_at")
);
create index if not exists support_sessions_admin_idx on "app_private"."support_sessions" ("admin_id", "started_at" desc);
create index if not exists support_sessions_target_idx on "app_private"."support_sessions" ("target_user_id", "started_at" desc);
create unique index if not exists support_sessions_one_active_idx on "app_private"."support_sessions" ("admin_id") where "ended_at" is null;
alter table "app_private"."support_sessions" enable row level security;
revoke all on "app_private"."support_sessions" from anon, authenticated;
grant select on "app_private"."support_sessions" to service_role;
-- Platform staff read every session.
drop policy if exists bs_support_read on "app_private"."support_sessions";
create policy bs_support_read on "app_private"."support_sessions" for select to authenticated
  using ((select "better_supabase"."is_platform"('support.read')));
grant select on "app_private"."support_sessions" to authenticated;


-- Starts a support session: the admin sees the app as target until it expires
-- or ends. An admin has one active session; starting another ends the first.
-- Errors carry a code in the hint: SUPPORT_FORBIDDEN, SUPPORT_SELF,
-- SUPPORT_TARGET_MISSING, SUPPORT_TTL or SUPPORT_REASON_REQUIRED.
create or replace function "app_private"."start_support_session"(
  target uuid,
  reason text default null,
  ttl interval default '30 minutes',
  read_only boolean default true,
  metadata jsonb default '{}',
  tenant uuid default null,
  admin_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  admin uuid;
  session_id uuid;
  started jsonb;
begin
  if service then
    admin := admin_id;
    if admin is null then
      raise exception 'admin_id is required for the service role' using errcode = '22023', hint = 'SUPPORT_FORBIDDEN';
    end if;
  else
    admin := auth.uid();
    if admin is null or (admin_id is not null and admin_id <> admin)
      or not "better_supabase"."is_platform"('support.start') then
      raise exception 'Not allowed to start a support session' using errcode = '42501', hint = 'SUPPORT_FORBIDDEN';
    end if;
  end if;
  if target = admin then
    raise exception 'An admin cannot start a support session as themselves' using errcode = '22023', hint = 'SUPPORT_SELF';
  end if;
  if not exists (select 1 from auth.users u where u.id = target) then
    raise exception 'No user %', target using errcode = 'P0002', hint = 'SUPPORT_TARGET_MISSING';
  end if;
  if ttl <= interval '0' or ttl > '4 hours'::interval then
    raise exception 'ttl must be between 0 and %', '4 hours' using errcode = '22023', hint = 'SUPPORT_TTL';
  end if;
  -- Viewing the app as platform staff would hand the admin that staff's reach.
  if exists (
    select 1 from auth.users u
    where u.id = target and jsonb_typeof(u.raw_app_meta_data -> 'platform_permissions') = 'array'
      and jsonb_array_length(u.raw_app_meta_data -> 'platform_permissions') > 0
  ) then
    raise exception 'A support session cannot target platform staff' using errcode = '42501', hint = 'SUPPORT_TARGET_PLATFORM';
  end if;
  if not coalesce(read_only, true) then
    raise exception 'Support sessions are read-only (modules.support-sessions.options.allowWrites)' using errcode = '42501', hint = 'SUPPORT_WRITES_DISABLED';
  end if;
  if coalesce(btrim(reason), '') = '' then
    raise exception 'A reason is required' using errcode = '22023', hint = 'SUPPORT_REASON_REQUIRED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_support_start"(uuid, uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text, $4::jsonb)', v_hook::oid::regproc)
        using admin, target, reason, metadata;
    end if;
  end;
  update "app_private"."support_sessions" s set "ended_at" = now(), "ended_by" = 'admin'
  where s."admin_id" = admin and s."ended_at" is null;
  insert into "app_private"."support_sessions" ("admin_id", "target_user_id", "reason", "organization_id", "read_only", "expires_at", "metadata")
  values (admin, target, coalesce(reason, ''), tenant, read_only, now() + ttl, coalesce(metadata, '{}'))
  returning "id" into session_id;
  select jsonb_build_object(
    'id', s."id",
    'admin_id', s."admin_id",
    'target_user_id', s."target_user_id",
    'reason', s."reason",
    'tenant', s."organization_id",
    'read_only', s."read_only",
    'started_at', s."started_at",
    'expires_at', s."expires_at",
    'ended_at', s."ended_at",
    'ended_by', s."ended_by",
    'metadata', s."metadata"
  ) into started from "app_private"."support_sessions" s where s."id" = session_id;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_support_start"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using session_id;
    end if;
  end;
  perform better_supabase.audit_event(
    event_type => 'support.started',
    category => 'security',
    target_type => 'user',
    record_id => target::text,
    tenant => (tenant)::uuid,
    metadata => jsonb_build_object('session_id', session_id, 'reason', reason, 'read_only', read_only),
    idempotency_key => 'support.started:' || session_id,
    actor_id => admin,
    support_session => session_id,
    impersonated_by => admin,
    impersonation_reason => reason
  );
  return started;
end;
$$;

-- Ends a session. The admin who started it ends their own ('admin');
-- platform staff with the revoke permission end anyone's ('revoked'). Only
-- the service role chooses ended_by, for example 'expired' from a sweep.
create or replace function "app_private"."end_support_session"(
  session_id uuid,
  ended_by text default 'admin'
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  ended jsonb;
begin
  if service and ended_by not in ('admin', 'expired', 'revoked') then
    raise exception 'ended_by must be admin, expired or revoked' using errcode = '22023';
  end if;
  update "app_private"."support_sessions" s set "ended_at" = now(), "ended_by" = case
      when service then ended_by
      when s."admin_id" = auth.uid() then 'admin'
      else 'revoked'
    end
  where s."id" = session_id and s."ended_at" is null
    and (service or s."admin_id" = auth.uid()
      or "better_supabase"."is_platform"('support.revoke'))
  returning jsonb_build_object(
    'id', s."id",
    'admin_id', s."admin_id",
    'target_user_id', s."target_user_id",
    'reason', s."reason",
    'tenant', s."organization_id",
    'read_only', s."read_only",
    'started_at', s."started_at",
    'expires_at', s."expires_at",
    'ended_at', s."ended_at",
    'ended_by', s."ended_by",
    'metadata', s."metadata"
  ) into ended;
  if not service then
    ended_by := case when (ended ->> 'admin_id')::uuid = auth.uid() then 'admin' else 'revoked' end;
  end if;
  if ended is null then
    return false;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_support_end"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using session_id;
    end if;
  end;
  perform better_supabase.audit_event(
    event_type => 'support.ended',
    category => 'security',
    target_type => 'user',
    record_id => ended ->> 'target_user_id',
    tenant => ((ended ->> 'tenant')::uuid)::uuid,
    metadata => jsonb_build_object('session_id', session_id, 'ended_by', ended_by),
    idempotency_key => 'support.ended:' || session_id,
    actor_id => case when service then (ended ->> 'admin_id')::uuid else auth.uid() end,
    support_session => session_id,
    impersonated_by => (ended ->> 'admin_id')::uuid,
    impersonation_reason => ended ->> 'reason'
  );
  return true;
end;
$$;

-- Ends the sessions past their expiry, each with ended_by 'expired', and
-- returns them. Run it from a cron job as the service role.
create or replace function "app_private"."expire_support_sessions"()
returns setof jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  expired_id uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role expires support sessions' using errcode = '42501', hint = 'SUPPORT_FORBIDDEN';
  end if;
  for expired_id in
    select s."id" from "app_private"."support_sessions" s
    where s."ended_at" is null and s."expires_at" <= now()
    order by s."expires_at"
    for update skip locked
  loop
    if "app_private"."end_support_session"(expired_id, 'expired') then
      return next (select jsonb_build_object(
    'id', s."id",
    'admin_id', s."admin_id",
    'target_user_id', s."target_user_id",
    'reason', s."reason",
    'tenant', s."organization_id",
    'read_only', s."read_only",
    'started_at', s."started_at",
    'expires_at', s."expires_at",
    'ended_at', s."ended_at",
    'ended_by', s."ended_by",
    'metadata', s."metadata"
  ) from "app_private"."support_sessions" s where s."id" = expired_id);
    end if;
  end loop;
end;
$$;

-- Parameters are positional below: in SQL functions a column name wins over a
-- parameter of the same name.
-- The admin's session while it is active, or null. Read on every request
-- that carries the support cookie. Called as the admin, it also checks that
-- the admin may still start sessions.
create or replace function "app_private"."active_support_session"(
  session_id uuid,
  admin_id uuid default null
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', s."id",
    'admin_id', s."admin_id",
    'target_user_id', s."target_user_id",
    'reason', s."reason",
    'tenant', s."organization_id",
    'read_only', s."read_only",
    'started_at', s."started_at",
    'expires_at', s."expires_at",
    'ended_at', s."ended_at",
    'ended_by', s."ended_by",
    'metadata', s."metadata"
  )
  from "app_private"."support_sessions" s
  where s."id" = $1
    and s."ended_at" is null
    and s."expires_at" > now()
    and case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then s."admin_id" = $2
      else s."admin_id" = auth.uid() and "better_supabase"."is_platform"('support.start')
    end
$$;

-- Sessions, newest first, for platform staff with the view permission.
create or replace function "app_private"."list_support_sessions"(
  admin_id uuid default null,
  target uuid default null,
  active boolean default null,
  max_rows integer default 50
)
returns setof jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', s."id",
    'admin_id', s."admin_id",
    'target_user_id', s."target_user_id",
    'reason', s."reason",
    'tenant', s."organization_id",
    'read_only', s."read_only",
    'started_at', s."started_at",
    'expires_at', s."expires_at",
    'ended_at', s."ended_at",
    'ended_by', s."ended_by",
    'metadata', s."metadata"
  )
  from "app_private"."support_sessions" s
  where (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or "better_supabase"."is_platform"('support.read'))
    and ($1 is null or s."admin_id" = $1)
    and ($2 is null or s."target_user_id" = $2)
    and ($3 is null
      or $3 = (s."ended_at" is null and s."expires_at" > now()))
  order by s."started_at" desc
  limit $4
$$;

create or replace function "app_private"."support_target_claims"(target uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  base jsonb;
begin
  select jsonb_build_object(
    'user_id', u.id,
    'authentication_method', 'support',
    'claims', jsonb_strip_nulls(jsonb_build_object(
      'sub', u.id::text,
      'aud', 'authenticated',
      'role', coalesce(nullif(u.role, ''), 'authenticated'),
      'email', u.email,
      'phone', nullif(u.phone, ''),
      'app_metadata', coalesce(u.raw_app_meta_data, '{}'),
      'user_metadata', coalesce(u.raw_user_meta_data, '{}'),
      'is_anonymous', u.is_anonymous,
      'aal', 'aal1',
      'amr', '[]'::jsonb,
      'session_id', gen_random_uuid()
    ))
  ) into base
  from auth.users u where u.id = target;
  if base is null then
    raise exception 'No user %', target using errcode = 'P0002', hint = 'SUPPORT_TARGET_MISSING';
  end if;
  return base -> 'claims';
end;
$$;

revoke execute on function "app_private"."start_support_session"(uuid, text, interval, boolean, jsonb, uuid, uuid) from public, anon;
grant execute on function "app_private"."start_support_session"(uuid, text, interval, boolean, jsonb, uuid, uuid) to authenticated, service_role;
revoke execute on function "app_private"."end_support_session"(uuid, text) from public, anon;
grant execute on function "app_private"."end_support_session"(uuid, text) to authenticated, service_role;
revoke execute on function "app_private"."active_support_session"(uuid, uuid) from public, anon;
grant execute on function "app_private"."active_support_session"(uuid, uuid) to authenticated, service_role;
revoke execute on function "app_private"."list_support_sessions"(uuid, uuid, boolean, integer) from public, anon;
grant execute on function "app_private"."list_support_sessions"(uuid, uuid, boolean, integer) to authenticated, service_role;
revoke execute on function "app_private"."support_target_claims"(uuid) from public, anon, authenticated;
grant execute on function "app_private"."support_target_claims"(uuid) to service_role;
revoke execute on function "app_private"."expire_support_sessions"() from public, anon, authenticated;
grant execute on function "app_private"."expire_support_sessions"() to service_role;

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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_20_support_sessions.sql
-- better-supabase module: support-sessions
-- @bs-module-data support-sessions
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('support-sessions', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_20_support_sessions.sql
-- better-supabase module: support-sessions
-- @bs-module support-sessions@1 managed
-- Lets platform staff view the app as a user: time-limited, read-only by default, gated by is_platform(), recorded in the audit log, with the target's claims built by your access token hook.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."support_sessions" (
  "id" uuid primary key default gen_random_uuid(),
  -- Sessions outlive a deleted user, so the record of who viewed whom stays.
  "admin_id" uuid references auth.users (id) on delete set null,
  "target_user_id" uuid references auth.users (id) on delete set null,
  "reason" text not null,
  "organization_id" uuid,
  "read_only" boolean not null default true,
  "started_at" timestamptz not null default now(),
  "expires_at" timestamptz not null,
  "ended_at" timestamptz,
  "ended_by" text check ("ended_by" in ('admin', 'expired', 'revoked')),
  -- App data, such as a ticket id.
  "metadata" jsonb not null default '{}',
  check ("admin_id" <> "target_user_id"),
  check ("expires_at" > "started_at")
);
create index if not exists support_sessions_admin_idx on "better_supabase"."support_sessions" ("admin_id", "started_at" desc);
create index if not exists support_sessions_target_idx on "better_supabase"."support_sessions" ("target_user_id", "started_at" desc);
create unique index if not exists support_sessions_one_active_idx on "better_supabase"."support_sessions" ("admin_id") where "ended_at" is null;
alter table "better_supabase"."support_sessions" enable row level security;
revoke all on "better_supabase"."support_sessions" from anon, authenticated;
grant select on "better_supabase"."support_sessions" to service_role;
-- Platform staff read every session.
drop policy if exists bs_support_read on "better_supabase"."support_sessions";
create policy bs_support_read on "better_supabase"."support_sessions" for select to authenticated
  using ((select "better_supabase"."is_platform"('support.read')));
grant select on "better_supabase"."support_sessions" to authenticated;


-- Starts a support session: the admin sees the app as target until it expires
-- or ends. An admin has one active session; starting another ends the first.
-- Errors carry a code in the hint: SUPPORT_FORBIDDEN, SUPPORT_SELF,
-- SUPPORT_TARGET_MISSING, SUPPORT_TTL or SUPPORT_REASON_REQUIRED.
create or replace function "better_supabase"."start_support_session"(
  target uuid,
  reason text default null,
  ttl interval default '30 minutes',
  read_only boolean default true,
  metadata jsonb default '{}',
  tenant uuid default null,
  admin_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  admin uuid;
  session_id uuid;
  started jsonb;
begin
  if service then
    admin := admin_id;
    if admin is null then
      raise exception 'admin_id is required for the service role' using errcode = '22023', hint = 'SUPPORT_FORBIDDEN';
    end if;
  else
    admin := auth.uid();
    if admin is null or (admin_id is not null and admin_id <> admin)
      or not "better_supabase"."is_platform"('support.start') then
      raise exception 'Not allowed to start a support session' using errcode = '42501', hint = 'SUPPORT_FORBIDDEN';
    end if;
  end if;
  if target = admin then
    raise exception 'An admin cannot start a support session as themselves' using errcode = '22023', hint = 'SUPPORT_SELF';
  end if;
  if not exists (select 1 from auth.users u where u.id = target) then
    raise exception 'No user %', target using errcode = 'P0002', hint = 'SUPPORT_TARGET_MISSING';
  end if;
  if ttl <= interval '0' or ttl > '4 hours'::interval then
    raise exception 'ttl must be between 0 and %', '4 hours' using errcode = '22023', hint = 'SUPPORT_TTL';
  end if;
  -- Viewing the app as platform staff would hand the admin that staff's reach.
  if exists (
    select 1 from auth.users u
    where u.id = target and jsonb_typeof(u.raw_app_meta_data -> 'platform_permissions') = 'array'
      and jsonb_array_length(u.raw_app_meta_data -> 'platform_permissions') > 0
  ) then
    raise exception 'A support session cannot target platform staff' using errcode = '42501', hint = 'SUPPORT_TARGET_PLATFORM';
  end if;
  if not coalesce(read_only, true) then
    raise exception 'Support sessions are read-only (modules.support-sessions.options.allowWrites)' using errcode = '42501', hint = 'SUPPORT_WRITES_DISABLED';
  end if;
  if coalesce(btrim(reason), '') = '' then
    raise exception 'A reason is required' using errcode = '22023', hint = 'SUPPORT_REASON_REQUIRED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_support_start"(uuid, uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text, $4::jsonb)', v_hook::oid::regproc)
        using admin, target, reason, metadata;
    end if;
  end;
  update "better_supabase"."support_sessions" s set "ended_at" = now(), "ended_by" = 'admin'
  where s."admin_id" = admin and s."ended_at" is null;
  insert into "better_supabase"."support_sessions" ("admin_id", "target_user_id", "reason", "organization_id", "read_only", "expires_at", "metadata")
  values (admin, target, coalesce(reason, ''), tenant, read_only, now() + ttl, coalesce(metadata, '{}'))
  returning "id" into session_id;
  select jsonb_build_object(
    'id', s."id",
    'admin_id', s."admin_id",
    'target_user_id', s."target_user_id",
    'reason', s."reason",
    'tenant', s."organization_id",
    'read_only', s."read_only",
    'started_at', s."started_at",
    'expires_at', s."expires_at",
    'ended_at', s."ended_at",
    'ended_by', s."ended_by",
    'metadata', s."metadata"
  ) into started from "better_supabase"."support_sessions" s where s."id" = session_id;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_support_start"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using session_id;
    end if;
  end;
  perform better_supabase.audit_event(
    event_type => 'support.started',
    category => 'security',
    target_type => 'user',
    record_id => target::text,
    tenant => (tenant)::uuid,
    metadata => jsonb_build_object('session_id', session_id, 'reason', reason, 'read_only', read_only),
    idempotency_key => 'support.started:' || session_id,
    actor_id => admin,
    support_session => session_id,
    impersonated_by => admin,
    impersonation_reason => reason
  );
  return started;
end;
$$;

-- Ends a session. The admin who started it ends their own ('admin');
-- platform staff with the revoke permission end anyone's ('revoked'). Only
-- the service role chooses ended_by, for example 'expired' from a sweep.
create or replace function "better_supabase"."end_support_session"(
  session_id uuid,
  ended_by text default 'admin'
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  ended jsonb;
begin
  if service and ended_by not in ('admin', 'expired', 'revoked') then
    raise exception 'ended_by must be admin, expired or revoked' using errcode = '22023';
  end if;
  update "better_supabase"."support_sessions" s set "ended_at" = now(), "ended_by" = case
      when service then ended_by
      when s."admin_id" = auth.uid() then 'admin'
      else 'revoked'
    end
  where s."id" = session_id and s."ended_at" is null
    and (service or s."admin_id" = auth.uid()
      or "better_supabase"."is_platform"('support.revoke'))
  returning jsonb_build_object(
    'id', s."id",
    'admin_id', s."admin_id",
    'target_user_id', s."target_user_id",
    'reason', s."reason",
    'tenant', s."organization_id",
    'read_only', s."read_only",
    'started_at', s."started_at",
    'expires_at', s."expires_at",
    'ended_at', s."ended_at",
    'ended_by', s."ended_by",
    'metadata', s."metadata"
  ) into ended;
  if not service then
    ended_by := case when (ended ->> 'admin_id')::uuid = auth.uid() then 'admin' else 'revoked' end;
  end if;
  if ended is null then
    return false;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_support_end"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using session_id;
    end if;
  end;
  perform better_supabase.audit_event(
    event_type => 'support.ended',
    category => 'security',
    target_type => 'user',
    record_id => ended ->> 'target_user_id',
    tenant => ((ended ->> 'tenant')::uuid)::uuid,
    metadata => jsonb_build_object('session_id', session_id, 'ended_by', ended_by),
    idempotency_key => 'support.ended:' || session_id,
    actor_id => case when service then (ended ->> 'admin_id')::uuid else auth.uid() end,
    support_session => session_id,
    impersonated_by => (ended ->> 'admin_id')::uuid,
    impersonation_reason => ended ->> 'reason'
  );
  return true;
end;
$$;

-- Ends the sessions past their expiry, each with ended_by 'expired', and
-- returns them. Run it from a cron job as the service role.
create or replace function "better_supabase"."expire_support_sessions"()
returns setof jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  expired_id uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role expires support sessions' using errcode = '42501', hint = 'SUPPORT_FORBIDDEN';
  end if;
  for expired_id in
    select s."id" from "better_supabase"."support_sessions" s
    where s."ended_at" is null and s."expires_at" <= now()
    order by s."expires_at"
    for update skip locked
  loop
    if "better_supabase"."end_support_session"(expired_id, 'expired') then
      return next (select jsonb_build_object(
    'id', s."id",
    'admin_id', s."admin_id",
    'target_user_id', s."target_user_id",
    'reason', s."reason",
    'tenant', s."organization_id",
    'read_only', s."read_only",
    'started_at', s."started_at",
    'expires_at', s."expires_at",
    'ended_at', s."ended_at",
    'ended_by', s."ended_by",
    'metadata', s."metadata"
  ) from "better_supabase"."support_sessions" s where s."id" = expired_id);
    end if;
  end loop;
end;
$$;

-- Parameters are positional below: in SQL functions a column name wins over a
-- parameter of the same name.
-- The admin's session while it is active, or null. Read on every request
-- that carries the support cookie. Called as the admin, it also checks that
-- the admin may still start sessions.
create or replace function "better_supabase"."active_support_session"(
  session_id uuid,
  admin_id uuid default null
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', s."id",
    'admin_id', s."admin_id",
    'target_user_id', s."target_user_id",
    'reason', s."reason",
    'tenant', s."organization_id",
    'read_only', s."read_only",
    'started_at', s."started_at",
    'expires_at', s."expires_at",
    'ended_at', s."ended_at",
    'ended_by', s."ended_by",
    'metadata', s."metadata"
  )
  from "better_supabase"."support_sessions" s
  where s."id" = $1
    and s."ended_at" is null
    and s."expires_at" > now()
    and case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then s."admin_id" = $2
      else s."admin_id" = auth.uid() and "better_supabase"."is_platform"('support.start')
    end
$$;

-- Sessions, newest first, for platform staff with the view permission.
create or replace function "better_supabase"."list_support_sessions"(
  admin_id uuid default null,
  target uuid default null,
  active boolean default null,
  max_rows integer default 50
)
returns setof jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', s."id",
    'admin_id', s."admin_id",
    'target_user_id', s."target_user_id",
    'reason', s."reason",
    'tenant', s."organization_id",
    'read_only', s."read_only",
    'started_at', s."started_at",
    'expires_at', s."expires_at",
    'ended_at', s."ended_at",
    'ended_by', s."ended_by",
    'metadata', s."metadata"
  )
  from "better_supabase"."support_sessions" s
  where (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or "better_supabase"."is_platform"('support.read'))
    and ($1 is null or s."admin_id" = $1)
    and ($2 is null or s."target_user_id" = $2)
    and ($3 is null
      or $3 = (s."ended_at" is null and s."expires_at" > now()))
  order by s."started_at" desc
  limit $4
$$;

create or replace function "better_supabase"."support_target_claims"(target uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  base jsonb;
begin
  select jsonb_build_object(
    'user_id', u.id,
    'authentication_method', 'support',
    'claims', jsonb_strip_nulls(jsonb_build_object(
      'sub', u.id::text,
      'aud', 'authenticated',
      'role', coalesce(nullif(u.role, ''), 'authenticated'),
      'email', u.email,
      'phone', nullif(u.phone, ''),
      'app_metadata', coalesce(u.raw_app_meta_data, '{}'),
      'user_metadata', coalesce(u.raw_user_meta_data, '{}'),
      'is_anonymous', u.is_anonymous,
      'aal', 'aal1',
      'amr', '[]'::jsonb,
      'session_id', gen_random_uuid()
    ))
  ) into base
  from auth.users u where u.id = target;
  if base is null then
    raise exception 'No user %', target using errcode = 'P0002', hint = 'SUPPORT_TARGET_MISSING';
  end if;
  return base -> 'claims';
end;
$$;

revoke execute on function "better_supabase"."start_support_session"(uuid, text, interval, boolean, jsonb, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."start_support_session"(uuid, text, interval, boolean, jsonb, uuid, uuid) to authenticated, service_role;
revoke execute on function "better_supabase"."end_support_session"(uuid, text) from public, anon;
grant execute on function "better_supabase"."end_support_session"(uuid, text) to authenticated, service_role;
revoke execute on function "better_supabase"."active_support_session"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."active_support_session"(uuid, uuid) to authenticated, service_role;
revoke execute on function "better_supabase"."list_support_sessions"(uuid, uuid, boolean, integer) from public, anon;
grant execute on function "better_supabase"."list_support_sessions"(uuid, uuid, boolean, integer) to authenticated, service_role;
revoke execute on function "better_supabase"."support_target_claims"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."support_target_claims"(uuid) to service_role;
revoke execute on function "better_supabase"."expire_support_sessions"() from public, anon, authenticated;
grant execute on function "better_supabase"."expire_support_sessions"() to service_role;

-- sql.modules.support-sessions.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."start_support_session"(target uuid, reason text default null, ttl interval default '30 minutes', read_only boolean default true, metadata jsonb default '{}', tenant uuid default null, admin_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."start_support_session"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."start_support_session"(uuid, text, interval, boolean, jsonb, uuid, uuid) from public, anon;
grant execute on function "api"."start_support_session"(uuid, text, interval, boolean, jsonb, uuid, uuid) to authenticated, service_role;

create or replace function "api"."end_support_session"(session_id uuid, ended_by text default 'admin')
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."end_support_session"($1, $2) $$;
revoke execute on function "api"."end_support_session"(uuid, text) from public, anon;
grant execute on function "api"."end_support_session"(uuid, text) to authenticated, service_role;

create or replace function "api"."active_support_session"(session_id uuid, admin_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."active_support_session"($1, $2) $$;
revoke execute on function "api"."active_support_session"(uuid, uuid) from public, anon;
grant execute on function "api"."active_support_session"(uuid, uuid) to authenticated, service_role;

create or replace function "api"."list_support_sessions"(admin_id uuid default null, target uuid default null, active boolean default null, max_rows integer default 50)
returns setof jsonb
language sql
security invoker
set search_path = ''
as $$ select * from "better_supabase"."list_support_sessions"($1, $2, $3, $4) $$;
revoke execute on function "api"."list_support_sessions"(uuid, uuid, boolean, integer) from public, anon;
grant execute on function "api"."list_support_sessions"(uuid, uuid, boolean, integer) to authenticated, service_role;

create or replace function "api"."support_target_claims"(target uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."support_target_claims"($1) $$;
revoke execute on function "api"."support_target_claims"(uuid) from public, anon, authenticated;
grant execute on function "api"."support_target_claims"(uuid) to service_role;

create or replace function "api"."expire_support_sessions"()
returns setof jsonb
language sql
security invoker
set search_path = ''
as $$ select * from "better_supabase"."expire_support_sessions"() $$;
revoke execute on function "api"."expire_support_sessions"() from public, anon, authenticated;
grant execute on function "api"."expire_support_sessions"() to service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_20_support_sessions.sql
-- better-supabase module: support-sessions
-- @bs-module-data support-sessions
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('support-sessions', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== adopt: schema supabase/schemas/900_better_supabase_20_support_sessions.sql
-- better-supabase module: support-sessions
-- @bs-module support-sessions@1 adopt
-- Lets platform staff view the app as a user: time-limited, read-only by default, gated by is_platform(), recorded in the audit log, with the target's claims built by your access token hook.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- Starts a support session: the admin sees the app as target until it expires
-- or ends. An admin has one active session; starting another ends the first.
-- Errors carry a code in the hint: SUPPORT_FORBIDDEN, SUPPORT_SELF,
-- SUPPORT_TARGET_MISSING, SUPPORT_TTL or SUPPORT_REASON_REQUIRED.
create or replace function "better_supabase"."start_support_session"(
  target uuid,
  reason text default null,
  ttl interval default '30 minutes',
  read_only boolean default true,
  metadata jsonb default '{}',
  tenant uuid default null,
  admin_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  admin uuid;
  session_id uuid;
  started jsonb;
begin
  if service then
    admin := admin_id;
    if admin is null then
      raise exception 'admin_id is required for the service role' using errcode = '22023', hint = 'SUPPORT_FORBIDDEN';
    end if;
  else
    admin := auth.uid();
    if admin is null or (admin_id is not null and admin_id <> admin)
      or not "better_supabase"."is_platform"('support.start') then
      raise exception 'Not allowed to start a support session' using errcode = '42501', hint = 'SUPPORT_FORBIDDEN';
    end if;
  end if;
  if target = admin then
    raise exception 'An admin cannot start a support session as themselves' using errcode = '22023', hint = 'SUPPORT_SELF';
  end if;
  if not exists (select 1 from auth.users u where u.id = target) then
    raise exception 'No user %', target using errcode = 'P0002', hint = 'SUPPORT_TARGET_MISSING';
  end if;
  if ttl <= interval '0' or ttl > '4 hours'::interval then
    raise exception 'ttl must be between 0 and %', '4 hours' using errcode = '22023', hint = 'SUPPORT_TTL';
  end if;
  -- Viewing the app as platform staff would hand the admin that staff's reach.
  if exists (
    select 1 from auth.users u
    where u.id = target and jsonb_typeof(u.raw_app_meta_data -> 'platform_permissions') = 'array'
      and jsonb_array_length(u.raw_app_meta_data -> 'platform_permissions') > 0
  ) then
    raise exception 'A support session cannot target platform staff' using errcode = '42501', hint = 'SUPPORT_TARGET_PLATFORM';
  end if;
  if not coalesce(read_only, true) then
    raise exception 'Support sessions are read-only (modules.support-sessions.options.allowWrites)' using errcode = '42501', hint = 'SUPPORT_WRITES_DISABLED';
  end if;
  if coalesce(btrim(reason), '') = '' then
    raise exception 'A reason is required' using errcode = '22023', hint = 'SUPPORT_REASON_REQUIRED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_support_start"(uuid, uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text, $4::jsonb)', v_hook::oid::regproc)
        using admin, target, reason, metadata;
    end if;
  end;
  update "better_supabase"."support_sessions" s set "ended_at" = now(), "ended_by" = 'admin'
  where s."admin_id" = admin and s."ended_at" is null;
  insert into "better_supabase"."support_sessions" ("admin_id", "target_user_id", "reason", "organization_id", "read_only", "expires_at", "metadata")
  values (admin, target, coalesce(reason, ''), tenant, read_only, now() + ttl, coalesce(metadata, '{}'))
  returning "id" into session_id;
  select jsonb_build_object(
    'id', s."id",
    'admin_id', s."admin_id",
    'target_user_id', s."target_user_id",
    'reason', s."reason",
    'tenant', s."organization_id",
    'read_only', s."read_only",
    'started_at', s."started_at",
    'expires_at', s."expires_at",
    'ended_at', s."ended_at",
    'ended_by', s."ended_by",
    'metadata', s."metadata"
  ) into started from "better_supabase"."support_sessions" s where s."id" = session_id;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_support_start"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using session_id;
    end if;
  end;
  perform better_supabase.audit_event(
    event_type => 'support.started',
    category => 'security',
    target_type => 'user',
    record_id => target::text,
    tenant => (tenant)::uuid,
    metadata => jsonb_build_object('session_id', session_id, 'reason', reason, 'read_only', read_only),
    idempotency_key => 'support.started:' || session_id,
    actor_id => admin,
    support_session => session_id,
    impersonated_by => admin,
    impersonation_reason => reason
  );
  return started;
end;
$$;

-- Ends a session. The admin who started it ends their own ('admin');
-- platform staff with the revoke permission end anyone's ('revoked'). Only
-- the service role chooses ended_by, for example 'expired' from a sweep.
create or replace function "better_supabase"."end_support_session"(
  session_id uuid,
  ended_by text default 'admin'
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  ended jsonb;
begin
  if service and ended_by not in ('admin', 'expired', 'revoked') then
    raise exception 'ended_by must be admin, expired or revoked' using errcode = '22023';
  end if;
  update "better_supabase"."support_sessions" s set "ended_at" = now(), "ended_by" = case
      when service then ended_by
      when s."admin_id" = auth.uid() then 'admin'
      else 'revoked'
    end
  where s."id" = session_id and s."ended_at" is null
    and (service or s."admin_id" = auth.uid()
      or "better_supabase"."is_platform"('support.revoke'))
  returning jsonb_build_object(
    'id', s."id",
    'admin_id', s."admin_id",
    'target_user_id', s."target_user_id",
    'reason', s."reason",
    'tenant', s."organization_id",
    'read_only', s."read_only",
    'started_at', s."started_at",
    'expires_at', s."expires_at",
    'ended_at', s."ended_at",
    'ended_by', s."ended_by",
    'metadata', s."metadata"
  ) into ended;
  if not service then
    ended_by := case when (ended ->> 'admin_id')::uuid = auth.uid() then 'admin' else 'revoked' end;
  end if;
  if ended is null then
    return false;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_support_end"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using session_id;
    end if;
  end;
  perform better_supabase.audit_event(
    event_type => 'support.ended',
    category => 'security',
    target_type => 'user',
    record_id => ended ->> 'target_user_id',
    tenant => ((ended ->> 'tenant')::uuid)::uuid,
    metadata => jsonb_build_object('session_id', session_id, 'ended_by', ended_by),
    idempotency_key => 'support.ended:' || session_id,
    actor_id => case when service then (ended ->> 'admin_id')::uuid else auth.uid() end,
    support_session => session_id,
    impersonated_by => (ended ->> 'admin_id')::uuid,
    impersonation_reason => ended ->> 'reason'
  );
  return true;
end;
$$;

-- Ends the sessions past their expiry, each with ended_by 'expired', and
-- returns them. Run it from a cron job as the service role.
create or replace function "better_supabase"."expire_support_sessions"()
returns setof jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  expired_id uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role expires support sessions' using errcode = '42501', hint = 'SUPPORT_FORBIDDEN';
  end if;
  for expired_id in
    select s."id" from "better_supabase"."support_sessions" s
    where s."ended_at" is null and s."expires_at" <= now()
    order by s."expires_at"
    for update skip locked
  loop
    if "better_supabase"."end_support_session"(expired_id, 'expired') then
      return next (select jsonb_build_object(
    'id', s."id",
    'admin_id', s."admin_id",
    'target_user_id', s."target_user_id",
    'reason', s."reason",
    'tenant', s."organization_id",
    'read_only', s."read_only",
    'started_at', s."started_at",
    'expires_at', s."expires_at",
    'ended_at', s."ended_at",
    'ended_by', s."ended_by",
    'metadata', s."metadata"
  ) from "better_supabase"."support_sessions" s where s."id" = expired_id);
    end if;
  end loop;
end;
$$;

-- Parameters are positional below: in SQL functions a column name wins over a
-- parameter of the same name.
-- The admin's session while it is active, or null. Read on every request
-- that carries the support cookie. Called as the admin, it also checks that
-- the admin may still start sessions.
create or replace function "better_supabase"."active_support_session"(
  session_id uuid,
  admin_id uuid default null
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', s."id",
    'admin_id', s."admin_id",
    'target_user_id', s."target_user_id",
    'reason', s."reason",
    'tenant', s."organization_id",
    'read_only', s."read_only",
    'started_at', s."started_at",
    'expires_at', s."expires_at",
    'ended_at', s."ended_at",
    'ended_by', s."ended_by",
    'metadata', s."metadata"
  )
  from "better_supabase"."support_sessions" s
  where s."id" = $1
    and s."ended_at" is null
    and s."expires_at" > now()
    and case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then s."admin_id" = $2
      else s."admin_id" = auth.uid() and "better_supabase"."is_platform"('support.start')
    end
$$;

-- Sessions, newest first, for platform staff with the view permission.
create or replace function "better_supabase"."list_support_sessions"(
  admin_id uuid default null,
  target uuid default null,
  active boolean default null,
  max_rows integer default 50
)
returns setof jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', s."id",
    'admin_id', s."admin_id",
    'target_user_id', s."target_user_id",
    'reason', s."reason",
    'tenant', s."organization_id",
    'read_only', s."read_only",
    'started_at', s."started_at",
    'expires_at', s."expires_at",
    'ended_at', s."ended_at",
    'ended_by', s."ended_by",
    'metadata', s."metadata"
  )
  from "better_supabase"."support_sessions" s
  where (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or "better_supabase"."is_platform"('support.read'))
    and ($1 is null or s."admin_id" = $1)
    and ($2 is null or s."target_user_id" = $2)
    and ($3 is null
      or $3 = (s."ended_at" is null and s."expires_at" > now()))
  order by s."started_at" desc
  limit $4
$$;

create or replace function "better_supabase"."support_target_claims"(target uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  base jsonb;
begin
  select jsonb_build_object(
    'user_id', u.id,
    'authentication_method', 'support',
    'claims', jsonb_strip_nulls(jsonb_build_object(
      'sub', u.id::text,
      'aud', 'authenticated',
      'role', coalesce(nullif(u.role, ''), 'authenticated'),
      'email', u.email,
      'phone', nullif(u.phone, ''),
      'app_metadata', coalesce(u.raw_app_meta_data, '{}'),
      'user_metadata', coalesce(u.raw_user_meta_data, '{}'),
      'is_anonymous', u.is_anonymous,
      'aal', 'aal1',
      'amr', '[]'::jsonb,
      'session_id', gen_random_uuid()
    ))
  ) into base
  from auth.users u where u.id = target;
  if base is null then
    raise exception 'No user %', target using errcode = 'P0002', hint = 'SUPPORT_TARGET_MISSING';
  end if;
  return base -> 'claims';
end;
$$;

revoke execute on function "better_supabase"."start_support_session"(uuid, text, interval, boolean, jsonb, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."start_support_session"(uuid, text, interval, boolean, jsonb, uuid, uuid) to authenticated, service_role;
revoke execute on function "better_supabase"."end_support_session"(uuid, text) from public, anon;
grant execute on function "better_supabase"."end_support_session"(uuid, text) to authenticated, service_role;
revoke execute on function "better_supabase"."active_support_session"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."active_support_session"(uuid, uuid) to authenticated, service_role;
revoke execute on function "better_supabase"."list_support_sessions"(uuid, uuid, boolean, integer) from public, anon;
grant execute on function "better_supabase"."list_support_sessions"(uuid, uuid, boolean, integer) to authenticated, service_role;
revoke execute on function "better_supabase"."support_target_claims"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."support_target_claims"(uuid) to service_role;
revoke execute on function "better_supabase"."expire_support_sessions"() from public, anon, authenticated;
grant execute on function "better_supabase"."expire_support_sessions"() to service_role;

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

-- ==== adopt: data supabase/better-supabase-data/900_better_supabase_20_support_sessions.sql
-- better-supabase module: support-sessions
-- @bs-module-data support-sessions
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('support-sessions', 1, 'adopt')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
