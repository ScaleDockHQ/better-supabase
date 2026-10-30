-- better-supabase module: access-requests
-- @bsb-block access-requests@1 managed
-- @bsb-hash sha256:6684a33f924d5281dfc657de2a302c3b93b9930f93f41ff40d1d915d16bc9b5f
-- Members ask for a role or for access to one record, for a set time if they like. The request goes through approvals; the final approval grants it, and the grant ends early on request or when it expires. Emergency access opens a record at once and waits for a review.
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
  "role" text check (length("role") between 1 and 200),
  "target" text not null default 'role' check ("target" in ('role', 'record')),
  "subject_type" text check (length("subject_type") between 1 and 200),
  "subject_id" text check (length("subject_id") between 1 and 200),
  "action" text check (length("action") between 1 and 200),
  "emergency" boolean not null default false,
  "member_id" uuid,
  "review_verdict" text check ("review_verdict" in ('justified', 'unjustified')),
  "review_note" text check (length("review_note") <= 2000),
  "reviewed_by" uuid,
  "reviewed_at" timestamptz,
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
alter table "better_supabase"."access_requests" alter column "role" drop not null;
alter table "better_supabase"."access_requests" add column if not exists "target" text not null default 'role' check ("target" in ('role', 'record'));
alter table "better_supabase"."access_requests" add column if not exists "subject_type" text check (length("subject_type") between 1 and 200);
alter table "better_supabase"."access_requests" add column if not exists "subject_id" text check (length("subject_id") between 1 and 200);
alter table "better_supabase"."access_requests" add column if not exists "action" text check (length("action") between 1 and 200);
alter table "better_supabase"."access_requests" add column if not exists "emergency" boolean not null default false;
alter table "better_supabase"."access_requests" add column if not exists "member_id" uuid;
alter table "better_supabase"."access_requests" add column if not exists "review_verdict" text check ("review_verdict" in ('justified', 'unjustified'));
alter table "better_supabase"."access_requests" add column if not exists "review_note" text check (length("review_note") <= 2000);
alter table "better_supabase"."access_requests" add column if not exists "reviewed_by" uuid;
alter table "better_supabase"."access_requests" add column if not exists "reviewed_at" timestamptz;
create index if not exists "access_requests_subject_idx" on "better_supabase"."access_requests" ("subject_type", "subject_id", "user_id") where "subject_type" is not null;
create index if not exists "access_requests_emergency_idx" on "better_supabase"."access_requests" ("tenant_id", "created_at" desc) where "emergency";
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
  select (select r."key" from "better_supabase"."roles" r where r."id" = m."role") into v_current from "public"."memberships" m
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
    where r."tenant_id" = request_access.tenant and r."user_id" = v_me and x."status" = 'pending' and r."target" = 'role'
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
  perform "better_supabase".emit_event('access_request.requested', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action"), 'access-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/access-requests');
  perform better_supabase.audit_event(
    event_type => 'access_request.requested',
    category => 'membership',
    target_type => 'user',
    record_id => v_row."user_id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_access_request"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'role', v_row."role", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action", 'emergency', v_row."emergency", 'review', case when v_row."reviewed_at" is null then null else jsonb_build_object('verdict', v_row."review_verdict", 'note', v_row."review_note", 'reviewedBy', v_row."reviewed_by", 'reviewedAt', v_row."reviewed_at") end, 'previousRole', v_row."previous_role", 'reason', v_row."reason", 'duration', v_row."duration"::text, 'status', 'pending', 'approvalId', v_row."approval_id", 'grantedAt', v_row."granted_at", 'expiresAt', v_row."expires_at", 'endedAt', v_row."ended_at", 'createdAt', v_row."created_at");
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
  v_ends timestamptz;
  v_member uuid;
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
  if v_row."target" = 'record' then
    v_ends := now() + v_row."duration";
    case v_row."subject_type"
    when 'drive_node' then
      perform "better_supabase"."drive_grant_access"(v_row."subject_id", v_row."user_id", v_row."action", v_ends);
    else
      v_member := "better_supabase"."grant_subject_member"(v_row."subject_type", v_row."subject_id", v_row."user_id", v_ends, v_row."emergency", v_row."reason");
    end case;
    update "better_supabase"."access_requests" r
    set "granted_at" = now(), "expires_at" = v_ends, "member_id" = v_member
    where r."id" = v_row."id"
    returning * into v_row;
    if not v_row."emergency" then
      perform "better_supabase".emit_event('access_request.approved', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action"), 'access-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/access-requests');
  perform better_supabase.audit_event(
    event_type => 'access_request.approved',
    category => 'membership',
    target_type => 'user',
    record_id => v_row."user_id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action")
  );
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_access_grant"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
    return;
  end if;
  select (select r."key" from "better_supabase"."roles" r where r."id" = m."role") into v_previous from "public"."memberships" m
  where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
  for update;
  if found then
    update "public"."memberships" set "role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = (v_row."role")::text or r."key" = (v_row."role")::text) order by (r."id"::text = (v_row."role")::text) desc limit 1)
    where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
  else
    insert into "public"."memberships" ("organization_id", "user_id", "role")
    values (v_row."tenant_id", v_row."user_id", (select r."id" from "better_supabase"."roles" r where (r."id"::text = (v_row."role")::text or r."key" = (v_row."role")::text) order by (r."id"::text = (v_row."role")::text) desc limit 1));
  end if;
  update "better_supabase"."access_requests" r
  set "previous_role" = v_previous,
      "granted_at" = now(),
      "expires_at" = case when v_row."duration" is null then null else now() + v_row."duration" end
  where r."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('access_request.approved', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action"), 'access-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/access-requests');
  perform better_supabase.audit_event(
    event_type => 'access_request.approved',
    category => 'membership',
    target_type => 'user',
    record_id => v_row."user_id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action")
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."user_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'access_requests.manage'), false)) then
    raise exception 'not allowed to end this access' using errcode = '42501', hint = 'ACCESS_REQUEST_FORBIDDEN';
  end if;
  if v_row."granted_at" is null or v_row."ended_at" is not null then
    raise exception 'this access isn''t active' using errcode = '22023', hint = 'ACCESS_NOT_GRANTED';
  end if;
  if v_row."target" = 'record' then
    case v_row."subject_type"
    when 'drive_node' then
      perform "better_supabase"."drive_grant_access"(v_row."subject_id", v_row."user_id", v_row."action", now());
    else
      if v_row."member_id" is not null then
        perform "better_supabase"."close_subject_member"(v_row."member_id");
      end if;
    end case;
  else
    -- Only a role that is still the granted one goes back; a later change wins.
    if exists (
      select 1 from "public"."memberships" m
      where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
        and (select r."key" from "better_supabase"."roles" r where r."id" = m."role") = v_row."role"
    ) then
      if v_row."previous_role" is null then
        delete from "public"."memberships" where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
      else
        update "public"."memberships" set "role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = (v_row."previous_role")::text or r."key" = (v_row."previous_role")::text) order by (r."id"::text = (v_row."previous_role")::text) desc limit 1)
        where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
      end if;
    end if;
  end if;
  update "better_supabase"."access_requests" r set "ended_at" = now() where r."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('access_request.ended', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action", 'reason', 'revoked'), 'access-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/access-requests');
  perform better_supabase.audit_event(
    event_type => 'access_request.ended',
    category => 'membership',
    target_type => 'user',
    record_id => v_row."user_id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action", 'reason', 'revoked')
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'role', v_row."role", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action", 'emergency', v_row."emergency", 'review', case when v_row."reviewed_at" is null then null else jsonb_build_object('verdict', v_row."review_verdict", 'note', v_row."review_note", 'reviewedBy', v_row."reviewed_by", 'reviewedAt', v_row."reviewed_at") end, 'previousRole', v_row."previous_role", 'reason', v_row."reason", 'duration', v_row."duration"::text, 'status', 'ended', 'approvalId', v_row."approval_id", 'grantedAt', v_row."granted_at", 'expiresAt', v_row."expires_at", 'endedAt', v_row."ended_at", 'createdAt', v_row."created_at");
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
    if v_row."target" = 'role' then
      -- Only a role that is still the granted one goes back; a later change wins.
      if exists (
        select 1 from "public"."memberships" m
        where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
          and (select r."key" from "better_supabase"."roles" r where r."id" = m."role") = v_row."role"
      ) then
        if v_row."previous_role" is null then
          delete from "public"."memberships" where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
        else
          update "public"."memberships" set "role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = (v_row."previous_role")::text or r."key" = (v_row."previous_role")::text) order by (r."id"::text = (v_row."previous_role")::text) desc limit 1)
          where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
        end if;
      end if;
    end if;
    update "better_supabase"."access_requests" r set "ended_at" = now() where r."id" = v_row."id" returning * into v_row;
    perform "better_supabase".emit_event('access_request.ended', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action", 'reason', 'expired'), 'access-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/access-requests');
  perform better_supabase.audit_event(
    event_type => 'access_request.ended',
    category => 'membership',
    target_type => 'user',
    record_id => v_row."user_id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action", 'reason', 'expired')
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
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."user_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'access_requests.read'), false)) then
    raise exception 'access request not found' using errcode = 'P0002', hint = 'ACCESS_REQUEST_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_row."approval_id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'role', v_row."role", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action", 'emergency', v_row."emergency", 'review', case when v_row."reviewed_at" is null then null else jsonb_build_object('verdict', v_row."review_verdict", 'note', v_row."review_note", 'reviewedBy', v_row."reviewed_by", 'reviewedAt', v_row."reviewed_at") end, 'previousRole', v_row."previous_role", 'reason', v_row."reason", 'duration', v_row."duration"::text, 'status', case when v_row."ended_at" is not null then 'ended' when v_row."granted_at" is not null then 'granted' else coalesce(v_approval."status", 'pending') end, 'approvalId', v_row."approval_id", 'grantedAt', v_row."granted_at", 'expiresAt', v_row."expires_at", 'endedAt', v_row."ended_at", 'createdAt', v_row."created_at");
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
    select jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'userId', r."user_id", 'role', r."role", 'target', r."target", 'subjectType', r."subject_type", 'subjectId', r."subject_id", 'action', r."action", 'emergency', r."emergency", 'review', case when r."reviewed_at" is null then null else jsonb_build_object('verdict', r."review_verdict", 'note', r."review_note", 'reviewedBy', r."reviewed_by", 'reviewedAt', r."reviewed_at") end, 'previousRole', r."previous_role", 'reason', r."reason", 'duration', r."duration"::text, 'status', case when r."ended_at" is not null then 'ended' when r."granted_at" is not null then 'granted' else coalesce(x."status", 'pending') end, 'approvalId', r."approval_id", 'grantedAt', r."granted_at", 'expiresAt', r."expires_at", 'endedAt', r."ended_at", 'createdAt', r."created_at") as item, r."created_at" as created
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

