import type { BlockSqlContext } from "../context.ts";
import type { ApprovalPolicy } from "./approvals-policies.ts";

import { fail, SERVICE_CALLER, serviceGrant, userGrant } from "../shared.ts";

/** What the step functions share with the rest of the approvals module. */
export interface ApprovalSqlKit {
  readonly requests: string;
  readonly decisions: string;
  readonly c: (column: string) => string;
  readonly d: (column: string) => string;
  readonly has: (column: string) => boolean;
  readonly fn: (name: string) => string;
  readonly policyOf: (row: string) => string;
  readonly stepOf: (row: string) => string;
  readonly record: (event: string, row: string, audit: boolean) => string;
  readonly json: (row: string) => string;
  readonly also: (table: string, logical: string) => string;
  readonly alsoValue: (table: string, logical: string, value: string) => string;
  readonly decided: string;
  readonly notFound: string;
  readonly stepsRefusal: string;
  readonly linkedReject: string;
  readonly commentRefusal: (arg: string) => string;
}

// A step with required "all" asks every holder of its permission when the
// request is filed, except the requester unless the policy lets them decide.
export function allHoldersSql(
  k: ApprovalSqlKit,
  holders: string | undefined,
): string {
  const { has } = k;

  return has("policy")
    ? `
  if exists (select 1 from jsonb_array_elements(coalesce(v_policy -> 'steps', '[]'::jsonb)) e where e.value -> 'required' = '"all"'::jsonb) then${
    holders === undefined
      ? `
    ${fail("APPROVAL_ALL_UNSUPPORTED", "required all needs an access model that lists permission holders", "22023")}`
      : `
    v_policy := jsonb_set(v_policy, '{steps}', (
      select jsonb_agg(case when e.value -> 'required' = '"all"'::jsonb
        then e.value || jsonb_build_object('approvers', jsonb_build_object('users', h.users), 'required', jsonb_array_length(h.users), 'permission', e.value -> 'approvers' ->> 'permission')
        else e.value end order by e.ordinality)
      from jsonb_array_elements(v_policy -> 'steps') with ordinality e
      left join lateral (
        select coalesce(jsonb_agg(distinct to_jsonb(u.id::text)), '[]'::jsonb) as users
        from (${holders}) as u(id)
        where u.id is not null and (u.id is distinct from v_requester or coalesce((v_policy ->> 'selfApproval')::boolean, false))
      ) h on e.value -> 'required' = '"all"'::jsonb
    ));
    if exists (select 1 from jsonb_array_elements(v_policy -> 'steps') e where e.value -> 'required' = '0'::jsonb) then
      ${fail("APPROVAL_APPROVERS_EMPTY", "nobody holds the permission a step asks every holder of", "22023")}
    end if;`
  }
  end if;`
    : "";
}

