-- better-supabase module: approvals
-- @bsb-block approvals@1 managed
-- @bsb-hash sha256:4a7e5e3c8afa420d61765cf7f27e53fcddac5f9c77fbc0de6dba5a2740710c0a
-- Approval requests with steps per subject type and action: approvers by permission, role, team, user or the requester's manager, a required count, delegation, expiry and reminders. Tenants tighten the configured policies with conditions and a confirm or authorize mode, and an approval is consumed once against a request fingerprint. The final approval runs a state-machine transition or a job.
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
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."approval_requests";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."approval_requests";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."approval_requests";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."approval_requests";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."approval_decisions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."approval_decisions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."approval_decisions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."approval_decisions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."approval_decisions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."approval_policies";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."approval_policies";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."approval_policies";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."approval_policies";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."approval_policies";
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
  "fingerprint" text check ("fingerprint" is null or "fingerprint" ~ '^[0-9a-f]{64}$'),
  "consumed_at" timestamptz,
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."approval_requests" add column if not exists "fingerprint" text check ("fingerprint" is null or "fingerprint" ~ '^[0-9a-f]{64}$');
alter table "better_supabase"."approval_requests" add column if not exists "consumed_at" timestamptz;
create unique index if not exists "approval_requests_pending_idx" on "better_supabase"."approval_requests" ("subject_type", "subject_id", "action") where "status" = 'pending';
create index if not exists "approval_requests_tenant_idx" on "better_supabase"."approval_requests" ("tenant_id", "status", "created_at" desc);
alter table "better_supabase"."approval_requests" enable row level security;
revoke all on "better_supabase"."approval_requests" from public, anon, authenticated;
grant select on "better_supabase"."approval_requests" to authenticated;
grant all on "better_supabase"."approval_requests" to service_role;
drop policy if exists approval_requests_read on "better_supabase"."approval_requests";
create policy approval_requests_read on "better_supabase"."approval_requests"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('approvals.read')) and not "subject_type" in ('ai_tool_approval')) or "requested_by" = (select auth.uid()));

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
revoke all on "better_supabase"."approval_decisions" from public, anon, authenticated;
grant select on "better_supabase"."approval_decisions" to authenticated;
grant all on "better_supabase"."approval_decisions" to service_role;
drop policy if exists approval_decisions_read on "better_supabase"."approval_decisions";
create policy approval_decisions_read on "better_supabase"."approval_decisions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('approvals.read')));

-- The policy a new request snapshots, from options.policies.
create or replace function "better_supabase"."approval_policy"(subject_type text, action text)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(case approval_policy.subject_type || ':' || approval_policy.action
    when '*:quote.send' then '{"steps":[],"selfApproval":false,"expiresIn":null,"run":null,"effects":["money-movement"]}'::jsonb
    when 'customer:discount' then '{"steps":[{"approvers":{"permission":"approvals.manage"},"required":1}],"selfApproval":true,"expiresIn":null,"run":null}'::jsonb
    when 'customer:refund' then '{"steps":[],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb
    when 'customer:export' then '{"steps":[{"approvers":{"manager":true},"required":1}],"selfApproval":false,"expiresIn":null,"run":null,"mode":"confirm"}'::jsonb
    when 'drive_node:approve' then '{"steps":[{"approvers":{"permission":"approvals.manage"},"required":1}],"selfApproval":true,"expiresIn":null,"run":null}'::jsonb
    when 'eve_tool_call:add_note' then '{"steps":[{"approvers":{"permission":"approvals.manage"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb
    when 'workflow_run:approve' then '{"steps":[{"approvers":{"permission":"approvals.manage"},"required":1}],"selfApproval":true,"expiresIn":null,"run":null}'::jsonb
    else null::jsonb
  end, case '*:' || approval_policy.action
    when '*:quote.send' then '{"steps":[],"selfApproval":false,"expiresIn":null,"run":null,"effects":["money-movement"]}'::jsonb
    else null::jsonb
  end)
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
  v_step jsonb;
  v_approvers jsonb;
  v_me uuid := auth.uid();
begin
  select * into v_req from "better_supabase"."approval_requests" r where r."id" = approval_eligible.request_id;
  if not found or v_me is null or v_req."status" <> 'pending' then
    return false;
  end if;
  if exists (
    select 1 from "better_supabase"."approval_decisions" x
    where x."request_id" = v_req."id" and x."step" = v_req."step" and x."approver" = v_me
  ) then
    return false;
  end if;
  if v_me = v_req."requested_by" then
    if v_req."policy" ->> 'mode' = 'confirm' then
      return true;
    end if;
    if not coalesce((v_req."policy" ->> 'selfApproval')::boolean, false) then
      return false;
    end if;
  end if;
  if v_req."subject_type" = 'ai_tool_approval' then
    return "better_supabase"."ai_tool_approval_approvable"(v_req."subject_id");
  end if;
  v_step := v_req."policy" -> 'steps' -> v_req."step";
  v_approvers := v_step -> 'approvers';
  if ((coalesce(v_approvers -> 'users', '[]'::jsonb) ? v_me::text)
    or (v_approvers ->> 'permission' is not null and coalesce(better_supabase.can('tenant', v_req."tenant_id", v_approvers ->> 'permission'), false))
    or (v_approvers ->> 'role' is not null and exists (
      select 1 from "public"."memberships" m
      where m."organization_id" = v_req."tenant_id" and m."user_id" = v_me and m."role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = (v_approvers ->> 'role')::text or r."key" = (v_approvers ->> 'role')::text) order by (r."id"::text = (v_approvers ->> 'role')::text) desc limit 1)
    ))
    or (v_approvers ->> 'team' is not null and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = v_approvers ->> 'team' and tm."user_id" = v_me))
    or (coalesce((v_approvers ->> 'manager')::boolean, false) and (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = v_req."tenant_id" and (case when (v_req."policy" ->> 'managerOf') is not null then me."id"::text = (v_req."policy" ->> 'managerOf') else me."user_id" = v_req."requested_by" end)
        and mgr."user_id" is not null and mgr."status" <> 'offboarded'
      limit 1) = v_me, false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = v_req."tenant_id" and mm."user_id" = v_me
    )))) then
    return true;
  end if;
  if coalesce((v_step ->> 'escalated')::boolean, false) then
    v_approvers := v_step -> 'escalateTo';
    if ((coalesce(v_approvers -> 'users', '[]'::jsonb) ? v_me::text)
    or (v_approvers ->> 'permission' is not null and coalesce(better_supabase.can('tenant', v_req."tenant_id", v_approvers ->> 'permission'), false))
    or (v_approvers ->> 'role' is not null and exists (
      select 1 from "public"."memberships" m
      where m."organization_id" = v_req."tenant_id" and m."user_id" = v_me and m."role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = (v_approvers ->> 'role')::text or r."key" = (v_approvers ->> 'role')::text) order by (r."id"::text = (v_approvers ->> 'role')::text) desc limit 1)
    ))
    or (v_approvers ->> 'team' is not null and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = v_approvers ->> 'team' and tm."user_id" = v_me))
    or (coalesce((v_approvers ->> 'manager')::boolean, false) and (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = v_req."tenant_id" and (case when (v_req."policy" ->> 'managerOf') is not null then me."id"::text = (v_req."policy" ->> 'managerOf') else me."user_id" = v_req."requested_by" end)
        and mgr."user_id" is not null and mgr."status" <> 'offboarded'
      limit 1) = v_me, false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = v_req."tenant_id" and mm."user_id" = v_me
    )))) then
      return true;
    end if;
  end if;
  return exists (
      select 1 from "better_supabase"."approval_decisions" x
      where x."request_id" = v_req."id" and x."step" = v_req."step"
        and x."decision" = 'delegated' and x."delegate_to" = v_me
    );
end;
$$;
revoke execute on function "better_supabase"."approval_eligible"(uuid) from public, anon;
grant execute on function "better_supabase"."approval_eligible"(uuid) to authenticated, service_role;

-- Notifies the current step's approvers (requested, reminder), its fallback
-- approvers (escalated), a delegate (delegated) or the requester (approved,
-- rejected, expired).
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
  v_note jsonb;
  v_hook regprocedure;
  v_extra jsonb;
