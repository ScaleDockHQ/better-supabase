-- ==== alone: schema supabase/schemas/900_better_supabase_078_access_requests.sql
-- better-supabase module: access-requests
-- @bsb-block access-requests@1 managed
-- @bsb-hash sha256:2ee38667acb96fe884bb80f728955de4e586e27982bb727d56e697fac2bb1b45
-- Members ask for a role, for a set time if they like. The request goes through approvals; the final approval grants the role, and the grant ends early on request or when it expires.
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
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."access_requests";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."access_requests";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."access_requests";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."access_requests";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."access_requests";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."access_requests" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null,
  "role" text not null check (length("role") between 1 and 200),
  "previous_role" text,
  "reason" text check ("reason" is null or length("reason") <= 2000),
  "duration" interval check ("duration" is null or "duration" > interval '0'),
  "approval_id" uuid references "better_supabase"."approval_requests" ("id") on delete cascade,
  "granted_at" timestamptz,
  "expires_at" timestamptz,
  "ended_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create index if not exists "access_requests_tenant_idx" on "better_supabase"."access_requests" ("tenant_id", "created_at" desc);
create index if not exists "access_requests_approval_idx" on "better_supabase"."access_requests" ("approval_id") where "approval_id" is not null;
create index if not exists "access_requests_expiry_idx" on "better_supabase"."access_requests" ("expires_at") where "granted_at" is not null and "ended_at" is null;
alter table "better_supabase"."access_requests" enable row level security;
revoke all on "better_supabase"."access_requests" from public, anon, authenticated;
grant select on "better_supabase"."access_requests" to authenticated;
grant all on "better_supabase"."access_requests" to service_role;
drop policy if exists access_requests_read on "better_supabase"."access_requests";
create policy access_requests_read on "better_supabase"."access_requests"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('access_requests.read')) or "user_id" = (select auth.uid()));

-- Asks for a role in an organization. Approvers come from options.policy;
-- the final approval calls grant_access_request.
drop function if exists "better_supabase"."request_access"(uuid, text, text, interval, jsonb);
create or replace function "better_supabase"."request_access"(tenant uuid, role text, reason text default null, duration interval default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_current text;
  v_duration interval;
  v_row "better_supabase"."access_requests"%rowtype;
  v_approval jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to request access' using errcode = '42501', hint = 'ACCESS_SIGN_IN';
  end if;
  select m."role" into v_current from "better_supabase"."memberships" m
  where m."organization_id" = request_access.tenant and m."user_id" = v_me;
  if not found then
    raise exception 'only members can request a role' using errcode = '42501', hint = 'ACCESS_REQUEST_FORBIDDEN';
  elsif not coalesce(better_supabase.can('tenant', request_access.tenant, 'access_requests.create'), false) then
    raise exception 'not allowed to request a role here' using errcode = '42501', hint = 'ACCESS_REQUEST_FORBIDDEN';
  end if;
  if not (request_access.role = any (array['admin', 'member', 'viewer']::text[])) then
    raise exception 'this role can''t be requested' using errcode = '22023', hint = 'ACCESS_ROLE_INVALID';
  end if;
  if v_current = request_access.role then
    raise exception 'you already hold this role' using errcode = '22023', hint = 'ACCESS_ROLE_HELD';
  end if;
  if v_current = 'owner' then
    raise exception 'an owner can''t request another role' using errcode = '22023', hint = 'ACCESS_ROLE_INVALID';
  end if;
  v_duration := request_access.duration;
  if v_duration is not null and v_duration <= interval '0' then
    raise exception 'duration must be positive' using errcode = '22023', hint = 'ACCESS_DURATION_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('access_request:' || request_access.tenant::text || ':' || v_me::text, 0));
  if exists (
    select 1 from "better_supabase"."access_requests" r join "better_supabase"."approval_requests" x on x."id" = r."approval_id"
    where r."tenant_id" = request_access.tenant and r."user_id" = v_me and x."status" = 'pending'
  ) then
    raise exception 'you already have a pending access request here' using errcode = '23505', hint = 'ACCESS_REQUEST_PENDING';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_access_request"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using request_access.tenant, request_access.role;
    end if;
  end;
  insert into "better_supabase"."access_requests" ("tenant_id", "user_id", "role", "reason", "duration")
  values (request_access.tenant, v_me, request_access.role, request_access.reason, v_duration)
  returning * into v_row;
  v_approval := "better_supabase"."open_approval"(
    request_access.tenant, 'access_request', v_row."id"::text, 'grant',
    '{"steps":[{"approvers":{"permission":"members.update_role"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb, request_access.reason,
    jsonb_build_object('role', request_access.role, 'userId', v_me, 'duration', v_duration::text)
  );
  update "better_supabase"."access_requests" r set "approval_id" = (v_approval ->> 'id')::uuid
  where r."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_access_request"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'role', v_row."role", 'previousRole', v_row."previous_role", 'reason', v_row."reason", 'duration', v_row."duration"::text, 'status', 'pending', 'approvalId', v_row."approval_id", 'grantedAt', v_row."granted_at", 'expiresAt', v_row."expires_at", 'endedAt', v_row."ended_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."request_access"(uuid, text, text, interval) from public, anon;
grant execute on function "better_supabase"."request_access"(uuid, text, text, interval) to authenticated, service_role;

-- Grants the role once the approval is final. Approvals calls it; it
-- isn't granted to anyone.
create or replace function "better_supabase"."grant_access_request"(request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."access_requests"%rowtype;
  v_previous text;
begin
  select * into v_row from "better_supabase"."access_requests" r where r."id" = grant_access_request.request_id for update;
  if not found or v_row."granted_at" is not null then
    return;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_access_grant"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  select m."role" into v_previous from "better_supabase"."memberships" m
  where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
  for update;
  if found then
    update "better_supabase"."memberships" set "role" = v_row."role"
    where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
  else
    insert into "better_supabase"."memberships" ("organization_id", "user_id", "role")
    values (v_row."tenant_id", v_row."user_id", v_row."role");
  end if;
  update "better_supabase"."access_requests" r
  set "previous_role" = v_previous,
      "granted_at" = now(),
      "expires_at" = case when v_row."duration" is null then null else now() + v_row."duration" end
  where r."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_access_grant"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
end;
$$;
revoke execute on function "better_supabase"."grant_access_request"(uuid) from public, anon, authenticated;

-- Ends a granted role early: a manager, or the holder giving it up.
create or replace function "better_supabase"."end_access"(request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
declare
  v_row "better_supabase"."access_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."access_requests" r where r."id" = end_access.request_id for update;
  if not found then
    raise exception 'access request not found' using errcode = 'P0002', hint = 'ACCESS_REQUEST_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."user_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'access_requests.manage'), false)) then
    raise exception 'not allowed to end this access' using errcode = '42501', hint = 'ACCESS_REQUEST_FORBIDDEN';
  end if;
  if v_row."granted_at" is null or v_row."ended_at" is not null then
    raise exception 'this access isn''t active' using errcode = '22023', hint = 'ACCESS_NOT_GRANTED';
  end if;
  -- Only a role that is still the granted one goes back; a later change wins.
  if exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
      and m."role" = v_row."role"
  ) then
    if v_row."previous_role" is null then
      delete from "better_supabase"."memberships" where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
    else
      update "better_supabase"."memberships" set "role" = v_row."previous_role"
      where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
    end if;
  end if;
  update "better_supabase"."access_requests" r set "ended_at" = now() where r."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'role', v_row."role", 'previousRole', v_row."previous_role", 'reason', v_row."reason", 'duration', v_row."duration"::text, 'status', 'ended', 'approvalId', v_row."approval_id", 'grantedAt', v_row."granted_at", 'expiresAt', v_row."expires_at", 'endedAt', v_row."ended_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."end_access"(uuid) from public, anon;
grant execute on function "better_supabase"."end_access"(uuid) to authenticated, service_role;

-- Ends grants past their expiry. Schedule it with pg_cron or the jobs drain.
create or replace function "better_supabase"."expire_access_grants"(max_grants integer default 200)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."access_requests"%rowtype;
  v_count integer := 0;
begin
  for v_row in
    select * from "better_supabase"."access_requests" r
    where r."granted_at" is not null and r."ended_at" is null and r."expires_at" <= now()
    order by r."expires_at"
    limit greatest(coalesce(expire_access_grants.max_grants, 200), 1)
    for update skip locked
  loop
  -- Only a role that is still the granted one goes back; a later change wins.
  if exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
      and m."role" = v_row."role"
  ) then
    if v_row."previous_role" is null then
      delete from "better_supabase"."memberships" where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
    else
      update "better_supabase"."memberships" set "role" = v_row."previous_role"
      where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
    end if;
  end if;
    update "better_supabase"."access_requests" r set "ended_at" = now() where r."id" = v_row."id" returning * into v_row;
    null;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."expire_access_grants"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."expire_access_grants"(integer) to service_role;

create or replace function "better_supabase"."get_access_request"(request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
declare
  v_row "better_supabase"."access_requests"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  select * into v_row from "better_supabase"."access_requests" r where r."id" = get_access_request.request_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."user_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'access_requests.read'), false)) then
    raise exception 'access request not found' using errcode = 'P0002', hint = 'ACCESS_REQUEST_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_row."approval_id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'role', v_row."role", 'previousRole', v_row."previous_role", 'reason', v_row."reason", 'duration', v_row."duration"::text, 'status', case when v_row."ended_at" is not null then 'ended' when v_row."granted_at" is not null then 'granted' else coalesce(v_approval."status", 'pending') end, 'approvalId', v_row."approval_id", 'grantedAt', v_row."granted_at", 'expiresAt', v_row."expires_at", 'endedAt', v_row."ended_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."get_access_request"(uuid) from public, anon;
grant execute on function "better_supabase"."get_access_request"(uuid) to authenticated, service_role;

-- Newest first. Readers of the organization see every request; others see
-- their own.
create or replace function "better_supabase"."list_access_requests"(tenant uuid, status text default null, mine boolean default false, page_size integer default null, before timestamptz default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
  select coalesce(jsonb_agg(item order by created desc), '[]'::jsonb)
  from (
    select jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'userId', r."user_id", 'role', r."role", 'previousRole', r."previous_role", 'reason', r."reason", 'duration', r."duration"::text, 'status', case when r."ended_at" is not null then 'ended' when r."granted_at" is not null then 'granted' else coalesce(x."status", 'pending') end, 'approvalId', r."approval_id", 'grantedAt', r."granted_at", 'expiresAt', r."expires_at", 'endedAt', r."ended_at", 'createdAt', r."created_at") as item, r."created_at" as created
    from "better_supabase"."access_requests" r
    left join "better_supabase"."approval_requests" x on x."id" = r."approval_id"
    where r."tenant_id" = list_access_requests.tenant
      and (r."user_id" = auth.uid() or (not list_access_requests.mine and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_access_requests.tenant, 'access_requests.read'), false))))
      and (list_access_requests.status is null or case when r."ended_at" is not null then 'ended' when r."granted_at" is not null then 'granted' else coalesce(x."status", 'pending') end = list_access_requests.status)
      and (list_access_requests.before is null or r."created_at" < list_access_requests.before)
    order by r."created_at" desc
    limit least(greatest(coalesce(list_access_requests.page_size, 50), 1), 200)
  ) items
