import type { BlockSqlContext } from "../context.ts";
import type { CarePlansSql } from "./care-plans-sql.ts";

import { sqlString } from "../../core/template.ts";
import { fail, serviceGrant, triggerGrant, userGrant } from "../shared.ts";
import { moveSubjectRows, subjectMergeHandler } from "../subject-merge-sql.ts";
import { registeredSubjects } from "../subject-registry.ts";
import { policyOf, policySnapshot } from "./approvals-policies.ts";
import { carePlansSql } from "./care-plans-sql.ts";
import { OPERATIONS } from "./permissions-model.ts";

/** Another block's context when it is installed with its tables. */
const managed = (
  ctx: BlockSqlContext,
  module: string,
): BlockSqlContext | undefined =>
  ctx.installed(module) && ctx.of(module).mode !== "custom"
    ? ctx.of(module)
    : undefined;

const notActive = fail(
  "CARE_PLAN_INVALID",
  "only an active care plan does this",
  "55000",
);

const approvalRequired = (message: string): string =>
  fail("CARE_PLAN_ACTION_APPROVAL_REQUIRED", message, "55000");

/**
 * Loads actions row `id` into `v_row` and its plan into `v_plan` for update,
 * checking the caller holds `permission` and can read the client.
 */
const loadAction = (
  q: CarePlansSql,
  id: string,
  permission: string,
): string => `
  select * into v_row from ${q.actions} w where w.${q.a("id")} = ${id} for update;
  if not found then
    ${fail("CARE_PLAN_NOT_FOUND", "no such action on a care plan", "P0002")}
  end if;
  select * into v_plan from ${q.plans} x where x.${q.p("id")} = v_row.${q.a("plan")} for update;
  if not ${q.allowed(`v_plan.${q.p("tenant")}`, permission)} then
    ${q.forbidden("not allowed to change this care plan")}
  end if;
  if not ${q.clientReadable("v_plan")} then
    ${q.forbidden("not allowed to read this client")}
  end if;`;

/** The policy a measure's approval snapshots when no policy covers it. */
function defaultPolicy(ctx: BlockSqlContext): string {
  return policySnapshot(
    policyOf(
      ctx.naming.rename("care_plan_action"),
      "start",
      {
        steps: [
          {
            approvers: {
              permission: ctx.permissionKey(
                "manage",
                OPERATIONS["care-plans.manage"],
              ),
            },
          },
        ],
      },
      "blocks.care-plans",
    ),
  );
}

function actionPayload(q: CarePlansSql, extra = ""): string {
  return `jsonb_build_object('actionId', v_row.${q.a("id")}, 'kind', v_row.${q.a("kind")}, 'title', v_row.${q.a("title")}${extra})`;
}