begin
  select * into v_req from "better_supabase"."approval_requests" r where r."id" = approval_notify.request_id;
  if not found then
    return;
  end if;
  if approval_notify.kind in ('approved', 'rejected', 'expired') then
    v_recipients := array[v_req."requested_by"];
    v_permission := null;
  else
    v_approvers := v_req."policy" -> 'steps' -> v_req."step" -> case when approval_notify.kind = 'escalated' then 'escalateTo' else 'approvers' end;
    v_permission := v_approvers ->> 'permission';
    v_recipients := array(
      select x::uuid from jsonb_array_elements_text(coalesce(v_approvers -> 'users', '[]'::jsonb)) x
      union
      select m."user_id" from "public"."memberships" m
      where m."organization_id" = v_req."tenant_id" and m."role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = (v_approvers ->> 'role')::text or r."key" = (v_approvers ->> 'role')::text) order by (r."id"::text = (v_approvers ->> 'role')::text) desc limit 1)
      union
      select tm."user_id" from "better_supabase"."team_members" tm
      where tm."team_id"::text = v_approvers ->> 'team'
      union
      select (select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = v_req."tenant_id" and (case when (v_req."policy" ->> 'managerOf') is not null then me."id"::text = (v_req."policy" ->> 'managerOf') else me."user_id" = v_req."requested_by" end)
        and mgr."user_id" is not null and mgr."status" <> 'offboarded'
      limit 1) where coalesce((v_approvers ->> 'manager')::boolean, false)
      union
      select x."delegate_to" from "better_supabase"."approval_decisions" x
      where x."request_id" = v_req."id" and x."step" = v_req."step" and x."decision" = 'delegated'
    );
    if approval_notify.kind = 'delegated' then
      v_recipients := array(
        select x."delegate_to" from "better_supabase"."approval_decisions" x
        where x."request_id" = v_req."id" and x."step" = v_req."step" and x."decision" = 'delegated'
        order by x."created_at" desc limit 1
      );
      v_permission := null;
    end if;
    -- Approvers who already decided this step aren't asked again.
    v_recipients := array(
      select u from unnest(v_recipients) u
      where not exists (
        select 1 from "better_supabase"."approval_decisions" x
        where x."request_id" = v_req."id" and x."step" = v_req."step" and x."approver" = u
      )
    );
  end if;
  if cardinality(v_recipients) = 0 and v_permission is null then
    return;
  end if;
  v_note := jsonb_build_object(
      'type', 'approval.' || approval_notify.kind,
      'tenant', v_req."tenant_id",
      'actor', coalesce(auth.uid(), v_req."requested_by"),
      'subject_type', v_req."subject_type",
      'subject_id', v_req."subject_id",
      'summary', left(v_req."action" || coalesce(': ' || v_req."reason", ''), 140),
      'recipients', to_jsonb(v_recipients),
      'permission', v_permission,
      'exclude', case when coalesce((v_req."policy" ->> 'selfApproval')::boolean, false) or approval_notify.kind in ('approved', 'rejected', 'expired') then '[]'::jsonb else jsonb_build_array(v_req."requested_by") end,
      'include_actor', approval_notify.kind in ('approved', 'rejected', 'expired'),
      'key', 'approval.' || approval_notify.kind || ':' || v_req."id"::text || ':' || v_req."step"::text || ':' || extract(epoch from now())::bigint::text,
      'data', jsonb_build_object('requestId', v_req."id", 'action', v_req."action", 'step', v_req."step")
    );
  v_hook := to_regprocedure('"public"."approval_notification"(uuid, text, jsonb)');
  if v_hook is not null then
    execute format('select %s($1, $2, $3)', v_hook::oid::regproc) into v_extra
      using v_req."id", approval_notify.kind, v_note;
    if v_extra is null then
      return;
    end if;
    v_note := v_note || (v_extra - 'data') || jsonb_build_object('data', coalesce(v_note -> 'data', '{}'::jsonb) || coalesce(v_extra -> 'data', '{}'::jsonb));
  end if;
  v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."notify"(v_note);
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
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
  if v_req."subject_type" = 'ai_tool_approval' then
    perform "better_supabase"."apply_ai_tool_approval"(v_req."subject_id", true, (select x."comment" from "better_supabase"."approval_decisions" x where x."request_id" = v_req."id" order by x."created_at" desc, x."id" desc limit 1));
  end if;
  if v_req."subject_type" = 'access_request' then
    perform "better_supabase"."grant_access_request"(v_req."subject_id"::uuid);
  end if;
  if v_req."subject_type" = 'timesheet' then
    perform "better_supabase"."approve_timesheet"(v_req."subject_id"::uuid);
  end if;
  if v_req."subject_type" = 'expense_report' then
    perform "better_supabase"."approve_expense_report"(v_req."subject_id"::uuid);
  end if;
  if v_req."subject_type" = 'content_entry' then
    perform "better_supabase"."content_entry_approved"((v_req."subject_id")::uuid);
  end if;
  perform "better_supabase".emit_event('approval.approved', jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step"), 'approval-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/approvals');
  perform better_supabase.audit_event(
    event_type => 'approval.approved',
    category => 'data',
    target_type => 'approval_request',
    record_id => v_req."id"::text,
    summary => 'approved' || ' ' || v_req."action" || ' on ' || v_req."subject_type" || ' ' || v_req."subject_id",
    tenant => (v_req."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step")
  );
  perform "better_supabase"."approval_notify"(v_req."id", 'approved');
end;
$$;
revoke execute on function "better_supabase"."approval_finalize"(uuid) from public, anon, authenticated;

-- Files a request under an explicit policy snapshot. request_approval and
-- the access-requests module call it after their own checks. requested_by
-- defaults to the caller.
drop function if exists "better_supabase"."open_approval"(uuid, text, text, text, jsonb, text, jsonb);
create or replace function "better_supabase"."open_approval"(tenant uuid, subject_type text, subject_id text, action text, policy jsonb, reason text, payload jsonb, requested_by uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_req "better_supabase"."approval_requests"%rowtype;
  v_policy jsonb := open_approval.policy;
  v_requester uuid := coalesce(open_approval.requested_by, auth.uid());
begin
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_approval_request"(uuid, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text)', v_hook::oid::regproc)
        using open_approval.tenant, open_approval.subject_type, open_approval.subject_id, open_approval.action;
    end if;
  end;
  if exists (select 1 from jsonb_array_elements(coalesce(v_policy -> 'steps', '[]'::jsonb)) e where e.value -> 'required' = '"all"'::jsonb) then
    v_policy := jsonb_set(v_policy, '{steps}', (
      select jsonb_agg(case when e.value -> 'required' = '"all"'::jsonb
        then e.value || jsonb_build_object('approvers', jsonb_build_object('users', h.users), 'required', jsonb_array_length(h.users), 'permission', e.value -> 'approvers' ->> 'permission')
        else e.value end order by e.ordinality)
      from jsonb_array_elements(v_policy -> 'steps') with ordinality e
      left join lateral (
        select coalesce(jsonb_agg(distinct to_jsonb(u.id::text)), '[]'::jsonb) as users
        from (select m."user_id" from "public"."memberships" m
        where m."organization_id" = open_approval.tenant
          and coalesce(better_supabase.can_user(m."user_id", 'tenant', open_approval.tenant, (e.value -> 'approvers' ->> 'permission')), false)) as u(id)
        where u.id is not null and (u.id is distinct from v_requester or coalesce((v_policy ->> 'selfApproval')::boolean, false))
      ) h on e.value -> 'required' = '"all"'::jsonb
    ));
    if exists (select 1 from jsonb_array_elements(v_policy -> 'steps') e where e.value -> 'required' = '0'::jsonb) then
      raise exception 'nobody holds the permission a step asks every holder of' using errcode = '22023', hint = 'APPROVAL_APPROVERS_EMPTY';
    end if;
  end if;
  insert into "better_supabase"."approval_requests" ("tenant_id", "subject_type", "subject_id", "action", "policy", "requested_by", "reason", "payload", "expires_at")
  values (open_approval.tenant, open_approval.subject_type, open_approval.subject_id, open_approval.action, v_policy, v_requester, open_approval.reason, coalesce(open_approval.payload, '{}'::jsonb),
    case when open_approval.policy ->> 'expiresIn' is not null then now() + (open_approval.policy ->> 'expiresIn')::interval end)
  on conflict ("subject_type", "subject_id", "action") where "status" = 'pending' do nothing
  returning * into v_req;
  if not found then
    raise exception 'this record already has a pending request for that action' using errcode = '23505', hint = 'APPROVAL_PENDING';
  end if;
  perform "better_supabase".emit_event('approval.requested', jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step"), 'approval-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/approvals');
  perform better_supabase.audit_event(
    event_type => 'approval.requested',
    category => 'data',
    target_type => 'approval_request',
    record_id => v_req."id"::text,
    summary => 'requested' || ' ' || v_req."action" || ' on ' || v_req."subject_type" || ' ' || v_req."subject_id",
    tenant => (v_req."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step")
  );
  perform "better_supabase"."approval_notify"(v_req."id", 'requested');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_approval_request"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_req."id";
    end if;
  end;
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'mode', coalesce(v_req."policy" ->> 'mode', 'authorize'), 'fingerprint', v_req."fingerprint", 'consumedAt', v_req."consumed_at", 'createdAt', v_req."created_at");
end;
$$;
revoke execute on function "better_supabase"."open_approval"(uuid, text, text, text, jsonb, text, jsonb, uuid) from public, anon, authenticated;

-- Closes the pending request for a subject that its own module decided
-- (decide_ai_tool_approval, approve_support_request) without running the
-- module again. A request that is no longer pending is left as it is.
create or replace function "better_supabase"."approval_settle"(subject_type text, subject_id text, action text, decision text, approver uuid, comment text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_req "better_supabase"."approval_requests"%rowtype;
begin
  select * into v_req from "better_supabase"."approval_requests" r
  where r."subject_type" = approval_settle.subject_type and r."subject_id" = approval_settle.subject_id
    and r."action" = approval_settle.action and r."status" = 'pending'
  for update;
  if not found then
    return;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_approval_decide"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_req."id", approval_settle.decision;
    end if;
  end;
  insert into "better_supabase"."approval_decisions" ("request_id", "tenant_id", "step", "approver", "decision", "comment")
  values (v_req."id", v_req."tenant_id", v_req."step", approval_settle.approver, approval_settle.decision, approval_settle.comment)
  on conflict do nothing;
  update "better_supabase"."approval_requests" r set "status" = approval_settle.decision, "decided_at" = now()
    where r."id" = v_req."id" returning * into v_req;
  if approval_settle.decision = 'approved' then
    perform "better_supabase".emit_event('approval.approved', jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step"), 'approval-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/approvals');
  perform better_supabase.audit_event(
    event_type => 'approval.approved',
    category => 'data',
    target_type => 'approval_request',
    record_id => v_req."id"::text,
    summary => 'approved' || ' ' || v_req."action" || ' on ' || v_req."subject_type" || ' ' || v_req."subject_id",
    tenant => (v_req."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step")
  );
  else
    perform "better_supabase".emit_event('approval.rejected', jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step"), 'approval-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/approvals');
  perform better_supabase.audit_event(
    event_type => 'approval.rejected',
    category => 'data',
    target_type => 'approval_request',
    record_id => v_req."id"::text,
    summary => 'rejected' || ' ' || v_req."action" || ' on ' || v_req."subject_type" || ' ' || v_req."subject_id",
    tenant => (v_req."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step")
  );
  end if;
  perform "better_supabase"."approval_notify"(v_req."id", approval_settle.decision);
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_approval_decide"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_req."id", v_req."status";
    end if;
  end;
end;
$$;
revoke execute on function "better_supabase"."approval_settle"(text, text, text, text, uuid, text) from public, anon, authenticated;


create table if not exists "better_supabase"."approval_policies" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "action" text not null,
  "name" text not null check (length("name") between 1 and 200),
  "conditions" jsonb,
  "effect" text,
  "mode" text not null default 'authorize' check ("mode" in ('confirm', 'authorize')),
  "steps" jsonb not null default '[]'::jsonb check (jsonb_typeof("steps") = 'array'),
  "self_approval" boolean not null default false,
  "expires_in" interval check ("expires_in" is null or "expires_in" > interval '0'),
  "enabled" boolean not null default true,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
alter table "better_supabase"."approval_policies" add column if not exists "effect" text;
create index if not exists "approval_policies_lookup_idx" on "better_supabase"."approval_policies" ("tenant_id", "subject_type", "action");
alter table "better_supabase"."approval_policies" add column if not exists "description" text;
alter table "better_supabase"."approval_policies" enable row level security;
revoke all on "better_supabase"."approval_policies" from public, anon, authenticated;
grant select on "better_supabase"."approval_policies" to authenticated;
grant all on "better_supabase"."approval_policies" to service_role;
drop policy if exists approval_policies_read on "better_supabase"."approval_policies";
create policy approval_policies_read on "better_supabase"."approval_policies"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('approvals.read')));

-- Creates or changes a tenant policy. policy is { id?, subjectType, action,
-- name, conditions, mode, steps, selfApproval, expiresIn, enabled }; keys
-- left out keep their value. A tenant policy only adds to the options.policies
-- floor for its subject type and action, so it can never loosen it.
create or replace function "better_supabase"."save_approval_policy"(tenant uuid, policy jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_old "better_supabase"."approval_policies"%rowtype;
  v_row "better_supabase"."approval_policies"%rowtype;
  v_type text;
  v_action text;
  v_conditions jsonb;
  v_steps jsonb;
  v_step jsonb;
  v_fields jsonb;
  v_effect text;
  v_who jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_approval_policy.tenant, 'approvals.manage'), false)) then
    raise exception 'managing approval policies needs approvals.manage' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  if jsonb_typeof(save_approval_policy.policy) is distinct from 'object' then
    raise exception 'policy must be an object' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
  end if;
  if save_approval_policy.policy ? 'id' then
    select * into v_old from "better_supabase"."approval_policies" x
    where x."id" = (save_approval_policy.policy ->> 'id')::uuid and x."tenant_id" is not distinct from save_approval_policy.tenant
    for update;
    if not found then
      raise exception 'approval policy not found' using errcode = 'P0002', hint = 'APPROVAL_POLICY_NOT_FOUND';
    end if;
  end if;
  v_type := coalesce(save_approval_policy.policy ->> 'subjectType', v_old."subject_type");
  v_action := coalesce(save_approval_policy.policy ->> 'action', v_old."action");
  v_effect := case when save_approval_policy.policy ? 'effect' then nullif(save_approval_policy.policy ->> 'effect', '') else v_old."effect" end;
  if v_type is null or v_action is null or not (exists (
      select 1 from jsonb_array_elements('[{"subjectType":"*","action":"quote.send","effects":["money-movement"]},{"subjectType":"customer","action":"discount","effects":[]},{"subjectType":"customer","action":"refund","effects":[]},{"subjectType":"customer","action":"export","effects":[]},{"subjectType":"drive_node","action":"approve","effects":[]},{"subjectType":"eve_tool_call","action":"add_note","effects":[]},{"subjectType":"workflow_run","action":"approve","effects":[]}]'::jsonb) f
      where (v_type = '*' or f.value ->> 'subjectType' in (v_type, '*'))
        and (v_action = '*' or f.value ->> 'action' in (v_action, '*'))
        and (v_effect is null or f.value -> 'effects' ? v_effect)
    )) then
    raise exception 'a tenant policy tightens an options.policies entry, and there is none for this subject type, action and effect' using errcode = '22023', hint = 'APPROVAL_POLICY_UNKNOWN';
  end if;
  v_conditions := case when save_approval_policy.policy ? 'conditions' then nullif(save_approval_policy.policy -> 'conditions', 'null'::jsonb) else v_old."conditions" end;
  if v_conditions is not null then
    v_fields := "better_supabase"."rule_field_map"(v_type);
    if v_fields = '{}'::jsonb then
      raise exception 'no rule fields for this subject type; sync them first' using errcode = '22023', hint = 'APPROVAL_FIELDS_MISSING';
    end if;
    perform "better_supabase"."rule_check"(v_conditions, v_fields, 1);
  end if;
  v_steps := coalesce(save_approval_policy.policy -> 'steps', v_old."steps", '[]'::jsonb);
  if jsonb_typeof(v_steps) <> 'array' or jsonb_array_length(v_steps) > 20 then
    raise exception 'steps must be a list of { approvers: { permission, role, team, users, manager }, required, escalateAfter, escalateTo } objects' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
  end if;
  for v_step in select * from jsonb_array_elements(v_steps) loop
    if jsonb_typeof(v_step) <> 'object' then
      raise exception 'steps must be a list of { approvers: { permission, role, team, users, manager }, required, escalateAfter, escalateTo } objects' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
    end if;
    for v_who in select a.w from (values (v_step -> 'approvers', true), (v_step -> 'escalateTo', v_step ? 'escalateTo')) a(w, checked) where a.checked loop
      if jsonb_typeof(v_who) is distinct from 'object'
        or not (v_who ?| array['permission', 'role', 'team', 'users', 'manager'])
        or (v_who ? 'manager' and v_who -> 'manager' <> 'true'::jsonb)
        or (v_who ? 'users' and (jsonb_typeof(v_who -> 'users') <> 'array'
          or exists (select 1 from jsonb_array_elements(v_who -> 'users') u
            where jsonb_typeof(u) <> 'string' or u #>> '{}' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'))) then
        raise exception 'steps must be a list of { approvers: { permission, role, team, users, manager }, required, escalateAfter, escalateTo } objects' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
      end if;
    end loop;
    if (v_step ? 'required' and v_step -> 'required' <> '"all"'::jsonb and (jsonb_typeof(v_step -> 'required') <> 'number' or (v_step ->> 'required')::numeric < 1
        or (v_step ->> 'required')::numeric <> trunc((v_step ->> 'required')::numeric)))
      or (v_step -> 'required' = '"all"'::jsonb and (v_step -> 'approvers') - 'permission' <> '{}'::jsonb
        and ((v_step -> 'approvers') - 'users' <> '{}'::jsonb or jsonb_array_length(v_step -> 'approvers' -> 'users') = 0))
      or (jsonb_typeof(v_step -> 'required') = 'number' and (v_step -> 'approvers') - 'users' = '{}'::jsonb
        and (v_step ->> 'required')::numeric > jsonb_array_length(v_step -> 'approvers' -> 'users'))
      or ((v_step ? 'escalateAfter') <> (v_step ? 'escalateTo'))
      or (v_step ? 'escalateAfter' and (jsonb_typeof(v_step -> 'escalateAfter') <> 'string' or (v_step ->> 'escalateAfter')::interval <= interval '0')) then
      raise exception 'steps must be a list of { approvers: { permission, role, team, users, manager }, required, escalateAfter, escalateTo } objects' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
    end if;
  end loop;
  v_steps := (select coalesce(jsonb_agg(case when s -> 'required' = '"all"'::jsonb and (s -> 'approvers') ? 'users'
    then jsonb_set(s, '{required}', to_jsonb(jsonb_array_length(s -> 'approvers' -> 'users'))) else s end order by o), '[]'::jsonb)
    from jsonb_array_elements(v_steps) with ordinality e(s, o));
  if coalesce(save_approval_policy.policy ->> 'mode', v_old."mode"::text, 'authorize') not in ('confirm', 'authorize') then
    raise exception 'mode must be confirm or authorize' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
  end if;
  if v_old."id" is null then
    insert into "better_supabase"."approval_policies" ("tenant_id", "subject_type", "action", "name", "conditions", "effect", "mode", "steps", "self_approval", "expires_in", "enabled", "created_by", "description")
    values (save_approval_policy.tenant, v_type, v_action, btrim(save_approval_policy.policy ->> 'name'), v_conditions, v_effect,
      coalesce(save_approval_policy.policy ->> 'mode', 'authorize'), v_steps,
      coalesce((save_approval_policy.policy ->> 'selfApproval')::boolean, false), (save_approval_policy.policy ->> 'expiresIn')::interval,
      coalesce((save_approval_policy.policy ->> 'enabled')::boolean, true), auth.uid(), (jsonb_populate_record(null::"better_supabase"."approval_policies", jsonb_build_object('description', coalesce(save_approval_policy.policy -> 'fields', '{}'::jsonb) -> 'description')))."description")
    returning * into v_row;
  else
    update "better_supabase"."approval_policies" x set
      "subject_type" = v_type,
      "action" = v_action,
      "name" = coalesce(btrim(save_approval_policy.policy ->> 'name'), x."name"),
      "conditions" = v_conditions,
      "effect" = v_effect,
      "mode" = coalesce(save_approval_policy.policy ->> 'mode', x."mode"),
      "steps" = v_steps,
      "self_approval" = coalesce((save_approval_policy.policy ->> 'selfApproval')::boolean, x."self_approval"),
      "expires_in" = case when save_approval_policy.policy ? 'expiresIn' then (save_approval_policy.policy ->> 'expiresIn')::interval else x."expires_in" end,
      "enabled" = coalesce((save_approval_policy.policy ->> 'enabled')::boolean, x."enabled"),
      "updated_at" = now(), "description" = case when (save_approval_policy.policy -> 'fields') ? 'description' then (jsonb_populate_record(null::"better_supabase"."approval_policies", jsonb_build_object('description', (save_approval_policy.policy -> 'fields') -> 'description')))."description" else x."description" end
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  perform "better_supabase".emit_event('approval_policy.saved', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'subjectType', v_row."subject_type", 'action', v_row."action"), 'approval-policies/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/approvals');
  perform better_supabase.audit_event(
    event_type => 'approval_policy.saved',
    category => 'configuration',
    target_type => 'approval_policy',
    record_id => v_row."id"::text,
    summary => 'saved approval policy ' || v_row."name",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'subjectType', v_row."subject_type", 'action', v_row."action")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'action', v_row."action", 'effect', v_row."effect", 'name', v_row."name", 'conditions', v_row."conditions", 'mode', v_row."mode", 'steps', v_row."steps", 'selfApproval', v_row."self_approval", 'expiresIn', v_row."expires_in"::text, 'enabled', v_row."enabled", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'fields', jsonb_build_object('description', v_row."description"));
exception
  when invalid_text_representation or invalid_datetime_format or not_null_violation or check_violation then
    raise exception 'policy has an invalid name, mode, expiry or flag' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
end;
$$;
revoke execute on function "better_supabase"."save_approval_policy"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_approval_policy"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."remove_approval_policy"(policy_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."approval_policies"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."approval_policies" x where x."id" = remove_approval_policy.policy_id;
  if not found then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'approvals.manage'), false)) then
    raise exception 'managing approval policies needs approvals.manage' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  delete from "better_supabase"."approval_policies" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('approval_policy.removed', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'subjectType', v_row."subject_type", 'action', v_row."action"), 'approval-policies/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/approvals');
  perform better_supabase.audit_event(
    event_type => 'approval_policy.removed',
    category => 'configuration',
    target_type => 'approval_policy',
    record_id => v_row."id"::text,
    summary => 'removed approval policy ' || v_row."name",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'subjectType', v_row."subject_type", 'action', v_row."action")
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."remove_approval_policy"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_approval_policy"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_approval_policies"(tenant uuid, subject_type text default null, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_approval_policies.tenant, 'approvals.read'), false)) then
    raise exception 'reading approval policies needs approvals.read' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'action', x."action", 'effect', x."effect", 'name', x."name", 'conditions', x."conditions", 'mode', x."mode", 'steps', x."steps", 'selfApproval', x."self_approval", 'expiresIn', x."expires_in"::text, 'enabled', x."enabled", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'fields', jsonb_build_object('description', x."description")) order by x."subject_type", x."action", x."created_at", x."id")
    from (
      select * from "better_supabase"."approval_policies" y
      where (y."tenant_id" = list_approval_policies.tenant or (list_approval_policies.tenant is null and y."tenant_id" is null))
        and (list_approval_policies.subject_type is null or y."subject_type" = list_approval_policies.subject_type)
      order by y."subject_type", y."action", y."created_at", y."id"
      limit least(greatest(coalesce(list_approval_policies.page_size, 100), 1), 500)
    ) x
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_approval_policies"(uuid, text, integer) from public, anon;
grant execute on function "better_supabase"."list_approval_policies"(uuid, text, integer) to authenticated, service_role;