/** Decide_approval, with the service role deciding for a named user. */
export function decideSql(ctx: BlockSqlContext, k: ApprovalSqlKit): string {
  const {
    requests,
    decisions,
    c,
    d,
    has,
    fn,
    policyOf,
    stepOf,
    record,
    json,
    also,
    alsoValue,
    decided,
    notFound,
    stepsRefusal,
    linkedReject,
    commentRefusal,
  } = k;

  return `-- Approves or rejects the current step. Enough approvals move the request
-- to the next step, and the last step runs the policy's action. The service
-- role decides for the user in decided_by, who is recorded as the approver;
-- it skips the approver check, never the requester's.
drop function if exists ${fn("decide_approval")}(uuid, text, text);
create or replace function ${fn("decide_approval")}(request_id uuid, decision text, comment text default null, decided_by uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_req ${requests}%rowtype;
  v_count integer;
  v_service boolean := ${SERVICE_CALLER};
  v_actor uuid := coalesce(decide_approval.decided_by, auth.uid());
begin
  if decide_approval.decision not in ('approved', 'rejected') then
    ${fail("APPROVAL_DECISION_INVALID", "decision must be approved or rejected", "22023")}
  end if;${commentRefusal("decide_approval.comment")}
  if decide_approval.decided_by is not null and not v_service and decide_approval.decided_by is distinct from auth.uid() then
    ${fail("APPROVAL_FORBIDDEN", "only the service role decides for another user")}
  end if;
  select * into v_req from ${requests} r where r.${c("id")} = decide_approval.request_id for update;
  if not found then
    ${notFound}
  end if;
  if v_req.${c("status")} <> 'pending' then
    ${fail("APPROVAL_CLOSED", "this request is no longer pending", "22023")}
  end if;${
    has("expiresAt")
      ? `
  if v_req.${c("expiresAt")} is not null and v_req.${c("expiresAt")} <= now() then
    ${fail("APPROVAL_EXPIRED", "this request has expired", "22023")}
  end if;`
      : ""
  }
  if v_service then
    if v_actor is not null and v_actor = v_req.${c("requestedBy")} and coalesce(${policyOf("v_req")} ->> 'mode', 'authorize') <> 'confirm'
      and not coalesce((${policyOf("v_req")} ->> 'selfApproval')::boolean, false) then
      ${fail("APPROVAL_FORBIDDEN", "the requester can't decide their own request")}
    end if;
    if v_actor is not null and exists (
      select 1 from ${decisions} x
      where x.${d("request")} = v_req.${c("id")} and x.${d("step")} = ${stepOf("v_req")} and x.${d("approver")} = v_actor
    ) then
      ${fail("APPROVAL_FORBIDDEN", "this user already decided this step")}
    end if;
  elsif not ${fn("approval_eligible")}(v_req.${c("id")}) then
    ${fail("APPROVAL_FORBIDDEN", "not an approver for this step")}
  end if;
  ${ctx.hook("before_approval_decide", [
    ["uuid", `v_req.${c("id")}`],
    ["text", "decide_approval.decision"],
  ])}
  insert into ${decisions} (${d("request")}, ${d("tenant")}, ${d("step")}, ${d("approver")}, ${d("decision")}${also("decisions", "comment")})
  values (v_req.${c("id")}, v_req.${c("tenant")}, ${stepOf("v_req")}, v_actor, ${ctx.cast("decisions", "decision", "decide_approval.decision")}${alsoValue("decisions", "comment", "decide_approval.comment")});
  if decide_approval.decision = 'rejected' then
    update ${requests} r set ${c("status")} = 'rejected'${decided}
      where r.${c("id")} = v_req.${c("id")} returning * into v_req;
    ${record("approval.rejected", "v_req", true)}
    perform ${fn("approval_notify")}(v_req.${c("id")}, 'rejected');${linkedReject}
  else
    select count(*) into v_count from ${decisions} x
      where x.${d("request")} = v_req.${c("id")} and x.${d("step")} = ${stepOf("v_req")} and x.${d("decision")} = 'approved';
    if ${policyOf("v_req")} ->> 'mode' = 'confirm' and v_req.${c("requestedBy")} = v_actor then
      update ${requests} r set ${c("status")} = 'approved'${decided}
        where r.${c("id")} = v_req.${c("id")} returning * into v_req;
      perform ${fn("approval_finalize")}(v_req.${c("id")});
    elsif v_count >= coalesce((${policyOf("v_req")} -> 'steps' -> ${stepOf("v_req")} ->> 'required')::integer, 1) then
      if ${stepOf("v_req")} + 1 >= jsonb_array_length(${policyOf("v_req")} -> 'steps') then
        update ${requests} r set ${c("status")} = 'approved'${decided}
          where r.${c("id")} = v_req.${c("id")} returning * into v_req;
        perform ${fn("approval_finalize")}(v_req.${c("id")});
      else
        ${
          has("step")
            ? `update ${requests} r set ${c("step")} = r.${c("step")} + 1${has("remindedAt") ? `, ${c("remindedAt")} = null` : ""}
          where r.${c("id")} = v_req.${c("id")} returning * into v_req;
        perform ${fn("approval_notify")}(v_req.${c("id")}, 'requested');`
            : stepsRefusal
        }
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
${userGrant(`${fn("decide_approval")}(uuid, text, text, uuid)`)}`;
}