/** Starting, ending and the approval of actions. */
function actionSteps(ctx: BlockSqlContext, q: CarePlansSql): string {
  const { fn, p, a, plans, actions } = q;
  const tasks = managed(ctx, "tasks");
  const approvals = managed(ctx, "approvals");

  const task =
    tasks === undefined
      ? ""
      : `
  if v_row.${a("kind")} = 'task' and v_row.${a("task")} is null then
    v_task := ${tasks.fn("create_work_item")}(v_row.${a("tenant")},
      jsonb_strip_nulls(jsonb_build_object('title', v_row.${a("title")}, 'body', v_row.${a("instructions")})),
      case when v_plan.${p("owner")} is null then '{}'::uuid[] else array[v_plan.${p("owner")}] end);
    update ${actions} w set ${a("task")} = (v_task ->> 'id')::uuid where w.${a("id")} = v_row.${a("id")};
  end if;`;

  const requestApproval =
    approvals === undefined
      ? ""
      : `
-- Asks approvals to start a measure, under the organization's policy for
-- care_plan_action start or the default one: a holder of the manage permission.
create or replace function ${fn("care_plan_action_request_approval")}(action_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${actions};
  v_payload jsonb;
  v_approval jsonb;
begin
  select * into v_row from ${actions} w where w.${a("id")} = care_plan_action_request_approval.action_id;
  v_payload := jsonb_build_object('planId', v_row.${a("plan")}, 'kind', v_row.${a("kind")}, 'measureKind', v_row.${a("measureKind")}, 'title', v_row.${a("title")});
  v_approval := ${approvals.fn("open_approval")}(
    v_row.${a("tenant")}, ${q.actionSubject}, v_row.${a("id")}::text, 'start',
    coalesce(${approvals.fn("approval_effective_policy")}(v_row.${a("tenant")}, ${q.actionSubject}, 'start', v_payload), ${sqlString(defaultPolicy(ctx))}::jsonb),
    null, v_payload
  );
  update ${actions} w set ${a("approval")} = (v_approval ->> 'id')::uuid, ${a("updatedAt")} = now()
  where w.${a("id")} = v_row.${a("id")};
  return (v_approval ->> 'id')::uuid;
end;
$$;
${serviceGrant(`${fn("care_plan_action_request_approval")}(uuid)`)}
`;

  const approvalGate =
    approvals === undefined
      ? `if not ${q.allowed(`v_plan.${p("tenant")}`, q.manage)} then
      ${approvalRequired("without approvals, only a holder of the manage permission starts a measure")}
    end if;`
      : `select x.${approvals.col("requests", "status")} into v_status
    from ${approvals.table("requests")} x where x.${approvals.col("requests", "id")} = v_row.${a("approval")};
    if v_status = 'pending' then
      ${approvalRequired("the action waits for its approval")}
    end if;
    if v_status is distinct from 'approved' then
      perform ${fn("care_plan_action_request_approval")}(v_row.${a("id")});
      select * into v_row from ${actions} w where w.${a("id")} = v_row.${a("id")};
      return ${q.actionJson("v_row")};
    end if;`;

  return `${requestApproval}
-- Starts a planned action of an active plan: a task action creates its work
-- item (tasks block). The other functions call it after their checks.
create or replace function ${fn("care_plan_action_start")}(action_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${actions};
  v_plan ${plans};${tasks === undefined ? "" : "\n  v_task jsonb;"}
begin
  update ${actions} w set ${a("status")} = 'active', ${a("startedAt")} = now(), ${a("updatedAt")} = now()
  where w.${a("id")} = care_plan_action_start.action_id and w.${a("status")} = 'planned'
  returning * into v_row;
  if not found then
    return;
  end if;
  select * into v_plan from ${plans} x where x.${p("id")} = v_row.${a("plan")};${task}
  ${q.recordChild("care_plan_action.started", "v_plan", actionPayload(q), "care plan action started")}
end;
$$;
${serviceGrant(`${fn("care_plan_action_start")}(uuid)`)}

-- Ends an action that hasn't ended. The other functions call it after their checks.
create or replace function ${fn("care_plan_action_end")}(action_id uuid, reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${actions};
  v_plan ${plans};
begin
  update ${actions} w set ${a("status")} = 'ended', ${a("endedAt")} = now(), ${a("endReason")} = care_plan_action_end.reason, ${a("updatedAt")} = now()
  where w.${a("id")} = care_plan_action_end.action_id and w.${a("status")} <> 'ended'
  returning * into v_row;
  if not found then
    return;
  end if;
  select * into v_plan from ${plans} x where x.${p("id")} = v_row.${a("plan")};
  ${q.recordChild("care_plan_action.ended", "v_plan", actionPayload(q, `, 'reason', v_row.${a("endReason")}`), "care plan action ended")}
end;
$$;
${serviceGrant(`${fn("care_plan_action_end")}(uuid, text)`)}

-- Starts a measure once its approval is final. Approvals calls it; it isn't
-- granted to anyone.
create or replace function ${fn("care_plan_action_approved")}(action_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from ${actions} w join ${plans} x on x.${p("id")} = w.${a("plan")}
    where w.${a("id")} = care_plan_action_approved.action_id and x.${p("status")} = 'active'
  ) then
    perform ${fn("care_plan_action_start")}(care_plan_action_approved.action_id);
  end if;
end;
$$;
revoke execute on function ${fn("care_plan_action_approved")}(uuid) from public, anon, authenticated;

-- Starts a planned action of an active plan. An action that requires an
-- approval starts once approved;${approvals === undefined ? " without approvals, only a holder of the manage permission starts it." : " without an open or granted approval, this asks for one and returns the action still planned."}
create or replace function ${fn("start_care_plan_action")}(action_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${actions};
  v_plan ${plans};${approvals === undefined ? "" : "\n  v_status text;"}
begin${loadAction(q, "start_care_plan_action.action_id", q.write)}
  if v_plan.${p("status")} <> 'active' then
    ${notActive}
  end if;
  if v_row.${a("status")} <> 'planned' then
    ${q.invalid("only a planned action starts")}
  end if;
  if v_row.${a("requiresApproval")} then
    ${approvalGate}
  end if;
  perform ${fn("care_plan_action_start")}(v_row.${a("id")});
  select * into v_row from ${actions} w where w.${a("id")} = v_row.${a("id")};
  return ${q.actionJson("v_row")};
end;
$$;
${userGrant(`${fn("start_care_plan_action")}(uuid)`)}

-- Ends an action of a draft or active plan, with an optional reason.
create or replace function ${fn("end_care_plan_action")}(action_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${actions};
  v_plan ${plans};
begin${loadAction(q, "end_care_plan_action.action_id", q.write)}
  if v_plan.${p("status")} = 'archived' then
    ${q.archived}
  end if;
  if v_row.${a("status")} = 'ended' then
    ${q.invalid("the action has already ended")}
  end if;
  if length(end_care_plan_action.reason) > 2000 then
    ${q.invalid("reason is at most 2000 characters")}
  end if;
  perform ${fn("care_plan_action_end")}(v_row.${a("id")}, nullif(trim(end_care_plan_action.reason), ''));
  select * into v_row from ${actions} w where w.${a("id")} = v_row.${a("id")};
  return ${q.actionJson("v_row")};
end;
$$;
${userGrant(`${fn("end_care_plan_action")}(uuid, text)`)}

-- Records that an active action was reviewed, which restarts its
-- reviewEvery clock.
create or replace function ${fn("review_care_plan_action")}(action_id uuid, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${actions};
  v_plan ${plans};
begin${loadAction(q, "review_care_plan_action.action_id", q.evaluate)}
  if v_row.${a("status")} <> 'active' then
    ${q.invalid("only an active action is reviewed")}
  end if;
  if length(review_care_plan_action.note) > 2000 then
    ${q.invalid("note is at most 2000 characters")}
  end if;
  update ${actions} w set ${a("reviewedAt")} = now(), ${a("updatedAt")} = now()
  where w.${a("id")} = v_row.${a("id")}
  returning * into v_row;
  ${q.recordChild("care_plan_action.reviewed", "v_plan", actionPayload(q, ", 'note', review_care_plan_action.note"), "care plan action reviewed")}
  return ${q.actionJson("v_row")};
end;
$$;
${userGrant(`${fn("review_care_plan_action")}(uuid, text)`)}
`;
}