-- Asks for access to one record: its team leads approve, then the record's
-- own approvers when its type names them, or the holders of subjects.manage.
-- The final approval adds a team row (or the record's accessGrant) that ends
-- after the duration.
create or replace function "better_supabase"."request_record_access"(subject_type text, subject_id text, action text default 'read', reason text default null, duration interval default interval '7 days')
returns jsonb
language plpgsql
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_tenant uuid;
  v_duration interval := coalesce(request_record_access.duration, interval '7 days');
  v_leads uuid[];
  v_row "better_supabase"."access_requests"%rowtype;
  v_approval jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to request access' using errcode = '42501', hint = 'ACCESS_SIGN_IN';
  end if;
  if not (request_record_access.subject_type = any (array['customer', 'drive_node']::text[])) or (case request_record_access.subject_type
      when 'customer' then not (request_record_access.action = any (array['read', 'write']::text[]))
      when 'drive_node' then not (request_record_access.action = any (array['read']::text[]))
      else true end) then
    raise exception 'this record or action can''t be requested' using errcode = '22023', hint = 'ACCESS_REQUEST_RECORD_INVALID';
  end if;
  v_tenant := "better_supabase"."record_team_tenant"(request_record_access.subject_type, request_record_access.subject_id);
  if v_tenant is null then
    raise exception 'record not found' using errcode = 'P0002', hint = 'ACCESS_REQUEST_RECORD_INVALID';
  end if;
  if not exists (select 1 from "public"."memberships" m where m."organization_id" = v_tenant and m."user_id" = auth.uid()) or not coalesce(better_supabase.can('tenant', v_tenant, 'access_requests.create'), false) then
    raise exception 'not allowed to request access here' using errcode = '42501', hint = 'ACCESS_REQUEST_FORBIDDEN';
  end if;
  if "better_supabase"."can_subject"(request_record_access.subject_type, request_record_access.subject_id, request_record_access.action) then
    raise exception 'you already have this access' using errcode = '22023', hint = 'ACCESS_REQUEST_RECORD_INVALID';
  end if;
  if v_duration <= interval '0' then
    raise exception 'duration must be positive' using errcode = '22023', hint = 'ACCESS_DURATION_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('access_request:' || request_record_access.subject_type || ':' || request_record_access.subject_id || ':' || v_me::text, 0));
  if exists (
    select 1 from "better_supabase"."access_requests" r join "better_supabase"."approval_requests" x on x."id" = r."approval_id"
    where r."subject_type" = request_record_access.subject_type and r."subject_id" = request_record_access.subject_id
      and r."user_id" = v_me and x."status" = 'pending'
  ) then
    raise exception 'you already have a pending access request for this record' using errcode = '23505', hint = 'ACCESS_REQUEST_PENDING';
  end if;
  insert into "better_supabase"."access_requests" ("tenant_id", "user_id", "target", "subject_type", "subject_id", "action", "reason", "duration")
  values (v_tenant, v_me, 'record', request_record_access.subject_type, request_record_access.subject_id, request_record_access.action, request_record_access.reason, v_duration)
  returning * into v_row;
  v_leads := "better_supabase"."record_team_leads"(request_record_access.subject_type, request_record_access.subject_id);
  if coalesce(cardinality(v_leads), 0) = 0 then
    v_leads := case request_record_access.subject_type
      when 'drive_node' then array_remove("better_supabase"."drive_access_approvers"(request_record_access.subject_id), v_me)
      else v_leads end;
  end if;
  v_approval := "better_supabase"."open_approval"(
    v_tenant, 'access_request', v_row."id"::text, 'grant',
    '{"steps":[{"approvers":{"permission":"members.update_role"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb || jsonb_build_object('steps', jsonb_build_array(jsonb_build_object(
      'approvers', case when cardinality(v_leads) > 0 then jsonb_build_object('users', to_jsonb(v_leads)) else jsonb_build_object('permission', 'subjects.manage') end,
      'required', 1))),
    request_record_access.reason,
    jsonb_build_object('subjectType', request_record_access.subject_type, 'subjectId', request_record_access.subject_id, 'action', request_record_access.action, 'userId', v_me, 'duration', v_duration::text)
  );
  update "better_supabase"."access_requests" r set "approval_id" = (v_approval ->> 'id')::uuid
  where r."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('access_request.requested', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action"), 'access-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/access-requests');
  perform better_supabase.audit_event(
    event_type => 'access_request.requested',
    category => 'membership',
    target_type => 'user',
    record_id => v_row."user_id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'role', v_row."role", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action", 'emergency', v_row."emergency", 'review', case when v_row."reviewed_at" is null then null else jsonb_build_object('verdict', v_row."review_verdict", 'note', v_row."review_note", 'reviewedBy', v_row."reviewed_by", 'reviewedAt', v_row."reviewed_at") end, 'previousRole', v_row."previous_role", 'reason', v_row."reason", 'duration', v_row."duration"::text, 'status', 'pending', 'approvalId', v_row."approval_id", 'grantedAt', v_row."granted_at", 'expiresAt', v_row."expires_at", 'endedAt', v_row."ended_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."request_record_access"(text, text, text, text, interval) from public, anon;
grant execute on function "better_supabase"."request_record_access"(text, text, text, text, interval) to authenticated, service_role;

-- Break-the-glass: read access to one record right away, for at most
-- options.emergency.maxHours, with a reason that a reviewer checks later.
create or replace function "better_supabase"."open_emergency_access"(subject_type text, subject_id text, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_tenant uuid;
  v_row "better_supabase"."access_requests"%rowtype;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to open emergency access' using errcode = '42501', hint = 'ACCESS_SIGN_IN';
  end if;
  if length(btrim(coalesce(open_emergency_access.reason, ''))) < 10 then
    raise exception 'say why you need emergency access, in at least 10 characters' using errcode = '22023', hint = 'ACCESS_REQUEST_REASON_REQUIRED';
  end if;
  if not (open_emergency_access.subject_type = any (array['customer', 'drive_node']::text[])) or (case open_emergency_access.subject_type
      when 'customer' then not ('read' = any (array['read', 'write']::text[]))
      when 'drive_node' then not ('read' = any (array['read']::text[]))
      else true end) then
    raise exception 'this record or action can''t be requested' using errcode = '22023', hint = 'ACCESS_REQUEST_RECORD_INVALID';
  end if;
  v_tenant := "better_supabase"."record_team_tenant"(open_emergency_access.subject_type, open_emergency_access.subject_id);
  if v_tenant is null then
    raise exception 'record not found' using errcode = 'P0002', hint = 'ACCESS_REQUEST_RECORD_INVALID';
  end if;
  if not exists (select 1 from "public"."memberships" m where m."organization_id" = v_tenant and m."user_id" = auth.uid()) or not coalesce(better_supabase.can('tenant', v_tenant, 'access_requests.emergency'), false) then
    raise exception 'not allowed to open emergency access here' using errcode = '42501', hint = 'ACCESS_REQUEST_FORBIDDEN';
  end if;
  insert into "better_supabase"."access_requests" ("tenant_id", "user_id", "target", "subject_type", "subject_id", "action", "emergency", "reason", "duration")
  values (v_tenant, v_me, 'record', open_emergency_access.subject_type, open_emergency_access.subject_id, 'read', true, btrim(open_emergency_access.reason), interval '8 hours')
  returning * into v_row;
  perform "better_supabase"."grant_access_request"(v_row."id");
  select * into v_row from "better_supabase"."access_requests" r where r."id" = v_row."id";
  v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'access_request.emergency_opened',
      'tenant', v_tenant,
      'actor', v_me,
      'subject_type', open_emergency_access.subject_type,
      'subject_id', open_emergency_access.subject_id,
      'summary', btrim(open_emergency_access.reason),
      'recipients', to_jsonb("better_supabase"."record_team_leads"(open_emergency_access.subject_type, open_emergency_access.subject_id)),
      'permission', 'access_requests.review',
      'watchers', false,
      'key', 'access_request.emergency_opened:' || v_row."id"::text,
      'data', jsonb_build_object('accessRequestId', v_row."id")
    ));
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform "better_supabase".emit_event('access_request.emergency_opened', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action", 'reason', v_row."reason"), 'access-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/access-requests');
  perform better_supabase.audit_event(
    event_type => 'access_request.emergency_opened',
    category => 'membership',
    target_type => 'user',
    record_id => v_row."user_id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action", 'reason', v_row."reason")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'role', v_row."role", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action", 'emergency', v_row."emergency", 'review', case when v_row."reviewed_at" is null then null else jsonb_build_object('verdict', v_row."review_verdict", 'note', v_row."review_note", 'reviewedBy', v_row."reviewed_by", 'reviewedAt', v_row."reviewed_at") end, 'previousRole', v_row."previous_role", 'reason', v_row."reason", 'duration', v_row."duration"::text, 'status', 'granted', 'approvalId', v_row."approval_id", 'grantedAt', v_row."granted_at", 'expiresAt', v_row."expires_at", 'endedAt', v_row."ended_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."open_emergency_access"(text, text, text) from public, anon;
grant execute on function "better_supabase"."open_emergency_access"(text, text, text) to authenticated, service_role;

-- Records whether an emergency access was justified. Needs
-- access_requests.review; nobody reviews their own.
create or replace function "better_supabase"."review_emergency_access"(request_id uuid, verdict text, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."access_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if review_emergency_access.verdict is null or review_emergency_access.verdict not in ('justified', 'unjustified') then
    raise exception 'verdict must be justified or unjustified' using errcode = '22023', hint = 'ACCESS_REQUEST_REVIEW_INVALID';
  end if;
  if length(review_emergency_access.note) > 2000 then
    raise exception 'a note is at most 2000 characters' using errcode = '22023', hint = 'ACCESS_REQUEST_REVIEW_INVALID';
  end if;
  select * into v_row from "better_supabase"."access_requests" r where r."id" = review_emergency_access.request_id and r."emergency" for update;
  if not found then
    raise exception 'emergency access not found' using errcode = 'P0002', hint = 'ACCESS_REQUEST_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'access_requests.review'), false)) then
    raise exception 'not allowed to review emergency access' using errcode = '42501', hint = 'ACCESS_REQUEST_FORBIDDEN';
  end if;
  if v_row."user_id" = auth.uid() then
    raise exception 'you can''t review your own emergency access' using errcode = '22023', hint = 'ACCESS_REQUEST_REVIEW_INVALID';
  end if;
  if v_row."reviewed_at" is not null then
    raise exception 'this emergency access is already reviewed' using errcode = '22023', hint = 'ACCESS_REQUEST_REVIEW_INVALID';
  end if;
  update "better_supabase"."access_requests" r
  set "review_verdict" = review_emergency_access.verdict,
      "review_note" = nullif(btrim(review_emergency_access.note), ''),
      "reviewed_by" = auth.uid(),
      "reviewed_at" = now()
  where r."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('access_request.emergency_reviewed', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action", 'verdict', v_row."review_verdict"), 'access-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/access-requests');
  perform better_supabase.audit_event(
    event_type => 'access_request.emergency_reviewed',
    category => 'membership',
    target_type => 'user',
    record_id => v_row."user_id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action", 'verdict', v_row."review_verdict")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'role', v_row."role", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action", 'emergency', v_row."emergency", 'review', case when v_row."reviewed_at" is null then null else jsonb_build_object('verdict', v_row."review_verdict", 'note', v_row."review_note", 'reviewedBy', v_row."reviewed_by", 'reviewedAt', v_row."reviewed_at") end, 'previousRole', v_row."previous_role", 'reason', v_row."reason", 'duration', v_row."duration"::text, 'status', case when v_row."ended_at" is not null then 'ended' else 'granted' end, 'approvalId', v_row."approval_id", 'grantedAt', v_row."granted_at", 'expiresAt', v_row."expires_at", 'endedAt', v_row."ended_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."review_emergency_access"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."review_emergency_access"(uuid, text, text) to authenticated, service_role;

