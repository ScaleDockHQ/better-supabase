import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleEvents,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  fail,
  lockTable,
  pageSize,
  schemaPreamble,
  SERVICE_CALLER,
  serviceGrant,
  tenantIn,
  userGrant,
} from "../shared.ts";
import {
  subjectCascades,
  subjectReadable,
  subjectsOption,
} from "../subjects.ts";
import { MODULE_PERMISSIONS } from "./access-model.ts";
import {
  type ApprovalPolicy,
  approvalPolicies,
  policySnapshot,
} from "./approvals-policies.ts";

/** Requests the access-requests module files; their subject is its row. */
export const ACCESS_REQUEST_SUBJECT = "access_request";

/** Requests the time-tracking module files; their subject is a timesheet. */
export const TIMESHEET_SUBJECT = "timesheet";

const PAYLOAD = [
  "organizationId",
  "subjectType",
  "subjectId",
  "id",
  "action",
  "status",
  "step",
] as const;

const EVENTS: ModuleEvents = {
  "approval.requested": { subject: "approval-requests", payload: PAYLOAD },
  "approval.approved": { subject: "approval-requests", payload: PAYLOAD },
  "approval.rejected": { subject: "approval-requests", payload: PAYLOAD },
  "approval.cancelled": { subject: "approval-requests", payload: PAYLOAD },
  "approval.expired": { subject: "approval-requests", payload: PAYLOAD },
  "approval.delegated": { subject: "approval-requests", payload: PAYLOAD },
};

const NAMES: ModuleNames = {
  events: EVENTS,
  hooks: [
    "before_approval_request",
    "after_approval_request",
    "before_approval_decide",
    "after_approval_decide",
  ],
  options: ["subjects", "policies"],
  tables: {
    requests: {
      name: "approval_requests",
      lifecycle: { tenant: "tenant", user: "requestedBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        action: "action",
        policy: "policy",
        step: "step",
        status: "status",
        requestedBy: "requested_by",
        reason: "reason",
        payload: "payload",
        expiresAt: "expires_at",
        remindedAt: "reminded_at",
        decidedAt: "decided_at",
        createdAt: "created_at",
      },
    },
    decisions: {
      name: "approval_decisions",
      lifecycle: { tenant: "tenant", user: "approver", export: true },
      columns: {
        id: "id",
        request: "request_id",
        tenant: "tenant_id",
        step: "step",
        approver: "approver",
        decision: "decision",
        delegateTo: "delegate_to",
        comment: "comment",
        createdAt: "created_at",
      },
    },
  },
};

function policyCase(policies: readonly ApprovalPolicy[]): string {
  if (policies.length === 0) return "null::jsonb";
  return `case approval_policy.subject_type || ':' || approval_policy.action
${policies
  .map(
    (policy) =>
      `    when ${sqlString(`${policy.subjectType}:${policy.action}`)} then ${sqlString(policySnapshot(policy))}::jsonb`,
  )
  .join("\n")}
    else null::jsonb
  end`;
}