$$;
revoke execute on function "better_supabase"."list_access_requests"(uuid, text, boolean, integer, timestamptz) from public, anon;
grant execute on function "better_supabase"."list_access_requests"(uuid, text, boolean, integer, timestamptz) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."access_requests";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."access_requests";
create policy bsb_tenant_scope_select on "better_supabase"."access_requests" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('access_requests.read')) or "user_id" = (select auth.uid()))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."access_requests";
create policy bsb_tenant_scope_insert on "better_supabase"."access_requests" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."access_requests";
create policy bsb_tenant_scope_update on "better_supabase"."access_requests" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."access_requests";
create policy bsb_tenant_scope_delete on "better_supabase"."access_requests" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_078_access_requests.sql
-- better-supabase module: access-requests
-- @bsb-block-data access-requests
-- @bsb-hash sha256:5ecfb15306bd8d51b0820b8afc96355b2183538887699d447a1077c7e0e498cf
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('access-requests', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_078_access_requests.sql
-- better-supabase module: access-requests
-- @bsb-block access-requests@1 managed
-- @bsb-hash sha256:58b7af641dfcbc23d53cf78720595f40acb66ed495e76d5fc8ea76a26b006b5c
-- Members ask for a role, for a set time if they like. The request goes through approvals; the final approval grants the role, and the grant ends early on request or when it expires.
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
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."access_requests";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."access_requests";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."access_requests";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."access_requests";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."access_requests";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."access_requests" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null,
  "role" text not null check (length("role") between 1 and 200),
  "previous_role" text,
  "reason" text check ("reason" is null or length("reason") <= 2000),
  "duration" interval check ("duration" is null or "duration" > interval '0'),
  "approval_id" uuid references "better_supabase"."approval_requests" ("id") on delete cascade,
  "granted_at" timestamptz,
  "expires_at" timestamptz,
  "ended_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create index if not exists "access_requests_tenant_idx" on "better_supabase"."access_requests" ("tenant_id", "created_at" desc);
create index if not exists "access_requests_approval_idx" on "better_supabase"."access_requests" ("approval_id") where "approval_id" is not null;
create index if not exists "access_requests_expiry_idx" on "better_supabase"."access_requests" ("expires_at") where "granted_at" is not null and "ended_at" is null;
alter table "better_supabase"."access_requests" enable row level security;
revoke all on "better_supabase"."access_requests" from public, anon, authenticated;
grant select on "better_supabase"."access_requests" to authenticated;
grant all on "better_supabase"."access_requests" to service_role;
drop policy if exists access_requests_read on "better_supabase"."access_requests";
create policy access_requests_read on "better_supabase"."access_requests"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('access_requests.read')) or "user_id" = (select auth.uid()));

-- Asks for a role in an organization. Approvers come from options.policy;
-- the final approval calls grant_access_request.
drop function if exists "better_supabase"."request_access"(uuid, text, text, interval, jsonb);
create or replace function "better_supabase"."request_access"(tenant uuid, role text, reason text default null, duration interval default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_current text;
  v_duration interval;
  v_row "better_supabase"."access_requests"%rowtype;
  v_approval jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to request access' using errcode = '42501', hint = 'ACCESS_SIGN_IN';
  end if;
  select m."role" into v_current from "better_supabase"."memberships" m
  where m."organization_id" = request_access.tenant and m."user_id" = v_me;
  if not found then
    raise exception 'only members can request a role' using errcode = '42501', hint = 'ACCESS_REQUEST_FORBIDDEN';
  elsif not coalesce(better_supabase.can('tenant', request_access.tenant, 'access_requests.create'), false) then
    raise exception 'not allowed to request a role here' using errcode = '42501', hint = 'ACCESS_REQUEST_FORBIDDEN';
  end if;
  if not (request_access.role = any (array['admin', 'member', 'viewer']::text[])) then
    raise exception 'this role can''t be requested' using errcode = '22023', hint = 'ACCESS_ROLE_INVALID';
  end if;
  if v_current = request_access.role then
    raise exception 'you already hold this role' using errcode = '22023', hint = 'ACCESS_ROLE_HELD';
  end if;
  if v_current = 'owner' then
    raise exception 'an owner can''t request another role' using errcode = '22023', hint = 'ACCESS_ROLE_INVALID';
  end if;
  v_duration := request_access.duration;
  if v_duration is not null and v_duration <= interval '0' then
    raise exception 'duration must be positive' using errcode = '22023', hint = 'ACCESS_DURATION_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('access_request:' || request_access.tenant::text || ':' || v_me::text, 0));
  if exists (
    select 1 from "better_supabase"."access_requests" r join "better_supabase"."approval_requests" x on x."id" = r."approval_id"
    where r."tenant_id" = request_access.tenant and r."user_id" = v_me and x."status" = 'pending'
  ) then
    raise exception 'you already have a pending access request here' using errcode = '23505', hint = 'ACCESS_REQUEST_PENDING';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_access_request"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using request_access.tenant, request_access.role;
    end if;
  end;
  insert into "better_supabase"."access_requests" ("tenant_id", "user_id", "role", "reason", "duration")
  values (request_access.tenant, v_me, request_access.role, request_access.reason, v_duration)
  returning * into v_row;
  v_approval := "better_supabase"."open_approval"(
    request_access.tenant, 'access_request', v_row."id"::text, 'grant',
    '{"steps":[{"approvers":{"permission":"members.update_role"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb, request_access.reason,
    jsonb_build_object('role', request_access.role, 'userId', v_me, 'duration', v_duration::text)
  );
  update "better_supabase"."access_requests" r set "approval_id" = (v_approval ->> 'id')::uuid
  where r."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('access.requested', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at"), 'access-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/access-requests');
  perform better_supabase.audit_event(
    event_type => 'access.requested',
    category => 'membership',
    target_type => 'user',
    record_id => v_row."user_id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_access_request"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'role', v_row."role", 'previousRole', v_row."previous_role", 'reason', v_row."reason", 'duration', v_row."duration"::text, 'status', 'pending', 'approvalId', v_row."approval_id", 'grantedAt', v_row."granted_at", 'expiresAt', v_row."expires_at", 'endedAt', v_row."ended_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."request_access"(uuid, text, text, interval) from public, anon;
grant execute on function "better_supabase"."request_access"(uuid, text, text, interval) to authenticated, service_role;

-- Grants the role once the approval is final. Approvals calls it; it
-- isn't granted to anyone.
create or replace function "better_supabase"."grant_access_request"(request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."access_requests"%rowtype;
  v_previous text;
begin
  select * into v_row from "better_supabase"."access_requests" r where r."id" = grant_access_request.request_id for update;
  if not found or v_row."granted_at" is not null then
    return;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_access_grant"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  select m."role" into v_previous from "better_supabase"."memberships" m
  where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
  for update;
  if found then
    update "better_supabase"."memberships" set "role" = v_row."role"
    where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
  else
    insert into "better_supabase"."memberships" ("organization_id", "user_id", "role")
    values (v_row."tenant_id", v_row."user_id", v_row."role");
  end if;
  update "better_supabase"."access_requests" r
  set "previous_role" = v_previous,
      "granted_at" = now(),
      "expires_at" = case when v_row."duration" is null then null else now() + v_row."duration" end
  where r."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('access.request_approved', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at"), 'access-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/access-requests');
  perform better_supabase.audit_event(
    event_type => 'access.request_approved',
    category => 'membership',
    target_type => 'user',
    record_id => v_row."user_id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_access_grant"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
end;
$$;
revoke execute on function "better_supabase"."grant_access_request"(uuid) from public, anon, authenticated;

-- Ends a granted role early: a manager, or the holder giving it up.
create or replace function "better_supabase"."end_access"(request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
declare
  v_row "better_supabase"."access_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."access_requests" r where r."id" = end_access.request_id for update;
  if not found then
    raise exception 'access request not found' using errcode = 'P0002', hint = 'ACCESS_REQUEST_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."user_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'access_requests.manage'), false)) then
    raise exception 'not allowed to end this access' using errcode = '42501', hint = 'ACCESS_REQUEST_FORBIDDEN';
  end if;
  if v_row."granted_at" is null or v_row."ended_at" is not null then
    raise exception 'this access isn''t active' using errcode = '22023', hint = 'ACCESS_NOT_GRANTED';
  end if;
  -- Only a role that is still the granted one goes back; a later change wins.
  if exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
      and m."role" = v_row."role"
  ) then
    if v_row."previous_role" is null then
      delete from "better_supabase"."memberships" where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
    else
      update "better_supabase"."memberships" set "role" = v_row."previous_role"
      where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
    end if;
  end if;
  update "better_supabase"."access_requests" r set "ended_at" = now() where r."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('access.ended', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'reason', 'revoked'), 'access-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/access-requests');
  perform better_supabase.audit_event(
    event_type => 'access.ended',
    category => 'membership',
    target_type => 'user',
    record_id => v_row."user_id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'reason', 'revoked')
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'role', v_row."role", 'previousRole', v_row."previous_role", 'reason', v_row."reason", 'duration', v_row."duration"::text, 'status', 'ended', 'approvalId', v_row."approval_id", 'grantedAt', v_row."granted_at", 'expiresAt', v_row."expires_at", 'endedAt', v_row."ended_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."end_access"(uuid) from public, anon;
grant execute on function "better_supabase"."end_access"(uuid) to authenticated, service_role;

-- Ends grants past their expiry. Schedule it with pg_cron or the jobs drain.
create or replace function "better_supabase"."expire_access_grants"(max_grants integer default 200)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."access_requests"%rowtype;
  v_count integer := 0;
begin
  for v_row in
    select * from "better_supabase"."access_requests" r
    where r."granted_at" is not null and r."ended_at" is null and r."expires_at" <= now()
    order by r."expires_at"
    limit greatest(coalesce(expire_access_grants.max_grants, 200), 1)
    for update skip locked
  loop
  -- Only a role that is still the granted one goes back; a later change wins.
  if exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
      and m."role" = v_row."role"
  ) then
    if v_row."previous_role" is null then
      delete from "better_supabase"."memberships" where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
    else
      update "better_supabase"."memberships" set "role" = v_row."previous_role"
      where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
    end if;
  end if;
    update "better_supabase"."access_requests" r set "ended_at" = now() where r."id" = v_row."id" returning * into v_row;
    perform "better_supabase".emit_event('access.ended', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'reason', 'expired'), 'access-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/access-requests');
  perform better_supabase.audit_event(
    event_type => 'access.ended',
    category => 'membership',
    target_type => 'user',
    record_id => v_row."user_id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'reason', 'expired')
  );
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."expire_access_grants"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."expire_access_grants"(integer) to service_role;

