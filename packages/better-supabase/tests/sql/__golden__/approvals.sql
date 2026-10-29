-- ==== alone: schema supabase/schemas/900_better_supabase_077_approvals.sql
-- better-supabase module: approvals
-- @bsb-block approvals@1 managed
-- @bsb-hash sha256:371679247945b0f7a96b318fc6a974227dece762702734b65da21fdecee1eff4
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
  v_step := v_req."policy" -> 'steps' -> v_req."step";
  v_approvers := v_step -> 'approvers';
  if ((coalesce(v_approvers -> 'users', '[]'::jsonb) ? v_me::text)
    or (v_approvers ->> 'permission' is not null and coalesce(better_supabase.can('tenant', v_req."tenant_id", v_approvers ->> 'permission'), false))
    or (v_approvers ->> 'role' is not null and exists (
      select 1 from "better_supabase"."memberships" m
      where m."organization_id" = v_req."tenant_id" and m."user_id" = v_me and m."role" = v_approvers ->> 'role'
    ))
    or (v_approvers ->> 'team' is not null and false)) then
    return true;
  end if;
  if coalesce((v_step ->> 'escalated')::boolean, false) then
    v_approvers := v_step -> 'escalateTo';
    if ((coalesce(v_approvers -> 'users', '[]'::jsonb) ? v_me::text)
    or (v_approvers ->> 'permission' is not null and coalesce(better_supabase.can('tenant', v_req."tenant_id", v_approvers ->> 'permission'), false))
    or (v_approvers ->> 'role' is not null and exists (
      select 1 from "better_supabase"."memberships" m
      where m."organization_id" = v_req."tenant_id" and m."user_id" = v_me and m."role" = v_approvers ->> 'role'
    ))
    or (v_approvers ->> 'team' is not null and false)) then
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
        from (select m."user_id" from "better_supabase"."memberships" m
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
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'mode', coalesce(v_req."policy" ->> 'mode', 'authorize'), 'fingerprint', v_req."fingerprint", 'consumedAt', v_req."consumed_at", 'createdAt', v_req."created_at");
end;
$$;
revoke execute on function "better_supabase"."open_approval"(uuid, text, text, text, jsonb, text, jsonb, uuid) from public, anon, authenticated;



