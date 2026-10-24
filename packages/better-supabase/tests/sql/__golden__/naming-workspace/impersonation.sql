-- ==== schema supabase/schemas/900_better_supabase_020_impersonation.sql
-- better-supabase module: impersonation
-- @bsb-block impersonation@2 managed
-- @bsb-hash sha256:9e47a5e83f4b4103c4f963ac4b9b2ca87cc59296e3c881bee1cdcc7fdbf37ca6
-- Lets platform staff view the app as a user: time-limited, read-only by default, gated by is_platform() and a second admin's approval, recorded in the audit log, with the target's claims built by your access token hook.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."support_sessions";
  exception when undefined_table then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."support_requests";
  exception when undefined_table then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."support_sessions" (
  "id" uuid primary key default gen_random_uuid(),
  -- Sessions outlive a deleted user, so the record of who viewed whom stays.
  "admin_id" uuid references auth.users (id) on delete set null,
  "target_user_id" uuid references auth.users (id) on delete set null,
  "reason" text not null,
  "workspace_id" uuid,
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
drop policy if exists bsb_support_read on "better_supabase"."support_sessions";
create policy bsb_support_read on "better_supabase"."support_sessions" for select to authenticated
  using ((select "better_supabase"."is_platform"('support.read')));
grant select on "better_supabase"."support_sessions" to authenticated;

-- A support session waits for a second admin: the requester asks here, and
-- another admin approves. Rows are written only through the functions below.
create table if not exists "better_supabase"."support_requests" (
  "id" uuid primary key default gen_random_uuid(),
  "admin_id" uuid not null references auth.users (id) on delete cascade,
  "target_user_id" uuid not null references auth.users (id) on delete cascade,
  "reason" text not null,
  "workspace_id" uuid,
  "read_only" boolean not null default true,
  "metadata" jsonb not null default '{}',
  "requested_at" timestamptz not null default now(),
  "expires_at" timestamptz not null,
  "approved_by" uuid references auth.users (id) on delete set null,
  "approved_at" timestamptz,
  -- The session the approval started; an approval starts one session.
  "session_id" uuid,
  check ("admin_id" <> "target_user_id"),
  constraint support_requests_distinct_approver check ("approved_by" <> "admin_id"),
  check (("approved_by" is null) = ("approved_at" is null))
);
create index if not exists support_requests_admin_idx on "better_supabase"."support_requests" ("admin_id", "target_user_id", "requested_at" desc);
create index if not exists support_requests_target_idx on "better_supabase"."support_requests" ("target_user_id");
create index if not exists support_requests_approved_by_idx on "better_supabase"."support_requests" ("approved_by");
alter table "better_supabase"."support_requests" enable row level security;
revoke all on "better_supabase"."support_requests" from anon, authenticated;
grant select on "better_supabase"."support_requests" to service_role;
-- The requester reads their own requests; platform staff read every one.
drop policy if exists bsb_support_requests_read on "better_supabase"."support_requests";
create policy bsb_support_requests_read on "better_supabase"."support_requests" for select to authenticated
  using ("admin_id" = (select auth.uid())
    or (select "better_supabase"."is_platform"('support.read')));
grant select on "better_supabase"."support_requests" to authenticated;


-- Asks for a support session. Another admin approves it with
-- approve_support_request before start_support_session accepts it. The
-- service role passes admin_id, and approved_by for an approval the server's
-- authorization hook already decided. Errors carry a code in the hint:
-- SUPPORT_FORBIDDEN, SUPPORT_SELF, SUPPORT_SELF_APPROVAL,
-- SUPPORT_TARGET_MISSING, SUPPORT_REASON_REQUIRED or SUPPORT_WRITES_DISABLED.
create or replace function "better_supabase"."request_support_session"(
  target uuid,
  reason text default null,
  read_only boolean default true,
  metadata jsonb default '{}',
  tenant uuid default null,
  admin_id uuid default null,
  approved_by uuid default null
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
  new_id uuid;
  requested jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if service then
    admin := admin_id;
    if admin is null then
      raise exception 'admin_id is required for the service role' using errcode = '22023', hint = 'SUPPORT_FORBIDDEN';
    end if;
  else
    admin := auth.uid();
    if admin is null or (admin_id is not null and admin_id <> admin) or approved_by is not null
      or not "better_supabase"."is_platform"('support.start') then
      raise exception 'Not allowed to ask for a support session' using errcode = '42501', hint = 'SUPPORT_FORBIDDEN';
    end if;
  end if;
  if target = admin then
    raise exception 'An admin cannot start a support session as themselves' using errcode = '22023', hint = 'SUPPORT_SELF';
  end if;
  if approved_by = admin then
    raise exception 'An admin cannot approve their own support session' using errcode = '42501', hint = 'SUPPORT_SELF_APPROVAL';
  end if;
  if not exists (select 1 from auth.users u where u.id = target) then
    raise exception 'No user %', target using errcode = 'P0002', hint = 'SUPPORT_TARGET_MISSING';
  end if;
  if coalesce(btrim(reason), '') = '' then
    raise exception 'A reason is required' using errcode = '22023', hint = 'SUPPORT_REASON_REQUIRED';
  end if;
  if not coalesce(read_only, true) then
    raise exception 'Support sessions are read-only (blocks.impersonation.options.allowWrites)' using errcode = '42501', hint = 'SUPPORT_WRITES_DISABLED';
  end if;
  insert into "better_supabase"."support_requests" ("admin_id", "target_user_id", "reason", "workspace_id", "read_only", "metadata", "expires_at", "approved_by", "approved_at")
  values (admin, target, coalesce(btrim(reason), ''), tenant, coalesce(read_only, true), coalesce(metadata, '{}'),
    now() + '1 hour'::interval, approved_by, case when approved_by is null then null else now() end)
  returning "id" into new_id;
  select jsonb_build_object(
    'id', x."id",
    'admin_id', x."admin_id",
    'target_user_id', x."target_user_id",
    'reason', x."reason",
    'tenant', x."workspace_id",
    'read_only', x."read_only",
    'metadata', x."metadata",
    'requested_at', x."requested_at",
    'expires_at', x."expires_at",
    'approved_by', x."approved_by",
    'approved_at', x."approved_at",
    'session_id', x."session_id"
  ) into requested from "better_supabase"."support_requests" x where x."id" = new_id;
  return requested;
end;
$$;

-- Approves a waiting request as a second admin. The requester never approves
-- their own request; the service role passes approver_id for an approver the
-- server's approverOf hook already allowed. Approving again as the same
-- approver returns the row. Errors carry a code in the hint:
-- SUPPORT_FORBIDDEN, SUPPORT_SELF_APPROVAL, SUPPORT_REQUEST_MISSING,
-- SUPPORT_REQUEST_CLOSED or SUPPORT_REQUEST_DECIDED.
create or replace function "better_supabase"."approve_support_request"(
  request_id uuid,
  approver_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  approver uuid;
  v_row "better_supabase"."support_requests";
begin
  perform better_supabase.raise_actor_readonly() where not better_supabase.actor_may_write();
  if service then
    approver := approver_id;
    if approver is null then
      raise exception 'approver_id is required for the service role' using errcode = '22023', hint = 'SUPPORT_FORBIDDEN';
    end if;
  else
    approver := auth.uid();
    if approver is null or (approver_id is not null and approver_id <> approver) then
      raise exception 'Not allowed to approve a support session' using errcode = '42501', hint = 'SUPPORT_FORBIDDEN';
    end if;
  end if;
  select * into v_row from "better_supabase"."support_requests" x where x."id" = request_id for update;
  if not found then
    raise exception 'No support request %', request_id using errcode = 'P0002', hint = 'SUPPORT_REQUEST_MISSING';
  end if;
  if v_row."admin_id" = approver then
    raise exception 'An admin cannot approve their own support session' using errcode = '42501', hint = 'SUPPORT_SELF_APPROVAL';
  end if;
  if not service and not "better_supabase"."is_platform"('support.start') then
    raise exception 'Not allowed to approve this support session' using errcode = '42501', hint = 'SUPPORT_FORBIDDEN';
  end if;
  return "better_supabase"."apply_support_approval"(request_id, approver);
end;
$$;

-- Records the approval of a waiting request, once; approve_support_request calls it after its own checks.
create or replace function "better_supabase"."apply_support_approval"(request_id uuid, approver uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."support_requests";
begin
  select * into v_row from "better_supabase"."support_requests" x where x."id" = request_id for update;
  if not found then
    raise exception 'No support request %', request_id using errcode = 'P0002', hint = 'SUPPORT_REQUEST_MISSING';
  end if;
  if approver is null then
    raise exception 'Not allowed to approve a support session' using errcode = '42501', hint = 'SUPPORT_FORBIDDEN';
  end if;
  if v_row."admin_id" = approver then
    raise exception 'An admin cannot approve their own support session' using errcode = '42501', hint = 'SUPPORT_SELF_APPROVAL';
  end if;
  if v_row."approved_by" is not null then
    if v_row."approved_by" = approver then
      return jsonb_build_object(
    'id', v_row."id",
    'admin_id', v_row."admin_id",
    'target_user_id', v_row."target_user_id",
    'reason', v_row."reason",
    'tenant', v_row."workspace_id",
    'read_only', v_row."read_only",
    'metadata', v_row."metadata",
    'requested_at', v_row."requested_at",
    'expires_at', v_row."expires_at",
    'approved_by', v_row."approved_by",
    'approved_at', v_row."approved_at",
    'session_id', v_row."session_id"
  );
    end if;
    raise exception 'Support request % is already approved', request_id using errcode = 'P0001', hint = 'SUPPORT_REQUEST_DECIDED';
  end if;
  if v_row."session_id" is not null or v_row."expires_at" <= now() then
    raise exception 'Support request % has expired or was used', request_id using errcode = 'P0001', hint = 'SUPPORT_REQUEST_CLOSED';
  end if;
  update "better_supabase"."support_requests" x set "approved_by" = approver, "approved_at" = now()
  where x."id" = request_id
  returning * into v_row;
  return jsonb_build_object(
    'id', v_row."id",
    'admin_id', v_row."admin_id",
    'target_user_id', v_row."target_user_id",
    'reason', v_row."reason",
    'tenant', v_row."workspace_id",
    'read_only', v_row."read_only",
    'metadata', v_row."metadata",
    'requested_at', v_row."requested_at",
    'expires_at', v_row."expires_at",
    'approved_by', v_row."approved_by",
    'approved_at', v_row."approved_at",
    'session_id', v_row."session_id"
  );
end;
$$;
revoke execute on function "better_supabase"."apply_support_approval"(uuid, uuid) from public, anon, authenticated;

-- Parameters are positional below: in SQL functions a column name wins over a
-- parameter of the same name.
-- A request, for the service role, its requester and the admins who may approve it.
create or replace function "better_supabase"."support_request"(request_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', x."id",
    'admin_id', x."admin_id",
    'target_user_id', x."target_user_id",
    'reason', x."reason",
    'tenant', x."workspace_id",
    'read_only', x."read_only",
    'metadata', x."metadata",
    'requested_at', x."requested_at",
    'expires_at', x."expires_at",
    'approved_by', x."approved_by",
    'approved_at', x."approved_at",
    'session_id', x."session_id"
  )
  from "better_supabase"."support_requests" x
  where x."id" = $1
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or x."admin_id" = auth.uid() or "better_supabase"."is_platform"('support.start'))
$$;

-- The approved request a start would use, or null; the caller is the admin,
-- or admin_id for the service role.
create or replace function "better_supabase"."approved_support_request"(
  target uuid,
  tenant uuid default null,
  read_only boolean default true,
  admin_id uuid default null
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', x."id",
    'admin_id', x."admin_id",
    'target_user_id', x."target_user_id",
    'reason', x."reason",
    'tenant', x."workspace_id",
    'read_only', x."read_only",
    'metadata', x."metadata",
    'requested_at', x."requested_at",
    'expires_at', x."expires_at",
    'approved_by', x."approved_by",
    'approved_at', x."approved_at",
    'session_id', x."session_id"
  )
  from "better_supabase"."support_requests" x
  where x."admin_id" = case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then $4 else auth.uid() end
    and x."target_user_id" = $1
    and x."workspace_id" is not distinct from $2
    and (not x."read_only" or coalesce($3, true))
    and x."approved_by" is not null
    and x."approved_by" <> case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then $4 else auth.uid() end
    and x."session_id" is null
    and x."expires_at" > now()
  order by x."approved_at" desc
  limit 1
$$;

-- Starts a support session: the admin sees the app as target until it expires
-- or ends. An admin has one active session; starting another ends the first.
-- It needs a request another admin approved (request_support_session, then
-- approve_support_request) for the same target, tenant and read-only flag.
-- Errors carry a code in the hint: SUPPORT_FORBIDDEN, SUPPORT_SELF,
-- SUPPORT_TARGET_MISSING, SUPPORT_TTL, SUPPORT_REASON_REQUIRED, SUPPORT_APPROVAL_REQUIRED.
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
  approval_id uuid;
  approver uuid;
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
    raise exception 'Support sessions are read-only (blocks.impersonation.options.allowWrites)' using errcode = '42501', hint = 'SUPPORT_WRITES_DISABLED';
  end if;
  if coalesce(btrim(reason), '') = '' then
    raise exception 'A reason is required' using errcode = '22023', hint = 'SUPPORT_REASON_REQUIRED';
  end if;
  -- A second admin approved this start: the approval is consumed below.
  select x."id", x."approved_by" into approval_id, approver
  from "better_supabase"."support_requests" x
  where x."admin_id" = admin
    and x."target_user_id" = target
    and x."workspace_id" is not distinct from tenant
    and (not x."read_only" or coalesce(read_only, true))
    and x."approved_by" is not null
    and x."approved_by" <> admin
    and x."session_id" is null
    and x."expires_at" > now()
  order by x."approved_at" desc
  limit 1
  for update;
  if approval_id is null then
    raise exception 'A second admin must approve this support session (approve_support_request)' using errcode = '42501', hint = 'SUPPORT_APPROVAL_REQUIRED';
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
  insert into "better_supabase"."support_sessions" ("admin_id", "target_user_id", "reason", "workspace_id", "read_only", "expires_at", "metadata")
  values (admin, target, coalesce(reason, ''), tenant, read_only, now() + ttl, coalesce(metadata, '{}'))
  returning "id" into session_id;
  update "better_supabase"."support_requests" x set "session_id" = session_id where x."id" = approval_id;
  select jsonb_build_object(
    'id', s."id",
    'admin_id', s."admin_id",
    'target_user_id', s."target_user_id",
    'reason', s."reason",
    'tenant', s."workspace_id",
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
    metadata => jsonb_build_object('session_id', session_id, 'reason', reason, 'read_only', read_only, 'request_id', approval_id, 'approved_by', approver),
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
    'tenant', s."workspace_id",
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
    'tenant', s."workspace_id",
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
    'tenant', s."workspace_id",
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
    'tenant', s."workspace_id",
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
revoke execute on function "better_supabase"."request_support_session"(uuid, text, boolean, jsonb, uuid, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."request_support_session"(uuid, text, boolean, jsonb, uuid, uuid, uuid) to authenticated, service_role;
revoke execute on function "better_supabase"."approve_support_request"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."approve_support_request"(uuid, uuid) to authenticated, service_role;
revoke execute on function "better_supabase"."support_request"(uuid) from public, anon;
grant execute on function "better_supabase"."support_request"(uuid) to authenticated, service_role;
revoke execute on function "better_supabase"."approved_support_request"(uuid, uuid, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."approved_support_request"(uuid, uuid, boolean, uuid) to authenticated, service_role;
revoke execute on function "better_supabase"."support_target_claims"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."support_target_claims"(uuid) to service_role;
revoke execute on function "better_supabase"."expire_support_sessions"() from public, anon, authenticated;
grant execute on function "better_supabase"."expire_support_sessions"() to service_role;

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
drop policy if exists bsb_tenant_scope on "better_supabase"."support_sessions";
create policy bsb_tenant_scope on "better_supabase"."support_sessions" as restrictive
  for all to authenticated
  using (
    "workspace_id" in (select better_supabase.member_workspace_ids())
    or ((select "better_supabase"."is_platform"('support.read')))
  )
  with check ("workspace_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."support_requests";
create policy bsb_tenant_scope on "better_supabase"."support_requests" as restrictive
  for all to authenticated
  using (
    "workspace_id" in (select better_supabase.member_workspace_ids())
    or ("admin_id" = (select auth.uid())
    or (select "better_supabase"."is_platform"('support.read')))
  )
  with check ("workspace_id" in (select better_supabase.member_workspace_ids()));

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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== data supabase/better-supabase-data/900_better_supabase_020_impersonation.sql
-- better-supabase module: impersonation
-- @bsb-block-data impersonation
-- @bsb-hash sha256:5b75ec6020bd1354c5949a5872776c45a105f49ad9d7557d8968fcebf0428695
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('impersonation', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