function lifecycle(ctx: BlockSqlContext, q: CarePlansSql): string {
  const { fn, p, a, plans, actions } = q;
  const versions = managed(ctx, "versions");
  const approvals = managed(ctx, "approvals");

  const keepsVersion =
    versions !== undefined && ctx.has("plans", "publishedVersion");

  const snapshot = keepsVersion
    ? `
  v_version := (${versions.fn("version_insert")}(v_row.${p("tenant")}, ${q.subject}, v_row.${p("id")}::text,
    ${fn("care_plan_json")}(v_row.${p("id")}) - 'status' - 'updatedAt' - 'signatureRequestId' - 'agreedAt' - 'evaluations',
    null, 'Version ' || v_row.${p("version")}::text, 'manual', true, auth.uid()) ->> 'id')::uuid;
  update ${plans} x set ${p("publishedVersion")} = v_version where x.${p("id")} = v_row.${p("id")}
  returning * into v_row;`
    : "";

  const start =
    approvals === undefined
      ? `if not v_action.${a("requiresApproval")} then
      perform ${fn("care_plan_action_start")}(v_action.${a("id")});
    end if;`
      : `if v_action.${a("requiresApproval")} then
      perform ${fn("care_plan_action_request_approval")}(v_action.${a("id")});
    else
      perform ${fn("care_plan_action_start")}(v_action.${a("id")});
    end if;`;

  const endAll = (plan: string, reason: string): string => `
    for v_action in
      select * from ${actions} w where w.${a("plan")} = ${plan} and w.${a("status")} <> 'ended'
    loop
      perform ${fn("care_plan_action_end")}(v_action.${a("id")}, ${sqlString(reason)});
    end loop;`;

  return `
-- Makes a draft plan the client's active plan: the plan in force before it
-- is archived and its actions end, the plan is snapshotted as a version
-- (versions block), and its actions start. An action that requires an
-- approval waits for it${approvals === undefined ? "" : " (approvals block)"}.
create or replace function ${fn("publish_care_plan")}(plan_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${plans};
  v_previous ${plans};
  v_action ${actions};
  v_version uuid;
begin
  select * into v_row from ${plans} x where x.${p("id")} = publish_care_plan.plan_id for update;
  if not found then
    ${q.missing}
  end if;
  if not ${q.allowed(`v_row.${p("tenant")}`, q.publish)} then
    ${q.forbidden("not allowed to publish care plans")}
  end if;
  if not ${q.clientReadable("v_row")} then
    ${q.forbidden("not allowed to read this client")}
  end if;
  if v_row.${p("status")} = 'archived' then
    ${q.archived}
  end if;
  if v_row.${p("status")} <> 'draft' then
    ${q.notDraft}
  end if;
  if not exists (select 1 from ${q.problems} y where y.${q.pr("plan")} = v_row.${p("id")}) then
    ${q.invalid("a care plan needs a problem before it is published")}
  end if;
  ${ctx.hook("before_care_plan_publish", [["uuid", `v_row.${p("id")}`]])}
  select * into v_previous from ${plans} x
  where x.${p("subjectType")} = v_row.${p("subjectType")} and x.${p("subjectId")} = v_row.${p("subjectId")} and x.${p("status")} = 'active'
  for update;
  if found then
    update ${plans} x set ${p("status")} = 'archived', ${p("archivedAt")} = now(), ${p("updatedAt")} = now()
    where x.${p("id")} = v_previous.${p("id")}
    returning * into v_previous;${endAll(`v_previous.${p("id")}`, "superseded")}
    ${q.record("care_plan.archived", "v_previous", "care plan archived")}
  end if;
  update ${plans} x set ${p("status")} = 'active', ${p("publishedAt")} = now(), ${p("publishedBy")} = auth.uid(), ${p("updatedAt")} = now()
  where x.${p("id")} = v_row.${p("id")}
  returning * into v_row;${snapshot}
  for v_action in
    select * from ${actions} w where w.${a("plan")} = v_row.${p("id")} and w.${a("status")} = 'planned'
    order by w.${a("rank")}
  loop
    ${start}
  end loop;
  ${q.record("care_plan.published", "v_row", "care plan published", `, 'previousPlanId', v_previous.${p("id")}, 'versionId', v_version`)}
  ${ctx.hook("after_care_plan_publish", [["uuid", `v_row.${p("id")}`]])}
  return ${fn("care_plan_json")}(v_row.${p("id")});
end;
$$;
${userGrant(`${fn("publish_care_plan")}(uuid)`)}

-- Archives a draft or active plan; its actions that haven't ended end.
create or replace function ${fn("archive_care_plan")}(plan_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${plans};
  v_action ${actions};
begin
  select * into v_row from ${plans} x where x.${p("id")} = archive_care_plan.plan_id for update;
  if not found then
    ${q.missing}
  end if;
  if not ${q.allowed(`v_row.${p("tenant")}`, q.publish)} then
    ${q.forbidden("not allowed to archive care plans")}
  end if;
  if not ${q.clientReadable("v_row")} then
    ${q.forbidden("not allowed to read this client")}
  end if;
  if v_row.${p("status")} = 'archived' then
    ${q.archived}
  end if;
  update ${plans} x set ${p("status")} = 'archived', ${p("archivedAt")} = now(),
    ${p("publishedAt")} = coalesce(x.${p("publishedAt")}, now()), ${p("updatedAt")} = now()
  where x.${p("id")} = v_row.${p("id")}
  returning * into v_row;${endAll(`v_row.${p("id")}`, "plan archived")}
  ${q.record("care_plan.archived", "v_row", "care plan archived")}
  return ${fn("care_plan_json")}(v_row.${p("id")});
end;
$$;
${userGrant(`${fn("archive_care_plan")}(uuid)`)}
`;
}

