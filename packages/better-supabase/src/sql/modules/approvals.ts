import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";
import type { BlockContributes } from "../contributions.ts";
import type { BlockSqlDefinition, BlockSqlLayout } from "../module-types.ts";
import type { ApprovalSqlKit } from "./approvals-steps.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { uniqueContributions } from "../contributions.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  extraFieldsArg,
  extraFieldsJson,
  fail,
  pageSize,
  schemaPreamble,
  SERVICE_CALLER,
  serviceGrant,
  triggerGrant,
  userGrant,
} from "../shared.ts";
import {
  subjectCascades,
  subjectReadable,
  subjectsOption,
} from "../subjects.ts";
import {
  APPROVALS_NAMES,
  approvalsContract,
  REQUEST_KEYS,
} from "./approvals-contract.ts";
import {
  approvalItemsContract,
  itemsOf,
  itemsSql,
  itemsTableSql,
} from "./approvals-items.ts";
import {
  approvalPolicies,
  policyCase,
  validateApprovers,
  validateRuns,
} from "./approvals-policies.ts";
import {
  allHoldersSql,
  decideSql,
  escalateSql,
  settleSql,
  validateSteps,
} from "./approvals-steps.ts";
import {
  approvalsTenantContract,
  approvalsTenantSql,
  managerMatch,
  managerOf,
  platformPoliciesOn,
  tenantlessTypes,
  tenantPoliciesOn,
} from "./approvals-tenant.ts";
import { approvalTests } from "./approvals-tests.ts";
import { approverCheck } from "./approver.ts";
import { driveSubjectGuard } from "./drive-kit.ts";
import { providerMembers, roleThrough } from "./memberships.ts";
import { permissionHolders } from "./notifications-audience.ts";
import { roleValue } from "./organizations-roles.ts";
import { appUniqueIndex, asText, lockModuleTable } from "./over-app.ts";
import { accessModel, OPERATIONS } from "./permissions-model.ts";
import { myWorkTenant } from "./subjects.ts";

/**
 * The policy snapshot of a request another module files and decides: one step
 * that the module's own approver check answers, never the requester.
 * `expiresIn` is a text SQL expression or `null`.
 */
export function linkedPolicy(expiresIn = "null"): string {
  return `jsonb_build_object('steps', '[{"approvers": {}, "required": 1}]'::jsonb, 'selfApproval', false, 'expiresIn', ${expiresIn}, 'run', null)`;
}