-- The policy a request snapshots: options.policies, as tenant policies are off.
create or replace function "better_supabase"."approval_effective_policy"(tenant uuid, subject_type text, action text, subject jsonb default '{}'::jsonb)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select "better_supabase"."approval_policy"(approval_effective_policy.subject_type, approval_effective_policy.action)
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
    or (approval_policy_tighten.own ? 'managerOf' and true)
    or (approval_policy_tighten.own ->> 'expiresIn' is not null and (approval_policy_tighten.own ->> 'expiresIn')::interval <= interval '0') then
    raise exception 'policy must be { steps: [{ approvers: { permission, role, team, users }, required, escalateAfter, escalateTo }], mode, selfApproval, expiresIn }' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
  end if;
  for v_step in select * from jsonb_array_elements(v_steps) loop
    if jsonb_typeof(v_step) <> 'object' then
      raise exception 'policy must be { steps: [{ approvers: { permission, role, team, users }, required, escalateAfter, escalateTo }], mode, selfApproval, expiresIn }' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
    end if;
    for v_who in select a.w from (values (v_step -> 'approvers', true), (v_step -> 'escalateTo', v_step ? 'escalateTo')) a(w, checked) where a.checked loop
      if jsonb_typeof(v_who) is distinct from 'object'
        or not (v_who ?| array['permission', 'role', 'team', 'users', 'manager'])
        or (v_who ? 'manager' and true)
        or (v_who ? 'users' and (jsonb_typeof(v_who -> 'users') <> 'array'
          or exists (select 1 from jsonb_array_elements(v_who -> 'users') u
            where jsonb_typeof(u) <> 'string' or u #>> '{}' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'))) then
        raise exception 'policy must be { steps: [{ approvers: { permission, role, team, users }, required, escalateAfter, escalateTo }], mode, selfApproval, expiresIn }' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
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
      raise exception 'policy must be { steps: [{ approvers: { permission, role, team, users }, required, escalateAfter, escalateTo }], mode, selfApproval, expiresIn }' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
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
    raise exception 'policy must be { steps: [{ approvers: { permission, role, team, users }, required, escalateAfter, escalateTo }], mode, selfApproval, expiresIn }' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
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
  if not (v_service or (coalesce(better_supabase.can('tenant', request_approval.tenant, 'approvals.request'), false) and true)) then
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
  null;
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
    null;
    perform "better_supabase"."approval_notify"(v_req."id", 'rejected');
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
  if delegate_approval.to_user is null or delegate_approval.to_user = auth.uid() or delegate_approval.to_user = v_req."requested_by" then
    raise exception 'delegate to another user than yourself or the requester' using errcode = '22023', hint = 'APPROVAL_DELEGATE_INVALID';
  end if;
  if not exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = v_req."tenant_id" and m."user_id" = delegate_approval.to_user
  ) then
    raise exception 'the delegate is not a member of this organization' using errcode = '22023', hint = 'APPROVAL_DELEGATE_INVALID';
  end if;
  insert into "better_supabase"."approval_decisions" ("request_id", "tenant_id", "step", "approver", "decision", "delegate_to", "comment")
  values (v_req."id", v_req."tenant_id", v_req."step", auth.uid(), 'delegated', delegate_approval.to_user, delegate_approval.comment);
  null;
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
  null;
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
    or (coalesce(better_supabase.can('tenant', v_req."tenant_id", 'approvals.read'), false) and (true))) then
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
    null;
    perform "better_supabase"."approval_notify"(v_req."id", 'escalated');
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."escalate_approvals"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."escalate_approvals"(integer) to service_role;

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
    or ("tenant_id" in (select better_supabase.tenant_ids_with('approvals.read')) or "requested_by" = (select auth.uid()))
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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_077_approvals.sql
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

-- ==== with every module: schema supabase/schemas/900_better_supabase_077_approvals.sql
-- better-supabase module: approvals
-- @bsb-block approvals@1 managed
-- @bsb-hash sha256:f90077adb26f148ffa00dc28bcfc5bd84bdd57126aa3a58f32e3291aed348cd6
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
  using (("tenant_id" in (select better_supabase.tenant_ids_with('approvals.read')) and not "subject_type" in ('support_request', 'ai_tool_approval')) or "requested_by" = (select auth.uid()));

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
  if v_req."subject_type" = 'support_request' then
    return "better_supabase"."support_request_approvable"(v_req."subject_id"::uuid);
  end if;
  if v_req."subject_type" = 'ai_tool_approval' then
    return "better_supabase"."ai_tool_approval_approvable"(v_req."subject_id");
  end if;
  v_step := v_req."policy" -> 'steps' -> v_req."step";
  v_approvers := v_step -> 'approvers';
  if ((coalesce(v_approvers -> 'users', '[]'::jsonb) ? v_me::text)
    or (v_approvers ->> 'permission' is not null and coalesce(better_supabase.can('tenant', v_req."tenant_id", v_approvers ->> 'permission'), false))
    or (v_approvers ->> 'role' is not null and exists (
      select 1 from "better_supabase"."memberships" m
      where m."organization_id" = v_req."tenant_id" and m."user_id" = v_me and m."role" = v_approvers ->> 'role'
    ))
    or (v_approvers ->> 'team' is not null and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = v_approvers ->> 'team' and tm."user_id" = v_me))
    or (coalesce((v_approvers ->> 'manager')::boolean, false) and (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = v_req."tenant_id" and (case when (v_req."policy" ->> 'managerOf') is not null then me."id"::text = (v_req."policy" ->> 'managerOf') else me."user_id" = v_req."requested_by" end)
        and mgr."user_id" is not null and mgr."status"::text <> 'offboarded'
      limit 1) = v_me, false) and exists (
      select 1 from "better_supabase"."memberships" mm
      where mm."organization_id" = v_req."tenant_id" and mm."user_id" = v_me and mm."disabled_at" is null
    )))) then
    return true;
  end if;
  if coalesce((v_step ->> 'escalated')::boolean, false) then
    v_approvers := v_step -> 'escalateTo';
    if ((coalesce(v_approvers -> 'users', '[]'::jsonb) ? v_me::text)
    or (v_approvers ->> 'permission' is not null and coalesce(better_supabase.can('tenant', v_req."tenant_id", v_approvers ->> 'permission'), false))
    or (v_approvers ->> 'role' is not null and exists (
      select 1 from "better_supabase"."memberships" m
      where m."organization_id" = v_req."tenant_id" and m."user_id" = v_me and m."role" = v_approvers ->> 'role'
    ))
    or (v_approvers ->> 'team' is not null and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = v_approvers ->> 'team' and tm."user_id" = v_me))
    or (coalesce((v_approvers ->> 'manager')::boolean, false) and (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = v_req."tenant_id" and (case when (v_req."policy" ->> 'managerOf') is not null then me."id"::text = (v_req."policy" ->> 'managerOf') else me."user_id" = v_req."requested_by" end)
        and mgr."user_id" is not null and mgr."status"::text <> 'offboarded'
      limit 1) = v_me, false) and exists (
      select 1 from "better_supabase"."memberships" mm
      where mm."organization_id" = v_req."tenant_id" and mm."user_id" = v_me and mm."disabled_at" is null
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
      select m."user_id" from "better_supabase"."memberships" m
      where m."organization_id" = v_req."tenant_id" and m."role" = v_approvers ->> 'role'
      union
      select tm."user_id" from "better_supabase"."team_members" tm
      where tm."team_id"::text = v_approvers ->> 'team'
      union
      select (select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = v_req."tenant_id" and (case when (v_req."policy" ->> 'managerOf') is not null then me."id"::text = (v_req."policy" ->> 'managerOf') else me."user_id" = v_req."requested_by" end)
        and mgr."user_id" is not null and mgr."status"::text <> 'offboarded'
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
  if v_req."subject_type" = 'support_request' then
    perform "better_supabase"."apply_support_approval"(v_req."subject_id"::uuid, auth.uid());
  end if;
  if v_req."subject_type" = 'ai_tool_approval' then
    perform "better_supabase"."apply_ai_tool_approval"(v_req."subject_id", true, (select x."comment" from "better_supabase"."approval_decisions" x where x."request_id" = v_req."id" order by x."created_at" desc, x."id" desc limit 1));
  end if;
  if v_req."subject_type" = 'access_request' then
    perform "better_supabase"."grant_access_request"(v_req."subject_id"::uuid);
  end if;
  if v_req."subject_type" = 'timesheet' then
    perform "better_supabase"."approve_timesheet"(v_req."subject_id"::uuid);
  end if;
  if v_req."subject_type" = 'leave_request' then
    perform "better_supabase"."approve_leave_request"(v_req."subject_id"::uuid);
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
        from (select m."user_id" from "better_supabase"."memberships" m
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



-- The policy a request snapshots: options.policies, as tenant policies are off.
create or replace function "better_supabase"."approval_effective_policy"(tenant uuid, subject_type text, action text, subject jsonb default '{}'::jsonb)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select "better_supabase"."approval_policy"(approval_effective_policy.subject_type, approval_effective_policy.action)
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
  if not (v_service or (coalesce(better_supabase.can('tenant', request_approval.tenant, 'approvals.request'), false) and (case when request_approval.subject_type = 'drive_node' then coalesce(case when request_approval.subject_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then "better_supabase"."drive_can"((request_approval.subject_id)::uuid, 'editor') end, false) else true end))) then
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
    if v_req."subject_type" = 'support_request' then
      perform "better_supabase"."close_support_request"(v_req."subject_id"::uuid);
    end if;
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
  if v_req."subject_type" in ('support_request', 'ai_tool_approval') then
    raise exception 'the module that filed this request decides who approves it' using errcode = '22023', hint = 'APPROVAL_DELEGATE_INVALID';
  end if;
  if delegate_approval.to_user is null or delegate_approval.to_user = auth.uid() or delegate_approval.to_user = v_req."requested_by" then
    raise exception 'delegate to another user than yourself or the requester' using errcode = '22023', hint = 'APPROVAL_DELEGATE_INVALID';
  end if;
  if not exists (
    select 1 from "better_supabase"."memberships" m
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
    or (coalesce(better_supabase.can('tenant', v_req."tenant_id", 'approvals.read'), false) and (not v_req."subject_type" in ('support_request', 'ai_tool_approval') and (v_req."subject_type" in ('access_request', 'timesheet', 'leave_request', 'expense_report', 'content_entry') or (case when v_req."subject_type" = 'drive_node' then coalesce(case when v_req."subject_id" ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then "better_supabase"."drive_can"((v_req."subject_id")::uuid, 'viewer') end, false) else true end))))) then
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
        else x."requested_by" = auth.uid() or (v_read and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (not x."subject_type" in ('support_request', 'ai_tool_approval') and (x."subject_type" in ('access_request', 'timesheet', 'leave_request', 'expense_report', 'content_entry') or (case when x."subject_type" = 'drive_node' then coalesce(case when x."subject_id" ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then "better_supabase"."drive_can"((x."subject_id")::uuid, 'viewer') end, false) else true end))))) or "better_supabase"."approval_eligible"(x."id")
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
    or (("tenant_id" in (select better_supabase.tenant_ids_with('approvals.read')) and not "subject_type" in ('support_request', 'ai_tool_approval')) or "requested_by" = (select auth.uid()))
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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_077_approvals.sql
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

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_077_approvals.sql
-- better-supabase module: approvals
-- @bsb-block approvals@1 managed
-- @bsb-hash sha256:abf1096ac4e5d09f56e2b2b6f38b54d16e4e3eb002dcd42ff9ca87ce945ede4e
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
    drop policy if exists bsb_tenant_scope on "app_private"."approval_requests";
    drop policy if exists bsb_tenant_scope_select on "app_private"."approval_requests";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."approval_requests";
    drop policy if exists bsb_tenant_scope_update on "app_private"."approval_requests";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."approval_requests";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."approval_decisions";
    drop policy if exists bsb_tenant_scope_select on "app_private"."approval_decisions";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."approval_decisions";
    drop policy if exists bsb_tenant_scope_update on "app_private"."approval_decisions";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."approval_decisions";
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
create table if not exists "app_private"."approval_requests" (
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
alter table "app_private"."approval_requests" add column if not exists "fingerprint" text check ("fingerprint" is null or "fingerprint" ~ '^[0-9a-f]{64}$');
alter table "app_private"."approval_requests" add column if not exists "consumed_at" timestamptz;
create unique index if not exists "approval_requests_pending_idx" on "app_private"."approval_requests" ("subject_type", "subject_id", "action") where "status" = 'pending';
create index if not exists "approval_requests_tenant_idx" on "app_private"."approval_requests" ("tenant_id", "status", "created_at" desc);
alter table "app_private"."approval_requests" enable row level security;
revoke all on "app_private"."approval_requests" from public, anon, authenticated;
grant select on "app_private"."approval_requests" to authenticated;
grant all on "app_private"."approval_requests" to service_role;
drop policy if exists approval_requests_read on "app_private"."approval_requests";
create policy approval_requests_read on "app_private"."approval_requests"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('approvals.read')) or "requested_by" = (select auth.uid()));

create table if not exists "app_private"."approval_decisions" (
  "id" uuid primary key default gen_random_uuid(),
  "request_id" uuid not null references "app_private"."approval_requests" ("id") on delete cascade,
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
create index if not exists "approval_decisions_delegate_idx" on "app_private"."approval_decisions" ("delegate_to") where "delegate_to" is not null;
alter table "app_private"."approval_decisions" enable row level security;
revoke all on "app_private"."approval_decisions" from public, anon, authenticated;
grant select on "app_private"."approval_decisions" to authenticated;
grant all on "app_private"."approval_decisions" to service_role;
drop policy if exists approval_decisions_read on "app_private"."approval_decisions";
create policy approval_decisions_read on "app_private"."approval_decisions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('approvals.read')));

-- The policy a new request snapshots, from options.policies.
create or replace function "app_private"."approval_policy"(subject_type text, action text)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select null::jsonb
$$;
revoke execute on function "app_private"."approval_policy"(text, text) from public, anon;
grant execute on function "app_private"."approval_policy"(text, text) to authenticated, service_role;

-- Whether the caller may decide the request's current step: a named user,
-- a holder of the permission, a member with the role or in the team, or a
-- delegate. The requester can't, unless the policy allows self-approval.
create or replace function "app_private"."approval_eligible"(request_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_req "app_private"."approval_requests"%rowtype;
  v_step jsonb;
  v_approvers jsonb;
  v_me uuid := auth.uid();
begin
  select * into v_req from "app_private"."approval_requests" r where r."id" = approval_eligible.request_id;
  if not found or v_me is null or v_req."status" <> 'pending' then
    return false;
  end if;
  if exists (
    select 1 from "app_private"."approval_decisions" x
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
  v_step := v_req."policy" -> 'steps' -> v_req."step";
  v_approvers := v_step -> 'approvers';
  if ((coalesce(v_approvers -> 'users', '[]'::jsonb) ? v_me::text)
    or (v_approvers ->> 'permission' is not null and coalesce(better_supabase.can('tenant', v_req."tenant_id", v_approvers ->> 'permission'), false))
    or (v_approvers ->> 'role' is not null and exists (
      select 1 from "better_supabase"."memberships" m
      where m."organization_id" = v_req."tenant_id" and m."user_id" = v_me and m."role" = v_approvers ->> 'role'
    ))
    or (v_approvers ->> 'team' is not null and false)) then
    return true;
  end if;
  if coalesce((v_step ->> 'escalated')::boolean, false) then
    v_approvers := v_step -> 'escalateTo';
    if ((coalesce(v_approvers -> 'users', '[]'::jsonb) ? v_me::text)
    or (v_approvers ->> 'permission' is not null and coalesce(better_supabase.can('tenant', v_req."tenant_id", v_approvers ->> 'permission'), false))
    or (v_approvers ->> 'role' is not null and exists (
      select 1 from "better_supabase"."memberships" m
      where m."organization_id" = v_req."tenant_id" and m."user_id" = v_me and m."role" = v_approvers ->> 'role'
    ))
    or (v_approvers ->> 'team' is not null and false)) then
      return true;
    end if;
  end if;
  return exists (
      select 1 from "app_private"."approval_decisions" x
      where x."request_id" = v_req."id" and x."step" = v_req."step"
        and x."decision" = 'delegated' and x."delegate_to" = v_me
    );
end;
$$;
revoke execute on function "app_private"."approval_eligible"(uuid) from public, anon;
grant execute on function "app_private"."approval_eligible"(uuid) to authenticated, service_role;

-- Notifies the current step's approvers (requested, reminder), its fallback
-- approvers (escalated), a delegate (delegated) or the requester (approved,
-- rejected, expired).
create or replace function "app_private"."approval_notify"(request_id uuid, kind text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req "app_private"."approval_requests"%rowtype;
  v_approvers jsonb;
  v_permission text;
  v_recipients uuid[] := '{}';
  v_claims text;
begin
  null;
end;
$$;
revoke execute on function "app_private"."approval_notify"(uuid, text) from public, anon, authenticated;

-- Runs what the final approval unlocks: the policy's state-machine
-- transition or job, or the grant or decision of the module that filed it.
create or replace function "app_private"."approval_finalize"(request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req "app_private"."approval_requests"%rowtype;
  v_run jsonb;
begin
  select * into v_req from "app_private"."approval_requests" r where r."id" = approval_finalize.request_id;
  v_run := v_req."policy" -> 'run';
  null;
  perform "app_private"."approval_notify"(v_req."id", 'approved');
end;
$$;
revoke execute on function "app_private"."approval_finalize"(uuid) from public, anon, authenticated;

-- Files a request under an explicit policy snapshot. request_approval and
-- the access-requests module call it after their own checks. requested_by
-- defaults to the caller.
drop function if exists "app_private"."open_approval"(uuid, text, text, text, jsonb, text, jsonb);
create or replace function "app_private"."open_approval"(tenant uuid, subject_type text, subject_id text, action text, policy jsonb, reason text, payload jsonb, requested_by uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_req "app_private"."approval_requests"%rowtype;
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
        from (select m."user_id" from "better_supabase"."memberships" m
        where m."organization_id" = open_approval.tenant
          and coalesce(better_supabase.can_user(m."user_id", 'tenant', open_approval.tenant, (e.value -> 'approvers' ->> 'permission')), false)) as u(id)
        where u.id is not null and (u.id is distinct from v_requester or coalesce((v_policy ->> 'selfApproval')::boolean, false))
      ) h on e.value -> 'required' = '"all"'::jsonb
    ));
    if exists (select 1 from jsonb_array_elements(v_policy -> 'steps') e where e.value -> 'required' = '0'::jsonb) then
      raise exception 'nobody holds the permission a step asks every holder of' using errcode = '22023', hint = 'APPROVAL_APPROVERS_EMPTY';
    end if;
  end if;
  insert into "app_private"."approval_requests" ("tenant_id", "subject_type", "subject_id", "action", "policy", "requested_by", "reason", "payload", "expires_at")
  values (open_approval.tenant, open_approval.subject_type, open_approval.subject_id, open_approval.action, v_policy, v_requester, open_approval.reason, coalesce(open_approval.payload, '{}'::jsonb),
    case when open_approval.policy ->> 'expiresIn' is not null then now() + (open_approval.policy ->> 'expiresIn')::interval end)
  on conflict ("subject_type", "subject_id", "action") where "status" = 'pending' do nothing
  returning * into v_req;
  if not found then
    raise exception 'this record already has a pending request for that action' using errcode = '23505', hint = 'APPROVAL_PENDING';
  end if;
  null;
  perform "app_private"."approval_notify"(v_req."id", 'requested');
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
revoke execute on function "app_private"."open_approval"(uuid, text, text, text, jsonb, text, jsonb, uuid) from public, anon, authenticated;



-- The policy a request snapshots: options.policies, as tenant policies are off.
create or replace function "app_private"."approval_effective_policy"(tenant uuid, subject_type text, action text, subject jsonb default '{}'::jsonb)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select "app_private"."approval_policy"(approval_effective_policy.subject_type, approval_effective_policy.action)
$$;
revoke execute on function "app_private"."approval_effective_policy"(uuid, text, text, jsonb) from public, anon, authenticated;

-- What a request for the subject type and action would need right now, with
-- subject as the request payload the tenant policies' conditions read; null
-- when nothing is required.
create or replace function "app_private"."approval_requirement"(tenant uuid, subject_type text, action text, subject jsonb default '{}'::jsonb)
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
  v_policy := "app_private"."approval_effective_policy"(approval_requirement.tenant, approval_requirement.subject_type, approval_requirement.action, approval_requirement.subject);
  if v_policy is null or not (coalesce(v_policy ->> 'mode', 'authorize') = 'confirm' or jsonb_array_length(coalesce(v_policy -> 'steps', '[]'::jsonb)) > 0) then
    return null;
  end if;
  return v_policy || jsonb_build_object('mode', coalesce(v_policy ->> 'mode', 'authorize'));
end;
$$;
revoke execute on function "app_private"."approval_requirement"(uuid, text, text, jsonb) from public, anon;
grant execute on function "app_private"."approval_requirement"(uuid, text, text, jsonb) to authenticated, service_role;

-- An app's own policy for one request, tightened by the policy the request
-- would get anyway (base, null when there is none): steps add up, the stricter
-- mode wins, self-approval needs both to allow it and the shorter expiry
-- applies. It never loosens base.
create or replace function "app_private"."approval_policy_tighten"(base jsonb, own jsonb)
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
    or (approval_policy_tighten.own ? 'managerOf' and true)
    or (approval_policy_tighten.own ->> 'expiresIn' is not null and (approval_policy_tighten.own ->> 'expiresIn')::interval <= interval '0') then
    raise exception 'policy must be { steps: [{ approvers: { permission, role, team, users }, required, escalateAfter, escalateTo }], mode, selfApproval, expiresIn }' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
  end if;
  for v_step in select * from jsonb_array_elements(v_steps) loop
    if jsonb_typeof(v_step) <> 'object' then
      raise exception 'policy must be { steps: [{ approvers: { permission, role, team, users }, required, escalateAfter, escalateTo }], mode, selfApproval, expiresIn }' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
    end if;
    for v_who in select a.w from (values (v_step -> 'approvers', true), (v_step -> 'escalateTo', v_step ? 'escalateTo')) a(w, checked) where a.checked loop
      if jsonb_typeof(v_who) is distinct from 'object'
        or not (v_who ?| array['permission', 'role', 'team', 'users', 'manager'])
        or (v_who ? 'manager' and true)
        or (v_who ? 'users' and (jsonb_typeof(v_who -> 'users') <> 'array'
          or exists (select 1 from jsonb_array_elements(v_who -> 'users') u
            where jsonb_typeof(u) <> 'string' or u #>> '{}' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'))) then
        raise exception 'policy must be { steps: [{ approvers: { permission, role, team, users }, required, escalateAfter, escalateTo }], mode, selfApproval, expiresIn }' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
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
      raise exception 'policy must be { steps: [{ approvers: { permission, role, team, users }, required, escalateAfter, escalateTo }], mode, selfApproval, expiresIn }' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
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
    raise exception 'policy must be { steps: [{ approvers: { permission, role, team, users }, required, escalateAfter, escalateTo }], mode, selfApproval, expiresIn }' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
end;
$$;
revoke execute on function "app_private"."approval_policy_tighten"(jsonb, jsonb) from public, anon, authenticated;

drop function if exists "app_private"."request_approval"(uuid, text, text, text, text, jsonb);
drop function if exists "app_private"."request_approval"(uuid, text, text, text, text, jsonb, jsonb);
drop function if exists "app_private"."request_approval"(uuid, text, text, text, text, jsonb, jsonb, text);
drop function if exists "app_private"."request_approval"(uuid, text, text, text, text, jsonb, text);
drop function if exists "app_private"."request_approval"(uuid, text, text, text, text, jsonb, jsonb, text, jsonb, uuid);
-- fingerprint: the hex SHA-256 of the request's canonical form, which
-- consume_approval checks before the approved action runs. The service role
-- may pass its own policy, which only tightens the configured and stored ones,
-- and requested_by, the user it files for, who can't approve it.
create or replace function "app_private"."request_approval"(tenant uuid, subject_type text, subject_id text, action text, reason text default null, payload jsonb default '{}'::jsonb, fingerprint text default null, policy jsonb default null, requested_by uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_policy jsonb := "app_private"."approval_effective_policy"(request_approval.tenant, request_approval.subject_type, request_approval.action, coalesce(request_approval.payload, '{}'::jsonb));
  v_service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  v_result jsonb;
  v_req "app_private"."approval_requests"%rowtype;
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
    v_policy := "app_private"."approval_policy_tighten"(v_policy, request_approval.policy);
  end if;
  if v_policy is null then
    raise exception 'no approval policy for this subject type and action' using errcode = '22023', hint = 'APPROVAL_POLICY_UNKNOWN';
  end if;
  if not (v_service or (coalesce(better_supabase.can('tenant', request_approval.tenant, 'approvals.request'), false) and true)) then
    raise exception 'not allowed to request approval for this record' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  if not (coalesce(v_policy ->> 'mode', 'authorize') = 'confirm' or jsonb_array_length(coalesce(v_policy -> 'steps', '[]'::jsonb)) > 0) then
    raise exception 'no approval is required for this request' using errcode = '22023', hint = 'APPROVAL_NOT_REQUIRED';
  end if;
  if request_approval.fingerprint is not null and request_approval.fingerprint !~ '^[0-9a-f]{64}$' then
    raise exception 'fingerprint must be a lowercase hex SHA-256' using errcode = '22023', hint = 'APPROVAL_FINGERPRINT_INVALID';
  end if;
  v_result := "app_private"."open_approval"(request_approval.tenant, request_approval.subject_type, request_approval.subject_id, request_approval.action, v_policy, request_approval.reason, request_approval.payload, coalesce(request_approval.requested_by, auth.uid()));
  if request_approval.fingerprint is not null then
    update "app_private"."approval_requests" x set "fingerprint" = request_approval.fingerprint
    where x."id" = (v_result ->> 'id')::uuid and x."status" = 'pending';
  end if;
  select * into v_req from "app_private"."approval_requests" x where x."id" = (v_result ->> 'id')::uuid;
  if found then
    return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'mode', coalesce(v_req."policy" ->> 'mode', 'authorize'), 'fingerprint', v_req."fingerprint", 'consumedAt', v_req."consumed_at", 'createdAt', v_req."created_at");
  end if;
  return v_result;
end;
$$;
revoke execute on function "app_private"."request_approval"(uuid, text, text, text, text, jsonb, text, jsonb, uuid) from public, anon;
grant execute on function "app_private"."request_approval"(uuid, text, text, text, text, jsonb, text, jsonb, uuid) to authenticated, service_role;

-- Uses an approved request once, right before the approved action runs. The
-- fingerprint must match the one the request was filed with, so an approval
-- never covers a request that changed after it was decided.
create or replace function "app_private"."consume_approval"(request_id uuid, fingerprint text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_req "app_private"."approval_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_req from "app_private"."approval_requests" r where r."id" = consume_approval.request_id for update;
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
  update "app_private"."approval_requests" r set "consumed_at" = now()
    where r."id" = v_req."id" returning * into v_req;
  null;
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'mode', coalesce(v_req."policy" ->> 'mode', 'authorize'), 'fingerprint', v_req."fingerprint", 'consumedAt', v_req."consumed_at", 'createdAt', v_req."created_at");
end;
$$;
revoke execute on function "app_private"."consume_approval"(uuid, text) from public, anon;
grant execute on function "app_private"."consume_approval"(uuid, text) to authenticated, service_role;

-- Approves or rejects the current step. Enough approvals move the request
-- to the next step, and the last step runs the policy's action. The service
-- role decides for the user in decided_by, who is recorded as the approver;
-- it skips the approver check, never the requester's.
drop function if exists "app_private"."decide_approval"(uuid, text, text);
create or replace function "app_private"."decide_approval"(request_id uuid, decision text, comment text default null, decided_by uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_req "app_private"."approval_requests"%rowtype;
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
  select * into v_req from "app_private"."approval_requests" r where r."id" = decide_approval.request_id for update;
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
      select 1 from "app_private"."approval_decisions" x
      where x."request_id" = v_req."id" and x."step" = v_req."step" and x."approver" = v_actor
    ) then
      raise exception 'this user already decided this step' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
    end if;
  elsif not "app_private"."approval_eligible"(v_req."id") then
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
  insert into "app_private"."approval_decisions" ("request_id", "tenant_id", "step", "approver", "decision", "comment")
  values (v_req."id", v_req."tenant_id", v_req."step", v_actor, decide_approval.decision, decide_approval.comment);
  if decide_approval.decision = 'rejected' then
    update "app_private"."approval_requests" r set "status" = 'rejected', "decided_at" = now()
      where r."id" = v_req."id" returning * into v_req;
    null;
    perform "app_private"."approval_notify"(v_req."id", 'rejected');
  else
    select count(*) into v_count from "app_private"."approval_decisions" x
      where x."request_id" = v_req."id" and x."step" = v_req."step" and x."decision" = 'approved';
    if v_req."policy" ->> 'mode' = 'confirm' and v_req."requested_by" = v_actor then
      update "app_private"."approval_requests" r set "status" = 'approved', "decided_at" = now()
        where r."id" = v_req."id" returning * into v_req;
      perform "app_private"."approval_finalize"(v_req."id");
    elsif v_count >= coalesce((v_req."policy" -> 'steps' -> v_req."step" ->> 'required')::integer, 1) then
      if v_req."step" + 1 >= jsonb_array_length(v_req."policy" -> 'steps') then
        update "app_private"."approval_requests" r set "status" = 'approved', "decided_at" = now()
          where r."id" = v_req."id" returning * into v_req;
        perform "app_private"."approval_finalize"(v_req."id");
      else
        update "app_private"."approval_requests" r set "step" = r."step" + 1, "reminded_at" = null
          where r."id" = v_req."id" returning * into v_req;
        perform "app_private"."approval_notify"(v_req."id", 'requested');
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
revoke execute on function "app_private"."decide_approval"(uuid, text, text, uuid) from public, anon;
grant execute on function "app_private"."decide_approval"(uuid, text, text, uuid) to authenticated, service_role;

-- Hands the caller's place on the current step to another user.
create or replace function "app_private"."delegate_approval"(request_id uuid, to_user uuid, comment text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_req "app_private"."approval_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_req from "app_private"."approval_requests" r where r."id" = delegate_approval.request_id for update;
  if not found then
    raise exception 'approval request not found' using errcode = 'P0002', hint = 'APPROVAL_NOT_FOUND';
  end if;
  if v_req."status" <> 'pending' then
    raise exception 'this request is no longer pending' using errcode = '22023', hint = 'APPROVAL_CLOSED';
  end if;
  if not "app_private"."approval_eligible"(v_req."id") then
    raise exception 'not an approver for this step' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  if delegate_approval.to_user is null or delegate_approval.to_user = auth.uid() or delegate_approval.to_user = v_req."requested_by" then
    raise exception 'delegate to another user than yourself or the requester' using errcode = '22023', hint = 'APPROVAL_DELEGATE_INVALID';
  end if;
  if not exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = v_req."tenant_id" and m."user_id" = delegate_approval.to_user
  ) then
    raise exception 'the delegate is not a member of this organization' using errcode = '22023', hint = 'APPROVAL_DELEGATE_INVALID';
  end if;
  insert into "app_private"."approval_decisions" ("request_id", "tenant_id", "step", "approver", "decision", "delegate_to", "comment")
  values (v_req."id", v_req."tenant_id", v_req."step", auth.uid(), 'delegated', delegate_approval.to_user, delegate_approval.comment);
  null;
  perform "app_private"."approval_notify"(v_req."id", 'delegated');
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'mode', coalesce(v_req."policy" ->> 'mode', 'authorize'), 'fingerprint', v_req."fingerprint", 'consumedAt', v_req."consumed_at", 'createdAt', v_req."created_at");
end;
$$;
revoke execute on function "app_private"."delegate_approval"(uuid, uuid, text) from public, anon;
grant execute on function "app_private"."delegate_approval"(uuid, uuid, text) to authenticated, service_role;

create or replace function "app_private"."cancel_approval"(request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req "app_private"."approval_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_req from "app_private"."approval_requests" r where r."id" = cancel_approval.request_id for update;
  if not found then
    raise exception 'approval request not found' using errcode = 'P0002', hint = 'APPROVAL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_req."requested_by" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_req."tenant_id", 'approvals.manage'), false)) then
    raise exception 'only the requester or a manager can cancel this request' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  if v_req."status" <> 'pending' then
    raise exception 'this request is no longer pending' using errcode = '22023', hint = 'APPROVAL_CLOSED';
  end if;
  update "app_private"."approval_requests" r set "status" = 'cancelled', "decided_at" = now()
    where r."id" = v_req."id" returning * into v_req;
  null;
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'mode', coalesce(v_req."policy" ->> 'mode', 'authorize'), 'fingerprint', v_req."fingerprint", 'consumedAt', v_req."consumed_at", 'createdAt', v_req."created_at");
end;
$$;
revoke execute on function "app_private"."cancel_approval"(uuid) from public, anon;
grant execute on function "app_private"."cancel_approval"(uuid) to authenticated, service_role;

create or replace function "app_private"."get_approval"(request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_req "app_private"."approval_requests"%rowtype;
begin
  select * into v_req from "app_private"."approval_requests" r where r."id" = get_approval.request_id;
  if not found then
    raise exception 'approval request not found' using errcode = 'P0002', hint = 'APPROVAL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_req."requested_by" = auth.uid(), false) or "app_private"."approval_eligible"(v_req."id")
    or (coalesce(better_supabase.can('tenant', v_req."tenant_id", 'approvals.read'), false) and (true))) then
    raise exception 'approval request not found' using errcode = 'P0002', hint = 'APPROVAL_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'mode', coalesce(v_req."policy" ->> 'mode', 'authorize'), 'fingerprint', v_req."fingerprint", 'consumedAt', v_req."consumed_at", 'createdAt', v_req."created_at") || jsonb_build_object(
    'canDecide', "app_private"."approval_eligible"(v_req."id"),
    'decisions', coalesce((
      select jsonb_agg(jsonb_build_object('id', x."id", 'step', x."step", 'approver', x."approver", 'decision', x."decision", 'delegateTo', x."delegate_to", 'comment', x."comment", 'createdAt', x."created_at") order by x."created_at", x."id")
      from "app_private"."approval_decisions" x where x."request_id" = v_req."id"
    ), '[]'::jsonb)
  );
end;
$$;
revoke execute on function "app_private"."get_approval"(uuid) from public, anon;
grant execute on function "app_private"."get_approval"(uuid) to authenticated, service_role;

-- assigned: only requests whose current step the caller can decide.
create or replace function "app_private"."list_approvals"(tenant uuid, status text default 'pending', assigned boolean default false, subject_type text default null, subject_id text default null, page_size integer default 50, before timestamptz default null)
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
    from "app_private"."approval_requests" x
    where x."tenant_id" = list_approvals.tenant
      and (list_approvals.status is null or x."status" = list_approvals.status)
      and (list_approvals.subject_type is null or x."subject_type" = list_approvals.subject_type)
      and (list_approvals.subject_id is null or x."subject_id" = list_approvals.subject_id)
      and (list_approvals.before is null or x."created_at" < list_approvals.before)
      and case
        when list_approvals.assigned then "app_private"."approval_eligible"(x."id")
        else x."requested_by" = auth.uid() or (v_read and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (true))) or "app_private"."approval_eligible"(x."id")
      end
    order by x."created_at" desc, x."id"
    limit least(greatest(coalesce(list_approvals.page_size, 50), 1), 200)
  ) t;
  return v_rows;
end;
$$;
revoke execute on function "app_private"."list_approvals"(uuid, text, boolean, text, text, integer, timestamptz) from public, anon;
grant execute on function "app_private"."list_approvals"(uuid, text, boolean, text, text, integer, timestamptz) to authenticated, service_role;

-- Whether the subject's latest request for the action was approved.
create or replace function "app_private"."is_approved"(subject_type text, subject_id text, action text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select x."status" = 'approved' from "app_private"."approval_requests" x
    where x."subject_type" = is_approved.subject_type and x."subject_id" = is_approved.subject_id and x."action" = is_approved.action
    order by x."created_at" desc limit 1
  ), false)
$$;
revoke execute on function "app_private"."is_approved"(text, text, text) from public, anon;
grant execute on function "app_private"."is_approved"(text, text, text) to authenticated, service_role;

-- Closes pending requests past expires_at. Run it from pg_cron:
--   select cron.schedule('expire-approvals', '*/15 * * * *', 'select "app_private"."expire_approvals"()');
create or replace function "app_private"."expire_approvals"(max_requests integer default 500)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req "app_private"."approval_requests"%rowtype;
  v_count integer := 0;
begin
  for v_req in
    update "app_private"."approval_requests" r set "status" = 'expired', "decided_at" = now()
    where r."id" in (
      select x."id" from "app_private"."approval_requests" x
      where x."status" = 'pending' and x."expires_at" <= now()
      order by x."expires_at"
      limit greatest(coalesce(expire_approvals.max_requests, 500), 1)
      for update skip locked
    )
    returning r.*
  loop
    null;
    perform "app_private"."approval_notify"(v_req."id", 'expired');
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "app_private"."expire_approvals"(integer) from public, anon, authenticated;
grant execute on function "app_private"."expire_approvals"(integer) to service_role;

-- Reminds the approvers of requests pending longer than `after`, once per
-- `after`. Run it from pg_cron like expire_approvals.
create or replace function "app_private"."remind_approvals"(after interval default interval '1 day', max_requests integer default 200)
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
    update "app_private"."approval_requests" r set "reminded_at" = now()
    where r."id" in (
      select x."id" from "app_private"."approval_requests" x
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
    perform "app_private"."approval_notify"(v_id, 'reminder');
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "app_private"."remind_approvals"(interval, integer) from public, anon, authenticated;
grant execute on function "app_private"."remind_approvals"(interval, integer) to service_role;

-- Lets the fallback approvers (escalateTo) of a step decide it too once the
-- step has waited its escalateAfter, and asks them. Run it from pg_cron like
-- remind_approvals.
create or replace function "app_private"."escalate_approvals"(max_requests integer default 200)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req "app_private"."approval_requests"%rowtype;
  v_count integer := 0;
begin
  for v_req in
    select * from "app_private"."approval_requests" r
    where r."status" = 'pending'
      and (r."expires_at" is null or r."expires_at" > now())
      and r."policy" -> 'steps' -> r."step" ? 'escalateAfter'
      and not coalesce((r."policy" -> 'steps' -> r."step" ->> 'escalated')::boolean, false)
      and coalesce((
        select max(x."created_at") from "app_private"."approval_decisions" x
        where x."request_id" = r."id" and x."step" = r."step" - 1
      ), r."created_at") + (r."policy" -> 'steps' -> r."step" ->> 'escalateAfter')::interval <= now()
    order by r."created_at"
    limit greatest(coalesce(escalate_approvals.max_requests, 200), 1)
    for update skip locked
  loop
    update "app_private"."approval_requests" r set "policy" = jsonb_set(r."policy", array['steps', (r."step")::text, 'escalated'], 'true'::jsonb)
    where r."id" = v_req."id"
    returning * into v_req;
    null;
    perform "app_private"."approval_notify"(v_req."id", 'escalated');
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "app_private"."escalate_approvals"(integer) from public, anon, authenticated;
grant execute on function "app_private"."escalate_approvals"(integer) to service_role;

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
drop policy if exists bsb_tenant_scope on "app_private"."approval_requests";
drop policy if exists bsb_tenant_scope_select on "app_private"."approval_requests";
create policy bsb_tenant_scope_select on "app_private"."approval_requests" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('approvals.read')) or "requested_by" = (select auth.uid()))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."approval_requests";
create policy bsb_tenant_scope_insert on "app_private"."approval_requests" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."approval_requests";
create policy bsb_tenant_scope_update on "app_private"."approval_requests" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."approval_requests";
create policy bsb_tenant_scope_delete on "app_private"."approval_requests" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."approval_decisions";
drop policy if exists bsb_tenant_scope_select on "app_private"."approval_decisions";
create policy bsb_tenant_scope_select on "app_private"."approval_decisions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('approvals.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."approval_decisions";
create policy bsb_tenant_scope_insert on "app_private"."approval_decisions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."approval_decisions";
create policy bsb_tenant_scope_update on "app_private"."approval_decisions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."approval_decisions";
create policy bsb_tenant_scope_delete on "app_private"."approval_decisions" as restrictive
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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_077_approvals.sql
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

-- ==== api schema: schema supabase/schemas/900_better_supabase_077_approvals.sql
-- better-supabase module: approvals
-- @bsb-block approvals@1 managed
-- @bsb-hash sha256:80de9807420c115ea25c4023bf4c2916528cfd846bc65cb28843f09b553d8f21
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
  v_step := v_req."policy" -> 'steps' -> v_req."step";
  v_approvers := v_step -> 'approvers';
  if ((coalesce(v_approvers -> 'users', '[]'::jsonb) ? v_me::text)
    or (v_approvers ->> 'permission' is not null and coalesce(better_supabase.can('tenant', v_req."tenant_id", v_approvers ->> 'permission'), false))
    or (v_approvers ->> 'role' is not null and exists (
      select 1 from "better_supabase"."memberships" m
      where m."organization_id" = v_req."tenant_id" and m."user_id" = v_me and m."role" = v_approvers ->> 'role'
    ))
    or (v_approvers ->> 'team' is not null and false)) then
    return true;
  end if;
  if coalesce((v_step ->> 'escalated')::boolean, false) then
    v_approvers := v_step -> 'escalateTo';
    if ((coalesce(v_approvers -> 'users', '[]'::jsonb) ? v_me::text)
    or (v_approvers ->> 'permission' is not null and coalesce(better_supabase.can('tenant', v_req."tenant_id", v_approvers ->> 'permission'), false))
    or (v_approvers ->> 'role' is not null and exists (
      select 1 from "better_supabase"."memberships" m
      where m."organization_id" = v_req."tenant_id" and m."user_id" = v_me and m."role" = v_approvers ->> 'role'
    ))
    or (v_approvers ->> 'team' is not null and false)) then
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
        from (select m."user_id" from "better_supabase"."memberships" m
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
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'mode', coalesce(v_req."policy" ->> 'mode', 'authorize'), 'fingerprint', v_req."fingerprint", 'consumedAt', v_req."consumed_at", 'createdAt', v_req."created_at");
end;
$$;
revoke execute on function "better_supabase"."open_approval"(uuid, text, text, text, jsonb, text, jsonb, uuid) from public, anon, authenticated;



-- The policy a request snapshots: options.policies, as tenant policies are off.
create or replace function "better_supabase"."approval_effective_policy"(tenant uuid, subject_type text, action text, subject jsonb default '{}'::jsonb)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select "better_supabase"."approval_policy"(approval_effective_policy.subject_type, approval_effective_policy.action)
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
    or (approval_policy_tighten.own ? 'managerOf' and true)
    or (approval_policy_tighten.own ->> 'expiresIn' is not null and (approval_policy_tighten.own ->> 'expiresIn')::interval <= interval '0') then
    raise exception 'policy must be { steps: [{ approvers: { permission, role, team, users }, required, escalateAfter, escalateTo }], mode, selfApproval, expiresIn }' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
  end if;
  for v_step in select * from jsonb_array_elements(v_steps) loop
    if jsonb_typeof(v_step) <> 'object' then
      raise exception 'policy must be { steps: [{ approvers: { permission, role, team, users }, required, escalateAfter, escalateTo }], mode, selfApproval, expiresIn }' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
    end if;
    for v_who in select a.w from (values (v_step -> 'approvers', true), (v_step -> 'escalateTo', v_step ? 'escalateTo')) a(w, checked) where a.checked loop
      if jsonb_typeof(v_who) is distinct from 'object'
        or not (v_who ?| array['permission', 'role', 'team', 'users', 'manager'])
        or (v_who ? 'manager' and true)
        or (v_who ? 'users' and (jsonb_typeof(v_who -> 'users') <> 'array'
          or exists (select 1 from jsonb_array_elements(v_who -> 'users') u
            where jsonb_typeof(u) <> 'string' or u #>> '{}' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'))) then
        raise exception 'policy must be { steps: [{ approvers: { permission, role, team, users }, required, escalateAfter, escalateTo }], mode, selfApproval, expiresIn }' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
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
      raise exception 'policy must be { steps: [{ approvers: { permission, role, team, users }, required, escalateAfter, escalateTo }], mode, selfApproval, expiresIn }' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
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
    raise exception 'policy must be { steps: [{ approvers: { permission, role, team, users }, required, escalateAfter, escalateTo }], mode, selfApproval, expiresIn }' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
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
  if not (v_service or (coalesce(better_supabase.can('tenant', request_approval.tenant, 'approvals.request'), false) and true)) then
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
  null;
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
    null;
    perform "better_supabase"."approval_notify"(v_req."id", 'rejected');
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
  if delegate_approval.to_user is null or delegate_approval.to_user = auth.uid() or delegate_approval.to_user = v_req."requested_by" then
    raise exception 'delegate to another user than yourself or the requester' using errcode = '22023', hint = 'APPROVAL_DELEGATE_INVALID';
  end if;
  if not exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = v_req."tenant_id" and m."user_id" = delegate_approval.to_user
  ) then
    raise exception 'the delegate is not a member of this organization' using errcode = '22023', hint = 'APPROVAL_DELEGATE_INVALID';
  end if;
  insert into "better_supabase"."approval_decisions" ("request_id", "tenant_id", "step", "approver", "decision", "delegate_to", "comment")
  values (v_req."id", v_req."tenant_id", v_req."step", auth.uid(), 'delegated', delegate_approval.to_user, delegate_approval.comment);
  null;
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
  null;
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
    or (coalesce(better_supabase.can('tenant', v_req."tenant_id", 'approvals.read'), false) and (true))) then
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
    null;
    perform "better_supabase"."approval_notify"(v_req."id", 'escalated');
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."escalate_approvals"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."escalate_approvals"(integer) to service_role;

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
    or ("tenant_id" in (select better_supabase.tenant_ids_with('approvals.read')) or "requested_by" = (select auth.uid()))
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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_077_approvals.sql
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

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_077_approvals.sql
-- better-supabase module: approvals
-- @bsb-block approvals@1 managed
-- @bsb-hash sha256:d1c77b027cdaff5ae82a127d1adae7ca1ffaa7324b9cb6ee59fbb42a7617175e
-- Approval requests with steps per subject type and action: approvers by permission, role, team, user or the requester's manager, a required count, delegation, expiry and reminders. Tenants tighten the configured policies with conditions and a confirm or authorize mode, and an approval is consumed once against a request fingerprint. The final approval runs a state-machine transition or a job.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.as_column_type(value text, target anyelement)
returns anyelement
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return value;
end;
$$;
revoke execute on function better_supabase.as_column_type(text, anyelement) from public;
grant execute on function better_supabase.as_column_type(text, anyelement) to anon, authenticated, service_role;

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
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- better_supabase.approval_requests is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."approval_requests" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."approval_requests" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."approval_requests" add column if not exists "subject_type" text;
alter table "better_supabase"."approval_requests" add column if not exists "subject_id" text;
alter table "better_supabase"."approval_requests" add column if not exists "action" text;
alter table "better_supabase"."approval_requests" add column if not exists "policy" jsonb;
alter table "better_supabase"."approval_requests" add column if not exists "step" integer not null default 0 check ("step" >= 0);
alter table "better_supabase"."approval_requests" add column if not exists "status" text not null default 'pending' check ("status" in ('pending', 'approved', 'rejected', 'cancelled', 'expired'));
alter table "better_supabase"."approval_requests" add column if not exists "requested_by" uuid;
alter table "better_supabase"."approval_requests" add column if not exists "reason" text check ("reason" is null or length("reason") <= 2000);
alter table "better_supabase"."approval_requests" add column if not exists "payload" jsonb not null default '{}'::jsonb;
alter table "better_supabase"."approval_requests" add column if not exists "expires_at" timestamptz;
alter table "better_supabase"."approval_requests" add column if not exists "reminded_at" timestamptz;
alter table "better_supabase"."approval_requests" add column if not exists "decided_at" timestamptz;
alter table "better_supabase"."approval_requests" add column if not exists "fingerprint" text check ("fingerprint" is null or "fingerprint" ~ '^[0-9a-f]{64}$');
alter table "better_supabase"."approval_requests" add column if not exists "consumed_at" timestamptz;
alter table "better_supabase"."approval_requests" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."approval_requests" add column if not exists "fingerprint" text check ("fingerprint" is null or "fingerprint" ~ '^[0-9a-f]{64}$');
alter table "better_supabase"."approval_requests" add column if not exists "consumed_at" timestamptz;
create unique index if not exists "approval_requests_pending_idx" on "better_supabase"."approval_requests" ("subject_type", "subject_id", "action") where "status" = 'pending';
create index if not exists "approval_requests_tenant_idx" on "better_supabase"."approval_requests" ("tenant_id", "status", "created_at" desc);
alter table "better_supabase"."approval_requests" enable row level security;
grant select on "better_supabase"."approval_requests" to authenticated;
grant all on "better_supabase"."approval_requests" to service_role;
drop policy if exists bsb_approval_requests_select on "better_supabase"."approval_requests";
create policy bsb_approval_requests_select on "better_supabase"."approval_requests"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('approvals.read')) or "requested_by" = (select auth.uid()));