create or replace function "better_supabase"."get_access_request"(request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
declare
  v_row "better_supabase"."access_requests"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  select * into v_row from "better_supabase"."access_requests" r where r."id" = get_access_request.request_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."user_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'access_requests.read'), false)) then
    raise exception 'access request not found' using errcode = 'P0002', hint = 'ACCESS_REQUEST_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_row."approval_id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'role', v_row."role", 'previousRole', v_row."previous_role", 'reason', v_row."reason", 'duration', v_row."duration"::text, 'status', case when v_row."ended_at" is not null then 'ended' when v_row."granted_at" is not null then 'granted' else coalesce(v_approval."status", 'pending') end, 'approvalId', v_row."approval_id", 'grantedAt', v_row."granted_at", 'expiresAt', v_row."expires_at", 'endedAt', v_row."ended_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."get_access_request"(uuid) from public, anon;
grant execute on function "better_supabase"."get_access_request"(uuid) to authenticated, service_role;

-- Newest first. Readers of the organization see every request; others see
-- their own.
create or replace function "better_supabase"."list_access_requests"(tenant uuid, status text default null, mine boolean default false, page_size integer default null, before timestamptz default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
  select coalesce(jsonb_agg(item order by created desc), '[]'::jsonb)
  from (
    select jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'userId', r."user_id", 'role', r."role", 'previousRole', r."previous_role", 'reason', r."reason", 'duration', r."duration"::text, 'status', case when r."ended_at" is not null then 'ended' when r."granted_at" is not null then 'granted' else coalesce(x."status", 'pending') end, 'approvalId', r."approval_id", 'grantedAt', r."granted_at", 'expiresAt', r."expires_at", 'endedAt', r."ended_at", 'createdAt', r."created_at") as item, r."created_at" as created
    from "better_supabase"."access_requests" r
    left join "better_supabase"."approval_requests" x on x."id" = r."approval_id"
    where r."tenant_id" = list_access_requests.tenant
      and (r."user_id" = auth.uid() or (not list_access_requests.mine and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_access_requests.tenant, 'access_requests.read'), false))))
      and (list_access_requests.status is null or case when r."ended_at" is not null then 'ended' when r."granted_at" is not null then 'granted' else coalesce(x."status", 'pending') end = list_access_requests.status)
      and (list_access_requests.before is null or r."created_at" < list_access_requests.before)
    order by r."created_at" desc
    limit least(greatest(coalesce(list_access_requests.page_size, 50), 1), 200)
  ) items
$$;
revoke execute on function "better_supabase"."list_access_requests"(uuid, text, boolean, integer, timestamptz) from public, anon;
grant execute on function "better_supabase"."list_access_requests"(uuid, text, boolean, integer, timestamptz) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."access_requests";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."access_requests";
create policy bsb_tenant_scope_select on "better_supabase"."access_requests" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('access_requests.read')) or "user_id" = (select auth.uid()))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."access_requests";
create policy bsb_tenant_scope_insert on "better_supabase"."access_requests" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."access_requests";
create policy bsb_tenant_scope_update on "better_supabase"."access_requests" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."access_requests";
create policy bsb_tenant_scope_delete on "better_supabase"."access_requests" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_078_access_requests.sql
-- better-supabase module: access-requests
-- @bsb-block-data access-requests
-- @bsb-hash sha256:5ecfb15306bd8d51b0820b8afc96355b2183538887699d447a1077c7e0e498cf
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('access-requests', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_078_access_requests.sql
-- better-supabase module: access-requests
-- @bsb-block access-requests@1 managed
-- @bsb-hash sha256:db9c22e78a5821eb4e90cc7147e482d26e05c5ff29a055a4a4fb4c6e8478b42e
-- Members ask for a role, for a set time if they like. The request goes through approvals; the final approval grants the role, and the grant ends early on request or when it expires.
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
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."access_requests";
    drop policy if exists bsb_tenant_scope_select on "app_private"."access_requests";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."access_requests";
    drop policy if exists bsb_tenant_scope_update on "app_private"."access_requests";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."access_requests";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
create table if not exists "app_private"."access_requests" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null,
  "role" text not null check (length("role") between 1 and 200),
  "previous_role" text,
  "reason" text check ("reason" is null or length("reason") <= 2000),
  "duration" interval check ("duration" is null or "duration" > interval '0'),
  "approval_id" uuid references "better_supabase"."approval_requests" ("id") on delete cascade,
  "granted_at" timestamptz,
  "expires_at" timestamptz,
  "ended_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create index if not exists "access_requests_tenant_idx" on "app_private"."access_requests" ("tenant_id", "created_at" desc);
create index if not exists "access_requests_approval_idx" on "app_private"."access_requests" ("approval_id") where "approval_id" is not null;
create index if not exists "access_requests_expiry_idx" on "app_private"."access_requests" ("expires_at") where "granted_at" is not null and "ended_at" is null;
alter table "app_private"."access_requests" enable row level security;
revoke all on "app_private"."access_requests" from public, anon, authenticated;
grant select on "app_private"."access_requests" to authenticated;
grant all on "app_private"."access_requests" to service_role;
drop policy if exists access_requests_read on "app_private"."access_requests";
create policy access_requests_read on "app_private"."access_requests"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('access_requests.read')) or "user_id" = (select auth.uid()));

