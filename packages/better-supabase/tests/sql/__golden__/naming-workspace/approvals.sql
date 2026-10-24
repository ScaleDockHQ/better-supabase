-- ==== schema supabase/schemas/900_better_supabase_077_approvals.sql
-- better-supabase module: approvals
-- @bsb-block approvals@1 managed
-- @bsb-hash sha256:fd02cec607ec21b455fcbc422543c4f5c2404bff5173639f431de9f52eeb0517
-- Approval requests with steps per subject type and action: approvers by permission, role, team or user, a required count, delegation, expiry and reminders. The final approval runs a state-machine transition or a job.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."approval_requests";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."approval_decisions";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."approval_requests" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "action" text not null,
  "policy" jsonb not null,
  "step" integer not null default 0 check ("step" >= 0),
  "status" text not null default 'pending' check ("status" in ('pending', 'approved', 'rejected', 'cancelled', 'expired')),
  "requested_by" uuid,
  "reason" text check ("reason" is null or length("reason") <= 2000),
  "payload" jsonb not null default '{}'::jsonb,
  "expires_at" timestamptz,
  "reminded_at" timestamptz,
  "decided_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create unique index if not exists "approval_requests_pending_idx" on "better_supabase"."approval_requests" ("subject_type", "subject_id", "action") where "status" = 'pending';
create index if not exists "approval_requests_tenant_idx" on "better_supabase"."approval_requests" ("tenant_id", "status", "created_at" desc);
alter table "better_supabase"."approval_requests" enable row level security;
revoke all on "better_supabase"."approval_requests" from anon, authenticated;
grant select on "better_supabase"."approval_requests" to authenticated;
grant all on "better_supabase"."approval_requests" to service_role;
drop policy if exists approval_requests_read on "better_supabase"."approval_requests";
create policy approval_requests_read on "better_supabase"."approval_requests" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('approvals.read')) or "requested_by" = (select auth.uid()));

create table if not exists "better_supabase"."approval_decisions" (
  "id" uuid primary key default gen_random_uuid(),
  "request_id" uuid not null references "better_supabase"."approval_requests" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "step" integer not null,
  "approver" uuid,
  "decision" text not null check ("decision" in ('approved', 'rejected', 'delegated')),
  "delegate_to" uuid,
  "comment" text check ("comment" is null or length("comment") <= 2000),
  "created_at" timestamptz not null default clock_timestamp(),
  check (("decision" = 'delegated') = ("delegate_to" is not null)),
  unique ("request_id", "step", "approver")
);
create index if not exists "approval_decisions_delegate_idx" on "better_supabase"."approval_decisions" ("delegate_to") where "delegate_to" is not null;
alter table "better_supabase"."approval_decisions" enable row level security;
revoke all on "better_supabase"."approval_decisions" from anon, authenticated;
grant select on "better_supabase"."approval_decisions" to authenticated;
grant all on "better_supabase"."approval_decisions" to service_role;
drop policy if exists approval_decisions_read on "better_supabase"."approval_decisions";
create policy approval_decisions_read on "better_supabase"."approval_decisions" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('approvals.read')));

-- The policy a new request snapshots, from options.policies.
create or replace function "better_supabase"."approval_policy"(subject_type text, action text)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select null::jsonb
$$;
revoke execute on function "better_supabase"."approval_policy"(text, text) from public, anon;
grant execute on function "better_supabase"."approval_policy"(text, text) to authenticated, service_role;