function evaluations(ctx: BlockSqlContext, q: CarePlansSql): string {
  const { fn, p, g, e, plans, goals, evaluations: table } = q;

  return `
-- Records an evaluation of a goal on an active plan: the status found, an
-- outcome and the forms submission it came from, if any. A status the goal
-- doesn't have yet becomes the goal's status.
create or replace function ${fn("record_care_plan_evaluation")}(goal_id uuid, status text, outcome text default null, submission_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_plan ${plans};
  v_goal ${goals};
  v_row ${table};
  v_previous text;
begin
  select * into v_goal from ${goals} z where z.${g("id")} = record_care_plan_evaluation.goal_id for update;
  if not found then
    ${q.goalMissing}
  end if;
  select * into v_plan from ${plans} x where x.${p("id")} = v_goal.${g("plan")};
  if not ${q.allowed(`v_plan.${p("tenant")}`, q.evaluate)} then
    ${q.forbidden("not allowed to evaluate care plans")}
  end if;
  if not ${q.clientReadable("v_plan")} then
    ${q.forbidden("not allowed to read this client")}
  end if;
  if v_plan.${p("status")} <> 'active' then
    ${notActive}
  end if;
  if record_care_plan_evaluation.status is null or record_care_plan_evaluation.status not in ('planned', 'in_progress', 'achieved', 'not_achieved', 'canceled') then
    ${q.invalid("status is planned, in_progress, achieved, not_achieved or canceled")}
  end if;
  if length(record_care_plan_evaluation.outcome) > 10000 then
    ${q.invalid("outcome is at most 10000 characters")}
  end if;
  ${ctx.hook("before_care_plan_evaluation_create", [
    ["uuid", `v_goal.${g("id")}`],
    ["text", "record_care_plan_evaluation.status"],
  ])}
  insert into ${table} (${e("tenant")}, ${e("plan")}, ${e("goal")}, ${e("status")}, ${e("outcome")}, ${e("submission")}, ${e("author")})
  values (v_goal.${g("tenant")}, v_goal.${g("plan")}, v_goal.${g("id")}, record_care_plan_evaluation.status,
    nullif(trim(record_care_plan_evaluation.outcome), ''), record_care_plan_evaluation.submission_id, auth.uid())
  returning * into v_row;
  v_previous := v_goal.${g("status")};
  if v_previous is distinct from record_care_plan_evaluation.status then
    update ${goals} z set ${g("status")} = record_care_plan_evaluation.status, ${g("updatedAt")} = now()
    where z.${g("id")} = v_goal.${g("id")}
    returning * into v_goal;
    ${q.recordChild("care_plan_goal.status_changed", "v_plan", `jsonb_build_object('goalId', v_goal.${g("id")}, 'title', v_goal.${g("title")}, 'status', v_goal.${g("status")}, 'previousStatus', v_previous)`, "care plan goal status changed")}
  end if;
  ${q.recordChild("care_plan_evaluation.created", "v_plan", `jsonb_build_object('evaluationId', v_row.${e("id")}, 'goalId', v_goal.${g("id")}, 'status', v_row.${e("status")})`, "care plan evaluation recorded")}
  ${ctx.hook("after_care_plan_evaluation_create", [["uuid", `v_row.${e("id")}`]])}
  return ${q.evaluationJson("v_row")};
end;
$$;
${userGrant(`${fn("record_care_plan_evaluation")}(uuid, text, text, uuid)`)}

-- The organization's restrictive measures with their plan and client, for a
-- register: active_only keeps the ones in force, the others add planned and
-- ended ones. Only plans the caller reads count.
create or replace function ${fn("list_care_plan_measures")}(tenant ${ctx.idType}, active_only boolean default true)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(${q.actionJson("w")} || jsonb_build_object('planTitle', x.${p("title")}, 'planStatus', x.${p("status")}, 'subjectType', x.${p("subjectType")}, 'subjectId', x.${p("subjectId")})
    order by w.${q.a("startedAt")} desc nulls last, w.${q.a("createdAt")} desc), '[]'::jsonb)
  from ${q.actions} w
  join ${plans} x on x.${p("id")} = w.${q.a("plan")}
  where w.${q.a("tenant")} = list_care_plan_measures.tenant
    and w.${q.a("kind")} = 'measure'
    and (not list_care_plan_measures.active_only or w.${q.a("status")} = 'active')
    and ${q.allowed("list_care_plan_measures.tenant", q.read)}
    and ${q.visible("x")}
$$;
${userGrant(`${fn("list_care_plan_measures")}(${ctx.idType}, boolean)`)}
`;
}