-- Asks for a role in an organization. Approvers come from options.policy;
-- the final approval calls grant_access_request.
drop function if exists "app_private"."request_access"(uuid, text, text, interval, jsonb);
create or replace function "app_private"."request_access"(tenant uuid, role text, reason text default null, duration interval default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_current text;
  v_duration interval;
  v_row "app_private"."access_requests"%rowtype;
  v_approval jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to request access' using errcode = '42501', hint = 'ACCESS_SIGN_IN';
  end if;
  select m."role" into v_current from "better_supabase"."memberships" m
  where m."organization_id" = request_access.tenant and m."user_id" = v_me;
  if not found then
    raise exception 'only members can request a role' using errcode = '42501', hint = 'ACCESS_REQUEST_FORBIDDEN';
  elsif not coalesce(better_supabase.can('tenant', request_access.tenant, 'access_requests.create'), false) then
    raise exception 'not allowed to request a role here' using errcode = '42501', hint = 'ACCESS_REQUEST_FORBIDDEN';
  end if;
  if not (request_access.role = any (array['admin', 'member', 'viewer']::text[])) then
    raise exception 'this role can''t be requested' using errcode = '22023', hint = 'ACCESS_ROLE_INVALID';
  end if;
  if v_current = request_access.role then
    raise exception 'you already hold this role' using errcode = '22023', hint = 'ACCESS_ROLE_HELD';
  end if;
  if v_current = 'owner' then
    raise exception 'an owner can''t request another role' using errcode = '22023', hint = 'ACCESS_ROLE_INVALID';
  end if;
  v_duration := request_access.duration;
  if v_duration is not null and v_duration <= interval '0' then
    raise exception 'duration must be positive' using errcode = '22023', hint = 'ACCESS_DURATION_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('access_request:' || request_access.tenant::text || ':' || v_me::text, 0));
  if exists (
    select 1 from "app_private"."access_requests" r join "better_supabase"."approval_requests" x on x."id" = r."approval_id"
    where r."tenant_id" = request_access.tenant and r."user_id" = v_me and x."status" = 'pending'
  ) then
    raise exception 'you already have a pending access request here' using errcode = '23505', hint = 'ACCESS_REQUEST_PENDING';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_access_request"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using request_access.tenant, request_access.role;
    end if;
  end;
  insert into "app_private"."access_requests" ("tenant_id", "user_id", "role", "reason", "duration")
  values (request_access.tenant, v_me, request_access.role, request_access.reason, v_duration)
  returning * into v_row;
  v_approval := "better_supabase"."open_approval"(
    request_access.tenant, 'access_request', v_row."id"::text, 'grant',
    '{"steps":[{"approvers":{"permission":"members.update_role"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb, request_access.reason,
    jsonb_build_object('role', request_access.role, 'userId', v_me, 'duration', v_duration::text)
  );
  update "app_private"."access_requests" r set "approval_id" = (v_approval ->> 'id')::uuid
  where r."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_access_request"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'role', v_row."role", 'previousRole', v_row."previous_role", 'reason', v_row."reason", 'duration', v_row."duration"::text, 'status', 'pending', 'approvalId', v_row."approval_id", 'grantedAt', v_row."granted_at", 'expiresAt', v_row."expires_at", 'endedAt', v_row."ended_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "app_private"."request_access"(uuid, text, text, interval) from public, anon;
grant execute on function "app_private"."request_access"(uuid, text, text, interval) to authenticated, service_role;

-- Grants the role once the approval is final. Approvals calls it; it
-- isn't granted to anyone.
create or replace function "app_private"."grant_access_request"(request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."access_requests"%rowtype;
  v_previous text;
begin
  select * into v_row from "app_private"."access_requests" r where r."id" = grant_access_request.request_id for update;
  if not found or v_row."granted_at" is not null then
    return;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_access_grant"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  select m."role" into v_previous from "better_supabase"."memberships" m
  where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
  for update;
  if found then
    update "better_supabase"."memberships" set "role" = v_row."role"
    where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
  else
    insert into "better_supabase"."memberships" ("organization_id", "user_id", "role")
    values (v_row."tenant_id", v_row."user_id", v_row."role");
  end if;
  update "app_private"."access_requests" r
  set "previous_role" = v_previous,
      "granted_at" = now(),
      "expires_at" = case when v_row."duration" is null then null else now() + v_row."duration" end
  where r."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_access_grant"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
end;
$$;
revoke execute on function "app_private"."grant_access_request"(uuid) from public, anon, authenticated;

-- Ends a granted role early: a manager, or the holder giving it up.
create or replace function "app_private"."end_access"(request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
declare
  v_row "app_private"."access_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."access_requests" r where r."id" = end_access.request_id for update;
  if not found then
    raise exception 'access request not found' using errcode = 'P0002', hint = 'ACCESS_REQUEST_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."user_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'access_requests.manage'), false)) then
    raise exception 'not allowed to end this access' using errcode = '42501', hint = 'ACCESS_REQUEST_FORBIDDEN';
  end if;
  if v_row."granted_at" is null or v_row."ended_at" is not null then
    raise exception 'this access isn''t active' using errcode = '22023', hint = 'ACCESS_NOT_GRANTED';
  end if;
  -- Only a role that is still the granted one goes back; a later change wins.
  if exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
      and m."role" = v_row."role"
  ) then
    if v_row."previous_role" is null then
      delete from "better_supabase"."memberships" where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
    else
      update "better_supabase"."memberships" set "role" = v_row."previous_role"
      where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
    end if;
  end if;
  update "app_private"."access_requests" r set "ended_at" = now() where r."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'role', v_row."role", 'previousRole', v_row."previous_role", 'reason', v_row."reason", 'duration', v_row."duration"::text, 'status', 'ended', 'approvalId', v_row."approval_id", 'grantedAt', v_row."granted_at", 'expiresAt', v_row."expires_at", 'endedAt', v_row."ended_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "app_private"."end_access"(uuid) from public, anon;
grant execute on function "app_private"."end_access"(uuid) to authenticated, service_role;

-- Ends grants past their expiry. Schedule it with pg_cron or the jobs drain.
create or replace function "app_private"."expire_access_grants"(max_grants integer default 200)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."access_requests"%rowtype;
  v_count integer := 0;
begin
  for v_row in
    select * from "app_private"."access_requests" r
    where r."granted_at" is not null and r."ended_at" is null and r."expires_at" <= now()
    order by r."expires_at"
    limit greatest(coalesce(expire_access_grants.max_grants, 200), 1)
    for update skip locked
  loop
  -- Only a role that is still the granted one goes back; a later change wins.
  if exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
      and m."role" = v_row."role"
  ) then
    if v_row."previous_role" is null then
      delete from "better_supabase"."memberships" where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
    else
      update "better_supabase"."memberships" set "role" = v_row."previous_role"
      where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
    end if;
  end if;
    update "app_private"."access_requests" r set "ended_at" = now() where r."id" = v_row."id" returning * into v_row;
    null;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "app_private"."expire_access_grants"(integer) from public, anon, authenticated;
grant execute on function "app_private"."expire_access_grants"(integer) to service_role;

create or replace function "app_private"."get_access_request"(request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
declare
  v_row "app_private"."access_requests"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  select * into v_row from "app_private"."access_requests" r where r."id" = get_access_request.request_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."user_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'access_requests.read'), false)) then
    raise exception 'access request not found' using errcode = 'P0002', hint = 'ACCESS_REQUEST_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_row."approval_id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'role', v_row."role", 'previousRole', v_row."previous_role", 'reason', v_row."reason", 'duration', v_row."duration"::text, 'status', case when v_row."ended_at" is not null then 'ended' when v_row."granted_at" is not null then 'granted' else coalesce(v_approval."status", 'pending') end, 'approvalId', v_row."approval_id", 'grantedAt', v_row."granted_at", 'expiresAt', v_row."expires_at", 'endedAt', v_row."ended_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "app_private"."get_access_request"(uuid) from public, anon;
grant execute on function "app_private"."get_access_request"(uuid) to authenticated, service_role;

-- Newest first. Readers of the organization see every request; others see
-- their own.
create or replace function "app_private"."list_access_requests"(tenant uuid, status text default null, mine boolean default false, page_size integer default null, before timestamptz default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
  select coalesce(jsonb_agg(item order by created desc), '[]'::jsonb)
  from (
    select jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'userId', r."user_id", 'role', r."role", 'previousRole', r."previous_role", 'reason', r."reason", 'duration', r."duration"::text, 'status', case when r."ended_at" is not null then 'ended' when r."granted_at" is not null then 'granted' else coalesce(x."status", 'pending') end, 'approvalId', r."approval_id", 'grantedAt', r."granted_at", 'expiresAt', r."expires_at", 'endedAt', r."ended_at", 'createdAt', r."created_at") as item, r."created_at" as created
    from "app_private"."access_requests" r
    left join "better_supabase"."approval_requests" x on x."id" = r."approval_id"
    where r."tenant_id" = list_access_requests.tenant
      and (r."user_id" = auth.uid() or (not list_access_requests.mine and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_access_requests.tenant, 'access_requests.read'), false))))
      and (list_access_requests.status is null or case when r."ended_at" is not null then 'ended' when r."granted_at" is not null then 'granted' else coalesce(x."status", 'pending') end = list_access_requests.status)
      and (list_access_requests.before is null or r."created_at" < list_access_requests.before)
    order by r."created_at" desc
    limit least(greatest(coalesce(list_access_requests.page_size, 50), 1), 200)
  ) items
$$;
revoke execute on function "app_private"."list_access_requests"(uuid, text, boolean, integer, timestamptz) from public, anon;
grant execute on function "app_private"."list_access_requests"(uuid, text, boolean, integer, timestamptz) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "app_private"."access_requests";
drop policy if exists bsb_tenant_scope_select on "app_private"."access_requests";
create policy bsb_tenant_scope_select on "app_private"."access_requests" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('access_requests.read')) or "user_id" = (select auth.uid()))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."access_requests";
create policy bsb_tenant_scope_insert on "app_private"."access_requests" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."access_requests";
create policy bsb_tenant_scope_update on "app_private"."access_requests" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."access_requests";
create policy bsb_tenant_scope_delete on "app_private"."access_requests" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_078_access_requests.sql
-- better-supabase module: access-requests
-- @bsb-block-data access-requests
-- @bsb-hash sha256:5ecfb15306bd8d51b0820b8afc96355b2183538887699d447a1077c7e0e498cf
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('access-requests', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_078_access_requests.sql
-- better-supabase module: access-requests
-- @bsb-block access-requests@1 managed
-- @bsb-hash sha256:0f401a83653780d519a5505a88f7645ce184f9c33179921f00e9078fb470e4b1
-- Members ask for a role, for a set time if they like. The request goes through approvals; the final approval grants the role, and the grant ends early on request or when it expires.
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
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."access_requests";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."access_requests";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."access_requests";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."access_requests";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."access_requests";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."access_requests" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null,
  "role" text not null check (length("role") between 1 and 200),
  "previous_role" text,
  "reason" text check ("reason" is null or length("reason") <= 2000),
  "duration" interval check ("duration" is null or "duration" > interval '0'),
  "approval_id" uuid references "better_supabase"."approval_requests" ("id") on delete cascade,
  "granted_at" timestamptz,
  "expires_at" timestamptz,
  "ended_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create index if not exists "access_requests_tenant_idx" on "better_supabase"."access_requests" ("tenant_id", "created_at" desc);
create index if not exists "access_requests_approval_idx" on "better_supabase"."access_requests" ("approval_id") where "approval_id" is not null;
create index if not exists "access_requests_expiry_idx" on "better_supabase"."access_requests" ("expires_at") where "granted_at" is not null and "ended_at" is null;
alter table "better_supabase"."access_requests" enable row level security;
revoke all on "better_supabase"."access_requests" from public, anon, authenticated;
grant select on "better_supabase"."access_requests" to authenticated;
grant all on "better_supabase"."access_requests" to service_role;
drop policy if exists access_requests_read on "better_supabase"."access_requests";
create policy access_requests_read on "better_supabase"."access_requests"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('access_requests.read')) or "user_id" = (select auth.uid()));