-- Emergency accesses in an organization, newest first; by default the ones
-- nobody has reviewed. Empty for a caller without access_requests.review.
create or replace function "better_supabase"."list_emergency_access"(tenant uuid, unreviewed boolean default true, page_size integer default null, before timestamptz default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
  select coalesce(jsonb_agg(item order by created desc), '[]'::jsonb)
  from (
    select jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'userId', r."user_id", 'role', r."role", 'target', r."target", 'subjectType', r."subject_type", 'subjectId', r."subject_id", 'action', r."action", 'emergency', r."emergency", 'review', case when r."reviewed_at" is null then null else jsonb_build_object('verdict', r."review_verdict", 'note', r."review_note", 'reviewedBy', r."reviewed_by", 'reviewedAt', r."reviewed_at") end, 'previousRole', r."previous_role", 'reason', r."reason", 'duration', r."duration"::text, 'status', case when r."ended_at" is not null then 'ended' else 'granted' end, 'approvalId', r."approval_id", 'grantedAt', r."granted_at", 'expiresAt', r."expires_at", 'endedAt', r."ended_at", 'createdAt', r."created_at") as item, r."created_at" as created
    from "better_supabase"."access_requests" r
    where r."tenant_id" = list_emergency_access.tenant and r."emergency"
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_emergency_access.tenant, 'access_requests.review'), false))
      and (not coalesce(list_emergency_access.unreviewed, true) or r."reviewed_at" is null)
      and (list_emergency_access.before is null or r."created_at" < list_emergency_access.before)
    order by r."created_at" desc
    limit least(greatest(coalesce(list_emergency_access.page_size, 50), 1), 200)
  ) items