function agreement(ctx: BlockSqlContext, q: CarePlansSql): string {
  const { fn, p, plans } = q;
  const signatures = managed(ctx, "signatures");

  if (signatures === undefined) {
    return `
-- Asks the client side to agree to the plan. It needs the signatures block.
create or replace function ${fn("request_care_plan_agreement")}(plan_id uuid, signers uuid[], message text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  ${q.invalid("agreement needs the signatures block")}
end;
$$;
${userGrant(`${fn("request_care_plan_agreement")}(uuid, uuid[], text)`)}
`;
  }

  const s = (column: string): string => signatures.col("requests", column);
  const requests = signatures.table("requests");

  const version = ctx.has("plans", "publishedVersion")
    ? `v_plan.${p("publishedVersion")}`
    : "null";

  return `
-- Asks members who speak for the client (the client, a representative) to
-- agree to an active plan: a signature request with meaning agreed on the
-- published version. The caller also needs the signatures request
-- permission. Completing it records care_plan.agreed.
create or replace function ${fn("request_care_plan_agreement")}(plan_id uuid, signers uuid[], message text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_plan ${plans};
  v_request uuid;
begin
  select * into v_plan from ${plans} x where x.${p("id")} = request_care_plan_agreement.plan_id for update;
  if not found then
    ${q.missing}
  end if;
  if not ${q.allowed(`v_plan.${p("tenant")}`, q.publish)} then
    ${q.forbidden("not allowed to ask for agreement to care plans")}
  end if;
  if not ${q.clientReadable("v_plan")} then
    ${q.forbidden("not allowed to read this client")}
  end if;
  if v_plan.${p("status")} <> 'active' then
    ${notActive}
  end if;
  v_request := (${signatures.fn("create_signature_request")}(
    v_plan.${p("tenant")}, ${q.subject}, v_plan.${p("id")}::text,
    request_care_plan_agreement.signers, ${version},
    message => request_care_plan_agreement.message, meaning => 'agreed'
  ) ->> 'id')::uuid;
  update ${plans} x set ${p("signature")} = v_request, ${p("agreedAt")} = null, ${p("updatedAt")} = now()
  where x.${p("id")} = v_plan.${p("id")}
  returning * into v_plan;
  ${q.record("care_plan.updated", "v_plan", "care plan agreement requested")}
  return ${fn("care_plan_json")}(v_plan.${p("id")});
end;
$$;
${userGrant(`${fn("request_care_plan_agreement")}(uuid, uuid[], text)`)}

-- A completed agreement request marks its plan agreed.
create or replace function ${fn("care_plan_signature_settled")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${plans};
begin
  for v_row in
    update ${plans} x set ${p("agreedAt")} = now(), ${p("updatedAt")} = now()
    where x.${p("signature")} = new.${s("id")}
    returning *
  loop
    ${q.record("care_plan.agreed", "v_row", "care plan agreed", `, 'signatureRequestId', v_row.${p("signature")}`)}
  end loop;
  return new;
end;
$$;
${triggerGrant(`${fn("care_plan_signature_settled")}()`)}
drop trigger if exists ${ctx.trigger("care_plans_signature_settled")} on ${requests};
create trigger ${ctx.trigger("care_plans_signature_settled")} after update of ${s("status")} on ${requests}
  for each row when (old.${s("status")} = 'pending' and new.${s("status")} = 'completed')
  execute function ${fn("care_plan_signature_settled")}();
`;
}