-- Asks for a role in an organization. Approvers come from options.policy;
-- the final approval calls grant_access_request.
drop function if exists "better_supabase"."request_access"(uuid, text, text, interval, jsonb);
create or replace function "better_supabase"."request_access"(tenant uuid, role text, reason text default null, duration interval default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_current text;
  v_duration interval;
  v_row "better_supabase"."access_requests"%rowtype;
  v_approval jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to request access' using errcode = '42501', hint = 'ACCESS_SIGN_IN';
  end if;
  select m."role" into v_current from "better_supabase"."memberships" m
  where m."organization_id" = request_access.tenant and m."user_id" = v_me;
  if not found then
    raise exception 'only members can request a role' using errcode = '42501', hint = 'ACCESS_REQUEST_FORBIDDEN';
  elsif not coalesce(better_supabase.can('tenant', request_access.tenant, 'access_requests.create'), false) then
    raise exception 'not allowed to request a role here' using errcode = '42501', hint = 'ACCESS_REQUEST_FORBIDDEN';
  end if;
  if not (request_access.role = any (array['admin', 'member', 'viewer']::text[])) then
    raise exception 'this role can''t be requested' using errcode = '22023', hint = 'ACCESS_ROLE_INVALID';
  end if;
  if v_current = request_access.role then
    raise exception 'you already hold this role' using errcode = '22023', hint = 'ACCESS_ROLE_HELD';
  end if;
  if v_current = 'owner' then
    raise exception 'an owner can''t request another role' using errcode = '22023', hint = 'ACCESS_ROLE_INVALID';
  end if;
  v_duration := request_access.duration;
  if v_duration is not null and v_duration <= interval '0' then
    raise exception 'duration must be positive' using errcode = '22023', hint = 'ACCESS_DURATION_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('access_request:' || request_access.tenant::text || ':' || v_me::text, 0));
  if exists (
    select 1 from "better_supabase"."access_requests" r join "better_supabase"."approval_requests" x on x."id" = r."approval_id"
    where r."tenant_id" = request_access.tenant and r."user_id" = v_me and x."status" = 'pending'
  ) then
    raise exception 'you already have a pending access request here' using errcode = '23505', hint = 'ACCESS_REQUEST_PENDING';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_access_request"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using request_access.tenant, request_access.role;
    end if;
  end;
  insert into "better_supabase"."access_requests" ("tenant_id", "user_id", "role", "reason", "duration")
  values (request_access.tenant, v_me, request_access.role, request_access.reason, v_duration)
  returning * into v_row;
  v_approval := "better_supabase"."open_approval"(
    request_access.tenant, 'access_request', v_row."id"::text, 'grant',
    '{"steps":[{"approvers":{"permission":"members.update_role"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb, request_access.reason,
    jsonb_build_object('role', request_access.role, 'userId', v_me, 'duration', v_duration::text)
  );
  update "better_supabase"."access_requests" r set "approval_id" = (v_approval ->> 'id')::uuid
  where r."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_access_request"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'role', v_row."role", 'previousRole', v_row."previous_role", 'reason', v_row."reason", 'duration', v_row."duration"::text, 'status', 'pending', 'approvalId', v_row."approval_id", 'grantedAt', v_row."granted_at", 'expiresAt', v_row."expires_at", 'endedAt', v_row."ended_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."request_access"(uuid, text, text, interval) from public, anon;
grant execute on function "better_supabase"."request_access"(uuid, text, text, interval) to authenticated, service_role;

-- Grants the role once the approval is final. Approvals calls it; it
-- isn't granted to anyone.
create or replace function "better_supabase"."grant_access_request"(request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."access_requests"%rowtype;
  v_previous text;
begin
  select * into v_row from "better_supabase"."access_requests" r where r."id" = grant_access_request.request_id for update;
  if not found or v_row."granted_at" is not null then
    return;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_access_grant"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  select m."role" into v_previous from "better_supabase"."memberships" m
  where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
  for update;
  if found then
    update "better_supabase"."memberships" set "role" = v_row."role"
    where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
  else
    insert into "better_supabase"."memberships" ("organization_id", "user_id", "role")
    values (v_row."tenant_id", v_row."user_id", v_row."role");
  end if;
  update "better_supabase"."access_requests" r
  set "previous_role" = v_previous,
      "granted_at" = now(),
      "expires_at" = case when v_row."duration" is null then null else now() + v_row."duration" end
  where r."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_access_grant"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
end;
$$;
revoke execute on function "better_supabase"."grant_access_request"(uuid) from public, anon, authenticated;

-- Ends a granted role early: a manager, or the holder giving it up.
create or replace function "better_supabase"."end_access"(request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
declare
  v_row "better_supabase"."access_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."access_requests" r where r."id" = end_access.request_id for update;
  if not found then
    raise exception 'access request not found' using errcode = 'P0002', hint = 'ACCESS_REQUEST_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."user_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'access_requests.manage'), false)) then
    raise exception 'not allowed to end this access' using errcode = '42501', hint = 'ACCESS_REQUEST_FORBIDDEN';
  end if;
  if v_row."granted_at" is null or v_row."ended_at" is not null then
    raise exception 'this access isn''t active' using errcode = '22023', hint = 'ACCESS_NOT_GRANTED';
  end if;
  -- Only a role that is still the granted one goes back; a later change wins.
  if exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
      and m."role" = v_row."role"
  ) then
    if v_row."previous_role" is null then
      delete from "better_supabase"."memberships" where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
    else
      update "better_supabase"."memberships" set "role" = v_row."previous_role"
      where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
    end if;
  end if;
  update "better_supabase"."access_requests" r set "ended_at" = now() where r."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'role', v_row."role", 'previousRole', v_row."previous_role", 'reason', v_row."reason", 'duration', v_row."duration"::text, 'status', 'ended', 'approvalId', v_row."approval_id", 'grantedAt', v_row."granted_at", 'expiresAt', v_row."expires_at", 'endedAt', v_row."ended_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."end_access"(uuid) from public, anon;
grant execute on function "better_supabase"."end_access"(uuid) to authenticated, service_role;

-- Ends grants past their expiry. Schedule it with pg_cron or the jobs drain.
create or replace function "better_supabase"."expire_access_grants"(max_grants integer default 200)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."access_requests"%rowtype;
  v_count integer := 0;
begin
  for v_row in
    select * from "better_supabase"."access_requests" r
    where r."granted_at" is not null and r."ended_at" is null and r."expires_at" <= now()
    order by r."expires_at"
    limit greatest(coalesce(expire_access_grants.max_grants, 200), 1)
    for update skip locked
  loop
  -- Only a role that is still the granted one goes back; a later change wins.
  if exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
      and m."role" = v_row."role"
  ) then
    if v_row."previous_role" is null then
      delete from "better_supabase"."memberships" where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
    else
      update "better_supabase"."memberships" set "role" = v_row."previous_role"
      where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
    end if;
  end if;
    update "better_supabase"."access_requests" r set "ended_at" = now() where r."id" = v_row."id" returning * into v_row;
    null;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."expire_access_grants"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."expire_access_grants"(integer) to service_role;

create or replace function "better_supabase"."get_access_request"(request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
declare
  v_row "better_supabase"."access_requests"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  select * into v_row from "better_supabase"."access_requests" r where r."id" = get_access_request.request_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."user_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'access_requests.read'), false)) then
    raise exception 'access request not found' using errcode = 'P0002', hint = 'ACCESS_REQUEST_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_row."approval_id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'role', v_row."role", 'previousRole', v_row."previous_role", 'reason', v_row."reason", 'duration', v_row."duration"::text, 'status', case when v_row."ended_at" is not null then 'ended' when v_row."granted_at" is not null then 'granted' else coalesce(v_approval."status", 'pending') end, 'approvalId', v_row."approval_id", 'grantedAt', v_row."granted_at", 'expiresAt', v_row."expires_at", 'endedAt', v_row."ended_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."get_access_request"(uuid) from public, anon;
grant execute on function "better_supabase"."get_access_request"(uuid) to authenticated, service_role;

-- Newest first. Readers of the organization see every request; others see
-- their own.
create or replace function "better_supabase"."list_access_requests"(tenant uuid, status text default null, mine boolean default false, page_size integer default null, before timestamptz default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
  select coalesce(jsonb_agg(item order by created desc), '[]'::jsonb)
  from (
    select jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'userId', r."user_id", 'role', r."role", 'previousRole', r."previous_role", 'reason', r."reason", 'duration', r."duration"::text, 'status', case when r."ended_at" is not null then 'ended' when r."granted_at" is not null then 'granted' else coalesce(x."status", 'pending') end, 'approvalId', r."approval_id", 'grantedAt', r."granted_at", 'expiresAt', r."expires_at", 'endedAt', r."ended_at", 'createdAt', r."created_at") as item, r."created_at" as created
    from "better_supabase"."access_requests" r
    left join "better_supabase"."approval_requests" x on x."id" = r."approval_id"
    where r."tenant_id" = list_access_requests.tenant
      and (r."user_id" = auth.uid() or (not list_access_requests.mine and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_access_requests.tenant, 'access_requests.read'), false))))
      and (list_access_requests.status is null or case when r."ended_at" is not null then 'ended' when r."granted_at" is not null then 'granted' else coalesce(x."status", 'pending') end = list_access_requests.status)
      and (list_access_requests.before is null or r."created_at" < list_access_requests.before)
    order by r."created_at" desc
    limit least(greatest(coalesce(list_access_requests.page_size, 50), 1), 200)
  ) items