function build(ctx: BlockSqlContext, layout: BlockSqlLayout): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const requests = ctx.table("requests");
  const decisions = ctx.table("decisions");
  const c = (column: string): string => ctx.col("requests", column);
  const d = (column: string): string => ctx.col("decisions", column);
  const has = (column: string): boolean => ctx.has("requests", column);
  const delegation = ctx.has("decisions", "delegateTo");
  const commented = ctx.has("decisions", "comment");

  // The column on row, or null when the app maps it away.
  const or = (table: string, row: string, logical: string): string =>
    ctx.has(table, logical) ? `${row}.${ctx.col(table, logical)}` : "null";

  // ", <column>" for an insert's column list, when the column exists.
  const also = (table: string, logical: string): string =>
    ctx.has(table, logical) ? `, ${ctx.col(table, logical)}` : "";

  // ", <value>" matching also().
  const alsoValue = (table: string, logical: string, value: string): string =>
    ctx.has(table, logical) ? `, ${value}` : "";

  // A request without a policy column follows the live policy.
  const policyOf = (row: string): string =>
    has("policy")
      ? `${row}.${c("policy")}`
      : `${ctx.fn("approval_policy")}(${row}.${c("subjectType")}, ${row}.${c("action")})`;

  // A request without a step column stays on its single step 0.
  const stepOf = (row: string): string =>
    has("step") ? `${row}.${c("step")}` : "0";

  const decided = has("decidedAt") ? `, ${c("decidedAt")} = now()` : "";

  const refuse = (when: string, code: string, message: string): string => `
  if ${when} then
    ${fail(code, message, "22023")}
  end if;`;

  const stepsRefusal = fail(
    "APPROVAL_STEPS_UNSUPPORTED",
    "this approval requests table has no step column, so a policy has one step",
    "22023",
  );

  const openRefusals = [
    has("policy")
      ? ""
      : refuse(
          `open_approval.policy is distinct from ${ctx.fn("approval_policy")}(open_approval.subject_type, open_approval.action)`,
          "APPROVAL_POLICY_UNSUPPORTED",
          "this approval requests table has no policy column, so a request follows the approval policy of its subject type and action",
        ),
    has("step")
      ? ""
      : refuse(
          "coalesce(jsonb_array_length(open_approval.policy -> 'steps'), 0) > 1",
          "APPROVAL_STEPS_UNSUPPORTED",
          "this approval requests table has no step column, so a policy has one step",
        ),
    has("reason")
      ? ""
      : refuse(
          "nullif(btrim(open_approval.reason), '') is not null",
          "APPROVAL_REASON_UNSUPPORTED",
          "this approval requests table has no reason column",
        ),
    has("payload")
      ? ""
      : refuse(
          "coalesce(open_approval.payload, '{}'::jsonb) <> '{}'::jsonb",
          "APPROVAL_PAYLOAD_UNSUPPORTED",
          "this approval requests table has no payload column",
        ),
    has("expiresAt")
      ? ""
      : refuse(
          "open_approval.policy ->> 'expiresIn' is not null",
          "APPROVAL_EXPIRY_UNSUPPORTED",
          "this approval requests table has no expiry column",
        ),
  ].join("");

  const commentRefusal = (arg: string): string =>
    commented
      ? ""
      : refuse(
          `${arg} is not null`,
          "APPROVAL_COMMENT_UNSUPPORTED",
          "this approval decisions table has no comment column",
        );

  const read = ctx.permission("read", OPERATIONS["approvals.read"]);
  const request = ctx.permission("request", OPERATIONS["approvals.request"]);
  const manage = ctx.permission("manage", OPERATIONS["approvals.manage"]);
  const policies = approvalPolicies(ctx);
  validateRuns(ctx, policies);
  validateApprovers(ctx, policies, tenantPoliciesOn(ctx));

  if (tenantPoliciesOn(ctx) && !has("policy")) {
    throw new TypeError(
      "blocks.approvals.options.tenantPolicies needs a policy column on the approval requests table",
    );
  }

  const tenantless = tenantlessTypes(ctx).length > 0;
  platformPoliciesOn(ctx);

  const holders = permissionHolders(
    ctx,
    layout,
    "(e.value -> 'approvers' ->> 'permission')",
    "open_approval.tenant",
  );

  validateSteps(policies, has("policy"), holders !== undefined);

  const provider = approverCheck(ctx, layout, {
    kind: { sql: `v_req.${c("subjectType")} || '.' || v_req.${c("action")}` },
    subject: `v_req.${c("subjectId")}::text`,
    tenant: `v_req.${c("tenant")}`,
    requester: `v_req.${c("requestedBy")}`,
    approvers:
      "(coalesce(v_approvers, '{}'::jsonb) || jsonb_build_object('required', coalesce(v_step -> 'required', '1'::jsonb)))",
  });

  const subjects = subjectsOption(ctx);
  const fn = (name: string): string => ctx.fn(name);

  const contributed = uniqueContributions(
    "approvals",
    ctx.contributions("approvals"),
    (each) => each.subject,
  );

  const drive = driveSubjectGuard(ctx);

  const own = contributed.filter(
    (each) =>
      each.access === "declared" && sqlString(each.subject) !== drive?.type,
  );

  const linked = contributed.filter((each) => each.access === "linked");

  const ownSubjects = own.map((each) => sqlString(each.subject)).join(", ");

  const linkedRow = (column: string): string =>
    linked.length === 0
      ? "false"
      : `${column} in (${linked.map((each) => sqlString(each.subject)).join(", ")})`;

  const subjectAccess = (
    args: {
      readonly type: string;
      readonly id: string;
      readonly tenant: string;
    },
    access: "read" | "write",
  ): string => {
    const listed = subjectReadable(ctx, subjects, args);

    return drive === undefined
      ? listed
      : drive.guard(args.type, args.id, access, listed);
  };

  const declared = (row: string): string => {
    const access = subjectAccess(
      {
        type: `${row}.${c("subjectType")}`,
        id: `${row}.${c("subjectId")}`,
        tenant: `${row}.${c("tenant")}`,
      },
      "read",
    );

    return own.length === 0
      ? `(${access})`
      : `(${row}.${c("subjectType")} ${own.length === 1 ? `= ${ownSubjects}` : `in (${ownSubjects})`} or ${access})`;
  };

  const readable = (row: string): string =>
    linked.length === 0
      ? declared(row)
      : `(not ${linkedRow(`${row}.${c("subjectType")}`)} and ${declared(row)})`;

  const extras = ctx.extraColumns("requests", REQUEST_KEYS);

  const json = (row: string): string =>
    `jsonb_build_object('id', ${row}.${c("id")}, 'organizationId', ${row}.${c("tenant")}, 'subjectType', ${row}.${c("subjectType")}, 'subjectId', ${row}.${c("subjectId")}, 'action', ${row}.${c("action")}, 'status', ${row}.${c("status")}, 'step', ${stepOf(row)}, 'steps', ${policyOf(row)} -> 'steps', 'requestedBy', ${row}.${c("requestedBy")}, 'reason', ${or("requests", row, "reason")}, 'payload', ${or("requests", row, "payload")}, 'expiresAt', ${or("requests", row, "expiresAt")}, 'decidedAt', ${or("requests", row, "decidedAt")}, 'mode', coalesce(${policyOf(row)} ->> 'mode', 'authorize'), 'fingerprint', ${or("requests", row, "fingerprint")}, 'consumedAt', ${or("requests", row, "consumedAt")}, 'createdAt', ${row}.${c("createdAt")}${extraFieldsJson(row, extras)})`;

  const record = (event: string, row: string, audit: boolean): string =>
    ctx.record({
      type: event,
      payload: `jsonb_build_object('organizationId', ${row}.${c("tenant")}::text, 'subjectType', ${row}.${c("subjectType")}, 'subjectId', ${row}.${c("subjectId")}, 'id', ${row}.${c("id")}, 'action', ${row}.${c("action")}, 'status', ${row}.${c("status")}, 'step', ${stepOf(row)})`,
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

  const members = ctx.of("memberships");
  const mu = members.col("memberships", "user");
  const mt = members.col("memberships", "tenant");
  const mr = members.col("memberships", "role");

  // A policy names an approver role by key; the catalog stores its id.
  const approverRole = roleValue(
    ctx,
    "v_approvers ->> 'role'",
    `v_req.${c("tenant")}`,
  );

  const memberIdsFor = providerMembers(ctx, layout).idsFor;

  const delegateMember =
    memberIdsFor === undefined
      ? `exists (
    select 1 from ${members.table("memberships")} m
    where m.${mt} = v_req.${c("tenant")} and m.${mu} = delegate_approval.to_user
  )`
      : `v_req.${c("tenant")}::text in (
    select t.id::text from ${memberIdsFor("delegate_approval.to_user")} as t(id)
  )`;

  const teams =
    ctx.installed("teams") && ctx.of("teams").mode !== "custom"
      ? ctx.of("teams")
      : undefined;

  const teamMatch = (member: string, team: string): string =>
    teams === undefined
      ? "false"
      : `exists (select 1 from ${teams.table("members")} tm where tm.${teams.col("members", "team")}::text = ${team} and tm.${teams.col("members", "user")} = ${member})`;

  const teamMembers =
    teams === undefined
      ? ""
      : `
      union
      select tm.${teams.col("members", "user")} from ${teams.table("members")} tm
      where tm.${teams.col("members", "team")}::text = v_approvers ->> 'team'`;

  // A policy's managerOf names the employee whose manager a manager step asks.
  const managerEmployee = has("policy")
    ? `(${policyOf("v_req")} ->> 'managerOf')`
    : undefined;

  const manager = managerOf(
    ctx,
    `v_req.${c("requestedBy")}`,
    `v_req.${c("tenant")}`,
    managerEmployee,
  );

  const managerMember =
    manager === undefined
      ? ""
      : `
      union
      select ${manager} where coalesce((v_approvers ->> 'manager')::boolean, false)`;

  const factTenant = "approval_fact.tenant";
  const factValue = "approval_fact.value";

  const permissionMatch = tenantless
    ? `case when v_req.${c("tenant")} is null then ${ctx.staff("v_approvers ->> 'permission'")} else ${ctx.can("tenant", `v_req.${c("tenant")}`, "v_approvers ->> 'permission'")} end`
    : ctx.can("tenant", `v_req.${c("tenant")}`, "v_approvers ->> 'permission'");

  const roleFact = `exists (
      select 1 from ${members.table("memberships")} m
      where m.${mt} = ${factTenant} and m.${mu} = v_me and m.${mr} = ${roleValue(ctx, factValue, factTenant)}
    )`;

  const managerFact =
    manager === undefined
      ? "false"
      : managerMatch(ctx, {
          requester: "approval_fact.requester",
          tenant: factTenant,
          user: "v_me",
          ...(managerEmployee === undefined ? {} : { employee: factValue }),
        });

  const fact = (kind: string, value: string, requester = "null"): string =>
    `${fn("approval_fact")}(v_req.${c("tenant")}, ${sqlString(kind)}, ${value}, ${requester})`;

  // Whether v_me is one of the approvers in v_approvers.
  const approverMatch = `((coalesce(v_approvers -> 'users', '[]'::jsonb) ? v_me::text)
    or (v_approvers ->> 'permission' is not null and ${permissionMatch})
    or (v_approvers ->> 'role' is not null and ${fact("role", "v_approvers ->> 'role'")})
    or (v_approvers ->> 'team' is not null and ${fact("team", "v_approvers ->> 'team'")})${
      manager === undefined
        ? ""
        : `
    or (coalesce((v_approvers ->> 'manager')::boolean, false) and ${fact("manager", managerEmployee ?? "null", `v_req.${c("requestedBy")}`)})`
    })`;

  const through = roleThrough(members);

  const rolesTable = through
    ? through.table
    : accessModel(ctx) === "catalog"
      ? ctx.of("permissions").table("roles")
      : undefined;

  const memoTables = [
    members.table("memberships"),
    ...(rolesTable === undefined ? [] : [rolesTable]),
    ...(teams === undefined ? [] : [teams.table("members")]),
  ];

  const memoTriggers = memoTables
    .map(
      (
        table,
      ) => `drop trigger if exists ${ctx.trigger("approval_memo")} on ${table};
create trigger ${ctx.trigger("approval_memo")} after insert or update or delete on ${table}
  for each statement execute function ${fn("approval_memo_bump")}();`,
    )
    .join("\n");

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
        ${ctx.enqueue(queue, `jsonb_build_object('requestId', v_req.${c("id")}, 'organizationId', v_req.${c("tenant")}, 'subjectType', v_req.${c("subjectType")}, 'subjectId', v_req.${c("subjectId")}, 'action', v_req.${c("action")}, 'payload', ${or("requests", "v_req", "payload")})`, `'approval:' || v_req.${c("id")}::text`)}`,
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

  const lastComment = commented
    ? `(select x.${d("comment")} from ${decisions} x where x.${d("request")} = v_req.${c("id")} order by x.${d("createdAt")} desc, x.${d("id")} desc limit 1)`
    : "null::text";

  const when = (subject: string, body: string, indent: string): string => `
${indent}if v_req.${c("subjectType")} = ${sqlString(subject)} then
${indent}  ${body}
${indent}end if;`;

  const subjectId = (cast: string): string => `v_req.${c("subjectId")}${cast}`;

  const lastApprover = `(select x.${d("approver")} from ${decisions} x where x.${d("request")} = v_req.${c("id")} and x.${d("decision")} = 'approved' order by x.${d("createdAt")} desc, x.${d("id")} desc limit 1)`;

  const contributedRun = contributed
    .map((each) =>
      when(
        each.subject,
        each.approve({
          id: `v_req.${c("id")}`,
          subjectId: subjectId(""),
          comment: lastComment,
          approver: lastApprover,
        }),
        "  ",
      ),
    )
    .join("");

  const linkedReject = contributed
    .flatMap((each) =>
      each.reject === undefined
        ? []
        : [
            when(
              each.subject,
              each.reject({
                id: `v_req.${c("id")}`,
                subjectId: subjectId(""),
                comment: "decide_approval.comment",
                approver: "v_actor",
              }),
              "    ",
            ),
          ],
    )
    .join("");

  const linkedEligible = linked
    .flatMap((each) =>
      each.approvable === undefined
        ? []
        : [
            when(
              each.subject,
              `return ${each.approvable({ id: `v_req.${c("id")}`, subjectId: subjectId(""), comment: lastComment, approver: "v_me" })};`,
              "  ",
            ),
          ],
    )
    .join("");

  // approval_eligible_ids answers the rules of approval_eligible for every
  // pending request in one statement: the approver kinds are joins, a
  // permission is checked once per tenant and permission pair, and only a
  // provider's isApprover still runs per request.
  const escalates = has("policy");

  const approversIn = (set: "approvers" | "escalateTo"): string =>
    `(q.bsb_step -> '${set}')`;

  const setMatch = (ap: string): string => {
    const tenantOf = `q.${c("tenant")}`;
    const employee = managerEmployee?.replaceAll("v_req.", "q.");

    const managerClause =
      manager === undefined
        ? ""
        : `
    or (coalesce((${ap} ->> 'manager')::boolean, false) and ${managerMatch(ctx, { requester: `q.${c("requestedBy")}`, tenant: tenantOf, user: "q.bsb_me", ...(employee === undefined ? {} : { employee }) })})`;

    return `((coalesce(${ap} -> 'users', '[]'::jsonb) ? q.bsb_me::text)
    or (${ap} ->> 'permission' is not null and exists (select 1 from granted g where g.t is not distinct from ${tenantOf} and g.p = ${ap} ->> 'permission'))
    or (${ap} ->> 'role' is not null and exists (
      select 1 from ${members.table("memberships")} mm
      where mm.${mt} = ${tenantOf} and mm.${mu} = q.bsb_me and mm.${mr} = ${roleValue(ctx, `${ap} ->> 'role'`, tenantOf)}
    ))
    or (${ap} ->> 'team' is not null and ${teamMatch("q.bsb_me", `${ap} ->> 'team'`)})${managerClause})`;
  };

  const escalatedSet = `coalesce((q.bsb_step ->> 'escalated')::boolean, false)`;

  const decidedHere = (row: string): string =>
    `exists (select 1 from ${decisions} x where x.${d("request")} = ${row}.${c("id")} and x.${d("step")} = ${stepOf(row)} and x.${d("approver")} = ${row}.bsb_me)`;

  const delegatedHere = delegation
    ? `\n    or exists (select 1 from ${decisions} x where x.${d("request")} = q.${c("id")} and x.${d("step")} = ${stepOf("q")} and x.${d("decision")} = 'delegated' and x.${d("delegateTo")} = q.bsb_me)`
    : "";

  const providerFallback =
    provider === undefined
      ? ""
      : `\n    or ${fn("approval_eligible")}(q.${c("id")})`;

  const linkedSet = linked.flatMap((each) =>
    each.approvable === undefined
      ? []
      : [
          `when q.${c("subjectType")} = ${sqlString(each.subject)} then (${each.approvable({ id: `q.${c("id")}`, subjectId: `q.${c("subjectId")}`, comment: lastComment.replaceAll("v_req.", "q."), approver: "q.bsb_me" })})`,
        ],
  );

  const setCore = `(${setMatch(approversIn("approvers"))}${escalates ? `\n    or (${escalatedSet} and ${setMatch(approversIn("escalateTo"))})` : ""}${delegatedHere}${providerFallback})`;

  const eligibleIdsBody = `with base as (
    select r.*, (select auth.uid()) as bsb_me from ${requests} r
    where r.${c("status")} = 'pending' and (select auth.uid()) is not null
      and (approval_eligible_ids.tenant is null or r.${c("tenant")} = approval_eligible_ids.tenant)
  ),
  q as (
    select b.*, ${policyOf("b")} -> 'steps' -> ${stepOf("b")} as bsb_step from base b
  ),
  needs as materialized (
    select distinct q.${c("tenant")} as t, s.ap ->> 'permission' as p
    from q, lateral (values (${approversIn("approvers")}${escalates ? `, (case when ${escalatedSet} then ${approversIn("escalateTo")} end)` : ""})) as s(ap)
    where s.ap ->> 'permission' is not null
  ),
  granted as materialized (
    select n.t, n.p from needs n
    where ${tenantless ? `case when n.t is null then ${ctx.staff("n.p")} else ${ctx.can("tenant", "n.t", "n.p")} end` : ctx.can("tenant", "n.t", "n.p")}
  )
  select q.${c("id")} from q
  where not ${decidedHere("q")}
    and ((q.bsb_me = q.${c("requestedBy")} and ${policyOf("q")} ->> 'mode' = 'confirm')
      or ((q.bsb_me is distinct from q.${c("requestedBy")} or coalesce((${policyOf("q")} ->> 'selfApproval')::boolean, false))
        and ${linkedSet.length === 0 ? setCore : `(case ${linkedSet.join("\n          ")}\n          else ${setCore} end)`}))`;

  const kit: ApprovalSqlKit = {
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
  };

  const allHolders = allHoldersSql(kit, holders);

  const notificationHook = ctx.hookTarget("approval_notification");

  // An app's approval_notification(request_id, kind, notification) returns
  // keys to merge into the notification (data merges too), or null to skip it.
  const enrich = `
  v_hook := to_regprocedure(${sqlString(`${notificationHook}(uuid, text, jsonb)`)});
  if v_hook is not null then
    execute format('select %s($1, $2, $3)', v_hook::oid::regproc) into v_extra
      using v_req.${c("id")}, approval_notify.kind, v_note;
    if v_extra is null then
      return;
    end if;
    v_note := v_note || (v_extra - 'data') || jsonb_build_object('data', coalesce(v_note -> 'data', '{}'::jsonb) || coalesce(v_extra -> 'data', '{}'::jsonb));
  end if;`;

  const notifyBody =
    ctx.installed("notifications") && ctx.flag("notifications", true)
      ? `
  select * into v_req from ${requests} r where r.${c("id")} = approval_notify.request_id;
  if not found${tenantless ? ` or v_req.${c("tenant")} is null` : ""} then
    return;
  end if;
  if approval_notify.kind in ('approved', 'rejected', 'expired') then
    v_recipients := array[v_req.${c("requestedBy")}];
    v_permission := null;
  else
    v_approvers := ${policyOf("v_req")} -> 'steps' -> ${stepOf("v_req")} -> case when approval_notify.kind = 'escalated' then 'escalateTo' else 'approvers' end;
    v_permission := v_approvers ->> 'permission';
    v_recipients := array(
      select x::uuid from jsonb_array_elements_text(coalesce(v_approvers -> 'users', '[]'::jsonb)) x
      union
      select m.${mu} from ${members.table("memberships")} m
      where m.${mt} = v_req.${c("tenant")} and m.${mr} = ${approverRole}${teamMembers}${managerMember}${
        delegation
          ? `
      union
      select x.${d("delegateTo")} from ${decisions} x
      where x.${d("request")} = v_req.${c("id")} and x.${d("step")} = ${stepOf("v_req")} and x.${d("decision")} = 'delegated'
    );
    if approval_notify.kind = 'delegated' then
      v_recipients := array(
        select x.${d("delegateTo")} from ${decisions} x
        where x.${d("request")} = v_req.${c("id")} and x.${d("step")} = ${stepOf("v_req")} and x.${d("decision")} = 'delegated'
        order by x.${d("createdAt")} desc limit 1
      );
      v_permission := null;
    end if;`
          : `
    );`
      }
    -- Approvers who already decided this step aren't asked again.
    v_recipients := array(
      select u from unnest(v_recipients) u
      where not exists (
        select 1 from ${decisions} x
        where x.${d("request")} = v_req.${c("id")} and x.${d("step")} = ${stepOf("v_req")} and x.${d("approver")} = u
      )
    );
  end if;
  if cardinality(v_recipients) = 0 and v_permission is null then
    return;
  end if;
  v_note := jsonb_build_object(
      'type', 'approval.' || approval_notify.kind,
      'tenant', v_req.${c("tenant")},
      'actor', coalesce(auth.uid(), v_req.${c("requestedBy")}),
      'subject_type', v_req.${c("subjectType")},
      'subject_id', v_req.${c("subjectId")},
      'summary', left(v_req.${c("action")}${has("reason") ? ` || coalesce(': ' || v_req.${c("reason")}, '')` : ""}, 140),
      'recipients', to_jsonb(v_recipients),
      'permission', v_permission,
      'exclude', case when coalesce((${policyOf("v_req")} ->> 'selfApproval')::boolean, false) or approval_notify.kind in ('approved', 'rejected', 'expired') then '[]'::jsonb else jsonb_build_array(v_req.${c("requestedBy")}) end,
      'include_actor', approval_notify.kind in ('approved', 'rejected', 'expired'),
      'key', 'approval.' || approval_notify.kind || ':' || v_req.${c("id")}::text || ':' || ${stepOf("v_req")}::text || ':' || extract(epoch from now())::bigint::text,
      'data', jsonb_build_object('requestId', v_req.${c("id")}, 'action', v_req.${c("action")}, 'step', ${stepOf("v_req")})
    );${enrich}
  ${ctx.notify("v_note")}`
      : `
  null;`;

  // A column definition, left out when the app maps the column to null.
  const column = (
    table: string,
    logical: string,
    definition: (name: string) => string,
  ): string =>
    ctx.has(table, logical)
      ? `\n  ${definition(ctx.col(table, logical))},`
      : "";

  const tables = ctx.manages
    ? `create table if not exists ${requests} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${ctx.idType}${tenantless ? "" : " not null"},
  ${c("subjectType")} text not null,
  ${c("subjectId")} text not null,
  ${c("action")} text not null,${column("requests", "policy", (name) => `${name} jsonb not null`)}${column("requests", "step", (name) => `${name} integer not null default 0 check (${name} >= 0)`)}
  ${c("status")} text not null default 'pending' check (${c("status")} in ('pending', 'approved', 'rejected', 'cancelled', 'expired')),
  ${c("requestedBy")} uuid,${column("requests", "reason", (name) => `${name} text check (${name} is null or length(${name}) <= 2000)`)}${column("requests", "payload", (name) => `${name} jsonb not null default '{}'::jsonb`)}${column("requests", "expiresAt", (name) => `${name} timestamptz`)}${column("requests", "remindedAt", (name) => `${name} timestamptz`)}${column("requests", "decidedAt", (name) => `${name} timestamptz`)}${column("requests", "fingerprint", (name) => `${name} text check (${name} is null or ${name} ~ '^[0-9a-f]{64}$')`)}${column("requests", "consumedAt", (name) => `${name} timestamptz`)}
  ${c("createdAt")} timestamptz not null default now()
);${has("fingerprint") ? `\nalter table ${requests} add column if not exists ${c("fingerprint")} text check (${c("fingerprint")} is null or ${c("fingerprint")} ~ '^[0-9a-f]{64}$');` : ""}${has("consumedAt") ? `\nalter table ${requests} add column if not exists ${c("consumedAt")} timestamptz;` : ""}
${tenantless ? `alter table ${requests} alter column ${c("tenant")} drop not null;\n` : ""}create unique index if not exists ${sqlIdent(`${ctx.tableName("requests").name}_pending_idx`)} on ${requests} (${c("subjectType")}, ${c("subjectId")}, ${c("action")}) where ${c("status")} = 'pending';
create index if not exists ${sqlIdent(`${ctx.tableName("requests").name}_subject_idx`)} on ${requests} (${c("subjectType")}, ${c("subjectId")});
create index if not exists ${sqlIdent(`${ctx.tableName("requests").name}_tenant_idx`)} on ${requests} (${c("tenant")}, ${c("status")}, ${c("createdAt")} desc);
${lockModuleTable(ctx, "requests", { read: true })}
${renderPolicy(makePolicy({ table: requests, name: ctx.naming.rename("approval_requests_read"), command: "select", roles: ["authenticated"], using: `${linked.length === 0 ? ctx.scope.check(c("tenant"), read) : `(${ctx.scope.check(c("tenant"), read)} and not ${linkedRow(c("subjectType"))})`} or ${c("requestedBy")} = (select auth.uid())` }), { target: requests })}

create table if not exists ${decisions} (
  ${d("id")} uuid primary key default gen_random_uuid(),
  ${d("request")} uuid not null references ${requests} (${c("id")}) on delete cascade,
  ${d("tenant")} ${ctx.idType}${tenantless ? "" : " not null"},
  ${d("step")} integer not null,
  ${d("approver")} uuid,
  ${d("decision")} text not null check (${d("decision")} in ('approved', 'rejected', 'delegated')),${column("decisions", "delegateTo", (name) => `${name} uuid`)}${column("decisions", "comment", (name) => `${name} text check (${name} is null or length(${name}) <= 2000)`)}
  ${d("createdAt")} timestamptz not null default clock_timestamp(),${delegation ? `\n  check ((${d("decision")} = 'delegated') = (${d("delegateTo")} is not null)),` : ""}
  unique (${d("request")}, ${d("step")}, ${d("approver")})
);${appUniqueIndex(ctx, "decisions", ["request", "step", "approver"])}${delegation ? `\ncreate index if not exists ${sqlIdent(`${ctx.tableName("decisions").name}_delegate_idx`)} on ${decisions} (${d("delegateTo")}) where ${d("delegateTo")} is not null;` : ""}
${tenantless ? `alter table ${decisions} alter column ${d("tenant")} drop not null;\n` : ""}${lockModuleTable(ctx, "decisions", { read: true })}
${renderPolicy(makePolicy({ table: decisions, name: ctx.naming.rename("approval_decisions_read"), command: "select", roles: ["authenticated"], using: ctx.scope.check(d("tenant"), read) }), { target: decisions })}
`
    : "";

  const itemsTable = itemsTableSql(ctx, kit, {
    tenantless,
    linked: (type) => linkedRow(type),
    read,
    manage,
  });

  return `${schemaPreamble(ctx)}
${tables}
${itemsTable}
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

create or replace function ${fn("approval_memo_bump")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform better_supabase.memo_set('approvals.gen', (coalesce(better_supabase.memo_get('approvals.gen'), '0')::bigint + 1)::text);
  return null;
end;
$$;
${triggerGrant(`${fn("approval_memo_bump")}()`)}
${memoTriggers}

create or replace function ${fn("approval_fact")}(tenant ${ctx.idType}, kind text, value text, requester uuid default null)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_key text := 'approvals.f' || md5(format('%s|%s|%s|%s|%s', v_me, approval_fact.tenant, approval_fact.kind, approval_fact.value, approval_fact.requester));
  v_stamp text := statement_timestamp()::text || '/' || coalesce(better_supabase.memo_get('approvals.gen'), '0');
  v_hit text := better_supabase.memo_get(v_key);
  v_result boolean;
begin
  if v_hit is not null and split_part(v_hit, '|', 1) = v_stamp then
    return split_part(v_hit, '|', 2) = 't';
  end if;
  v_result := coalesce(case approval_fact.kind
    when 'role' then ${roleFact}
    when 'team' then ${teamMatch("v_me", factValue)}
    when 'manager' then ${managerFact}
    else false
  end, false);
  perform better_supabase.memo_set(v_key, v_stamp || '|' || case when v_result then 't' else 'f' end);
  return v_result;
end;
$$;
${triggerGrant(`${fn("approval_fact")}(${ctx.idType}, text, text, uuid)`)}

-- Whether the caller may decide the request's current step: a named user,
-- a holder of the permission, a member with the role or in the team, or a
-- delegate. The requester can't, unless the policy allows self-approval.${
    provider
      ? `
-- A user the provider's isApprover allows for kind <subject type>.<action>
-- may decide as well, never the requester.`
      : ""
  }
create or replace function ${fn("approval_eligible")}(request ${requests})
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_req ${requests}%rowtype := approval_eligible.request;
  v_step jsonb;
  v_approvers jsonb;
  v_me uuid := auth.uid();
begin
  if v_req.${c("id")} is null or v_me is null or v_req.${c("status")} <> 'pending' then
    return false;
  end if;
  if exists (
    select 1 from ${decisions} x
    where x.${d("request")} = v_req.${c("id")} and x.${d("step")} = ${stepOf("v_req")} and x.${d("approver")} = v_me
  ) then
    return false;
  end if;
  if v_me = v_req.${c("requestedBy")} then
    if ${policyOf("v_req")} ->> 'mode' = 'confirm' then
      return true;
    end if;
    if not coalesce((${policyOf("v_req")} ->> 'selfApproval')::boolean, false) then
      return false;
    end if;
  end if;${linkedEligible}
  v_step := ${policyOf("v_req")} -> 'steps' -> ${stepOf("v_req")};
  v_approvers := v_step -> 'approvers';
  if ${approverMatch} then
    return true;
  end if;${
    has("policy")
      ? `
  if coalesce((v_step ->> 'escalated')::boolean, false) then
    v_approvers := v_step -> 'escalateTo';
    if ${approverMatch} then
      return true;
    end if;
  end if;`
      : ""
  }
  return ${
    [
      ...(delegation
        ? [
            `exists (
      select 1 from ${decisions} x
      where x.${d("request")} = v_req.${c("id")} and x.${d("step")} = ${stepOf("v_req")}
        and x.${d("decision")} = 'delegated' and x.${d("delegateTo")} = v_me
    )`,
          ]
        : []),
      ...(provider
        ? [
            `(v_me is distinct from v_req.${c("requestedBy")} and coalesce((${provider.sql}), false))`,
          ]
        : []),
    ].join("\n    or ") || "false"
  };
end;
$$;
${userGrant(`${fn("approval_eligible")}(${requests})`)}

create or replace function ${fn("approval_eligible")}(request_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_req ${requests}%rowtype;
begin
  select * into v_req from ${requests} r where r.${c("id")} = approval_eligible.request_id;
  if not found then
    return false;
  end if;
  return ${fn("approval_eligible")}(v_req);
end;
$$;
${userGrant(`${fn("approval_eligible")}(uuid)`)}

-- The pending requests the caller may decide, as a set, for a policy or a list
-- (\`id in (select ${fn("approval_eligible_ids")}())\`): Postgres evaluates the set once per
-- statement, not once per row. It applies the rules of approval_eligible as
-- joins over the pending requests (a permission is checked once per tenant and
-- permission pair${provider ? ", an access provider's isApprover per request" : ""}), and a parity test keeps the two
-- in step. Pass a tenant to read one tenant's.
create or replace function ${fn("approval_eligible_ids")}(tenant ${ctx.idType} default null)
returns setof uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query
  ${eligibleIdsBody};
end;
$$;
${userGrant(`${fn("approval_eligible_ids")}(${ctx.idType})`)}

-- Notifies the current step's approvers (requested, reminder), its fallback
-- approvers (escalated), a delegate (delegated) or the requester (approved,
-- rejected, expired).
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
  v_claims text;${notifyBody.includes("v_note") ? "\n  v_note jsonb;\n  v_hook regprocedure;\n  v_extra jsonb;" : ""}
begin${notifyBody}
end;
$$;
revoke execute on function ${fn("approval_notify")}(uuid, text) from public, anon, authenticated;

-- Runs what the final approval unlocks: the policy's state-machine
-- transition or job, or the grant or decision of the module that filed it.
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
  v_run := ${policyOf("v_req")} -> 'run';${transitionRun}${queueRun}${contributedRun}
  ${record("approval.approved", "v_req", true)}
  perform ${fn("approval_notify")}(v_req.${c("id")}, 'approved');
end;
$$;
revoke execute on function ${fn("approval_finalize")}(uuid) from public, anon, authenticated;

-- Files a request under an explicit policy snapshot. request_approval and
-- the access-requests module call it after their own checks. requested_by
-- defaults to the caller.
drop function if exists ${fn("open_approval")}(${ctx.idType}, text, text, text, jsonb, text, jsonb);
create or replace function ${fn("open_approval")}(tenant ${ctx.idType}, subject_type text, subject_id text, action text, policy jsonb, reason text, payload jsonb, requested_by uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_req ${requests}%rowtype;
  v_policy jsonb := open_approval.policy;
  v_requester uuid := coalesce(open_approval.requested_by, auth.uid());
begin
  ${ctx.hook("before_approval_request", [
    [ctx.idType, "open_approval.tenant"],
    ["text", "open_approval.subject_type"],
    ["text", "open_approval.subject_id"],
    ["text", "open_approval.action"],
  ])}${openRefusals}${allHolders}
  insert into ${requests} (${c("tenant")}, ${c("subjectType")}, ${c("subjectId")}, ${c("action")}${also("requests", "policy")}, ${c("requestedBy")}${also("requests", "reason")}${also("requests", "payload")}${also("requests", "expiresAt")})
  values (open_approval.tenant, open_approval.subject_type, open_approval.subject_id, open_approval.action${alsoValue("requests", "policy", "v_policy")}, v_requester${alsoValue("requests", "reason", "open_approval.reason")}${alsoValue("requests", "payload", "coalesce(open_approval.payload, '{}'::jsonb)")}${has("expiresAt") ? `,\n    case when open_approval.policy ->> 'expiresIn' is not null then now() + (open_approval.policy ->> 'expiresIn')::interval end` : ""})
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
revoke execute on function ${fn("open_approval")}(${ctx.idType}, text, text, text, jsonb, text, jsonb, uuid) from public, anon, authenticated;
${linked.length === 0 ? "" : settleSql(ctx, kit)}
${approvalsTenantSql(ctx, {
  json,
  record,
  notFound,
  subjectWrite: subjectAccess(
    {
      type: "request_approval.subject_type",
      id: "request_approval.subject_id",
      tenant: "request_approval.tenant",
    },
    "write",
  ),
  permissions: { read, request, manage },
  extras,
})}

${decideSql(ctx, kit)}

${itemsSql(ctx, kit, { tenantless, linked: (type) => linkedRow(type), read, manage })}

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
begin${
    delegation
      ? `${commentRefusal("delegate_approval.comment")}
  select * into v_req from ${requests} r where r.${c("id")} = delegate_approval.request_id for update;
  if not found then
    ${notFound}
  end if;
  if v_req.${c("status")} <> 'pending' then
    ${fail("APPROVAL_CLOSED", "this request is no longer pending", "22023")}
  end if;
  if not ${fn("approval_eligible")}(v_req.${c("id")}) then
    ${fail("APPROVAL_FORBIDDEN", "not an approver for this step")}
  end if;${
    linked.length === 0
      ? ""
      : `
  if ${linkedRow(`v_req.${c("subjectType")}`)} then
    ${fail("APPROVAL_DELEGATE_INVALID", "the module that filed this request decides who approves it", "22023")}
  end if;`
  }
  if delegate_approval.to_user is null or delegate_approval.to_user = auth.uid() or delegate_approval.to_user = v_req.${c("requestedBy")} then
    ${fail("APPROVAL_DELEGATE_INVALID", "delegate to another user than yourself or the requester", "22023")}
  end if;
  if not ${delegateMember} then
    ${fail("APPROVAL_DELEGATE_INVALID", "the delegate is not a member of this organization", "22023")}
  end if;
  insert into ${decisions} (${d("request")}, ${d("tenant")}, ${d("step")}, ${d("approver")}, ${d("decision")}, ${d("delegateTo")}${also("decisions", "comment")})
  values (v_req.${c("id")}, v_req.${c("tenant")}, ${stepOf("v_req")}, auth.uid(), 'delegated', delegate_approval.to_user${alsoValue("decisions", "comment", "delegate_approval.comment")});
  ${record("approval.delegated", "v_req", true)}
  perform ${fn("approval_notify")}(v_req.${c("id")}, 'delegated');
  return ${json("v_req")};`
      : `
  ${fail("APPROVAL_DELEGATION_UNSUPPORTED", "this approval decisions table has no delegate column", "22023")}`
  }
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
  if not (${SERVICE_CALLER} or coalesce(v_req.${c("requestedBy")} = auth.uid(), false) or ${ctx.can("tenant", `v_req.${c("tenant")}`, manage)}) then
    ${fail("APPROVAL_FORBIDDEN", "only the requester or a manager can cancel this request")}
  end if;
  if v_req.${c("status")} <> 'pending' then
    ${fail("APPROVAL_CLOSED", "this request is no longer pending", "22023")}
  end if;
  update ${requests} r set ${c("status")} = 'cancelled'${decided}
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
  if not (${SERVICE_CALLER} or coalesce(v_req.${c("requestedBy")} = auth.uid(), false) or ${fn("approval_eligible")}(v_req.${c("id")})
    or (${ctx.can("tenant", `v_req.${c("tenant")}`, read)} and ${readable("v_req")})) then
    ${notFound}
  end if;
  return ${json("v_req")} || jsonb_build_object(
    'canDecide', ${fn("approval_eligible")}(v_req.${c("id")}),
    'decisions', coalesce((
      select jsonb_agg(jsonb_build_object('id', x.${d("id")}, 'step', x.${d("step")}, 'approver', x.${d("approver")}, 'decision', x.${d("decision")}, 'delegateTo', ${or("decisions", "x", "delegateTo")}, 'comment', ${or("decisions", "x", "comment")}, 'createdAt', x.${d("createdAt")}) order by x.${d("createdAt")}, x.${d("id")})
      from ${decisions} x where x.${d("request")} = v_req.${c("id")}
    ), '[]'::jsonb),
    'items', ${itemsOf(ctx, `v_req.${c("id")}`)}
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
    where ${tenantless ? `(x.${c("tenant")} = list_approvals.tenant or (list_approvals.tenant is null and x.${c("tenant")} is null))` : `x.${c("tenant")} = list_approvals.tenant`}
      and (list_approvals.status is null or ${asText(ctx, "requests", `x.${c("status")}`)} = list_approvals.status)
      and (list_approvals.subject_type is null or x.${c("subjectType")} = list_approvals.subject_type)
      and (list_approvals.subject_id is null or x.${c("subjectId")} = list_approvals.subject_id)
      and (list_approvals.before is null or x.${c("createdAt")} < list_approvals.before)
      and case
        when list_approvals.assigned then x.${c("id")} in (select ${fn("approval_eligible_ids")}(list_approvals.tenant))
        else x.${c("requestedBy")} = auth.uid() or (v_read and (${SERVICE_CALLER} or ${readable("x")})) or x.${c("id")} in (select ${fn("approval_eligible_ids")}(list_approvals.tenant))
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
begin${
    has("expiresAt")
      ? `
  for v_req in
    update ${requests} r set ${c("status")} = 'expired'${decided}
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
  end loop;`
      : ""
  }
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
begin${
    has("remindedAt")
      ? `
  for v_id in
    update ${requests} r set ${c("remindedAt")} = now()
    where r.${c("id")} in (
      select x.${c("id")} from ${requests} x
      where x.${c("status")} = 'pending'${has("expiresAt") ? `\n        and (x.${c("expiresAt")} is null or x.${c("expiresAt")} > now())` : ""}
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
  end loop;`
      : ""
  }
  return v_count;
end;
$$;
${serviceGrant(`${fn("remind_approvals")}(interval, integer)`)}

${escalateSql(kit)}
${subjectCascades(ctx, subjects, `delete from ${requests} r where r.${c("subjectType")} = v_type and r.${c("subjectId")} = v_id;`)}
`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  return [
    ...approvalsContract(
      extraFieldsArg(ctx.extraColumns("requests", REQUEST_KEYS)).contract,
    ),
    ...approvalItemsContract(),
    ...approvalsTenantContract(ctx),
  ];
}

const CONTRIBUTES: BlockContributes = {
  housekeeping: (own) => [
    {
      job: own.fnName("expire_approvals"),
      function: own.fn("expire_approvals"),
      every: "15 minutes",
    },
  ],
  subjects: (own) => {
    const r = (column: string): string => `r.${own.col("requests", column)}`;

    return [
      {
        work: `select 'approval'::text, ${r("subjectType")}::text, ${r("subjectId")}::text, ${r("id")}::text, null::text,
      ${r("createdAt")}
    from ${own.table("requests")} r
    where ${r("status")} = 'pending'${own.has("requests", "expiresAt") ? `\n      and (${r("expiresAt")} is null or ${r("expiresAt")} > now())` : ""}
      and ${myWorkTenant(r("tenant"))}
      and ${own.fn("approval_eligible")}(r)`,
      },
    ];
  },
};

export const APPROVALS: BlockSqlDefinition = {
  contributes: CONTRIBUTES,
  name: "approvals",
  scopes: ["tenant"],
  title: "Approvals",
  description:
    "Approval requests with steps per subject type and action: approvers by permission, role, team, user or the requester's manager, a required count, delegation, expiry and reminders. Tenants tighten the configured policies with conditions and a confirm or authorize mode, and an approval is consumed once against a request fingerprint. The final approval runs a state-machine transition or a job.",
  requires: ["memberships", "permissions", "housekeeping"],
  integrates: [
    "outbox",
    "audit",
    "notifications",
    "queue",
    "drive",
    "teams",
    "state-machine",
    "employees",
    "automations",
  ],
  target: "schema",
  modes: ["managed", "custom"],
  version: 5,
  names: APPROVALS_NAMES,
  upgrades: [
    {
      from: 1,
      description:
        "Adds approval_items and the item functions; decide_approval refuses a request that has items.",
      sql: () => "",
    },
    {
      from: 2,
      description:
        "Adds approval_eligible_ids(tenant), the set of pending requests the caller may decide; list_approvals reads it once per statement.",
      sql: () => "",
    },
    {
      from: 3,
      description:
        "Adds approval_eligible(approval_requests) and approval_fact, which reads the caller's permission, role, team and manager approvals once per statement.",
      sql: () => "",
    },
    {
      from: 4,
      description:
        "approval_eligible_ids(tenant) joins the pending requests against the caller's approvals in one statement and no longer calls approval_eligible per request.",
      sql: () => "",
    },
  ],
  contract,
  build,
  tests: approvalTests,
};