function dueReviews(ctx: BlockSqlContext, q: CarePlansSql): string {
  const { fn, p, a, plans, actions } = q;

  const notify = (type: string, key: string, data: string): string =>
    ctx.installed("notifications")
      ? `if v_plan.${p("owner")} is not null then
      ${ctx.notify(
        `jsonb_build_object(
        'type', '${type}',
        'tenant', v_plan.${p("tenant")},
        'actor', null,
        'subject_type', ${q.subject},
        'subject_id', v_plan.${p("id")}::text,
        'summary', v_plan.${p("title")},
        'recipients', to_jsonb(array[v_plan.${p("owner")}]),
        'key', ${key},
        'data', ${data}
      )`,
        { indent: "      " },
      )}
    end if;`
      : "";

  return `
-- Reports each active plan whose review date has come, once per date, and
-- each active action whose reviewEvery has lapsed since its last review,
-- once per lapse: a review_date_reached event and, with notifications, a notification
-- to the plan's owner. Run it daily from a job (the care-plans.reviews timer).
create or replace function ${fn("due_care_plan_reviews")}()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_plan ${plans}%rowtype;
  v_row ${actions}%rowtype;
  v_due timestamptz;
  v_claims text;
  v_count integer := 0;
begin
  for v_plan in
    select * from ${plans} x
    where x.${p("status")} = 'active' and x.${p("reviewOn")} <= current_date
      and x.${p("reviewNotifiedFor")} is distinct from x.${p("reviewOn")}
    for update skip locked
  loop
    ${q.record("care_plan.review_date_reached", "v_plan", "care plan review due", `, 'ownerId', v_plan.${p("owner")}, 'reviewOn', v_plan.${p("reviewOn")}`)}
    ${notify("care_plan.review_date_reached", `'care_plan.review_date_reached:' || v_plan.${p("id")}::text || ':' || v_plan.${p("reviewOn")}::text`, `jsonb_build_object('planId', v_plan.${p("id")}, 'reviewOn', v_plan.${p("reviewOn")})`)}
    update ${plans} x set ${p("reviewNotifiedFor")} = v_plan.${p("reviewOn")} where x.${p("id")} = v_plan.${p("id")};
    v_count := v_count + 1;
  end loop;
  for v_row in
    select w.* from ${actions} w
    join ${plans} x on x.${p("id")} = w.${a("plan")} and x.${p("status")} = 'active'
    where w.${a("status")} = 'active' and w.${a("reviewEvery")} is not null
      and coalesce(w.${a("reviewedAt")}, w.${a("startedAt")}) + w.${a("reviewEvery")} <= now()
      and w.${a("reviewNotifiedAt")} is distinct from coalesce(w.${a("reviewedAt")}, w.${a("startedAt")}) + w.${a("reviewEvery")}
    for update of w skip locked
  loop
    v_due := coalesce(v_row.${a("reviewedAt")}, v_row.${a("startedAt")}) + v_row.${a("reviewEvery")};
    select * into v_plan from ${plans} x where x.${p("id")} = v_row.${a("plan")};
    ${q.recordChild("care_plan_action.review_date_reached", "v_plan", actionPayload(q, `, 'ownerId', v_plan.${p("owner")}, 'dueAt', v_due`), "care plan action review due")}
    ${notify("care_plan_action.review_date_reached", `'care_plan_action.review_date_reached:' || v_row.${a("id")}::text || ':' || v_due::text`, `jsonb_build_object('planId', v_plan.${p("id")}, 'actionId', v_row.${a("id")}, 'dueAt', v_due)`)}
    update ${actions} w set ${a("reviewNotifiedAt")} = v_due where w.${a("id")} = v_row.${a("id")};
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
${serviceGrant(`${fn("due_care_plan_reviews")}()`)}
`;
}