$$;
revoke execute on function "better_supabase"."list_access_requests"(uuid, text, boolean, integer, timestamptz) from public, anon;
grant execute on function "better_supabase"."list_access_requests"(uuid, text, boolean, integer, timestamptz) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."access_requests";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."access_requests";
create policy bsb_tenant_scope_select on "better_supabase"."access_requests" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('access_requests.read')) or "user_id" = (select auth.uid()))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."access_requests";
create policy bsb_tenant_scope_insert on "better_supabase"."access_requests" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."access_requests";
create policy bsb_tenant_scope_update on "better_supabase"."access_requests" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."access_requests";
create policy bsb_tenant_scope_delete on "better_supabase"."access_requests" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.access-requests.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."request_access"(uuid, text, text, interval, jsonb);

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

create or replace function "api"."request_access"(tenant uuid, role text, reason text default null, duration interval default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."request_access"($1, $2, $3, $4) $$;
revoke execute on function "api"."request_access"(uuid, text, text, interval) from public, anon;
grant execute on function "api"."request_access"(uuid, text, text, interval) to authenticated, service_role;

create or replace function "api"."end_access"(request_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."end_access"($1) $$;
revoke execute on function "api"."end_access"(uuid) from public, anon;
grant execute on function "api"."end_access"(uuid) to authenticated, service_role;

create or replace function "api"."expire_access_grants"(max_grants integer default 200)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."expire_access_grants"($1) $$;
revoke execute on function "api"."expire_access_grants"(integer) from public, anon, authenticated;
grant execute on function "api"."expire_access_grants"(integer) to service_role;

create or replace function "api"."get_access_request"(request_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_access_request"($1) $$;
revoke execute on function "api"."get_access_request"(uuid) from public, anon;
grant execute on function "api"."get_access_request"(uuid) to authenticated, service_role;

create or replace function "api"."list_access_requests"(tenant uuid, status text default null, mine boolean default false, page_size integer default null, before timestamptz default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_access_requests"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."list_access_requests"(uuid, text, boolean, integer, timestamptz) from public, anon;
grant execute on function "api"."list_access_requests"(uuid, text, boolean, integer, timestamptz) to authenticated, service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_078_access_requests.sql
-- better-supabase module: access-requests
-- @bsb-block-data access-requests
-- @bsb-hash sha256:5ecfb15306bd8d51b0820b8afc96355b2183538887699d447a1077c7e0e498cf
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('access-requests', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_078_access_requests.sql
-- better-supabase module: access-requests
-- @bsb-block access-requests@1 managed
-- @bsb-hash sha256:da70f8e5c58c0cc21c583a2a81bce1cf33e61967504dacd9a1f15f694fc75e58
-- Members ask for a role, for a set time if they like. The request goes through approvals; the final approval grants the role, and the grant ends early on request or when it expires.
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
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."access_requests";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."access_requests";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."access_requests";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."access_requests";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."access_requests";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- better_supabase.access_requests is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."access_requests" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."access_requests" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."access_requests" add column if not exists "user_id" uuid;
alter table "better_supabase"."access_requests" add column if not exists "role" text check (length("role") between 1 and 200);
alter table "better_supabase"."access_requests" add column if not exists "previous_role" text;
alter table "better_supabase"."access_requests" add column if not exists "reason" text check ("reason" is null or length("reason") <= 2000);
alter table "better_supabase"."access_requests" add column if not exists "duration" interval check ("duration" is null or "duration" > interval '0');
alter table "better_supabase"."access_requests" add column if not exists "approval_id" uuid references "better_supabase"."approval_requests" ("id") on delete cascade;
alter table "better_supabase"."access_requests" add column if not exists "granted_at" timestamptz;
alter table "better_supabase"."access_requests" add column if not exists "expires_at" timestamptz;
alter table "better_supabase"."access_requests" add column if not exists "ended_at" timestamptz;
alter table "better_supabase"."access_requests" add column if not exists "created_at" timestamptz not null default now();
create index if not exists "access_requests_tenant_idx" on "better_supabase"."access_requests" ("tenant_id", "created_at" desc);
create index if not exists "access_requests_approval_idx" on "better_supabase"."access_requests" ("approval_id") where "approval_id" is not null;
create index if not exists "access_requests_expiry_idx" on "better_supabase"."access_requests" ("expires_at") where "granted_at" is not null and "ended_at" is null;
alter table "better_supabase"."access_requests" enable row level security;
grant select on "better_supabase"."access_requests" to authenticated;
grant all on "better_supabase"."access_requests" to service_role;
drop policy if exists bsb_access_requests_select on "better_supabase"."access_requests";
create policy bsb_access_requests_select on "better_supabase"."access_requests"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('access_requests.read')) or "user_id" = (select auth.uid()));

-- Asks for a role in an organization. Approvers come from options.policy;
-- the final approval calls grant_access_request.
drop function if exists "better_supabase"."request_access"(uuid, text, text, interval, jsonb);
create or replace function "better_supabase"."request_access"(tenant uuid, role text, reason text default null, duration interval default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_current text;
  v_duration interval;
  v_row "better_supabase"."access_requests"%rowtype;
  v_approval jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to request access' using errcode = '42501', hint = 'ACCESS_SIGN_IN';
  end if;
  select m."role" into v_current from "better_supabase"."memberships" m
  where m."organization_id" = request_access.tenant and m."user_id" = v_me;
  if not found then
    raise exception 'only members can request a role' using errcode = '42501', hint = 'ACCESS_REQUEST_FORBIDDEN';
  elsif not coalesce(better_supabase.can('tenant', request_access.tenant, 'access_requests.create'), false) then
    raise exception 'not allowed to request a role here' using errcode = '42501', hint = 'ACCESS_REQUEST_FORBIDDEN';
  end if;
  if not (request_access.role = any (array['admin', 'member', 'viewer']::text[])) then
    raise exception 'this role can''t be requested' using errcode = '22023', hint = 'ACCESS_ROLE_INVALID';
  end if;
  if v_current = request_access.role then
    raise exception 'you already hold this role' using errcode = '22023', hint = 'ACCESS_ROLE_HELD';
  end if;
  if v_current = 'owner' then
    raise exception 'an owner can''t request another role' using errcode = '22023', hint = 'ACCESS_ROLE_INVALID';
  end if;
  v_duration := request_access.duration;
  if v_duration is not null and v_duration <= interval '0' then
    raise exception 'duration must be positive' using errcode = '22023', hint = 'ACCESS_DURATION_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('access_request:' || request_access.tenant::text || ':' || v_me::text, 0));
  if exists (
    select 1 from "better_supabase"."access_requests" r join "better_supabase"."approval_requests" x on x."id" = r."approval_id"
    where r."tenant_id" = request_access.tenant and r."user_id" = v_me and x."status" = 'pending'
  ) then
    raise exception 'you already have a pending access request here' using errcode = '23505', hint = 'ACCESS_REQUEST_PENDING';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_access_request"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using request_access.tenant, request_access.role;
    end if;
  end;
  insert into "better_supabase"."access_requests" ("tenant_id", "user_id", "role", "reason", "duration")
  values (request_access.tenant, v_me, request_access.role, request_access.reason, v_duration)
  returning * into v_row;
  v_approval := "better_supabase"."open_approval"(
    request_access.tenant, 'access_request', v_row."id"::text, 'grant',
    '{"steps":[{"approvers":{"permission":"members.update_role"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb, request_access.reason,
    jsonb_build_object('role', request_access.role, 'userId', v_me, 'duration', v_duration::text)
  );
  update "better_supabase"."access_requests" r set "approval_id" = (v_approval ->> 'id')::uuid
  where r."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_access_request"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'role', v_row."role", 'previousRole', v_row."previous_role", 'reason', v_row."reason", 'duration', v_row."duration"::text, 'status', 'pending', 'approvalId', v_row."approval_id", 'grantedAt', v_row."granted_at", 'expiresAt', v_row."expires_at", 'endedAt', v_row."ended_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."request_access"(uuid, text, text, interval) from public, anon;
grant execute on function "better_supabase"."request_access"(uuid, text, text, interval) to authenticated, service_role;

-- Grants the role once the approval is final. Approvals calls it; it
-- isn't granted to anyone.
create or replace function "better_supabase"."grant_access_request"(request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."access_requests"%rowtype;
  v_previous text;
begin
  select * into v_row from "better_supabase"."access_requests" r where r."id" = grant_access_request.request_id for update;
  if not found or v_row."granted_at" is not null then
    return;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_access_grant"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  select m."role" into v_previous from "better_supabase"."memberships" m
  where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
  for update;
  if found then
    update "better_supabase"."memberships" set "role" = v_row."role"
    where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
  else
    insert into "better_supabase"."memberships" ("organization_id", "user_id", "role")
    values (v_row."tenant_id", v_row."user_id", v_row."role");
  end if;
  update "better_supabase"."access_requests" r
  set "previous_role" = v_previous,
      "granted_at" = now(),
      "expires_at" = case when v_row."duration" is null then null else now() + v_row."duration" end
  where r."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_access_grant"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
end;
$$;
revoke execute on function "better_supabase"."grant_access_request"(uuid) from public, anon, authenticated;

-- Ends a granted role early: a manager, or the holder giving it up.
create or replace function "better_supabase"."end_access"(request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
declare
  v_row "better_supabase"."access_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."access_requests" r where r."id" = end_access.request_id for update;
  if not found then
    raise exception 'access request not found' using errcode = 'P0002', hint = 'ACCESS_REQUEST_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."user_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'access_requests.manage'), false)) then
    raise exception 'not allowed to end this access' using errcode = '42501', hint = 'ACCESS_REQUEST_FORBIDDEN';
  end if;
  if v_row."granted_at" is null or v_row."ended_at" is not null then
    raise exception 'this access isn''t active' using errcode = '22023', hint = 'ACCESS_NOT_GRANTED';
  end if;
  -- Only a role that is still the granted one goes back; a later change wins.
  if exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
      and m."role" = v_row."role"
  ) then
    if v_row."previous_role" is null then
      delete from "better_supabase"."memberships" where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
    else
      update "better_supabase"."memberships" set "role" = v_row."previous_role"
      where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
    end if;
  end if;
  update "better_supabase"."access_requests" r set "ended_at" = now() where r."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'role', v_row."role", 'previousRole', v_row."previous_role", 'reason', v_row."reason", 'duration', v_row."duration"::text, 'status', 'ended', 'approvalId', v_row."approval_id", 'grantedAt', v_row."granted_at", 'expiresAt', v_row."expires_at", 'endedAt', v_row."ended_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."end_access"(uuid) from public, anon;
grant execute on function "better_supabase"."end_access"(uuid) to authenticated, service_role;

-- Ends grants past their expiry. Schedule it with pg_cron or the jobs drain.
create or replace function "better_supabase"."expire_access_grants"(max_grants integer default 200)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."access_requests"%rowtype;
  v_count integer := 0;
begin
  for v_row in
    select * from "better_supabase"."access_requests" r
    where r."granted_at" is not null and r."ended_at" is null and r."expires_at" <= now()
    order by r."expires_at"
    limit greatest(coalesce(expire_access_grants.max_grants, 200), 1)
    for update skip locked
  loop
  -- Only a role that is still the granted one goes back; a later change wins.
  if exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
      and m."role" = v_row."role"
  ) then
    if v_row."previous_role" is null then
      delete from "better_supabase"."memberships" where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
    else
      update "better_supabase"."memberships" set "role" = v_row."previous_role"
      where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
    end if;
  end if;
    update "better_supabase"."access_requests" r set "ended_at" = now() where r."id" = v_row."id" returning * into v_row;
    null;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."expire_access_grants"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."expire_access_grants"(integer) to service_role;

create or replace function "better_supabase"."get_access_request"(request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
declare
  v_row "better_supabase"."access_requests"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  select * into v_row from "better_supabase"."access_requests" r where r."id" = get_access_request.request_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."user_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'access_requests.read'), false)) then
    raise exception 'access request not found' using errcode = 'P0002', hint = 'ACCESS_REQUEST_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_row."approval_id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'role', v_row."role", 'previousRole', v_row."previous_role", 'reason', v_row."reason", 'duration', v_row."duration"::text, 'status', case when v_row."ended_at" is not null then 'ended' when v_row."granted_at" is not null then 'granted' else coalesce(v_approval."status", 'pending') end, 'approvalId', v_row."approval_id", 'grantedAt', v_row."granted_at", 'expiresAt', v_row."expires_at", 'endedAt', v_row."ended_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."get_access_request"(uuid) from public, anon;
grant execute on function "better_supabase"."get_access_request"(uuid) to authenticated, service_role;

-- Newest first. Readers of the organization see every request; others see
-- their own.
create or replace function "better_supabase"."list_access_requests"(tenant uuid, status text default null, mine boolean default false, page_size integer default null, before timestamptz default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
  select coalesce(jsonb_agg(item order by created desc), '[]'::jsonb)
  from (
    select jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'userId', r."user_id", 'role', r."role", 'previousRole', r."previous_role", 'reason', r."reason", 'duration', r."duration"::text, 'status', case when r."ended_at" is not null then 'ended' when r."granted_at" is not null then 'granted' else coalesce(x."status", 'pending') end, 'approvalId', r."approval_id", 'grantedAt', r."granted_at", 'expiresAt', r."expires_at", 'endedAt', r."ended_at", 'createdAt', r."created_at") as item, r."created_at" as created
    from "better_supabase"."access_requests" r
    left join "better_supabase"."approval_requests" x on x."id" = r."approval_id"
    where r."tenant_id" = list_access_requests.tenant
      and (r."user_id" = auth.uid() or (not list_access_requests.mine and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_access_requests.tenant, 'access_requests.read'), false))))
      and (list_access_requests.status is null or case when r."ended_at" is not null then 'ended' when r."granted_at" is not null then 'granted' else coalesce(x."status", 'pending') end = list_access_requests.status)
      and (list_access_requests.before is null or r."created_at" < list_access_requests.before)
    order by r."created_at" desc
    limit least(greatest(coalesce(list_access_requests.page_size, 50), 1), 200)
  ) items
$$;
revoke execute on function "better_supabase"."list_access_requests"(uuid, text, boolean, integer, timestamptz) from public, anon;
grant execute on function "better_supabase"."list_access_requests"(uuid, text, boolean, integer, timestamptz) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."access_requests";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."access_requests";
create policy bsb_tenant_scope_select on "better_supabase"."access_requests" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('access_requests.read')) or "user_id" = (select auth.uid()))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."access_requests";
create policy bsb_tenant_scope_insert on "better_supabase"."access_requests" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."access_requests";
create policy bsb_tenant_scope_update on "better_supabase"."access_requests" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."access_requests";
create policy bsb_tenant_scope_delete on "better_supabase"."access_requests" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_078_access_requests.sql
-- better-supabase module: access-requests
-- @bsb-block-data access-requests
-- @bsb-hash sha256:5ecfb15306bd8d51b0820b8afc96355b2183538887699d447a1077c7e0e498cf
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('access-requests', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_078_access_requests.sql
-- better-supabase module: access-requests
-- @bsb-block access-requests@1 managed
-- @bsb-hash sha256:ba8d35debbb224c358fb3016a3360aa9ec01d3e11d3c1cea58c2605c99862b81
-- Members ask for a role, for a set time if they like. The request goes through approvals; the final approval grants the role, and the grant ends early on request or when it expires.
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
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."access_requests";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."access_requests";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."access_requests";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."access_requests";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."access_requests";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."access_requests" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "user_id" uuid not null,
  "role" text not null check (length("role") between 1 and 200),
  "previous_role" text,
  "reason" text check ("reason" is null or length("reason") <= 2000),
  "duration" interval check ("duration" is null or "duration" > interval '0'),
  "approval_id" uuid references "better_supabase"."approval_requests" ("id") on delete cascade,
  "granted_at" timestamptz,
  "expires_at" timestamptz,
  "ended_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create index if not exists "access_requests_tenant_idx" on "better_supabase"."access_requests" ("org_id", "created_at" desc);
create index if not exists "access_requests_approval_idx" on "better_supabase"."access_requests" ("approval_id") where "approval_id" is not null;
create index if not exists "access_requests_expiry_idx" on "better_supabase"."access_requests" ("expires_at") where "granted_at" is not null and "ended_at" is null;
alter table "better_supabase"."access_requests" enable row level security;
revoke all on "better_supabase"."access_requests" from public, anon, authenticated;
grant select on "better_supabase"."access_requests" to authenticated;
grant all on "better_supabase"."access_requests" to service_role;
drop policy if exists access_requests_read on "better_supabase"."access_requests";
create policy access_requests_read on "better_supabase"."access_requests"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('access_requests.read')) or "user_id" = (select auth.uid()));