-- better_supabase.approval_decisions is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."approval_decisions" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."approval_decisions" add column if not exists "request_id" uuid references "better_supabase"."approval_requests" ("id") on delete cascade;
alter table "better_supabase"."approval_decisions" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."approval_decisions" add column if not exists "step" integer;
alter table "better_supabase"."approval_decisions" add column if not exists "approver" uuid;
alter table "better_supabase"."approval_decisions" add column if not exists "decision" text check ("decision" in ('approved', 'rejected', 'delegated'));
alter table "better_supabase"."approval_decisions" add column if not exists "delegate_to" uuid;
alter table "better_supabase"."approval_decisions" add column if not exists "comment" text check ("comment" is null or length("comment") <= 2000);
alter table "better_supabase"."approval_decisions" add column if not exists "created_at" timestamptz not null default clock_timestamp();
create unique index if not exists "approval_decisions_request_id_step_approver_key" on "better_supabase"."approval_decisions" ("request_id", "step", "approver");
create index if not exists "approval_decisions_delegate_idx" on "better_supabase"."approval_decisions" ("delegate_to") where "delegate_to" is not null;
alter table "better_supabase"."approval_decisions" enable row level security;
grant select on "better_supabase"."approval_decisions" to authenticated;
grant all on "better_supabase"."approval_decisions" to service_role;
drop policy if exists bsb_approval_decisions_select on "better_supabase"."approval_decisions";
create policy bsb_approval_decisions_select on "better_supabase"."approval_decisions"
  for select to authenticated
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
  v_step := v_req."policy" -> 'steps' -> v_req."step";
  v_approvers := v_step -> 'approvers';
  if ((coalesce(v_approvers -> 'users', '[]'::jsonb) ? v_me::text)
    or (v_approvers ->> 'permission' is not null and coalesce(better_supabase.can('tenant', v_req."tenant_id", v_approvers ->> 'permission'), false))
    or (v_approvers ->> 'role' is not null and exists (
      select 1 from "better_supabase"."memberships" m
      where m."organization_id" = v_req."tenant_id" and m."user_id" = v_me and m."role" = v_approvers ->> 'role'
    ))
    or (v_approvers ->> 'team' is not null and false)) then
    return true;
  end if;
  if coalesce((v_step ->> 'escalated')::boolean, false) then
    v_approvers := v_step -> 'escalateTo';
    if ((coalesce(v_approvers -> 'users', '[]'::jsonb) ? v_me::text)
    or (v_approvers ->> 'permission' is not null and coalesce(better_supabase.can('tenant', v_req."tenant_id", v_approvers ->> 'permission'), false))
    or (v_approvers ->> 'role' is not null and exists (
      select 1 from "better_supabase"."memberships" m
      where m."organization_id" = v_req."tenant_id" and m."user_id" = v_me and m."role" = v_approvers ->> 'role'
    ))
    or (v_approvers ->> 'team' is not null and false)) then
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
        from (select m."user_id" from "better_supabase"."memberships" m
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
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'mode', coalesce(v_req."policy" ->> 'mode', 'authorize'), 'fingerprint', v_req."fingerprint", 'consumedAt', v_req."consumed_at", 'createdAt', v_req."created_at");
end;
$$;
revoke execute on function "better_supabase"."open_approval"(uuid, text, text, text, jsonb, text, jsonb, uuid) from public, anon, authenticated;