-- Whether the caller may decide the request's current step: a named user,
-- a holder of the permission, a member with the role or in the team, or a
-- delegate. The requester can't, unless the policy allows self-approval.
create or replace function "better_supabase"."approval_eligible"(request_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_req "better_supabase"."approval_requests"%rowtype;
  v_approvers jsonb;
  v_me uuid := auth.uid();
begin
  select * into v_req from "better_supabase"."approval_requests" r where r."id" = approval_eligible.request_id;
  if not found or v_me is null or v_req."status" <> 'pending' then
    return false;
  end if;
  if v_me = v_req."requested_by" and not coalesce((v_req."policy" ->> 'selfApproval')::boolean, false) then
    return false;
  end if;
  if exists (
    select 1 from "better_supabase"."approval_decisions" x
    where x."request_id" = v_req."id" and x."step" = v_req."step" and x."approver" = v_me
  ) then
    return false;
  end if;
  v_approvers := v_req."policy" -> 'steps' -> v_req."step" -> 'approvers';
  return (coalesce(v_approvers -> 'users', '[]'::jsonb) ? v_me::text)
    or (v_approvers ->> 'permission' is not null and coalesce(better_supabase.can('tenant', v_req."tenant_id", v_approvers ->> 'permission'), false))
    or (v_approvers ->> 'role' is not null and exists (
      select 1 from "better_supabase"."memberships" m
      where m."workspace_id" = v_req."tenant_id" and m."user_id" = v_me and m."role" = v_approvers ->> 'role'
    ))
    or (v_approvers ->> 'team' is not null and false)
    or exists (
      select 1 from "better_supabase"."approval_decisions" x
      where x."request_id" = v_req."id" and x."step" = v_req."step"
        and x."decision" = 'delegated' and x."delegate_to" = v_me
    );
end;
$$;
revoke execute on function "better_supabase"."approval_eligible"(uuid) from public, anon;
grant execute on function "better_supabase"."approval_eligible"(uuid) to authenticated, service_role;

-- Notifies the current step's approvers (requested, reminder), a delegate
-- (delegated) or the requester (approved, rejected, expired).
create or replace function "better_supabase"."approval_notify"(request_id uuid, kind text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req "better_supabase"."approval_requests"%rowtype;
  v_approvers jsonb;
  v_permission text;
  v_recipients uuid[] := '{}';
  v_claims text;
begin
  null;
end;
$$;
revoke execute on function "better_supabase"."approval_notify"(uuid, text) from public, anon, authenticated;

-- Runs what the final approval unlocks: the policy's state-machine
-- transition or job, or the grant or decision of the module that filed it.
create or replace function "better_supabase"."approval_finalize"(request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req "better_supabase"."approval_requests"%rowtype;
  v_run jsonb;
begin
  select * into v_req from "better_supabase"."approval_requests" r where r."id" = approval_finalize.request_id;
  v_run := v_req."policy" -> 'run';
  null;
  perform "better_supabase"."approval_notify"(v_req."id", 'approved');
end;
$$;
revoke execute on function "better_supabase"."approval_finalize"(uuid) from public, anon, authenticated;

-- Files a request under an explicit policy snapshot. request_approval and
-- the access-requests module call it after their own checks.
create or replace function "better_supabase"."open_approval"(tenant uuid, subject_type text, subject_id text, action text, policy jsonb, reason text, payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_req "better_supabase"."approval_requests"%rowtype;
begin
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_approval_request"(uuid, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text)', v_hook::oid::regproc)
        using open_approval.tenant, open_approval.subject_type, open_approval.subject_id, open_approval.action;
    end if;
  end;
  insert into "better_supabase"."approval_requests" ("tenant_id", "subject_type", "subject_id", "action", "policy", "requested_by", "reason", "payload", "expires_at")
  values (open_approval.tenant, open_approval.subject_type, open_approval.subject_id, open_approval.action, open_approval.policy, auth.uid(), open_approval.reason, coalesce(open_approval.payload, '{}'::jsonb),
    case when open_approval.policy ->> 'expiresIn' is not null then now() + (open_approval.policy ->> 'expiresIn')::interval end)
  on conflict ("subject_type", "subject_id", "action") where "status" = 'pending' do nothing
  returning * into v_req;
  if not found then
    raise exception 'this record already has a pending request for that action' using errcode = '23505', hint = 'APPROVAL_PENDING';
  end if;
  null;
  perform "better_supabase"."approval_notify"(v_req."id", 'requested');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_approval_request"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_req."id";
    end if;
  end;
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'createdAt', v_req."created_at");
end;
$$;
revoke execute on function "better_supabase"."open_approval"(uuid, text, text, text, jsonb, text, jsonb) from public, anon, authenticated;

drop function if exists "better_supabase"."request_approval"(uuid, text, text, text, text, jsonb, jsonb);
create or replace function "better_supabase"."request_approval"(tenant uuid, subject_type text, subject_id text, action text, reason text default null, payload jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_policy jsonb := "better_supabase"."approval_policy"(request_approval.subject_type, request_approval.action);
begin
  if v_policy is null then
    raise exception 'no approval policy for this subject type and action' using errcode = '22023', hint = 'APPROVAL_POLICY_UNKNOWN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', request_approval.tenant, 'approvals.request'), false) and true)) then
    raise exception 'not allowed to request approval for this record' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  return "better_supabase"."open_approval"(request_approval.tenant, request_approval.subject_type, request_approval.subject_id, request_approval.action, v_policy, request_approval.reason, request_approval.payload);