-- The policy a request snapshots: the options.policies floor, tightened by
-- every enabled tenant policy whose conditions match the request payload.
-- A policy matches its subject type and action, `*` for any, and the
-- floor's effects when it names one. Steps add up, the stricter mode wins,
-- self-approval needs every policy to allow it and the shortest expiry
-- applies.
create or replace function "better_supabase"."approval_effective_policy"(tenant uuid, subject_type text, action text, subject jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_floor jsonb := "better_supabase"."approval_policy"(approval_effective_policy.subject_type, approval_effective_policy.action);
  v_row "better_supabase"."approval_policies"%rowtype;
  v_steps jsonb;
  v_level integer;
  v_self boolean;
  v_expires interval;
  v_ids jsonb := '[]'::jsonb;
  v_fields jsonb;
  v_effects jsonb;
  v_matched boolean := true;
begin
  if v_floor is null then
    return null;
  end if;
  v_effects := coalesce(v_floor -> 'effects', '[]'::jsonb);
  v_steps := coalesce(v_floor -> 'steps', '[]'::jsonb);
  v_level := case when coalesce(v_floor ->> 'mode', 'authorize') = 'authorize' and jsonb_array_length(v_steps) > 0 then 2 when coalesce(v_floor ->> 'mode', 'authorize') = 'confirm' then 1 else 0 end;
  v_self := coalesce((v_floor ->> 'selfApproval')::boolean, false);
  v_expires := (v_floor ->> 'expiresIn')::interval;
  for v_row in
    select * from "better_supabase"."approval_policies" x
    where (x."tenant_id" = approval_effective_policy.tenant)
      and (x."subject_type" = approval_effective_policy.subject_type or x."subject_type" = '*')
      and (x."action" = approval_effective_policy.action or x."action" = '*')
      and (x."effect" is null or v_effects ? x."effect")
      and x."enabled"
    order by x."created_at", x."id"
  loop
    if v_row."conditions" is not null then
      if v_fields is null then
        v_fields := "better_supabase"."rule_field_map"(approval_effective_policy.subject_type);
      end if;
      if not "better_supabase"."rule_matches"(v_row."conditions", coalesce(approval_effective_policy.subject, '{}'::jsonb), v_fields, 'UTC', now()) then
        continue;
      end if;
    end if;
    v_matched := true;
    v_steps := v_steps || v_row."steps";
    v_level := greatest(v_level, case when v_row."mode"::text = 'authorize' and jsonb_array_length(v_row."steps") > 0 then 2 when v_row."mode"::text = 'confirm' then 1 else 0 end);
    v_self := v_self and v_row."self_approval";
    v_expires := least(v_expires, v_row."expires_in");
    v_ids := v_ids || to_jsonb(v_row."id");
  end loop;
  if not v_matched then
    return null;
  end if;
  return jsonb_build_object(
    'steps', v_steps, 'selfApproval', v_self, 'expiresIn', v_expires::text, 'run', v_floor -> 'run',
    'mode', case when v_level = 1 then 'confirm' else 'authorize' end, 'policies', v_ids
  ) || case when jsonb_array_length(v_effects) > 0 then jsonb_build_object('effects', v_effects) else '{}'::jsonb end;
end;
$$;
revoke execute on function "better_supabase"."approval_effective_policy"(uuid, text, text, jsonb) from public, anon, authenticated;

-- What a request for the subject type and action would need right now, with
-- subject as the request payload the tenant policies' conditions read; null
-- when nothing is required.
create or replace function "better_supabase"."approval_requirement"(tenant uuid, subject_type text, action text, subject jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_policy jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', approval_requirement.tenant, 'approvals.request'), false)) then
    raise exception 'checking an approval requirement needs approvals.request' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  v_policy := "better_supabase"."approval_effective_policy"(approval_requirement.tenant, approval_requirement.subject_type, approval_requirement.action, approval_requirement.subject);
  if v_policy is null or not (coalesce(v_policy ->> 'mode', 'authorize') = 'confirm' or jsonb_array_length(coalesce(v_policy -> 'steps', '[]'::jsonb)) > 0) then
    return null;
  end if;
  return v_policy || jsonb_build_object('mode', coalesce(v_policy ->> 'mode', 'authorize'));
end;
$$;
revoke execute on function "better_supabase"."approval_requirement"(uuid, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."approval_requirement"(uuid, text, text, jsonb) to authenticated, service_role;

-- An app's own policy for one request, tightened by the policy the request
-- would get anyway (base, null when there is none): steps add up, the stricter
-- mode wins, self-approval needs both to allow it and the shorter expiry
-- applies. It never loosens base.
create or replace function "better_supabase"."approval_policy_tighten"(base jsonb, own jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_step jsonb;
  v_who jsonb;
  v_mode text := coalesce(approval_policy_tighten.own ->> 'mode', 'authorize');
  v_steps jsonb := coalesce(approval_policy_tighten.own -> 'steps', '[]'::jsonb);
  v_level integer;
  v_expires interval;
begin
  if jsonb_typeof(approval_policy_tighten.own) is distinct from 'object'
    or jsonb_typeof(v_steps) <> 'array' or jsonb_array_length(v_steps) > 20
    or v_mode not in ('confirm', 'authorize')
    or (approval_policy_tighten.own ? 'selfApproval' and jsonb_typeof(approval_policy_tighten.own -> 'selfApproval') <> 'boolean')
    or (approval_policy_tighten.own ? 'managerOf' and jsonb_typeof(approval_policy_tighten.own -> 'managerOf') <> 'string')
    or (approval_policy_tighten.own ->> 'expiresIn' is not null and (approval_policy_tighten.own ->> 'expiresIn')::interval <= interval '0') then
    raise exception 'policy must be { steps: [{ approvers: { permission, role, team, users, manager }, required, escalateAfter, escalateTo }], mode, selfApproval, expiresIn, managerOf }' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
  end if;
  for v_step in select * from jsonb_array_elements(v_steps) loop
    if jsonb_typeof(v_step) <> 'object' then
      raise exception 'policy must be { steps: [{ approvers: { permission, role, team, users, manager }, required, escalateAfter, escalateTo }], mode, selfApproval, expiresIn, managerOf }' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
    end if;
    for v_who in select a.w from (values (v_step -> 'approvers', true), (v_step -> 'escalateTo', v_step ? 'escalateTo')) a(w, checked) where a.checked loop
      if jsonb_typeof(v_who) is distinct from 'object'
        or not (v_who ?| array['permission', 'role', 'team', 'users', 'manager'])
        or (v_who ? 'manager' and v_who -> 'manager' <> 'true'::jsonb)
        or (v_who ? 'users' and (jsonb_typeof(v_who -> 'users') <> 'array'
          or exists (select 1 from jsonb_array_elements(v_who -> 'users') u
            where jsonb_typeof(u) <> 'string' or u #>> '{}' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'))) then
        raise exception 'policy must be { steps: [{ approvers: { permission, role, team, users, manager }, required, escalateAfter, escalateTo }], mode, selfApproval, expiresIn, managerOf }' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
      end if;
    end loop;
    if (v_step ? 'required' and v_step -> 'required' <> '"all"'::jsonb and (jsonb_typeof(v_step -> 'required') <> 'number' or (v_step ->> 'required')::numeric < 1
        or (v_step ->> 'required')::numeric <> trunc((v_step ->> 'required')::numeric)))
      or (v_step -> 'required' = '"all"'::jsonb and (v_step -> 'approvers') - 'permission' <> '{}'::jsonb
        and ((v_step -> 'approvers') - 'users' <> '{}'::jsonb or jsonb_array_length(v_step -> 'approvers' -> 'users') = 0))
      or (jsonb_typeof(v_step -> 'required') = 'number' and (v_step -> 'approvers') - 'users' = '{}'::jsonb
        and (v_step ->> 'required')::numeric > jsonb_array_length(v_step -> 'approvers' -> 'users'))
      or ((v_step ? 'escalateAfter') <> (v_step ? 'escalateTo'))
      or (v_step ? 'escalateAfter' and (jsonb_typeof(v_step -> 'escalateAfter') <> 'string' or (v_step ->> 'escalateAfter')::interval <= interval '0')) then
      raise exception 'policy must be { steps: [{ approvers: { permission, role, team, users, manager }, required, escalateAfter, escalateTo }], mode, selfApproval, expiresIn, managerOf }' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
    end if;
  end loop;
  v_steps := (select coalesce(jsonb_agg(case when s -> 'required' = '"all"'::jsonb and (s -> 'approvers') ? 'users'
    then jsonb_set(s, '{required}', to_jsonb(jsonb_array_length(s -> 'approvers' -> 'users'))) else s end order by o), '[]'::jsonb)
    from jsonb_array_elements(v_steps) with ordinality e(s, o));
  v_expires := (approval_policy_tighten.own ->> 'expiresIn')::interval;
  if approval_policy_tighten.base is null then
    return jsonb_build_object(
      'steps', v_steps,
      'selfApproval', coalesce((approval_policy_tighten.own ->> 'selfApproval')::boolean, false),
      'expiresIn', v_expires::text, 'run', null
    ) || case when v_mode = 'confirm' then '{"mode": "confirm"}'::jsonb else '{}'::jsonb end
      || case when approval_policy_tighten.own ? 'managerOf' then jsonb_build_object('managerOf', approval_policy_tighten.own -> 'managerOf') else '{}'::jsonb end;
  end if;
  v_level := greatest(
    case when coalesce(approval_policy_tighten.base ->> 'mode', 'authorize') = 'authorize' and jsonb_array_length(coalesce(approval_policy_tighten.base -> 'steps', '[]'::jsonb)) > 0 then 2 when coalesce(approval_policy_tighten.base ->> 'mode', 'authorize') = 'confirm' then 1 else 0 end,
    case when v_mode = 'authorize' and jsonb_array_length(v_steps) > 0 then 2 when v_mode = 'confirm' then 1 else 0 end
  );
  return approval_policy_tighten.base || jsonb_build_object(
    'steps', coalesce(approval_policy_tighten.base -> 'steps', '[]'::jsonb) || v_steps,
    'selfApproval', coalesce((approval_policy_tighten.base ->> 'selfApproval')::boolean, false) and coalesce((approval_policy_tighten.own ->> 'selfApproval')::boolean, false),
    'expiresIn', least((approval_policy_tighten.base ->> 'expiresIn')::interval, v_expires)::text,
    'mode', case when v_level = 1 then 'confirm' else 'authorize' end
  ) || case when approval_policy_tighten.own ? 'managerOf' then jsonb_build_object('managerOf', approval_policy_tighten.own -> 'managerOf') else '{}'::jsonb end;
exception
  when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    raise exception 'policy must be { steps: [{ approvers: { permission, role, team, users, manager }, required, escalateAfter, escalateTo }], mode, selfApproval, expiresIn, managerOf }' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
end;
$$;
revoke execute on function "better_supabase"."approval_policy_tighten"(jsonb, jsonb) from public, anon, authenticated;

drop function if exists "better_supabase"."request_approval"(uuid, text, text, text, text, jsonb);
drop function if exists "better_supabase"."request_approval"(uuid, text, text, text, text, jsonb, jsonb);
drop function if exists "better_supabase"."request_approval"(uuid, text, text, text, text, jsonb, jsonb, text);
drop function if exists "better_supabase"."request_approval"(uuid, text, text, text, text, jsonb, text);
drop function if exists "better_supabase"."request_approval"(uuid, text, text, text, text, jsonb, jsonb, text, jsonb, uuid);
-- fingerprint: the hex SHA-256 of the request's canonical form, which
-- consume_approval checks before the approved action runs. The service role
-- may pass its own policy, which only tightens the configured and stored ones,
-- and requested_by, the user it files for, who can't approve it.
create or replace function "better_supabase"."request_approval"(tenant uuid, subject_type text, subject_id text, action text, reason text default null, payload jsonb default '{}'::jsonb, fingerprint text default null, policy jsonb default null, requested_by uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_policy jsonb := "better_supabase"."approval_effective_policy"(request_approval.tenant, request_approval.subject_type, request_approval.action, coalesce(request_approval.payload, '{}'::jsonb));
  v_service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  v_result jsonb;
  v_req "better_supabase"."approval_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if request_approval.policy is not null and not v_service then
    raise exception 'only the service role files a request under its own policy' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  if request_approval.requested_by is not null and not v_service and request_approval.requested_by is distinct from auth.uid() then
    raise exception 'only the service role files a request for another user' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  if request_approval.policy is not null then
    v_policy := "better_supabase"."approval_policy_tighten"(v_policy, request_approval.policy);
  end if;
  if v_policy is null then
    raise exception 'no approval policy for this subject type and action' using errcode = '22023', hint = 'APPROVAL_POLICY_UNKNOWN';
  end if;
  if not (v_service or (coalesce(better_supabase.can('tenant', request_approval.tenant, 'approvals.request'), false) and (case when request_approval.subject_type = 'drive_node' then coalesce(case when request_approval.subject_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then "better_supabase"."drive_can"((request_approval.subject_id)::uuid, 'editor') end, false) else case request_approval.subject_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (request_approval.subject_id)::uuid and s."organization_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant and (coalesce(better_supabase.can('tenant', request_approval.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (request_approval.subject_id)::uuid and s."organization_id" = request_approval.tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (request_approval.subject_id)::uuid and s."organization_id" = request_approval.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (request_approval.subject_id)::uuid and s."organization_id" = request_approval.tenant)
    else false
  end end))) then
    raise exception 'not allowed to request approval for this record' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  if not (coalesce(v_policy ->> 'mode', 'authorize') = 'confirm' or jsonb_array_length(coalesce(v_policy -> 'steps', '[]'::jsonb)) > 0) then
    raise exception 'no approval is required for this request' using errcode = '22023', hint = 'APPROVAL_NOT_REQUIRED';
  end if;
  if request_approval.fingerprint is not null and request_approval.fingerprint !~ '^[0-9a-f]{64}$' then
    raise exception 'fingerprint must be a lowercase hex SHA-256' using errcode = '22023', hint = 'APPROVAL_FINGERPRINT_INVALID';
  end if;
  v_result := "better_supabase"."open_approval"(request_approval.tenant, request_approval.subject_type, request_approval.subject_id, request_approval.action, v_policy, request_approval.reason, request_approval.payload, coalesce(request_approval.requested_by, auth.uid()));
  if request_approval.fingerprint is not null then
    update "better_supabase"."approval_requests" x set "fingerprint" = request_approval.fingerprint
    where x."id" = (v_result ->> 'id')::uuid and x."status" = 'pending';
  end if;
  select * into v_req from "better_supabase"."approval_requests" x where x."id" = (v_result ->> 'id')::uuid;
  if found then
    return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'mode', coalesce(v_req."policy" ->> 'mode', 'authorize'), 'fingerprint', v_req."fingerprint", 'consumedAt', v_req."consumed_at", 'createdAt', v_req."created_at");
  end if;
  return v_result;
end;
$$;
revoke execute on function "better_supabase"."request_approval"(uuid, text, text, text, text, jsonb, text, jsonb, uuid) from public, anon;
grant execute on function "better_supabase"."request_approval"(uuid, text, text, text, text, jsonb, text, jsonb, uuid) to authenticated, service_role;

-- Uses an approved request once, right before the approved action runs. The
-- fingerprint must match the one the request was filed with, so an approval
-- never covers a request that changed after it was decided.
create or replace function "better_supabase"."consume_approval"(request_id uuid, fingerprint text default null)
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
  select * into v_req from "better_supabase"."approval_requests" r where r."id" = consume_approval.request_id for update;
  if not found then
    raise exception 'approval request not found' using errcode = 'P0002', hint = 'APPROVAL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_req."requested_by" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_req."tenant_id", 'approvals.manage'), false)) then
    raise exception 'approval request not found' using errcode = 'P0002', hint = 'APPROVAL_NOT_FOUND';
  end if;
  if v_req."consumed_at" is not null then
    raise exception 'this approval was already used' using errcode = '22023', hint = 'APPROVAL_CONSUMED';
  end if;
  if v_req."status" <> 'approved' then
    raise exception 'this request is not approved' using errcode = '22023', hint = 'APPROVAL_NOT_APPROVED';
  end if;
  if v_req."fingerprint" is distinct from consume_approval.fingerprint then
    raise exception 'the request changed after it was approved; ask for approval again' using errcode = '22023', hint = 'APPROVAL_FINGERPRINT_MISMATCH';
  end if;
  update "better_supabase"."approval_requests" r set "consumed_at" = now()
    where r."id" = v_req."id" returning * into v_req;
  perform "better_supabase".emit_event('approval.consumed', jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step"), 'approval-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/approvals');
  perform better_supabase.audit_event(
    event_type => 'approval.consumed',
    category => 'data',
    target_type => 'approval_request',
    record_id => v_req."id"::text,
    summary => 'consumed' || ' ' || v_req."action" || ' on ' || v_req."subject_type" || ' ' || v_req."subject_id",
    tenant => (v_req."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step")
  );
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'mode', coalesce(v_req."policy" ->> 'mode', 'authorize'), 'fingerprint', v_req."fingerprint", 'consumedAt', v_req."consumed_at", 'createdAt', v_req."created_at");
end;
$$;
revoke execute on function "better_supabase"."consume_approval"(uuid, text) from public, anon;
grant execute on function "better_supabase"."consume_approval"(uuid, text) to authenticated, service_role;

-- Approves or rejects the current step. Enough approvals move the request
-- to the next step, and the last step runs the policy's action. The service
-- role decides for the user in decided_by, who is recorded as the approver;
-- it skips the approver check, never the requester's.
drop function if exists "better_supabase"."decide_approval"(uuid, text, text);
create or replace function "better_supabase"."decide_approval"(request_id uuid, decision text, comment text default null, decided_by uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_req "better_supabase"."approval_requests"%rowtype;
  v_count integer;
  v_service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  v_actor uuid := coalesce(decide_approval.decided_by, auth.uid());
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if decide_approval.decision not in ('approved', 'rejected') then
    raise exception 'decision must be approved or rejected' using errcode = '22023', hint = 'APPROVAL_DECISION_INVALID';
  end if;
  if decide_approval.decided_by is not null and not v_service and decide_approval.decided_by is distinct from auth.uid() then
    raise exception 'only the service role decides for another user' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
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
  if v_service then
    if v_actor is not null and v_actor = v_req."requested_by" and coalesce(v_req."policy" ->> 'mode', 'authorize') <> 'confirm'
      and not coalesce((v_req."policy" ->> 'selfApproval')::boolean, false) then
      raise exception 'the requester can''t decide their own request' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
    end if;
    if v_actor is not null and exists (
      select 1 from "better_supabase"."approval_decisions" x
      where x."request_id" = v_req."id" and x."step" = v_req."step" and x."approver" = v_actor
    ) then
      raise exception 'this user already decided this step' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
    end if;
  elsif not "better_supabase"."approval_eligible"(v_req."id") then
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
  values (v_req."id", v_req."tenant_id", v_req."step", v_actor, decide_approval.decision, decide_approval.comment);
  if decide_approval.decision = 'rejected' then
    update "better_supabase"."approval_requests" r set "status" = 'rejected', "decided_at" = now()
      where r."id" = v_req."id" returning * into v_req;
    perform "better_supabase".emit_event('approval.rejected', jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step"), 'approval-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/approvals');
  perform better_supabase.audit_event(
    event_type => 'approval.rejected',
    category => 'data',
    target_type => 'approval_request',
    record_id => v_req."id"::text,
    summary => 'rejected' || ' ' || v_req."action" || ' on ' || v_req."subject_type" || ' ' || v_req."subject_id",
    tenant => (v_req."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step")
  );
    perform "better_supabase"."approval_notify"(v_req."id", 'rejected');
    if v_req."subject_type" = 'ai_tool_approval' then
      perform "better_supabase"."apply_ai_tool_approval"(v_req."subject_id", false, decide_approval.comment);
    end if;
  else
    select count(*) into v_count from "better_supabase"."approval_decisions" x
      where x."request_id" = v_req."id" and x."step" = v_req."step" and x."decision" = 'approved';
    if v_req."policy" ->> 'mode' = 'confirm' and v_req."requested_by" = v_actor then
      update "better_supabase"."approval_requests" r set "status" = 'approved', "decided_at" = now()
        where r."id" = v_req."id" returning * into v_req;
      perform "better_supabase"."approval_finalize"(v_req."id");
    elsif v_count >= coalesce((v_req."policy" -> 'steps' -> v_req."step" ->> 'required')::integer, 1) then
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
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'mode', coalesce(v_req."policy" ->> 'mode', 'authorize'), 'fingerprint', v_req."fingerprint", 'consumedAt', v_req."consumed_at", 'createdAt', v_req."created_at");
end;
$$;
revoke execute on function "better_supabase"."decide_approval"(uuid, text, text, uuid) from public, anon;
grant execute on function "better_supabase"."decide_approval"(uuid, text, text, uuid) to authenticated, service_role;

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
  if v_req."subject_type" in ('ai_tool_approval') then
    raise exception 'the module that filed this request decides who approves it' using errcode = '22023', hint = 'APPROVAL_DELEGATE_INVALID';
  end if;
  if delegate_approval.to_user is null or delegate_approval.to_user = auth.uid() or delegate_approval.to_user = v_req."requested_by" then
    raise exception 'delegate to another user than yourself or the requester' using errcode = '22023', hint = 'APPROVAL_DELEGATE_INVALID';
  end if;
  if not exists (
    select 1 from "public"."memberships" m
    where m."organization_id" = v_req."tenant_id" and m."user_id" = delegate_approval.to_user
  ) then
    raise exception 'the delegate is not a member of this organization' using errcode = '22023', hint = 'APPROVAL_DELEGATE_INVALID';
  end if;
  insert into "better_supabase"."approval_decisions" ("request_id", "tenant_id", "step", "approver", "decision", "delegate_to", "comment")
  values (v_req."id", v_req."tenant_id", v_req."step", auth.uid(), 'delegated', delegate_approval.to_user, delegate_approval.comment);
  perform "better_supabase".emit_event('approval.delegated', jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step"), 'approval-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/approvals');
  perform better_supabase.audit_event(
    event_type => 'approval.delegated',
    category => 'data',
    target_type => 'approval_request',
    record_id => v_req."id"::text,
    summary => 'delegated' || ' ' || v_req."action" || ' on ' || v_req."subject_type" || ' ' || v_req."subject_id",
    tenant => (v_req."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step")
  );
  perform "better_supabase"."approval_notify"(v_req."id", 'delegated');
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'mode', coalesce(v_req."policy" ->> 'mode', 'authorize'), 'fingerprint', v_req."fingerprint", 'consumedAt', v_req."consumed_at", 'createdAt', v_req."created_at");
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_req."requested_by" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_req."tenant_id", 'approvals.manage'), false)) then
    raise exception 'only the requester or a manager can cancel this request' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  if v_req."status" <> 'pending' then
    raise exception 'this request is no longer pending' using errcode = '22023', hint = 'APPROVAL_CLOSED';
  end if;
  update "better_supabase"."approval_requests" r set "status" = 'cancelled', "decided_at" = now()
    where r."id" = v_req."id" returning * into v_req;
  perform "better_supabase".emit_event('approval.cancelled', jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step"), 'approval-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/approvals');
  perform better_supabase.audit_event(
    event_type => 'approval.cancelled',
    category => 'data',
    target_type => 'approval_request',
    record_id => v_req."id"::text,
    summary => 'cancelled' || ' ' || v_req."action" || ' on ' || v_req."subject_type" || ' ' || v_req."subject_id",
    tenant => (v_req."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step")
  );
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'mode', coalesce(v_req."policy" ->> 'mode', 'authorize'), 'fingerprint', v_req."fingerprint", 'consumedAt', v_req."consumed_at", 'createdAt', v_req."created_at");
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_req."requested_by" = auth.uid(), false) or "better_supabase"."approval_eligible"(v_req."id")
    or (coalesce(better_supabase.can('tenant', v_req."tenant_id", 'approvals.read'), false) and (not v_req."subject_type" in ('ai_tool_approval') and (v_req."subject_type" in ('access_request', 'timesheet', 'expense_report', 'content_entry') or (case when v_req."subject_type" = 'drive_node' then coalesce(case when v_req."subject_id" ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then "better_supabase"."drive_can"((v_req."subject_id")::uuid, 'viewer') end, false) else case v_req."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_req."subject_id")::uuid and s."organization_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id" and (coalesce(better_supabase.can('tenant', v_req."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_req."subject_id")::uuid and s."organization_id" = v_req."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_req."subject_id")::uuid and s."organization_id" = v_req."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_req."subject_id")::uuid and s."organization_id" = v_req."tenant_id")
    else false
  end end))))) then
    raise exception 'approval request not found' using errcode = 'P0002', hint = 'APPROVAL_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'mode', coalesce(v_req."policy" ->> 'mode', 'authorize'), 'fingerprint', v_req."fingerprint", 'consumedAt', v_req."consumed_at", 'createdAt', v_req."created_at") || jsonb_build_object(
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
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'action', x."action", 'status', x."status", 'step', x."step", 'steps', x."policy" -> 'steps', 'requestedBy', x."requested_by", 'reason', x."reason", 'payload', x."payload", 'expiresAt', x."expires_at", 'decidedAt', x."decided_at", 'mode', coalesce(x."policy" ->> 'mode', 'authorize'), 'fingerprint', x."fingerprint", 'consumedAt', x."consumed_at", 'createdAt', x."created_at") as j, x."created_at" as at, x."id" as id
    from "better_supabase"."approval_requests" x
    where x."tenant_id" = list_approvals.tenant
      and (list_approvals.status is null or x."status" = list_approvals.status)
      and (list_approvals.subject_type is null or x."subject_type" = list_approvals.subject_type)
      and (list_approvals.subject_id is null or x."subject_id" = list_approvals.subject_id)
      and (list_approvals.before is null or x."created_at" < list_approvals.before)
      and case
        when list_approvals.assigned then "better_supabase"."approval_eligible"(x."id")
        else x."requested_by" = auth.uid() or (v_read and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (not x."subject_type" in ('ai_tool_approval') and (x."subject_type" in ('access_request', 'timesheet', 'expense_report', 'content_entry') or (case when x."subject_type" = 'drive_node' then coalesce(case when x."subject_id" ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then "better_supabase"."drive_can"((x."subject_id")::uuid, 'viewer') end, false) else case x."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id" and (coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    else false
  end end))))) or "better_supabase"."approval_eligible"(x."id")
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
    perform "better_supabase".emit_event('approval.expired', jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step"), 'approval-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/approvals');
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

-- Lets the fallback approvers (escalateTo) of a step decide it too once the
-- step has waited its escalateAfter, and asks them. Run it from pg_cron like
-- remind_approvals.
create or replace function "better_supabase"."escalate_approvals"(max_requests integer default 200)
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
    select * from "better_supabase"."approval_requests" r
    where r."status" = 'pending'
      and (r."expires_at" is null or r."expires_at" > now())
      and r."policy" -> 'steps' -> r."step" ? 'escalateAfter'
      and not coalesce((r."policy" -> 'steps' -> r."step" ->> 'escalated')::boolean, false)
      and coalesce((
        select max(x."created_at") from "better_supabase"."approval_decisions" x
        where x."request_id" = r."id" and x."step" = r."step" - 1
      ), r."created_at") + (r."policy" -> 'steps' -> r."step" ->> 'escalateAfter')::interval <= now()
    order by r."created_at"
    limit greatest(coalesce(escalate_approvals.max_requests, 200), 1)
    for update skip locked
  loop
    update "better_supabase"."approval_requests" r set "policy" = jsonb_set(r."policy", array['steps', (r."step")::text, 'escalated'], 'true'::jsonb)
    where r."id" = v_req."id"
    returning * into v_req;
    perform "better_supabase".emit_event('approval.escalated', jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step"), 'approval-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/approvals');
  perform better_supabase.audit_event(
    event_type => 'approval.escalated',
    category => 'data',
    target_type => 'approval_request',
    record_id => v_req."id"::text,
    summary => 'escalated' || ' ' || v_req."action" || ' on ' || v_req."subject_type" || ' ' || v_req."subject_id",
    tenant => (v_req."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step")
  );
    perform "better_supabase"."approval_notify"(v_req."id", 'escalated');
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."escalate_approvals"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."escalate_approvals"(integer) to service_role;

-- on with cascade: deleting a subject row deletes its approvals rows.
create or replace function "better_supabase"."approvals_subject_deleted"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type text := tg_argv[0];
  v_id text := to_jsonb(old) ->> tg_argv[1];
begin
  delete from "better_supabase"."approval_requests" r where r."subject_type" = v_type and r."subject_id" = v_id;
  return null;
end;
$$;
revoke execute on function "better_supabase"."approvals_subject_deleted"() from public, anon, authenticated;

drop trigger if exists "bsb_approvals_product_cascade" on "better_supabase"."products";
create trigger "bsb_approvals_product_cascade"
  after delete on "better_supabase"."products"
  for each row execute function "better_supabase"."approvals_subject_deleted"('product', 'id');

drop trigger if exists "bsb_approvals_product_variant_cascade" on "better_supabase"."product_variants";
create trigger "bsb_approvals_product_variant_cascade"
  after delete on "better_supabase"."product_variants"
  for each row execute function "better_supabase"."approvals_subject_deleted"('product_variant', 'id');

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
drop policy if exists bsb_tenant_scope on "better_supabase"."approval_requests";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."approval_requests";
create policy bsb_tenant_scope_select on "better_supabase"."approval_requests" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("tenant_id" in (select better_supabase.tenant_ids_with('approvals.read')) and not "subject_type" in ('ai_tool_approval')) or "requested_by" = (select auth.uid()))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."approval_requests";
create policy bsb_tenant_scope_insert on "better_supabase"."approval_requests" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."approval_requests";
create policy bsb_tenant_scope_update on "better_supabase"."approval_requests" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."approval_requests";
create policy bsb_tenant_scope_delete on "better_supabase"."approval_requests" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."approval_decisions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."approval_decisions";
create policy bsb_tenant_scope_select on "better_supabase"."approval_decisions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('approvals.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."approval_decisions";
create policy bsb_tenant_scope_insert on "better_supabase"."approval_decisions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."approval_decisions";
create policy bsb_tenant_scope_update on "better_supabase"."approval_decisions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."approval_decisions";
create policy bsb_tenant_scope_delete on "better_supabase"."approval_decisions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."approval_policies";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."approval_policies";
create policy bsb_tenant_scope_select on "better_supabase"."approval_policies" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('approvals.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."approval_policies";
create policy bsb_tenant_scope_insert on "better_supabase"."approval_policies" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."approval_policies";
create policy bsb_tenant_scope_update on "better_supabase"."approval_policies" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."approval_policies";
create policy bsb_tenant_scope_delete on "better_supabase"."approval_policies" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.approvals.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."request_approval"(uuid, text, text, text, text, jsonb);
drop function if exists "api"."request_approval"(uuid, text, text, text, text, jsonb, jsonb);
drop function if exists "api"."request_approval"(uuid, text, text, text, text, jsonb, jsonb, text);
drop function if exists "api"."request_approval"(uuid, text, text, text, text, jsonb, text);
drop function if exists "api"."request_approval"(uuid, text, text, text, text, jsonb, jsonb, text, jsonb, uuid);
drop function if exists "api"."decide_approval"(uuid, text, text);

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

create or replace function "api"."approval_policy"(subject_type text, action text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."approval_policy"($1, $2) $$;
revoke execute on function "api"."approval_policy"(text, text) from public, anon;
grant execute on function "api"."approval_policy"(text, text) to authenticated, service_role;

create or replace function "api"."approval_eligible"(request_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."approval_eligible"($1) $$;
revoke execute on function "api"."approval_eligible"(uuid) from public, anon;
grant execute on function "api"."approval_eligible"(uuid) to authenticated, service_role;

create or replace function "api"."save_approval_policy"(tenant uuid, policy jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_approval_policy"($1, $2) $$;
revoke execute on function "api"."save_approval_policy"(uuid, jsonb) from public, anon;
grant execute on function "api"."save_approval_policy"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."remove_approval_policy"(policy_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."remove_approval_policy"($1) $$;
revoke execute on function "api"."remove_approval_policy"(uuid) from public, anon;
grant execute on function "api"."remove_approval_policy"(uuid) to authenticated, service_role;

create or replace function "api"."list_approval_policies"(tenant uuid, subject_type text default null, page_size integer default 100)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_approval_policies"($1, $2, $3) $$;
revoke execute on function "api"."list_approval_policies"(uuid, text, integer) from public, anon;
grant execute on function "api"."list_approval_policies"(uuid, text, integer) to authenticated, service_role;

create or replace function "api"."approval_requirement"(tenant uuid, subject_type text, action text, subject jsonb default '{}'::jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."approval_requirement"($1, $2, $3, $4) $$;
revoke execute on function "api"."approval_requirement"(uuid, text, text, jsonb) from public, anon;
grant execute on function "api"."approval_requirement"(uuid, text, text, jsonb) to authenticated, service_role;

create or replace function "api"."request_approval"(tenant uuid, subject_type text, subject_id text, action text, reason text default null, payload jsonb default '{}'::jsonb, fingerprint text default null, policy jsonb default null, requested_by uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."request_approval"($1, $2, $3, $4, $5, $6, $7, $8, $9) $$;
revoke execute on function "api"."request_approval"(uuid, text, text, text, text, jsonb, text, jsonb, uuid) from public, anon;
grant execute on function "api"."request_approval"(uuid, text, text, text, text, jsonb, text, jsonb, uuid) to authenticated, service_role;

create or replace function "api"."consume_approval"(request_id uuid, fingerprint text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."consume_approval"($1, $2) $$;
revoke execute on function "api"."consume_approval"(uuid, text) from public, anon;
grant execute on function "api"."consume_approval"(uuid, text) to authenticated, service_role;

create or replace function "api"."decide_approval"(request_id uuid, decision text, comment text default null, decided_by uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."decide_approval"($1, $2, $3, $4) $$;
revoke execute on function "api"."decide_approval"(uuid, text, text, uuid) from public, anon;
grant execute on function "api"."decide_approval"(uuid, text, text, uuid) to authenticated, service_role;

create or replace function "api"."delegate_approval"(request_id uuid, to_user uuid, comment text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delegate_approval"($1, $2, $3) $$;
revoke execute on function "api"."delegate_approval"(uuid, uuid, text) from public, anon;
grant execute on function "api"."delegate_approval"(uuid, uuid, text) to authenticated, service_role;

create or replace function "api"."cancel_approval"(request_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."cancel_approval"($1) $$;
revoke execute on function "api"."cancel_approval"(uuid) from public, anon;
grant execute on function "api"."cancel_approval"(uuid) to authenticated, service_role;

create or replace function "api"."get_approval"(request_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_approval"($1) $$;
revoke execute on function "api"."get_approval"(uuid) from public, anon;
grant execute on function "api"."get_approval"(uuid) to authenticated, service_role;

create or replace function "api"."list_approvals"(tenant uuid, status text default 'pending', assigned boolean default false, subject_type text default null, subject_id text default null, page_size integer default 50, before timestamptz default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_approvals"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."list_approvals"(uuid, text, boolean, text, text, integer, timestamptz) from public, anon;
grant execute on function "api"."list_approvals"(uuid, text, boolean, text, text, integer, timestamptz) to authenticated, service_role;

create or replace function "api"."is_approved"(subject_type text, subject_id text, action text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."is_approved"($1, $2, $3) $$;
revoke execute on function "api"."is_approved"(text, text, text) from public, anon;
grant execute on function "api"."is_approved"(text, text, text) to authenticated, service_role;

create or replace function "api"."expire_approvals"(max_requests integer default 500)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."expire_approvals"($1) $$;
revoke execute on function "api"."expire_approvals"(integer) from public, anon, authenticated;
grant execute on function "api"."expire_approvals"(integer) to service_role;

create or replace function "api"."remind_approvals"(after interval default interval '1 day', max_requests integer default 200)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."remind_approvals"($1, $2) $$;
revoke execute on function "api"."remind_approvals"(interval, integer) from public, anon, authenticated;
grant execute on function "api"."remind_approvals"(interval, integer) to service_role;

create or replace function "api"."escalate_approvals"(max_requests integer default 200)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."escalate_approvals"($1) $$;
revoke execute on function "api"."escalate_approvals"(integer) from public, anon, authenticated;
grant execute on function "api"."escalate_approvals"(integer) to service_role;

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