-- The policy a request snapshots: options.policies, as tenant policies are off.
create or replace function "better_supabase"."approval_effective_policy"(tenant uuid, subject_type text, action text, subject jsonb default '{}'::jsonb)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select "better_supabase"."approval_policy"(approval_effective_policy.subject_type, approval_effective_policy.action)
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
    or (approval_policy_tighten.own ? 'managerOf' and true)
    or (approval_policy_tighten.own ->> 'expiresIn' is not null and (approval_policy_tighten.own ->> 'expiresIn')::interval <= interval '0') then
    raise exception 'policy must be { steps: [{ approvers: { permission, role, team, users }, required, escalateAfter, escalateTo }], mode, selfApproval, expiresIn }' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
  end if;
  for v_step in select * from jsonb_array_elements(v_steps) loop
    if jsonb_typeof(v_step) <> 'object' then
      raise exception 'policy must be { steps: [{ approvers: { permission, role, team, users }, required, escalateAfter, escalateTo }], mode, selfApproval, expiresIn }' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
    end if;
    for v_who in select a.w from (values (v_step -> 'approvers', true), (v_step -> 'escalateTo', v_step ? 'escalateTo')) a(w, checked) where a.checked loop
      if jsonb_typeof(v_who) is distinct from 'object'
        or not (v_who ?| array['permission', 'role', 'team', 'users', 'manager'])
        or (v_who ? 'manager' and true)
        or (v_who ? 'users' and (jsonb_typeof(v_who -> 'users') <> 'array'
          or exists (select 1 from jsonb_array_elements(v_who -> 'users') u
            where jsonb_typeof(u) <> 'string' or u #>> '{}' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'))) then
        raise exception 'policy must be { steps: [{ approvers: { permission, role, team, users }, required, escalateAfter, escalateTo }], mode, selfApproval, expiresIn }' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
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
      raise exception 'policy must be { steps: [{ approvers: { permission, role, team, users }, required, escalateAfter, escalateTo }], mode, selfApproval, expiresIn }' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
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
    raise exception 'policy must be { steps: [{ approvers: { permission, role, team, users }, required, escalateAfter, escalateTo }], mode, selfApproval, expiresIn }' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
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
  if not (v_service or (coalesce(better_supabase.can('tenant', request_approval.tenant, 'approvals.request'), false) and true)) then
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
  null;
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
  values (v_req."id", v_req."tenant_id", v_req."step", v_actor, better_supabase.as_column_type(decide_approval.decision, (null::"better_supabase"."approval_decisions")."decision"), decide_approval.comment);
  if decide_approval.decision = 'rejected' then
    update "better_supabase"."approval_requests" r set "status" = 'rejected', "decided_at" = now()
      where r."id" = v_req."id" returning * into v_req;
    null;
    perform "better_supabase"."approval_notify"(v_req."id", 'rejected');
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
  if delegate_approval.to_user is null or delegate_approval.to_user = auth.uid() or delegate_approval.to_user = v_req."requested_by" then
    raise exception 'delegate to another user than yourself or the requester' using errcode = '22023', hint = 'APPROVAL_DELEGATE_INVALID';
  end if;
  if not exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = v_req."tenant_id" and m."user_id" = delegate_approval.to_user
  ) then
    raise exception 'the delegate is not a member of this organization' using errcode = '22023', hint = 'APPROVAL_DELEGATE_INVALID';
  end if;
  insert into "better_supabase"."approval_decisions" ("request_id", "tenant_id", "step", "approver", "decision", "delegate_to", "comment")
  values (v_req."id", v_req."tenant_id", v_req."step", auth.uid(), 'delegated', delegate_approval.to_user, delegate_approval.comment);
  null;
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
  null;
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
    or (coalesce(better_supabase.can('tenant', v_req."tenant_id", 'approvals.read'), false) and (true))) then
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
      and (list_approvals.status is null or x."status"::text = list_approvals.status)
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
    null;
    perform "better_supabase"."approval_notify"(v_req."id", 'escalated');
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."escalate_approvals"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."escalate_approvals"(integer) to service_role;

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
    or ("tenant_id" in (select better_supabase.tenant_ids_with('approvals.read')) or "requested_by" = (select auth.uid()))
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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_077_approvals.sql
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

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_077_approvals.sql
-- better-supabase module: approvals
-- @bsb-block approvals@1 managed
-- @bsb-hash sha256:f8d47792dc9126782966af44d94392dad361f209baf9794d054dda1e19c1e129
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
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."approval_requests" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
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
create index if not exists "approval_requests_tenant_idx" on "better_supabase"."approval_requests" ("org_id", "status", "created_at" desc);
alter table "better_supabase"."approval_requests" enable row level security;
revoke all on "better_supabase"."approval_requests" from public, anon, authenticated;
grant select on "better_supabase"."approval_requests" to authenticated;
grant all on "better_supabase"."approval_requests" to service_role;
drop policy if exists approval_requests_read on "better_supabase"."approval_requests";
create policy approval_requests_read on "better_supabase"."approval_requests"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('approvals.read')) or "requested_by" = (select auth.uid()));