-- Asks for a role in an organization. Approvers come from options.policy;
-- the final approval calls grant_access_request.
drop function if exists "better_supabase"."request_access"(uuid, text, text, interval, jsonb);
create or replace function "better_supabase"."request_access"(tenant uuid, role text, reason text default null, duration interval default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_current text;
  v_duration interval;
  v_row "better_supabase"."access_requests"%rowtype;
  v_approval jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to request access' using errcode = '42501', hint = 'ACCESS_SIGN_IN';
  end if;
  select m."role" into v_current from "better_supabase"."memberships" m
  where m."org_id" = request_access.tenant and m."user_id" = v_me;
  if not found then
    raise exception 'only members can request a role' using errcode = '42501', hint = 'ACCESS_REQUEST_FORBIDDEN';
  elsif not coalesce(better_supabase.can('tenant', request_access.tenant, 'access_requests.create'), false) then
    raise exception 'not allowed to request a role here' using errcode = '42501', hint = 'ACCESS_REQUEST_FORBIDDEN';
  end if;
  if not (request_access.role = any (array['admin', 'member', 'viewer']::text[])) then
    raise exception 'this role can''t be requested' using errcode = '22023', hint = 'ACCESS_ROLE_INVALID';
  end if;
  if v_current = request_access.role then
    raise exception 'you already hold this role' using errcode = '22023', hint = 'ACCESS_ROLE_HELD';
  end if;
  if v_current = 'owner' then
    raise exception 'an owner can''t request another role' using errcode = '22023', hint = 'ACCESS_ROLE_INVALID';
  end if;
  v_duration := request_access.duration;
  if v_duration is not null and v_duration <= interval '0' then
    raise exception 'duration must be positive' using errcode = '22023', hint = 'ACCESS_DURATION_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('access_request:' || request_access.tenant::text || ':' || v_me::text, 0));
  if exists (
    select 1 from "better_supabase"."access_requests" r join "better_supabase"."approval_requests" x on x."id" = r."approval_id"
    where r."org_id" = request_access.tenant and r."user_id" = v_me and x."status" = 'pending'
  ) then
    raise exception 'you already have a pending access request here' using errcode = '23505', hint = 'ACCESS_REQUEST_PENDING';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_access_request"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using request_access.tenant, request_access.role;
    end if;
  end;
  insert into "better_supabase"."access_requests" ("org_id", "user_id", "role", "reason", "duration")
  values (request_access.tenant, v_me, request_access.role, request_access.reason, v_duration)
  returning * into v_row;
  v_approval := "better_supabase"."open_approval"(
    request_access.tenant, 'access_request', v_row."id"::text, 'grant',
    '{"steps":[{"approvers":{"permission":"members.update_role"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb, request_access.reason,
    jsonb_build_object('role', request_access.role, 'userId', v_me, 'duration', v_duration::text)
  );
  update "better_supabase"."access_requests" r set "approval_id" = (v_approval ->> 'id')::uuid
  where r."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_access_request"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'userId', v_row."user_id", 'role', v_row."role", 'previousRole', v_row."previous_role", 'reason', v_row."reason", 'duration', v_row."duration"::text, 'status', 'pending', 'approvalId', v_row."approval_id", 'grantedAt', v_row."granted_at", 'expiresAt', v_row."expires_at", 'endedAt', v_row."ended_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."request_access"(uuid, text, text, interval) from public, anon;
grant execute on function "better_supabase"."request_access"(uuid, text, text, interval) to authenticated, service_role;

-- Grants the role once the approval is final. Approvals calls it; it
-- isn't granted to anyone.
create or replace function "better_supabase"."grant_access_request"(request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."access_requests"%rowtype;
  v_previous text;
begin
  select * into v_row from "better_supabase"."access_requests" r where r."id" = grant_access_request.request_id for update;
  if not found or v_row."granted_at" is not null then
    return;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_access_grant"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  select m."role" into v_previous from "better_supabase"."memberships" m
  where m."org_id" = v_row."org_id" and m."user_id" = v_row."user_id"
  for update;
  if found then
    update "better_supabase"."memberships" set "role" = v_row."role"
    where "org_id" = v_row."org_id" and "user_id" = v_row."user_id";
  else
    insert into "better_supabase"."memberships" ("org_id", "user_id", "role")
    values (v_row."org_id", v_row."user_id", v_row."role");
  end if;
  update "better_supabase"."access_requests" r
  set "previous_role" = v_previous,
      "granted_at" = now(),
      "expires_at" = case when v_row."duration" is null then null else now() + v_row."duration" end
  where r."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_access_grant"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
end;
$$;
revoke execute on function "better_supabase"."grant_access_request"(uuid) from public, anon, authenticated;

-- Ends a granted role early: a manager, or the holder giving it up.
create or replace function "better_supabase"."end_access"(request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
declare
  v_row "better_supabase"."access_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."access_requests" r where r."id" = end_access.request_id for update;
  if not found then
    raise exception 'access request not found' using errcode = 'P0002', hint = 'ACCESS_REQUEST_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."user_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."org_id", 'access_requests.manage'), false)) then
    raise exception 'not allowed to end this access' using errcode = '42501', hint = 'ACCESS_REQUEST_FORBIDDEN';
  end if;
  if v_row."granted_at" is null or v_row."ended_at" is not null then
    raise exception 'this access isn''t active' using errcode = '22023', hint = 'ACCESS_NOT_GRANTED';
  end if;
  -- Only a role that is still the granted one goes back; a later change wins.
  if exists (
    select 1 from "better_supabase"."memberships" m
    where m."org_id" = v_row."org_id" and m."user_id" = v_row."user_id"
      and m."role" = v_row."role"
  ) then
    if v_row."previous_role" is null then
      delete from "better_supabase"."memberships" where "org_id" = v_row."org_id" and "user_id" = v_row."user_id";
    else
      update "better_supabase"."memberships" set "role" = v_row."previous_role"
      where "org_id" = v_row."org_id" and "user_id" = v_row."user_id";
    end if;
  end if;
  update "better_supabase"."access_requests" r set "ended_at" = now() where r."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'userId', v_row."user_id", 'role', v_row."role", 'previousRole', v_row."previous_role", 'reason', v_row."reason", 'duration', v_row."duration"::text, 'status', 'ended', 'approvalId', v_row."approval_id", 'grantedAt', v_row."granted_at", 'expiresAt', v_row."expires_at", 'endedAt', v_row."ended_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."end_access"(uuid) from public, anon;
grant execute on function "better_supabase"."end_access"(uuid) to authenticated, service_role;

-- Ends grants past their expiry. Schedule it with pg_cron or the jobs drain.
create or replace function "better_supabase"."expire_access_grants"(max_grants integer default 200)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."access_requests"%rowtype;
  v_count integer := 0;
begin
  for v_row in
    select * from "better_supabase"."access_requests" r
    where r."granted_at" is not null and r."ended_at" is null and r."expires_at" <= now()
    order by r."expires_at"
    limit greatest(coalesce(expire_access_grants.max_grants, 200), 1)
    for update skip locked
  loop
  -- Only a role that is still the granted one goes back; a later change wins.
  if exists (
    select 1 from "better_supabase"."memberships" m
    where m."org_id" = v_row."org_id" and m."user_id" = v_row."user_id"
      and m."role" = v_row."role"
  ) then
    if v_row."previous_role" is null then
      delete from "better_supabase"."memberships" where "org_id" = v_row."org_id" and "user_id" = v_row."user_id";
    else
      update "better_supabase"."memberships" set "role" = v_row."previous_role"
      where "org_id" = v_row."org_id" and "user_id" = v_row."user_id";
    end if;
  end if;
    update "better_supabase"."access_requests" r set "ended_at" = now() where r."id" = v_row."id" returning * into v_row;
    null;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."expire_access_grants"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."expire_access_grants"(integer) to service_role;

create or replace function "better_supabase"."get_access_request"(request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
declare
  v_row "better_supabase"."access_requests"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  select * into v_row from "better_supabase"."access_requests" r where r."id" = get_access_request.request_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."user_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."org_id", 'access_requests.read'), false)) then
    raise exception 'access request not found' using errcode = 'P0002', hint = 'ACCESS_REQUEST_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_row."approval_id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'userId', v_row."user_id", 'role', v_row."role", 'previousRole', v_row."previous_role", 'reason', v_row."reason", 'duration', v_row."duration"::text, 'status', case when v_row."ended_at" is not null then 'ended' when v_row."granted_at" is not null then 'granted' else coalesce(v_approval."status", 'pending') end, 'approvalId', v_row."approval_id", 'grantedAt', v_row."granted_at", 'expiresAt', v_row."expires_at", 'endedAt', v_row."ended_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."get_access_request"(uuid) from public, anon;
grant execute on function "better_supabase"."get_access_request"(uuid) to authenticated, service_role;

-- Newest first. Readers of the organization see every request; others see
-- their own.
create or replace function "better_supabase"."list_access_requests"(tenant uuid, status text default null, mine boolean default false, page_size integer default null, before timestamptz default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
  select coalesce(jsonb_agg(item order by created desc), '[]'::jsonb)
  from (
    select jsonb_build_object('id', r."id", 'organizationId', r."org_id", 'userId', r."user_id", 'role', r."role", 'previousRole', r."previous_role", 'reason', r."reason", 'duration', r."duration"::text, 'status', case when r."ended_at" is not null then 'ended' when r."granted_at" is not null then 'granted' else coalesce(x."status", 'pending') end, 'approvalId', r."approval_id", 'grantedAt', r."granted_at", 'expiresAt', r."expires_at", 'endedAt', r."ended_at", 'createdAt', r."created_at") as item, r."created_at" as created
    from "better_supabase"."access_requests" r
    left join "better_supabase"."approval_requests" x on x."id" = r."approval_id"
    where r."org_id" = list_access_requests.tenant
      and (r."user_id" = auth.uid() or (not list_access_requests.mine and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_access_requests.tenant, 'access_requests.read'), false))))
      and (list_access_requests.status is null or case when r."ended_at" is not null then 'ended' when r."granted_at" is not null then 'granted' else coalesce(x."status", 'pending') end = list_access_requests.status)
      and (list_access_requests.before is null or r."created_at" < list_access_requests.before)
    order by r."created_at" desc
    limit least(greatest(coalesce(list_access_requests.page_size, 50), 1), 200)
  ) items
$$;
revoke execute on function "better_supabase"."list_access_requests"(uuid, text, boolean, integer, timestamptz) from public, anon;
grant execute on function "better_supabase"."list_access_requests"(uuid, text, boolean, integer, timestamptz) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."access_requests";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."access_requests";
create policy bsb_tenant_scope_select on "better_supabase"."access_requests" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('access_requests.read')) or "user_id" = (select auth.uid()))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."access_requests";
create policy bsb_tenant_scope_insert on "better_supabase"."access_requests" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."access_requests";
create policy bsb_tenant_scope_update on "better_supabase"."access_requests" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."access_requests";
create policy bsb_tenant_scope_delete on "better_supabase"."access_requests" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));

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

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_078_access_requests.sql
-- better-supabase module: access-requests
-- @bsb-block-data access-requests
-- @bsb-hash sha256:5ecfb15306bd8d51b0820b8afc96355b2183538887699d447a1077c7e0e498cf
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('access-requests', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