/**
 * Moves a merged client's plans; its active plan is archived when the kept
 * client has one.
 */
function subjectMerges(ctx: BlockSqlContext, q: CarePlansSql): string {
  const { p, plans } = q;

  const subjects = registeredSubjects(ctx.subjects, ctx.naming).map(
    (subject) =>
      [
        subject.type,
        { table: `${subject.schema}.${subject.table}`, extra: {} },
      ] as const,
  );

  return subjectMergeHandler(
    ctx,
    subjects,
    `update ${plans} x set ${p("status")} = 'archived', ${p("archivedAt")} = now(), ${p("updatedAt")} = now()
    where x.${p("subjectType")} = v_type and x.${p("subjectId")} = v_drop and x.${p("status")} = 'active'
      and exists (select 1 from ${plans} y where y.${p("subjectType")} = v_type and y.${p("subjectId")} = v_keep and y.${p("status")} = 'active');
    ${moveSubjectRows(
      { table: plans, type: p("subjectType"), id: p("subjectId") },
      "v_type",
    )}`,
  );
}

export function carePlanFlowFunctions(ctx: BlockSqlContext): string {
  const q = carePlansSql(ctx);

  return `${actionSteps(ctx, q)}${lifecycle(ctx, q)}${evaluations(ctx, q)}${agreement(ctx, q)}${dueReviews(ctx, q)}${subjectMerges(ctx, q)}`;
}