$$;
revoke execute on function "better_supabase"."list_emergency_access"(uuid, boolean, integer, timestamptz) from public, anon;
grant execute on function "better_supabase"."list_emergency_access"(uuid, boolean, integer, timestamptz) to authenticated, service_role;

-- The access requests on one record, newest first: every one for a holder of
-- access_requests.read, a team lead or one of the record's approvers, and the
-- caller's own for anyone else.
create or replace function "better_supabase"."list_record_access_requests"(subject_type text, subject_id text, status text default null, page_size integer default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_all boolean;
begin
  v_tenant := "better_supabase"."record_team_tenant"(list_record_access_requests.subject_type, list_record_access_requests.subject_id);
  if v_tenant is null then
    return '[]'::jsonb;
  end if;
  v_all := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'access_requests.read'), false)
    or coalesce(auth.uid() = any ("better_supabase"."record_team_leads"(list_record_access_requests.subject_type, list_record_access_requests.subject_id)), false)
    or coalesce(auth.uid() = any (case list_record_access_requests.subject_type
      when 'drive_node' then "better_supabase"."drive_access_approvers"(list_record_access_requests.subject_id)
      end), false);
  return (
    select coalesce(jsonb_agg(item order by created desc), '[]'::jsonb)
    from (
      select jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'userId', r."user_id", 'role', r."role", 'target', r."target", 'subjectType', r."subject_type", 'subjectId', r."subject_id", 'action', r."action", 'emergency', r."emergency", 'review', case when r."reviewed_at" is null then null else jsonb_build_object('verdict', r."review_verdict", 'note', r."review_note", 'reviewedBy', r."reviewed_by", 'reviewedAt', r."reviewed_at") end, 'previousRole', r."previous_role", 'reason', r."reason", 'duration', r."duration"::text, 'status', case when r."ended_at" is not null then 'ended' when r."granted_at" is not null then 'granted' else coalesce(x."status", 'pending') end, 'approvalId', r."approval_id", 'grantedAt', r."granted_at", 'expiresAt', r."expires_at", 'endedAt', r."ended_at", 'createdAt', r."created_at") as item, r."created_at" as created
      from "better_supabase"."access_requests" r
      left join "better_supabase"."approval_requests" x on x."id" = r."approval_id"
      where r."tenant_id" = v_tenant and r."target" = 'record'
        and r."subject_type" = list_record_access_requests.subject_type and r."subject_id" = list_record_access_requests.subject_id
        and (v_all or r."user_id" = auth.uid())
        and (list_record_access_requests.status is null or case when r."ended_at" is not null then 'ended' when r."granted_at" is not null then 'granted' else coalesce(x."status", 'pending') end = list_record_access_requests.status)
      order by r."created_at" desc
      limit least(greatest(coalesce(list_record_access_requests.page_size, 50), 1), 200)
    ) items
  );