end;
$$;
revoke execute on function "better_supabase"."request_approval"(uuid, text, text, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."request_approval"(uuid, text, text, text, text, jsonb) to authenticated, service_role;

-- Approves or rejects the current step. Enough approvals move the request
-- to the next step, and the last step runs the policy's action.
create or replace function "better_supabase"."decide_approval"(request_id uuid, decision text, comment text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_req "better_supabase"."approval_requests"%rowtype;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if decide_approval.decision not in ('approved', 'rejected') then
    raise exception 'decision must be approved or rejected' using errcode = '22023', hint = 'APPROVAL_DECISION_INVALID';
  end if;
  select * into v_req from "better_supabase"."approval_requests" r where r."id" = decide_approval.request_id for update;
  if not found then
    raise exception 'approval request not found' using errcode = 'P0002', hint = 'APPROVAL_NOT_FOUND';
  end if;
  if v_req."status" <> 'pending' then
    raise exception 'this request is no longer pending' using errcode = '22023', hint = 'APPROVAL_CLOSED';
  end if;
  if v_req."expires_at" is not null and v_req."expires_at" <= now() then
    raise exception 'this request has expired' using errcode = '22023', hint = 'APPROVAL_EXPIRED';
  end if;
  if not "better_supabase"."approval_eligible"(v_req."id") then
    raise exception 'not an approver for this step' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_approval_decide"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_req."id", decide_approval.decision;
    end if;
  end;
  insert into "better_supabase"."approval_decisions" ("request_id", "tenant_id", "step", "approver", "decision", "comment")
  values (v_req."id", v_req."tenant_id", v_req."step", auth.uid(), decide_approval.decision, decide_approval.comment);
  if decide_approval.decision = 'rejected' then
    update "better_supabase"."approval_requests" r set "status" = 'rejected', "decided_at" = now()
      where r."id" = v_req."id" returning * into v_req;
    null;
    perform "better_supabase"."approval_notify"(v_req."id", 'rejected');
  else
    select count(*) into v_count from "better_supabase"."approval_decisions" x
      where x."request_id" = v_req."id" and x."step" = v_req."step" and x."decision" = 'approved';
    if v_count >= coalesce((v_req."policy" -> 'steps' -> v_req."step" ->> 'required')::integer, 1) then
      if v_req."step" + 1 >= jsonb_array_length(v_req."policy" -> 'steps') then
        update "better_supabase"."approval_requests" r set "status" = 'approved', "decided_at" = now()
          where r."id" = v_req."id" returning * into v_req;
        perform "better_supabase"."approval_finalize"(v_req."id");
      else
        update "better_supabase"."approval_requests" r set "step" = r."step" + 1, "reminded_at" = null
          where r."id" = v_req."id" returning * into v_req;
        perform "better_supabase"."approval_notify"(v_req."id", 'requested');
      end if;
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_approval_decide"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_req."id", v_req."status";
    end if;
  end;
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'createdAt', v_req."created_at");
end;
$$;
revoke execute on function "better_supabase"."decide_approval"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."decide_approval"(uuid, text, text) to authenticated, service_role;

-- Hands the caller's place on the current step to another user.
create or replace function "better_supabase"."delegate_approval"(request_id uuid, to_user uuid, comment text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_req "better_supabase"."approval_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_req from "better_supabase"."approval_requests" r where r."id" = delegate_approval.request_id for update;
  if not found then
    raise exception 'approval request not found' using errcode = 'P0002', hint = 'APPROVAL_NOT_FOUND';
  end if;
  if v_req."status" <> 'pending' then
    raise exception 'this request is no longer pending' using errcode = '22023', hint = 'APPROVAL_CLOSED';
  end if;
  if not "better_supabase"."approval_eligible"(v_req."id") then
    raise exception 'not an approver for this step' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  if delegate_approval.to_user is null or delegate_approval.to_user = auth.uid() or delegate_approval.to_user = v_req."requested_by" then
    raise exception 'delegate to another user than yourself or the requester' using errcode = '22023', hint = 'APPROVAL_DELEGATE_INVALID';
  end if;
  if not exists (
    select 1 from "better_supabase"."memberships" m
    where m."workspace_id" = v_req."tenant_id" and m."user_id" = delegate_approval.to_user
  ) then
    raise exception 'the delegate is not a member of this organization' using errcode = '22023', hint = 'APPROVAL_DELEGATE_INVALID';
  end if;
  insert into "better_supabase"."approval_decisions" ("request_id", "tenant_id", "step", "approver", "decision", "delegate_to", "comment")
  values (v_req."id", v_req."tenant_id", v_req."step", auth.uid(), 'delegated', delegate_approval.to_user, delegate_approval.comment);
  null;
  perform "better_supabase"."approval_notify"(v_req."id", 'delegated');
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'createdAt', v_req."created_at");
end;
$$;
revoke execute on function "better_supabase"."delegate_approval"(uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."delegate_approval"(uuid, uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."cancel_approval"(request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req "better_supabase"."approval_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_req from "better_supabase"."approval_requests" r where r."id" = cancel_approval.request_id for update;
  if not found then
    raise exception 'approval request not found' using errcode = 'P0002', hint = 'APPROVAL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_req."requested_by" = auth.uid() or coalesce(better_supabase.can('tenant', v_req."tenant_id", 'approvals.manage'), false)) then
    raise exception 'only the requester or a manager can cancel this request' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  if v_req."status" <> 'pending' then
    raise exception 'this request is no longer pending' using errcode = '22023', hint = 'APPROVAL_CLOSED';
  end if;
  update "better_supabase"."approval_requests" r set "status" = 'cancelled', "decided_at" = now()
    where r."id" = v_req."id" returning * into v_req;
  null;
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'createdAt', v_req."created_at");
end;
$$;
revoke execute on function "better_supabase"."cancel_approval"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_approval"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."get_approval"(request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_req "better_supabase"."approval_requests"%rowtype;
begin
  select * into v_req from "better_supabase"."approval_requests" r where r."id" = get_approval.request_id;
  if not found then
    raise exception 'approval request not found' using errcode = 'P0002', hint = 'APPROVAL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_req."requested_by" = auth.uid() or "better_supabase"."approval_eligible"(v_req."id")
    or (coalesce(better_supabase.can('tenant', v_req."tenant_id", 'approvals.read'), false) and (true))) then
    raise exception 'approval request not found' using errcode = 'P0002', hint = 'APPROVAL_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'createdAt', v_req."created_at") || jsonb_build_object(
    'canDecide', "better_supabase"."approval_eligible"(v_req."id"),
    'decisions', coalesce((
      select jsonb_agg(jsonb_build_object('id', x."id", 'step', x."step", 'approver', x."approver", 'decision', x."decision", 'delegateTo', x."delegate_to", 'comment', x."comment", 'createdAt', x."created_at") order by x."created_at", x."id")
      from "better_supabase"."approval_decisions" x where x."request_id" = v_req."id"
    ), '[]'::jsonb)
  );
end;
$$;
revoke execute on function "better_supabase"."get_approval"(uuid) from public, anon;
grant execute on function "better_supabase"."get_approval"(uuid) to authenticated, service_role;

-- assigned: only requests whose current step the caller can decide.
create or replace function "better_supabase"."list_approvals"(tenant uuid, status text default 'pending', assigned boolean default false, subject_type text default null, subject_id text default null, page_size integer default 50, before timestamptz default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_rows jsonb;
  v_read boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_approvals.tenant, 'approvals.read'), false);