function validateRuns(
  ctx: ModuleContext,
  policies: readonly ApprovalPolicy[],
): void {
  for (const policy of policies) {
    const where = `sql.modules.approvals.options.policies.${policy.subjectType}.${policy.action}.run`;
    if (policy.run?.kind === "transition") {
      if (!ctx.installed("state-machine")) {
        throw new TypeError(`${where} needs the state-machine module`);
      }
      const machines = ctx.of("state-machine").option("machines");
      const names =
        typeof machines === "object" && machines !== null
          ? Object.keys(machines)
          : [];
      if (!names.includes(policy.subjectType)) {
        throw new TypeError(
          `${where}: "${policy.subjectType}" is not a state-machine machine`,
        );
      }
    }
    if (policy.run?.kind === "queue" && !ctx.installed("jobs")) {
      throw new TypeError(`${where} needs the jobs module`);
    }
  }
}

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const requests = ctx.table("requests");
  const decisions = ctx.table("decisions");
  const c = (column: string): string => ctx.col("requests", column);
  const d = (column: string): string => ctx.col("decisions", column);
  const read = ctx.permission("read", MODULE_PERMISSIONS.approvals.read);
  const request = ctx.permission(
    "request",
    MODULE_PERMISSIONS.approvals.request,
  );
  const manage = ctx.permission("manage", MODULE_PERMISSIONS.approvals.manage);
  const policies = approvalPolicies(ctx);
  validateRuns(ctx, policies);
  const subjects = subjectsOption(ctx);
  const fn = (name: string): string => ctx.fn(name);
  const timesheets =
    ctx.installed("time-tracking") && ctx.of("time-tracking").mode !== "custom"
      ? ctx.of("time-tracking")
      : undefined;
  const ownSubjects = sqlString(ACCESS_REQUEST_SUBJECT).concat(
    timesheets === undefined ? "" : `, ${sqlString(TIMESHEET_SUBJECT)}`,
  );
  const readable = (row: string): string =>
    `(${row}.${c("subjectType")} ${timesheets === undefined ? `= ${ownSubjects}` : `in (${ownSubjects})`} or ${subjectReadable(
      subjects,
      {
        type: `${row}.${c("subjectType")}`,
        id: `${row}.${c("subjectId")}`,
        tenant: `${row}.${c("tenant")}`,
      },
    )})`;
  const json = (row: string): string =>
    `jsonb_build_object('id', ${row}.${c("id")}, 'organizationId', ${row}.${c("tenant")}, 'subjectType', ${row}.${c("subjectType")}, 'subjectId', ${row}.${c("subjectId")}, 'action', ${row}.${c("action")}, 'status', ${row}.${c("status")}, 'step', ${row}.${c("step")}, 'steps', ${row}.${c("policy")} -> 'steps', 'requestedBy', ${row}.${c("requestedBy")}, 'reason', ${row}.${c("reason")}, 'payload', ${row}.${c("payload")}, 'expiresAt', ${row}.${c("expiresAt")}, 'decidedAt', ${row}.${c("decidedAt")}, 'createdAt', ${row}.${c("createdAt")})`;
  const record = (event: string, row: string, audit: boolean): string =>
    ctx.record({
      type: event,
      payload: `jsonb_build_object('organizationId', ${row}.${c("tenant")}::text, 'subjectType', ${row}.${c("subjectType")}, 'subjectId', ${row}.${c("subjectId")}, 'id', ${row}.${c("id")}, 'action', ${row}.${c("action")}, 'status', ${row}.${c("status")}, 'step', ${row}.${c("step")})`,
      subject: `'approval-requests/' || ${row}.${c("id")}::text`,
      tenant: `${row}.${c("tenant")}`,
      audit: audit
        ? {
            category: "data",
            targetType: "approval_request",
            recordId: `${row}.${c("id")}::text`,
            summary: `${sqlString(event.replace("approval.", ""))} || ' ' || ${row}.${c("action")} || ' on ' || ${row}.${c("subjectType")} || ' ' || ${row}.${c("subjectId")}`,
          }
        : false,
    });
  const members = ctx.of("tenant");
  const mu = members.col("memberships", "user");
  const mt = members.col("memberships", "tenant");
  const mr = members.col("memberships", "role");
  const teams =
    ctx.installed("teams") && ctx.of("teams").mode !== "custom"
      ? ctx.of("teams")
      : undefined;
  const teamMatch = (member: string): string =>
    teams === undefined
      ? "false"
      : `exists (select 1 from ${teams.table("members")} tm where tm.${teams.col("members", "team")}::text = v_approvers ->> 'team' and tm.${teams.col("members", "user")} = ${member})`;
  const teamMembers =
    teams === undefined
      ? ""
      : `
      union
      select tm.${teams.col("members", "user")} from ${teams.table("members")} tm
      where tm.${teams.col("members", "team")}::text = v_approvers ->> 'team'`;
  const notFound = fail(
    "APPROVAL_NOT_FOUND",
    "approval request not found",
    "P0002",
  );
  const queues = [
    ...new Set(
      policies.flatMap((policy) =>
        policy.run?.kind === "queue" ? [policy.run.queue] : [],
      ),
    ),
  ];
  const queueRun =
    queues.length === 0
      ? ""
      : `
  if v_run ->> 'kind' = 'queue' then
    case v_run ->> 'queue'
${queues
  .map(
    (queue) => `      when ${sqlString(queue)} then
        ${ctx.enqueue(queue, `jsonb_build_object('requestId', v_req.${c("id")}, 'organizationId', v_req.${c("tenant")}, 'subjectType', v_req.${c("subjectType")}, 'subjectId', v_req.${c("subjectId")}, 'action', v_req.${c("action")}, 'payload', v_req.${c("payload")})`, `'approval:' || v_req.${c("id")}::text`)}`,
  )
  .join("\n")}
      else null;
    end case;
  end if;`;
  const transitionRun = policies.some(
    (policy) => policy.run?.kind === "transition",
  )
    ? `
  if v_run ->> 'kind' = 'transition' then
    perform set_config('better_supabase.approval', v_req.${c("id")}::text, true);
    perform ${ctx.of("state-machine").fn("transition")}(v_req.${c("subjectType")}, v_req.${c("subjectId")}, v_run ->> 'to', 'approved');
    perform set_config('better_supabase.approval', '', true);
  end if;`
    : "";
  const accessRun = ctx.installed("access-requests")
    ? `
  if v_req.${c("subjectType")} = ${sqlString(ACCESS_REQUEST_SUBJECT)} then
    perform ${ctx.of("access-requests").fn("grant_access_request")}(v_req.${c("subjectId")}::uuid);
  end if;`
    : "";
  const timesheetRun =
    timesheets === undefined
      ? ""
      : `
  if v_req.${c("subjectType")} = ${sqlString(TIMESHEET_SUBJECT)} then
    perform ${timesheets.fn("approve_timesheet")}(v_req.${c("subjectId")}::uuid);
  end if;`;
  const notifyBody = ctx.installed("notifications")
    ? `
  select * into v_req from ${requests} r where r.${c("id")} = approval_notify.request_id;
  if not found then
    return;
  end if;
  if approval_notify.kind in ('approved', 'rejected', 'expired') then
    v_recipients := array[v_req.${c("requestedBy")}];
    v_permission := null;
  else
    v_approvers := v_req.${c("policy")} -> 'steps' -> v_req.${c("step")} -> 'approvers';
    v_permission := v_approvers ->> 'permission';
    v_recipients := array(
      select x::uuid from jsonb_array_elements_text(coalesce(v_approvers -> 'users', '[]'::jsonb)) x
      union
      select m.${mu} from ${members.table("memberships")} m
      where m.${mt} = v_req.${c("tenant")} and m.${mr} = v_approvers ->> 'role'${teamMembers}
      union
      select x.${d("delegateTo")} from ${decisions} x
      where x.${d("request")} = v_req.${c("id")} and x.${d("step")} = v_req.${c("step")} and x.${d("decision")} = 'delegated'
    );
    if approval_notify.kind = 'delegated' then
      v_recipients := array(
        select x.${d("delegateTo")} from ${decisions} x
        where x.${d("request")} = v_req.${c("id")} and x.${d("step")} = v_req.${c("step")} and x.${d("decision")} = 'delegated'
        order by x.${d("createdAt")} desc limit 1
      );
      v_permission := null;
    end if;
    -- Approvers who already decided this step aren't asked again.
    v_recipients := array(
      select u from unnest(v_recipients) u
      where not exists (
        select 1 from ${decisions} x
        where x.${d("request")} = v_req.${c("id")} and x.${d("step")} = v_req.${c("step")} and x.${d("approver")} = u
      )
    );
  end if;
  if cardinality(v_recipients) = 0 and v_permission is null then
    return;
  end if;
  ${ctx.notify(
    `jsonb_build_object(
      'type', 'approval.' || approval_notify.kind,
      'tenant', v_req.${c("tenant")},
      'actor', coalesce(auth.uid(), v_req.${c("requestedBy")}),
      'subject_type', v_req.${c("subjectType")},
      'subject_id', v_req.${c("subjectId")},
      'summary', left(v_req.${c("action")} || coalesce(': ' || v_req.${c("reason")}, ''), 140),
      'recipients', to_jsonb(v_recipients),
      'permission', v_permission,
      'exclude', case when coalesce((v_req.${c("policy")} ->> 'selfApproval')::boolean, false) or approval_notify.kind in ('approved', 'rejected', 'expired') then '[]'::jsonb else jsonb_build_array(v_req.${c("requestedBy")}) end,
      'include_actor', approval_notify.kind in ('approved', 'rejected', 'expired'),
      'key', 'approval.' || approval_notify.kind || ':' || v_req.${c("id")}::text || ':' || v_req.${c("step")}::text || ':' || extract(epoch from now())::bigint::text,
      'data', jsonb_build_object('requestId', v_req.${c("id")}, 'action', v_req.${c("action")}, 'step', v_req.${c("step")})
    )`,
  )}`
    : `
  null;`;
  const tables = ctx.manages
    ? `create table if not exists ${requests} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${ctx.idType} not null,
  ${c("subjectType")} text not null,
  ${c("subjectId")} text not null,
  ${c("action")} text not null,
  ${c("policy")} jsonb not null,
  ${c("step")} integer not null default 0 check (${c("step")} >= 0),
  ${c("status")} text not null default 'pending' check (${c("status")} in ('pending', 'approved', 'rejected', 'cancelled', 'expired')),
  ${c("requestedBy")} uuid,
  ${c("reason")} text check (${c("reason")} is null or length(${c("reason")}) <= 2000),
  ${c("payload")} jsonb not null default '{}'::jsonb,
  ${c("expiresAt")} timestamptz,
  ${c("remindedAt")} timestamptz,
  ${c("decidedAt")} timestamptz,
  ${c("createdAt")} timestamptz not null default now()
);
create unique index if not exists ${sqlIdent(`${ctx.tableName("requests").name}_pending_idx`)} on ${requests} (${c("subjectType")}, ${c("subjectId")}, ${c("action")}) where ${c("status")} = 'pending';
create index if not exists ${sqlIdent(`${ctx.tableName("requests").name}_tenant_idx`)} on ${requests} (${c("tenant")}, ${c("status")}, ${c("createdAt")} desc);
${lockTable(requests, { read: true })}
drop policy if exists "approval_requests_read" on ${requests};
create policy "approval_requests_read" on ${requests} for select to authenticated
  using (${tenantIn(c("tenant"), read)} or ${c("requestedBy")} = (select auth.uid()));

create table if not exists ${decisions} (
  ${d("id")} uuid primary key default gen_random_uuid(),
  ${d("request")} uuid not null references ${requests} (${c("id")}) on delete cascade,
  ${d("tenant")} ${ctx.idType} not null,
  ${d("step")} integer not null,
  ${d("approver")} uuid,
  ${d("decision")} text not null check (${d("decision")} in ('approved', 'rejected', 'delegated')),
  ${d("delegateTo")} uuid,
  ${d("comment")} text check (${d("comment")} is null or length(${d("comment")}) <= 2000),
  ${d("createdAt")} timestamptz not null default clock_timestamp(),
  check ((${d("decision")} = 'delegated') = (${d("delegateTo")} is not null)),
  unique (${d("request")}, ${d("step")}, ${d("approver")})
);
create index if not exists ${sqlIdent(`${ctx.tableName("decisions").name}_delegate_idx`)} on ${decisions} (${d("delegateTo")}) where ${d("delegateTo")} is not null;
${lockTable(decisions, { read: true })}
drop policy if exists "approval_decisions_read" on ${decisions};
create policy "approval_decisions_read" on ${decisions} for select to authenticated
  using (${tenantIn(d("tenant"), read)});
`
    : "";
  return `${schemaPreamble(ctx)}
${tables}
-- The policy a new request snapshots, from options.policies.
create or replace function ${fn("approval_policy")}(subject_type text, action text)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select ${policyCase(policies)}
$$;
${userGrant(`${fn("approval_policy")}(text, text)`)}

-- Whether the caller may decide the request's current step: a named user,
-- a holder of the permission, a member with the role or in the team, or a
-- delegate. The requester can't, unless the policy allows self-approval.
create or replace function ${fn("approval_eligible")}(request_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_req ${requests}%rowtype;
  v_approvers jsonb;
  v_me uuid := auth.uid();
begin
  select * into v_req from ${requests} r where r.${c("id")} = approval_eligible.request_id;
  if not found or v_me is null or v_req.${c("status")} <> 'pending' then
    return false;
  end if;
  if v_me = v_req.${c("requestedBy")} and not coalesce((v_req.${c("policy")} ->> 'selfApproval')::boolean, false) then
    return false;
  end if;
  if exists (
    select 1 from ${decisions} x
    where x.${d("request")} = v_req.${c("id")} and x.${d("step")} = v_req.${c("step")} and x.${d("approver")} = v_me
  ) then
    return false;
  end if;
  v_approvers := v_req.${c("policy")} -> 'steps' -> v_req.${c("step")} -> 'approvers';
  return (coalesce(v_approvers -> 'users', '[]'::jsonb) ? v_me::text)
    or (v_approvers ->> 'permission' is not null and ${ctx.can("tenant", `v_req.${c("tenant")}`, "v_approvers ->> 'permission'")})
    or (v_approvers ->> 'role' is not null and exists (
      select 1 from ${members.table("memberships")} m
      where m.${mt} = v_req.${c("tenant")} and m.${mu} = v_me and m.${mr} = v_approvers ->> 'role'
    ))
    or (v_approvers ->> 'team' is not null and ${teamMatch("v_me")})
    or exists (
      select 1 from ${decisions} x
      where x.${d("request")} = v_req.${c("id")} and x.${d("step")} = v_req.${c("step")}
        and x.${d("decision")} = 'delegated' and x.${d("delegateTo")} = v_me
    );
end;
$$;
${userGrant(`${fn("approval_eligible")}(uuid)`)}

-- Notifies the current step's approvers (requested, reminder), a delegate
-- (delegated) or the requester (approved, rejected, expired).
create or replace function ${fn("approval_notify")}(request_id uuid, kind text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req ${requests}%rowtype;
  v_approvers jsonb;
  v_permission text;
  v_recipients uuid[] := '{}';
  v_claims text;
begin${notifyBody}
end;
$$;
revoke execute on function ${fn("approval_notify")}(uuid, text) from public, anon, authenticated;

-- Runs what the final approval unlocks: the policy's state-machine
-- transition or job, or the access-requests grant.
create or replace function ${fn("approval_finalize")}(request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req ${requests}%rowtype;
  v_run jsonb;
begin
  select * into v_req from ${requests} r where r.${c("id")} = approval_finalize.request_id;
  v_run := v_req.${c("policy")} -> 'run';${transitionRun}${queueRun}${accessRun}${timesheetRun}
  ${record("approval.approved", "v_req", true)}
  perform ${fn("approval_notify")}(v_req.${c("id")}, 'approved');
end;
$$;
revoke execute on function ${fn("approval_finalize")}(uuid) from public, anon, authenticated;

-- Files a request under an explicit policy snapshot. request_approval and
-- the access-requests module call it after their own checks.
create or replace function ${fn("open_approval")}(tenant ${ctx.idType}, subject_type text, subject_id text, action text, policy jsonb, reason text, payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_req ${requests}%rowtype;
begin
  ${ctx.hook("before_approval_request", [
    [ctx.idType, "open_approval.tenant"],
    ["text", "open_approval.subject_type"],
    ["text", "open_approval.subject_id"],
    ["text", "open_approval.action"],
  ])}
  insert into ${requests} (${c("tenant")}, ${c("subjectType")}, ${c("subjectId")}, ${c("action")}, ${c("policy")}, ${c("requestedBy")}, ${c("reason")}, ${c("payload")}, ${c("expiresAt")})
  values (open_approval.tenant, open_approval.subject_type, open_approval.subject_id, open_approval.action, open_approval.policy, auth.uid(), open_approval.reason, coalesce(open_approval.payload, '{}'::jsonb),
    case when open_approval.policy ->> 'expiresIn' is not null then now() + (open_approval.policy ->> 'expiresIn')::interval end)
  on conflict (${c("subjectType")}, ${c("subjectId")}, ${c("action")}) where ${c("status")} = 'pending' do nothing
  returning * into v_req;
  if not found then
    ${fail("APPROVAL_PENDING", "this record already has a pending request for that action", "23505")}
  end if;
  ${record("approval.requested", "v_req", true)}
  perform ${fn("approval_notify")}(v_req.${c("id")}, 'requested');
  ${ctx.hook("after_approval_request", [["uuid", `v_req.${c("id")}`]])}
  return ${json("v_req")};
end;
$$;
revoke execute on function ${fn("open_approval")}(${ctx.idType}, text, text, text, jsonb, text, jsonb) from public, anon, authenticated;

create or replace function ${fn("request_approval")}(tenant ${ctx.idType}, subject_type text, subject_id text, action text, reason text default null, payload jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_policy jsonb := ${fn("approval_policy")}(request_approval.subject_type, request_approval.action);
begin
  if v_policy is null then
    ${fail("APPROVAL_POLICY_UNKNOWN", "no approval policy for this subject type and action", "22023")}
  end if;
  if not (${SERVICE_CALLER} or (${ctx.can("tenant", "request_approval.tenant", request)} and ${subjectReadable(subjects, { type: "request_approval.subject_type", id: "request_approval.subject_id", tenant: "request_approval.tenant" })})) then
    ${fail("APPROVAL_FORBIDDEN", "not allowed to request approval for this record")}
  end if;
  return ${fn("open_approval")}(request_approval.tenant, request_approval.subject_type, request_approval.subject_id, request_approval.action, v_policy, request_approval.reason, request_approval.payload);
end;
$$;
${userGrant(`${fn("request_approval")}(${ctx.idType}, text, text, text, text, jsonb)`)}

-- Approves or rejects the current step. Enough approvals move the request
-- to the next step, and the last step runs the policy's action.
create or replace function ${fn("decide_approval")}(request_id uuid, decision text, comment text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_req ${requests}%rowtype;
  v_count integer;
begin
  if decide_approval.decision not in ('approved', 'rejected') then
    ${fail("APPROVAL_DECISION_INVALID", "decision must be approved or rejected", "22023")}
  end if;
  select * into v_req from ${requests} r where r.${c("id")} = decide_approval.request_id for update;
  if not found then
    ${notFound}
  end if;
  if v_req.${c("status")} <> 'pending' then
    ${fail("APPROVAL_CLOSED", "this request is no longer pending", "22023")}
  end if;
  if v_req.${c("expiresAt")} is not null and v_req.${c("expiresAt")} <= now() then
    ${fail("APPROVAL_EXPIRED", "this request has expired", "22023")}
  end if;
  if not ${fn("approval_eligible")}(v_req.${c("id")}) then
    ${fail("APPROVAL_FORBIDDEN", "not an approver for this step")}
  end if;
  ${ctx.hook("before_approval_decide", [
    ["uuid", `v_req.${c("id")}`],
    ["text", "decide_approval.decision"],
  ])}
  insert into ${decisions} (${d("request")}, ${d("tenant")}, ${d("step")}, ${d("approver")}, ${d("decision")}, ${d("comment")})
  values (v_req.${c("id")}, v_req.${c("tenant")}, v_req.${c("step")}, auth.uid(), decide_approval.decision, decide_approval.comment);
  if decide_approval.decision = 'rejected' then
    update ${requests} r set ${c("status")} = 'rejected', ${c("decidedAt")} = now()
      where r.${c("id")} = v_req.${c("id")} returning * into v_req;
    ${record("approval.rejected", "v_req", true)}
    perform ${fn("approval_notify")}(v_req.${c("id")}, 'rejected');
  else
    select count(*) into v_count from ${decisions} x
      where x.${d("request")} = v_req.${c("id")} and x.${d("step")} = v_req.${c("step")} and x.${d("decision")} = 'approved';
    if v_count >= coalesce((v_req.${c("policy")} -> 'steps' -> v_req.${c("step")} ->> 'required')::integer, 1) then
      if v_req.${c("step")} + 1 >= jsonb_array_length(v_req.${c("policy")} -> 'steps') then
        update ${requests} r set ${c("status")} = 'approved', ${c("decidedAt")} = now()
          where r.${c("id")} = v_req.${c("id")} returning * into v_req;
        perform ${fn("approval_finalize")}(v_req.${c("id")});
      else
        update ${requests} r set ${c("step")} = r.${c("step")} + 1, ${c("remindedAt")} = null
          where r.${c("id")} = v_req.${c("id")} returning * into v_req;
        perform ${fn("approval_notify")}(v_req.${c("id")}, 'requested');
      end if;
    end if;
  end if;
  ${ctx.hook("after_approval_decide", [
    ["uuid", `v_req.${c("id")}`],
    ["text", `v_req.${c("status")}`],
  ])}
  return ${json("v_req")};
end;
$$;
${userGrant(`${fn("decide_approval")}(uuid, text, text)`)}

-- Hands the caller's place on the current step to another user.
create or replace function ${fn("delegate_approval")}(request_id uuid, to_user uuid, comment text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_req ${requests}%rowtype;
begin
  select * into v_req from ${requests} r where r.${c("id")} = delegate_approval.request_id for update;
  if not found then
    ${notFound}
  end if;
  if v_req.${c("status")} <> 'pending' then
    ${fail("APPROVAL_CLOSED", "this request is no longer pending", "22023")}
  end if;
  if not ${fn("approval_eligible")}(v_req.${c("id")}) then
    ${fail("APPROVAL_FORBIDDEN", "not an approver for this step")}
  end if;
  if delegate_approval.to_user is null or delegate_approval.to_user = auth.uid() or delegate_approval.to_user = v_req.${c("requestedBy")} then
    ${fail("APPROVAL_DELEGATE_INVALID", "delegate to another user than yourself or the requester", "22023")}
  end if;
  if not exists (
    select 1 from ${members.table("memberships")} m
    where m.${mt} = v_req.${c("tenant")} and m.${mu} = delegate_approval.to_user
  ) then
    ${fail("APPROVAL_DELEGATE_INVALID", "the delegate is not a member of this organization", "22023")}
  end if;
  insert into ${decisions} (${d("request")}, ${d("tenant")}, ${d("step")}, ${d("approver")}, ${d("decision")}, ${d("delegateTo")}, ${d("comment")})
  values (v_req.${c("id")}, v_req.${c("tenant")}, v_req.${c("step")}, auth.uid(), 'delegated', delegate_approval.to_user, delegate_approval.comment);
  ${record("approval.delegated", "v_req", true)}
  perform ${fn("approval_notify")}(v_req.${c("id")}, 'delegated');
  return ${json("v_req")};
end;
$$;
${userGrant(`${fn("delegate_approval")}(uuid, uuid, text)`)}

create or replace function ${fn("cancel_approval")}(request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req ${requests}%rowtype;
begin
  select * into v_req from ${requests} r where r.${c("id")} = cancel_approval.request_id for update;
  if not found then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or v_req.${c("requestedBy")} = auth.uid() or ${ctx.can("tenant", `v_req.${c("tenant")}`, manage)}) then
    ${fail("APPROVAL_FORBIDDEN", "only the requester or a manager can cancel this request")}
  end if;
  if v_req.${c("status")} <> 'pending' then
    ${fail("APPROVAL_CLOSED", "this request is no longer pending", "22023")}
  end if;
  update ${requests} r set ${c("status")} = 'cancelled', ${c("decidedAt")} = now()
    where r.${c("id")} = v_req.${c("id")} returning * into v_req;
  ${record("approval.cancelled", "v_req", true)}
  return ${json("v_req")};
end;
$$;
${userGrant(`${fn("cancel_approval")}(uuid)`)}

create or replace function ${fn("get_approval")}(request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_req ${requests}%rowtype;
begin
  select * into v_req from ${requests} r where r.${c("id")} = get_approval.request_id;
  if not found then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or v_req.${c("requestedBy")} = auth.uid() or ${fn("approval_eligible")}(v_req.${c("id")})
    or (${ctx.can("tenant", `v_req.${c("tenant")}`, read)} and ${readable("v_req")})) then
    ${notFound}
  end if;
  return ${json("v_req")} || jsonb_build_object(
    'canDecide', ${fn("approval_eligible")}(v_req.${c("id")}),
    'decisions', coalesce((
      select jsonb_agg(jsonb_build_object('id', x.${d("id")}, 'step', x.${d("step")}, 'approver', x.${d("approver")}, 'decision', x.${d("decision")}, 'delegateTo', x.${d("delegateTo")}, 'comment', x.${d("comment")}, 'createdAt', x.${d("createdAt")}) order by x.${d("createdAt")}, x.${d("id")})
      from ${decisions} x where x.${d("request")} = v_req.${c("id")}
    ), '[]'::jsonb)
  );
end;
$$;
${userGrant(`${fn("get_approval")}(uuid)`)}

-- assigned: only requests whose current step the caller can decide.
create or replace function ${fn("list_approvals")}(tenant ${ctx.idType}, status text default 'pending', assigned boolean default false, subject_type text default null, subject_id text default null, page_size integer default 50, before timestamptz default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_rows jsonb;
  v_read boolean := ${SERVICE_CALLER} or ${ctx.can("tenant", "list_approvals.tenant", read)};
begin
  select coalesce(jsonb_agg(t.j order by t.at desc, t.id), '[]'::jsonb) into v_rows
  from (
    select ${json("x")} as j, x.${c("createdAt")} as at, x.${c("id")} as id
    from ${requests} x
    where x.${c("tenant")} = list_approvals.tenant
      and (list_approvals.status is null or x.${c("status")} = list_approvals.status)
      and (list_approvals.subject_type is null or x.${c("subjectType")} = list_approvals.subject_type)
      and (list_approvals.subject_id is null or x.${c("subjectId")} = list_approvals.subject_id)
      and (list_approvals.before is null or x.${c("createdAt")} < list_approvals.before)
      and case
        when list_approvals.assigned then ${fn("approval_eligible")}(x.${c("id")})
        else x.${c("requestedBy")} = auth.uid() or (v_read and (${SERVICE_CALLER} or ${readable("x")})) or ${fn("approval_eligible")}(x.${c("id")})
      end
    order by x.${c("createdAt")} desc, x.${c("id")}
    limit ${pageSize("list_approvals.page_size", 50, 200)}
  ) t;
  return v_rows;
end;
$$;
${userGrant(`${fn("list_approvals")}(${ctx.idType}, text, boolean, text, text, integer, timestamptz)`)}

-- Whether the subject's latest request for the action was approved.
create or replace function ${fn("is_approved")}(subject_type text, subject_id text, action text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select x.${c("status")} = 'approved' from ${requests} x
    where x.${c("subjectType")} = is_approved.subject_type and x.${c("subjectId")} = is_approved.subject_id and x.${c("action")} = is_approved.action
    order by x.${c("createdAt")} desc limit 1
  ), false)
$$;
${userGrant(`${fn("is_approved")}(text, text, text)`)}

-- Closes pending requests past expires_at. Run it from pg_cron:
--   select cron.schedule('expire-approvals', '*/15 * * * *', 'select ${fn("expire_approvals")}()');
create or replace function ${fn("expire_approvals")}(max_requests integer default 500)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req ${requests}%rowtype;
  v_count integer := 0;
begin
  for v_req in
    update ${requests} r set ${c("status")} = 'expired', ${c("decidedAt")} = now()
    where r.${c("id")} in (
      select x.${c("id")} from ${requests} x
      where x.${c("status")} = 'pending' and x.${c("expiresAt")} <= now()
      order by x.${c("expiresAt")}
      limit greatest(coalesce(expire_approvals.max_requests, 500), 1)
      for update skip locked
    )
    returning r.*
  loop
    ${record("approval.expired", "v_req", false)}
    perform ${fn("approval_notify")}(v_req.${c("id")}, 'expired');
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
${serviceGrant(`${fn("expire_approvals")}(integer)`)}

-- Reminds the approvers of requests pending longer than \`after\`, once per
-- \`after\`. Run it from pg_cron like expire_approvals.
create or replace function ${fn("remind_approvals")}(after interval default interval '1 day', max_requests integer default 200)
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
    update ${requests} r set ${c("remindedAt")} = now()
    where r.${c("id")} in (
      select x.${c("id")} from ${requests} x
      where x.${c("status")} = 'pending'
        and (x.${c("expiresAt")} is null or x.${c("expiresAt")} > now())
        and x.${c("createdAt")} <= now() - remind_approvals.after
        and (x.${c("remindedAt")} is null or x.${c("remindedAt")} <= now() - remind_approvals.after)
      order by x.${c("createdAt")}
      limit greatest(coalesce(remind_approvals.max_requests, 200), 1)
      for update skip locked
    )
    returning r.${c("id")}
  loop
    perform ${fn("approval_notify")}(v_id, 'reminder');
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
${serviceGrant(`${fn("remind_approvals")}(interval, integer)`)}
${subjectCascades(ctx, subjects, `delete from ${requests} r where r.${c("subjectType")} = v_type and r.${c("subjectId")} = v_id;`)}
`;
}

function contract(): readonly ModuleContractFunction[] {
  return [
    {
      name: "request_approval",
      args: ["{id}", "text", "text", "text", "text", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "decide_approval",
      args: ["uuid", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "delegate_approval",
      args: ["uuid", "uuid", "text"],
      returns: "jsonb",
    },
    { name: "cancel_approval", args: ["uuid"], returns: "jsonb" },
    { name: "is_approved", args: ["text", "text", "text"], returns: "boolean" },
  ];
}

export const APPROVALS: ModuleDefinition = {
  name: "approvals",
  title: "Approvals",
  description:
    "Approval requests with steps per subject type and action: approvers by permission, role, team or user, a required count, delegation, expiry and reminders. The final approval runs a state-machine transition or a job.",
  requires: ["tenant", "access"],
  integrates: [
    "outbox",
    "audit",
    "notifications",
    "jobs",
    "teams",
    "state-machine",
    "access-requests",
    "time-tracking",
  ],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