end;
$$;
revoke execute on function "better_supabase"."list_record_access_requests"(text, text, text, integer) from public, anon;
grant execute on function "better_supabase"."list_record_access_requests"(text, text, text, integer) to authenticated, service_role;

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

create or replace function "api"."request_record_access"(subject_type text, subject_id text, action text default 'read', reason text default null, duration interval default interval '7 days')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."request_record_access"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."request_record_access"(text, text, text, text, interval) from public, anon;
grant execute on function "api"."request_record_access"(text, text, text, text, interval) to authenticated, service_role;

create or replace function "api"."open_emergency_access"(subject_type text, subject_id text, reason text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."open_emergency_access"($1, $2, $3) $$;
revoke execute on function "api"."open_emergency_access"(text, text, text) from public, anon;
grant execute on function "api"."open_emergency_access"(text, text, text) to authenticated, service_role;

create or replace function "api"."review_emergency_access"(request_id uuid, verdict text, note text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."review_emergency_access"($1, $2, $3) $$;
revoke execute on function "api"."review_emergency_access"(uuid, text, text) from public, anon;
grant execute on function "api"."review_emergency_access"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."list_emergency_access"(tenant uuid, unreviewed boolean default true, page_size integer default null, before timestamptz default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_emergency_access"($1, $2, $3, $4) $$;
revoke execute on function "api"."list_emergency_access"(uuid, boolean, integer, timestamptz) from public, anon;
grant execute on function "api"."list_emergency_access"(uuid, boolean, integer, timestamptz) to authenticated, service_role;

create or replace function "api"."list_record_access_requests"(subject_type text, subject_id text, status text default null, page_size integer default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_record_access_requests"($1, $2, $3, $4) $$;
revoke execute on function "api"."list_record_access_requests"(text, text, text, integer) from public, anon;
grant execute on function "api"."list_record_access_requests"(text, text, text, integer) to authenticated, service_role;

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