/** Escalate_approvals, which lets a waiting step's fallback approvers in. */
export function escalateSql(k: ApprovalSqlKit): string {
  const { requests, decisions, c, d, has, fn, stepOf, record } = k;

  return `-- Lets the fallback approvers (escalateTo) of a step decide it too once the
-- step has waited its escalateAfter, and asks them. Run it from pg_cron like
-- remind_approvals.
create or replace function ${fn("escalate_approvals")}(max_requests integer default 200)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req ${requests}%rowtype;
  v_count integer := 0;
begin${
    has("policy")
      ? `
  for v_req in
    select * from ${requests} r
    where r.${c("status")} = 'pending'${has("expiresAt") ? `\n      and (r.${c("expiresAt")} is null or r.${c("expiresAt")} > now())` : ""}
      and r.${c("policy")} -> 'steps' -> ${stepOf("r")} ? 'escalateAfter'
      and not coalesce((r.${c("policy")} -> 'steps' -> ${stepOf("r")} ->> 'escalated')::boolean, false)
      and coalesce((
        select max(x.${d("createdAt")}) from ${decisions} x
        where x.${d("request")} = r.${c("id")} and x.${d("step")} = ${stepOf("r")} - 1
      ), r.${c("createdAt")}) + (r.${c("policy")} -> 'steps' -> ${stepOf("r")} ->> 'escalateAfter')::interval <= now()
    order by r.${c("createdAt")}
    limit greatest(coalesce(escalate_approvals.max_requests, 200), 1)
    for update skip locked
  loop
    update ${requests} r set ${c("policy")} = jsonb_set(r.${c("policy")}, array['steps', (${stepOf("r")})::text, 'escalated'], 'true'::jsonb)
    where r.${c("id")} = v_req.${c("id")}
    returning * into v_req;
    ${record("approval.escalated", "v_req", true)}
    perform ${fn("approval_notify")}(v_req.${c("id")}, 'escalated');
    v_count := v_count + 1;
  end loop;`
      : ""
  }
  return v_count;
end;
$$;
${serviceGrant(`${fn("escalate_approvals")}(integer)`)}`;
}

/**
 * Throws when a step escalates or asks every holder without a policy column, or
 * asks every holder under an access model that can't list them.
 */
export function validateSteps(
  policies: readonly ApprovalPolicy[],
  policyColumn: boolean,
  holders: boolean,
): void {
  for (const policy of policies) {
    const where = `blocks.approvals.options.policies.${policy.subjectType}.${policy.action}`;

    if (
      policy.steps.some((step) => step.escalateAfter !== undefined) &&
      !policyColumn
    ) {
      throw new TypeError(
        `${where}: escalateAfter needs a policy column on the approval requests table`,
      );
    }

    if (policy.steps.some((step) => step.required === "all")) {
      if (!policyColumn) {
        throw new TypeError(
          `${where}: required "all" with a permission needs a policy column on the approval requests table`,
        );
      }

      if (!holders) {
        throw new TypeError(
          `${where}: required "all" with a permission needs an access model that lists permission holders (holdersOf)`,
        );
      }
    }
  }
}

/**
 * Approval_settle, which closes the pending request of a subject its own module
 * decided.
 */
export function settleSql(ctx: BlockSqlContext, k: ApprovalSqlKit): string {
  const { requests, decisions, c, d, fn, stepOf, record, also, alsoValue } = k;
  const { decided } = k;

  return `
-- Closes the pending request for a subject that its own module decided
-- (decide_ai_tool_approval, approve_support_request) without running the
-- module again. A request that is no longer pending is left as it is.
create or replace function ${fn("approval_settle")}(subject_type text, subject_id text, action text, decision text, approver uuid, comment text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_req ${requests}%rowtype;
begin
  select * into v_req from ${requests} r
  where r.${c("subjectType")} = approval_settle.subject_type and r.${c("subjectId")} = approval_settle.subject_id
    and r.${c("action")} = approval_settle.action and r.${c("status")} = 'pending'
  for update;
  if not found then
    return;
  end if;
  ${ctx.hook("before_approval_decide", [
    ["uuid", `v_req.${c("id")}`],
    ["text", "approval_settle.decision"],
  ])}
  insert into ${decisions} (${d("request")}, ${d("tenant")}, ${d("step")}, ${d("approver")}, ${d("decision")}${also("decisions", "comment")})
  values (v_req.${c("id")}, v_req.${c("tenant")}, ${stepOf("v_req")}, approval_settle.approver, ${ctx.cast("decisions", "decision", "approval_settle.decision")}${alsoValue("decisions", "comment", "approval_settle.comment")})
  on conflict do nothing;
  update ${requests} r set ${c("status")} = ${ctx.cast("requests", "status", "approval_settle.decision")}${decided}
    where r.${c("id")} = v_req.${c("id")} returning * into v_req;
  if approval_settle.decision = 'approved' then
    ${record("approval.approved", "v_req", true)}
  else
    ${record("approval.rejected", "v_req", true)}
  end if;
  perform ${fn("approval_notify")}(v_req.${c("id")}, approval_settle.decision);
  ${ctx.hook("after_approval_decide", [
    ["uuid", `v_req.${c("id")}`],
    ["text", `v_req.${c("status")}`],
  ])}
end;
$$;
revoke execute on function ${fn("approval_settle")}(text, text, text, text, uuid, text) from public, anon, authenticated;
`;
}