create table if not exists "better_supabase"."approval_decisions" (
  "id" uuid primary key default gen_random_uuid(),
  "request_id" uuid not null references "better_supabase"."approval_requests" ("id") on delete cascade,
  "org_id" uuid not null,
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
  using ("org_id" in (select better_supabase.tenant_ids_with('approvals.read')));

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
  v_step := v_req."policy" -> 'steps' -> v_req."step";
  v_approvers := v_step -> 'approvers';
  if ((coalesce(v_approvers -> 'users', '[]'::jsonb) ? v_me::text)
    or (v_approvers ->> 'permission' is not null and coalesce(better_supabase.can('tenant', v_req."org_id", v_approvers ->> 'permission'), false))
    or (v_approvers ->> 'role' is not null and exists (
      select 1 from "better_supabase"."memberships" m
      where m."org_id" = v_req."org_id" and m."user_id" = v_me and m."role" = v_approvers ->> 'role'
    ))
    or (v_approvers ->> 'team' is not null and false)) then
    return true;
  end if;
  if coalesce((v_step ->> 'escalated')::boolean, false) then
    v_approvers := v_step -> 'escalateTo';
    if ((coalesce(v_approvers -> 'users', '[]'::jsonb) ? v_me::text)
    or (v_approvers ->> 'permission' is not null and coalesce(better_supabase.can('tenant', v_req."org_id", v_approvers ->> 'permission'), false))
    or (v_approvers ->> 'role' is not null and exists (
      select 1 from "better_supabase"."memberships" m
      where m."org_id" = v_req."org_id" and m."user_id" = v_me and m."role" = v_approvers ->> 'role'
    ))
    or (v_approvers ->> 'team' is not null and false)) then
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
        from (select m."user_id" from "better_supabase"."memberships" m
        where m."org_id" = open_approval.tenant
          and coalesce(better_supabase.can_user(m."user_id", 'tenant', open_approval.tenant, (e.value -> 'approvers' ->> 'permission')), false)) as u(id)
        where u.id is not null and (u.id is distinct from v_requester or coalesce((v_policy ->> 'selfApproval')::boolean, false))
      ) h on e.value -> 'required' = '"all"'::jsonb
    ));
    if exists (select 1 from jsonb_array_elements(v_policy -> 'steps') e where e.value -> 'required' = '0'::jsonb) then
      raise exception 'nobody holds the permission a step asks every holder of' using errcode = '22023', hint = 'APPROVAL_APPROVERS_EMPTY';
    end if;
  end if;
  insert into "better_supabase"."approval_requests" ("org_id", "subject_type", "subject_id", "action", "policy", "requested_by", "reason", "payload", "expires_at")
  values (open_approval.tenant, open_approval.subject_type, open_approval.subject_id, open_approval.action, v_policy, v_requester, open_approval.reason, coalesce(open_approval.payload, '{}'::jsonb),
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
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."org_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'mode', coalesce(v_req."policy" ->> 'mode', 'authorize'), 'fingerprint', v_req."fingerprint", 'consumedAt', v_req."consumed_at", 'createdAt', v_req."created_at");
end;
$$;
revoke execute on function "better_supabase"."open_approval"(uuid, text, text, text, jsonb, text, jsonb, uuid) from public, anon, authenticated;



-- The policy a request snapshots: options.policies, as tenant policies are off.
create or replace function "better_supabase"."approval_effective_policy"(tenant uuid, subject_type text, action text, subject jsonb default '{}'::jsonb)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select "better_supabase"."approval_policy"(approval_effective_policy.subject_type, approval_effective_policy.action)
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
    or (approval_policy_tighten.own ? 'managerOf' and true)
    or (approval_policy_tighten.own ->> 'expiresIn' is not null and (approval_policy_tighten.own ->> 'expiresIn')::interval <= interval '0') then
    raise exception 'policy must be { steps: [{ approvers: { permission, role, team, users }, required, escalateAfter, escalateTo }], mode, selfApproval, expiresIn }' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
  end if;
  for v_step in select * from jsonb_array_elements(v_steps) loop
    if jsonb_typeof(v_step) <> 'object' then
      raise exception 'policy must be { steps: [{ approvers: { permission, role, team, users }, required, escalateAfter, escalateTo }], mode, selfApproval, expiresIn }' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
    end if;
    for v_who in select a.w from (values (v_step -> 'approvers', true), (v_step -> 'escalateTo', v_step ? 'escalateTo')) a(w, checked) where a.checked loop
      if jsonb_typeof(v_who) is distinct from 'object'
        or not (v_who ?| array['permission', 'role', 'team', 'users', 'manager'])
        or (v_who ? 'manager' and true)
        or (v_who ? 'users' and (jsonb_typeof(v_who -> 'users') <> 'array'
          or exists (select 1 from jsonb_array_elements(v_who -> 'users') u
            where jsonb_typeof(u) <> 'string' or u #>> '{}' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'))) then
        raise exception 'policy must be { steps: [{ approvers: { permission, role, team, users }, required, escalateAfter, escalateTo }], mode, selfApproval, expiresIn }' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
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
      raise exception 'policy must be { steps: [{ approvers: { permission, role, team, users }, required, escalateAfter, escalateTo }], mode, selfApproval, expiresIn }' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
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
    raise exception 'policy must be { steps: [{ approvers: { permission, role, team, users }, required, escalateAfter, escalateTo }], mode, selfApproval, expiresIn }' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
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
  if not (v_service or (coalesce(better_supabase.can('tenant', request_approval.tenant, 'approvals.request'), false) and true)) then
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
    return jsonb_build_object('id', v_req."id", 'organizationId', v_req."org_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'mode', coalesce(v_req."policy" ->> 'mode', 'authorize'), 'fingerprint', v_req."fingerprint", 'consumedAt', v_req."consumed_at", 'createdAt', v_req."created_at");
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_req."requested_by" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_req."org_id", 'approvals.manage'), false)) then
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
  null;
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."org_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'mode', coalesce(v_req."policy" ->> 'mode', 'authorize'), 'fingerprint', v_req."fingerprint", 'consumedAt', v_req."consumed_at", 'createdAt', v_req."created_at");
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
  insert into "better_supabase"."approval_decisions" ("request_id", "org_id", "step", "approver", "decision", "comment")
  values (v_req."id", v_req."org_id", v_req."step", v_actor, decide_approval.decision, decide_approval.comment);
  if decide_approval.decision = 'rejected' then
    update "better_supabase"."approval_requests" r set "status" = 'rejected', "decided_at" = now()
      where r."id" = v_req."id" returning * into v_req;
    null;
    perform "better_supabase"."approval_notify"(v_req."id", 'rejected');
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
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."org_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'mode', coalesce(v_req."policy" ->> 'mode', 'authorize'), 'fingerprint', v_req."fingerprint", 'consumedAt', v_req."consumed_at", 'createdAt', v_req."created_at");
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
  if delegate_approval.to_user is null or delegate_approval.to_user = auth.uid() or delegate_approval.to_user = v_req."requested_by" then
    raise exception 'delegate to another user than yourself or the requester' using errcode = '22023', hint = 'APPROVAL_DELEGATE_INVALID';
  end if;
  if not exists (
    select 1 from "better_supabase"."memberships" m
    where m."org_id" = v_req."org_id" and m."user_id" = delegate_approval.to_user
  ) then
    raise exception 'the delegate is not a member of this organization' using errcode = '22023', hint = 'APPROVAL_DELEGATE_INVALID';
  end if;
  insert into "better_supabase"."approval_decisions" ("request_id", "org_id", "step", "approver", "decision", "delegate_to", "comment")
  values (v_req."id", v_req."org_id", v_req."step", auth.uid(), 'delegated', delegate_approval.to_user, delegate_approval.comment);
  null;
  perform "better_supabase"."approval_notify"(v_req."id", 'delegated');
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."org_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'mode', coalesce(v_req."policy" ->> 'mode', 'authorize'), 'fingerprint', v_req."fingerprint", 'consumedAt', v_req."consumed_at", 'createdAt', v_req."created_at");
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_req."requested_by" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_req."org_id", 'approvals.manage'), false)) then
    raise exception 'only the requester or a manager can cancel this request' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  if v_req."status" <> 'pending' then
    raise exception 'this request is no longer pending' using errcode = '22023', hint = 'APPROVAL_CLOSED';
  end if;
  update "better_supabase"."approval_requests" r set "status" = 'cancelled', "decided_at" = now()
    where r."id" = v_req."id" returning * into v_req;
  null;
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."org_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'mode', coalesce(v_req."policy" ->> 'mode', 'authorize'), 'fingerprint', v_req."fingerprint", 'consumedAt', v_req."consumed_at", 'createdAt', v_req."created_at");
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
    or (coalesce(better_supabase.can('tenant', v_req."org_id", 'approvals.read'), false) and (true))) then
    raise exception 'approval request not found' using errcode = 'P0002', hint = 'APPROVAL_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."org_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'mode', coalesce(v_req."policy" ->> 'mode', 'authorize'), 'fingerprint', v_req."fingerprint", 'consumedAt', v_req."consumed_at", 'createdAt', v_req."created_at") || jsonb_build_object(
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
    select jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'action', x."action", 'status', x."status", 'step', x."step", 'steps', x."policy" -> 'steps', 'requestedBy', x."requested_by", 'reason', x."reason", 'payload', x."payload", 'expiresAt', x."expires_at", 'decidedAt', x."decided_at", 'mode', coalesce(x."policy" ->> 'mode', 'authorize'), 'fingerprint', x."fingerprint", 'consumedAt', x."consumed_at", 'createdAt', x."created_at") as j, x."created_at" as at, x."id" as id
    from "better_supabase"."approval_requests" x
    where x."org_id" = list_approvals.tenant
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
    null;
    perform "better_supabase"."approval_notify"(v_req."id", 'escalated');
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."escalate_approvals"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."escalate_approvals"(integer) to service_role;

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
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('approvals.read')) or "requested_by" = (select auth.uid()))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."approval_requests";
create policy bsb_tenant_scope_insert on "better_supabase"."approval_requests" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."approval_requests";
create policy bsb_tenant_scope_update on "better_supabase"."approval_requests" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."approval_requests";
create policy bsb_tenant_scope_delete on "better_supabase"."approval_requests" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."approval_decisions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."approval_decisions";
create policy bsb_tenant_scope_select on "better_supabase"."approval_decisions" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('approvals.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."approval_decisions";
create policy bsb_tenant_scope_insert on "better_supabase"."approval_decisions" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."approval_decisions";
create policy bsb_tenant_scope_update on "better_supabase"."approval_decisions" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."approval_decisions";
create policy bsb_tenant_scope_delete on "better_supabase"."approval_decisions" as restrictive
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

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_077_approvals.sql
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