begin
  select coalesce(jsonb_agg(t.j order by t.at desc, t.id), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'action', x."action", 'status', x."status", 'step', x."step", 'steps', x."policy" -> 'steps', 'requestedBy', x."requested_by", 'reason', x."reason", 'payload', x."payload", 'expiresAt', x."expires_at", 'decidedAt', x."decided_at", 'createdAt', x."created_at") as j, x."created_at" as at, x."id" as id
    from "better_supabase"."approval_requests" x
    where x."tenant_id" = list_approvals.tenant
      and (list_approvals.status is null or x."status" = list_approvals.status)
      and (list_approvals.subject_type is null or x."subject_type" = list_approvals.subject_type)
      and (list_approvals.subject_id is null or x."subject_id" = list_approvals.subject_id)
      and (list_approvals.before is null or x."created_at" < list_approvals.before)
      and case
        when list_approvals.assigned then "better_supabase"."approval_eligible"(x."id")
        else x."requested_by" = auth.uid() or (v_read and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (true))) or "better_supabase"."approval_eligible"(x."id")
      end
    order by x."created_at" desc, x."id"
    limit least(greatest(coalesce(list_approvals.page_size, 50), 1), 200)
  ) t;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_approvals"(uuid, text, boolean, text, text, integer, timestamptz) from public, anon;
grant execute on function "better_supabase"."list_approvals"(uuid, text, boolean, text, text, integer, timestamptz) to authenticated, service_role;

-- Whether the subject's latest request for the action was approved.
create or replace function "better_supabase"."is_approved"(subject_type text, subject_id text, action text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select x."status" = 'approved' from "better_supabase"."approval_requests" x
    where x."subject_type" = is_approved.subject_type and x."subject_id" = is_approved.subject_id and x."action" = is_approved.action
    order by x."created_at" desc limit 1
  ), false)
$$;
revoke execute on function "better_supabase"."is_approved"(text, text, text) from public, anon;
grant execute on function "better_supabase"."is_approved"(text, text, text) to authenticated, service_role;

-- Closes pending requests past expires_at. Run it from pg_cron:
--   select cron.schedule('expire-approvals', '*/15 * * * *', 'select "better_supabase"."expire_approvals"()');
create or replace function "better_supabase"."expire_approvals"(max_requests integer default 500)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req "better_supabase"."approval_requests"%rowtype;
  v_count integer := 0;
begin
  for v_req in
    update "better_supabase"."approval_requests" r set "status" = 'expired', "decided_at" = now()
    where r."id" in (
      select x."id" from "better_supabase"."approval_requests" x
      where x."status" = 'pending' and x."expires_at" <= now()
      order by x."expires_at"
      limit greatest(coalesce(expire_approvals.max_requests, 500), 1)
      for update skip locked
    )
    returning r.*
  loop
    null;
    perform "better_supabase"."approval_notify"(v_req."id", 'expired');
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."expire_approvals"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."expire_approvals"(integer) to service_role;

-- Reminds the approvers of requests pending longer than `after`, once per
-- `after`. Run it from pg_cron like expire_approvals.
create or replace function "better_supabase"."remind_approvals"(after interval default interval '1 day', max_requests integer default 200)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_count integer := 0;
begin
  for v_id in
    update "better_supabase"."approval_requests" r set "reminded_at" = now()
    where r."id" in (
      select x."id" from "better_supabase"."approval_requests" x
      where x."status" = 'pending'
        and (x."expires_at" is null or x."expires_at" > now())
        and x."created_at" <= now() - remind_approvals.after
        and (x."reminded_at" is null or x."reminded_at" <= now() - remind_approvals.after)
      order by x."created_at"
      limit greatest(coalesce(remind_approvals.max_requests, 200), 1)
      for update skip locked
    )
    returning r."id"
  loop
    perform "better_supabase"."approval_notify"(v_id, 'reminder');
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."remind_approvals"(interval, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."remind_approvals"(interval, integer) to service_role;

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_workspace_ids(text[])') is null then
    create function better_supabase.member_workspace_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."approval_requests";
create policy bsb_tenant_scope on "better_supabase"."approval_requests" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('approvals.read')) or "requested_by" = (select auth.uid()))
  )
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."approval_decisions";
create policy bsb_tenant_scope on "better_supabase"."approval_decisions" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('approvals.read')))
  )
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));

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

-- ==== data supabase/better-supabase-data/900_better_supabase_077_approvals.sql
-- better-supabase module: approvals
-- @bsb-block-data approvals
-- @bsb-hash sha256:42c6ed9866679559107e98b7c390497981bf36b42dc763f3dc29712a073bb21e
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('approvals', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
