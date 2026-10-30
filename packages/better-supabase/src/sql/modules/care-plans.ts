import type { CarePlansEvents } from "../../blocks/care-plans/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockContributes } from "../contributions.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { guestOr } from "../guest-sql.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { RANK_KEY_PATTERN } from "../rank-sql.ts";
import { addExtraColumns, lockTable, schemaPreamble } from "../shared.ts";
import { carePlanFlowFunctions } from "./care-plans-flow.ts";
import { carePlanFunctions } from "./care-plans-functions.ts";
import {
  CARE_PLAN_ACTION_KINDS,
  CARE_PLAN_ACTION_STATUSES,
  CARE_PLAN_GOAL_STATUSES,
  CARE_PLAN_PROBLEM_STATUSES,
  CARE_PLAN_STATUSES,
  carePlansSql,
} from "./care-plans-sql.ts";

const PLAN = [
  "organizationId",
  "id",
  "subjectType",
  "subjectId",
  "title",
  "status",
  "version",
] as const;

const CHILD = ["organizationId", "planId", "subjectType", "subjectId"] as const;

const plan = { subject: "care-plans", payload: PLAN } as const;

const action = {
  subject: "care-plans",
  payload: [...CHILD, "actionId", "kind", "title"],
} as const;

const EVENTS: BlockSqlEvents<CarePlansEvents> = {
  "care_plan.created": plan,
  "care_plan.updated": plan,
  "care_plan.published": {
    subject: "care-plans",
    payload: [...PLAN, "previousPlanId", "versionId"],
  },
  "care_plan.archived": plan,
  "care_plan.agreed": {
    subject: "care-plans",
    payload: [...PLAN, "signatureRequestId"],
  },
  "care_plan.review_date_reached": {
    subject: "care-plans",
    payload: [...PLAN, "ownerId", "reviewOn"],
  },
  "care_plan_goal.status_changed": {
    subject: "care-plans",
    payload: [...CHILD, "goalId", "title", "status", "previousStatus"],
  },
  "care_plan_evaluation.created": {
    subject: "care-plans",
    payload: [...CHILD, "evaluationId", "goalId", "status"],
  },
  "care_plan_action.started": action,
  "care_plan_action.ended": {
    subject: "care-plans",
    payload: [...action.payload, "reason"],
  },
  "care_plan_action.review_date_reached": {
    subject: "care-plans",
    payload: [...action.payload, "ownerId", "dueAt"],
  },
  "care_plan_action.reviewed": {
    subject: "care-plans",
    payload: [...action.payload, "note"],
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    care_plan: {
      table: "plans",
      singular: "care_plan",
      primary: true,
      subject: {
        title: "title",
        permissions: { read: "read", write: "write" },
      },
    },
    care_plan_problem: { table: "problems", singular: "care_plan_problem" },
    care_plan_goal: { table: "goals", singular: "care_plan_goal" },
    care_plan_action: { table: "actions", singular: "care_plan_action" },
    care_plan_evaluation: {
      table: "evaluations",
      singular: "care_plan_evaluation",
    },
  },
  events: EVENTS,
  hooks: [
    "before_care_plan_create",
    "after_care_plan_create",
    "before_care_plan_publish",
    "after_care_plan_publish",
    "before_care_plan_evaluation_create",
    "after_care_plan_evaluation_create",
  ],
  options: ["codeSystems", "guestRead", "measureKinds", "extraColumns"],
  tables: {
    plans: {
      name: "care_plans",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        title: "title",
        status: "status",
        version: "version",
        startsOn: "starts_on",
        reviewOn: "review_on",
        owner: "owner_id",
        signature: "signature_id",
        agreedAt: "agreed_at",
        publishedVersion: "published_version_id",
        publishedAt: "published_at",
        publishedBy: "published_by",
        archivedAt: "archived_at",
        reviewNotifiedFor: "review_notified_for",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["publishedVersion", "createdBy"],
    },
    problems: {
      name: "care_plan_problems",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        plan: "plan_id",
        codeSystem: "code_system",
        code: "code",
        title: "title",
        description: "description",
        status: "status",
        rank: "rank",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    goals: {
      name: "care_plan_goals",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        plan: "plan_id",
        problem: "problem_id",
        title: "title",
        targetOn: "target_on",
        status: "status",
        measure: "measure",
        rank: "rank",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    actions: {
      name: "care_plan_actions",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        plan: "plan_id",
        goal: "goal_id",
        kind: "kind",
        title: "title",
        instructions: "instructions",
        frequency: "frequency",
        teamRole: "team_role",
        measureKind: "measure_kind",
        task: "task_id",
        bookingSeries: "booking_series_id",
        requiresApproval: "requires_approval",
        approval: "approval_id",
        reviewEvery: "review_every",
        reviewedAt: "reviewed_at",
        reviewNotifiedAt: "review_notified_at",
        startsOn: "starts_on",
        endsOn: "ends_on",
        status: "status",
        startedAt: "started_at",
        endedAt: "ended_at",
        endReason: "end_reason",
        rank: "rank",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    evaluations: {
      name: "care_plan_evaluations",
      app: {},
      lifecycle: { tenant: "tenant", user: "author", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        plan: "plan_id",
        goal: "goal_id",
        evaluatedAt: "evaluated_at",
        status: "status",
        outcome: "outcome",
        submission: "submission_id",
        author: "author_id",
      },
    },
  },
};

const list = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

function tables(ctx: BlockSqlContext): string {
  const q = carePlansSql(ctx);
  const { p, pr, g, a, e, plans, problems, goals, actions, evaluations } = q;

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  const opt = (logical: string, column: string, line: () => string): string =>
    ctx.has(logical, column) ? `\n  ${line()},` : "";

  const appKey = (logical: string, what: string, columns: string): string =>
    ctx.owns(logical)
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName(logical).name}_${what}_key`)} on ${ctx.table(logical)} (${columns});`;

  const readPolicy = (logical: string, using: string): string =>
    renderPolicy(
      makePolicy({
        table: ctx.table(logical),
        name: ctx.owns(logical)
          ? name(logical, "read")
          : sqlIdent(`bsb_${ctx.tableName(logical).name}_read`),
        command: "select",
        roles: ["authenticated"],
        using,
      }),
      { drop: true, target: ctx.table(logical) },
    );

  const guest = ctx.scope.guest(
    p("tenant"),
    p("subjectType"),
    `${p("subjectId")}::text`,
    "read",
  );

  // A guest reads the plans that are or were in force, never a draft.
  const planRead = guestOr(
    `${ctx.scope.check(p("tenant"), q.read)} and coalesce(${ctx.of("subjects").fn("can_subject")}(${plans}.${sqlIdent(ctx.colName("plans", "subjectType"))}, ${plans}.${sqlIdent(ctx.colName("plans", "subjectId"))}::text, 'read'), false)`,
    q.guestRead && guest !== "false"
      ? [`(${p("status")} <> 'draft' and ${guest})`]
      : [],
  );

  // A row of a plan reads like its plan: the plans policy applies inside.
  const childRead = (table: string, column: string): string =>
    `exists (select 1 from ${plans} x where x.${p("id")} = ${table}.${column})`;

  const text = (column: string, max: number): string =>
    `${column} text check (${column} is null or length(${column}) <= ${String(max)})`;

  const rank = (column: string): string =>
    `${column} text collate "C" not null default 'V' check (${column} ~ ${RANK_KEY_PATTERN})`;

  const versions = ctx.of("versions");

  const versionRef =
    ctx.installed("versions") && versions.owns("versions")
      ? ` references ${versions.table("versions")} (${versions.col("versions", "id")}) on delete set null`
      : "";

  return `
create table if not exists ${plans} (
  ${p("id")} uuid primary key default gen_random_uuid(),
  ${p("tenant")} ${ctx.idType} not null,
  -- The client the plan is for: any registered subject type.
  ${p("subjectType")} text not null check (length(${p("subjectType")}) between 1 and 63),
  ${p("subjectId")} text not null check (length(${p("subjectId")}) between 1 and 200),
  ${p("title")} text not null check (length(${p("title")}) between 1 and 300),
  ${p("status")} text not null default 'draft' check (${p("status")} in (${list(CARE_PLAN_STATUSES)})),
  -- 1 for a subject's first plan, one more for each plan after it.
  ${p("version")} integer not null default 1 check (${p("version")} >= 1),
  ${p("startsOn")} date,
  ${p("reviewOn")} date,
  ${p("owner")} uuid,
  -- The signature request asking the client side to agree to the plan.
  ${p("signature")} uuid,
  ${p("agreedAt")} timestamptz,${opt("plans", "publishedVersion", () => `${p("publishedVersion")} uuid${versionRef}`)}
  ${p("publishedAt")} timestamptz,
  ${p("publishedBy")} uuid,
  ${p("archivedAt")} timestamptz,
  -- The review date due_care_plan_reviews last reported, so each date reports once.
  ${p("reviewNotifiedFor")} date,${opt("plans", "createdBy", () => `${p("createdBy")} uuid`)}
  ${p("createdAt")} timestamptz not null default now(),
  ${p("updatedAt")} timestamptz not null default now(),
  unique (${p("tenant")}, ${p("id")}),
  check (${p("status")} = 'draft' or ${p("publishedAt")} is not null),
  check (${p("status")} <> 'archived' or ${p("archivedAt")} is not null)
);${addExtraColumns(plans, q.extras)}${appKey("plans", "tenant_id", `${p("tenant")}, ${p("id")}`)}
create unique index if not exists ${name("plans", "active_key")} on ${plans} (${p("subjectType")}, ${p("subjectId")}) where ${p("status")} = 'active';
create index if not exists ${name("plans", "subject_idx")} on ${plans} (${p("tenant")}, ${p("subjectType")}, ${p("subjectId")}, ${p("version")} desc);
create index if not exists ${name("plans", "review_idx")} on ${plans} (${p("reviewOn")}) where ${p("status")} = 'active';
create index if not exists ${name("plans", "signature_idx")} on ${plans} (${p("signature")}) where ${p("signature")} is not null;
${ctx.has("plans", "publishedVersion") ? `create index if not exists ${name("plans", "version_idx")} on ${plans} (${p("publishedVersion")}) where ${p("publishedVersion")} is not null;\n` : ""}${lockTable(plans, { read: true })}
${readPolicy("plans", planRead)}

create table if not exists ${problems} (
  ${pr("id")} uuid primary key default gen_random_uuid(),
  ${pr("tenant")} ${ctx.idType} not null,
  ${pr("plan")} uuid not null,
  -- One of options.codeSystems, such as icnp or snomed; the functions check it.
  ${pr("codeSystem")} text not null default 'custom' check (length(${pr("codeSystem")}) between 1 and 63),
  ${text(pr("code"), 100)},
  ${pr("title")} text not null check (length(${pr("title")}) between 1 and 300),
  ${text(pr("description"), 10_000)},
  ${pr("status")} text not null default 'active' check (${pr("status")} in (${list(CARE_PLAN_PROBLEM_STATUSES)})),
  ${rank(pr("rank"))},
  ${pr("createdAt")} timestamptz not null default now(),
  ${pr("updatedAt")} timestamptz not null default now(),
  unique (${pr("tenant")}, ${pr("plan")}, ${pr("id")}),
  foreign key (${pr("tenant")}, ${pr("plan")}) references ${plans} (${p("tenant")}, ${p("id")}) on delete cascade
);${appKey("problems", "tenant_plan_id", `${pr("tenant")}, ${pr("plan")}, ${pr("id")}`)}
create index if not exists ${name("problems", "plan_idx")} on ${problems} (${pr("tenant")}, ${pr("plan")}, ${pr("rank")});
${lockTable(problems, { read: true })}
${readPolicy("problems", childRead(problems, pr("plan")))}

create table if not exists ${goals} (
  ${g("id")} uuid primary key default gen_random_uuid(),
  ${g("tenant")} ${ctx.idType} not null,
  ${g("plan")} uuid not null,
  ${g("problem")} uuid not null,
  ${g("title")} text not null check (length(${g("title")}) between 1 and 300),
  ${g("targetOn")} date,
  ${g("status")} text not null default 'planned' check (${g("status")} in (${list(CARE_PLAN_GOAL_STATUSES)})),
  -- How progress is measured, such as { "kind": "score", "target": 3 }.
  ${g("measure")} jsonb check (${g("measure")} is null or jsonb_typeof(${g("measure")}) = 'object'),
  ${rank(g("rank"))},
  ${g("createdAt")} timestamptz not null default now(),
  ${g("updatedAt")} timestamptz not null default now(),
  unique (${g("tenant")}, ${g("plan")}, ${g("id")}),
  foreign key (${g("tenant")}, ${g("plan")}, ${g("problem")}) references ${problems} (${pr("tenant")}, ${pr("plan")}, ${pr("id")}) on delete cascade
);${appKey("goals", "tenant_plan_id", `${g("tenant")}, ${g("plan")}, ${g("id")}`)}
create index if not exists ${name("goals", "problem_idx")} on ${goals} (${g("tenant")}, ${g("plan")}, ${g("problem")});
${lockTable(goals, { read: true })}
${readPolicy("goals", childRead(goals, g("plan")))}

create table if not exists ${actions} (
  ${a("id")} uuid primary key default gen_random_uuid(),
  ${a("tenant")} ${ctx.idType} not null,
  ${a("plan")} uuid not null,
  ${a("goal")} uuid not null,
  ${a("kind")} text not null default 'intervention' check (${a("kind")} in (${list(CARE_PLAN_ACTION_KINDS)})),
  ${a("title")} text not null check (length(${a("title")}) between 1 and 300),
  ${text(a("instructions"), 10_000)},
  -- How often, such as { "every": "P1D", "times": ["08:00", "20:00"] }.
  ${a("frequency")} jsonb check (${a("frequency")} is null or jsonb_typeof(${a("frequency")}) = 'object'),
  -- The team role that carries the action out, such as nurse.
  ${text(a("teamRole"), 63)},
  -- For a measure: one of options.measureKinds when it lists any.
  ${text(a("measureKind"), 63)},
  -- The work item a task action created, with the tasks block.
  ${a("task")} uuid,
  -- The bookings series an appointment action placed.
  ${a("bookingSeries")} uuid,
  -- A measure always needs an approval before it starts.
  ${a("requiresApproval")} boolean not null default false,
  ${a("approval")} uuid,
  ${a("reviewEvery")} interval check (${a("reviewEvery")} is null or ${a("reviewEvery")} > interval '0'),
  ${a("reviewedAt")} timestamptz,
  -- The review moment due_care_plan_reviews last reported.
  ${a("reviewNotifiedAt")} timestamptz,
  ${a("startsOn")} date,
  ${a("endsOn")} date,
  ${a("status")} text not null default 'planned' check (${a("status")} in (${list(CARE_PLAN_ACTION_STATUSES)})),
  ${a("startedAt")} timestamptz,
  ${a("endedAt")} timestamptz,
  ${text(a("endReason"), 2000)},
  ${rank(a("rank"))},
  ${a("createdAt")} timestamptz not null default now(),
  ${a("updatedAt")} timestamptz not null default now(),
  check (${a("kind")} <> 'measure' or ${a("requiresApproval")}),
  check (${a("endsOn")} is null or ${a("startsOn")} is null or ${a("endsOn")} >= ${a("startsOn")}),
  foreign key (${a("tenant")}, ${a("plan")}, ${a("goal")}) references ${goals} (${g("tenant")}, ${g("plan")}, ${g("id")}) on delete cascade
);
create index if not exists ${name("actions", "goal_idx")} on ${actions} (${a("tenant")}, ${a("plan")}, ${a("goal")});
create index if not exists ${name("actions", "measure_idx")} on ${actions} (${a("tenant")}, ${a("status")}) where ${a("kind")} = 'measure';
create index if not exists ${name("actions", "approval_idx")} on ${actions} (${a("approval")}) where ${a("approval")} is not null;
create index if not exists ${name("actions", "review_idx")} on ${actions} (${a("status")}) where ${a("reviewEvery")} is not null;
${lockTable(actions, { read: true })}
${readPolicy("actions", childRead(actions, a("plan")))}

create table if not exists ${evaluations} (
  ${e("id")} uuid primary key default gen_random_uuid(),
  ${e("tenant")} ${ctx.idType} not null,
  ${e("plan")} uuid not null,
  ${e("goal")} uuid not null,
  ${e("evaluatedAt")} timestamptz not null default now(),
  -- The goal's status the evaluation found.
  ${e("status")} text not null check (${e("status")} in (${list(CARE_PLAN_GOAL_STATUSES)})),
  ${text(e("outcome"), 10_000)},
  -- The forms submission that recorded the evaluation, if one did.
  ${e("submission")} uuid,
  ${e("author")} uuid,
  foreign key (${e("tenant")}, ${e("plan")}, ${e("goal")}) references ${goals} (${g("tenant")}, ${g("plan")}, ${g("id")}) on delete cascade
);
create index if not exists ${name("evaluations", "goal_idx")} on ${evaluations} (${e("tenant")}, ${e("plan")}, ${e("goal")}, ${e("evaluatedAt")} desc);
${lockTable(evaluations, { read: true })}
${readPolicy("evaluations", childRead(evaluations, e("plan")))}
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  return `${schemaPreamble(ctx)}
-- Care plans per client: problems, goals and the actions that reach them,
-- evaluated over time, published as one active plan per client, agreed
-- through a signature, with restrictive measures started only on approval.
${tables(ctx)}
${carePlanFunctions(ctx)}
${carePlanFlowFunctions(ctx)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    { name: "create_care_plan", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "update_care_plan", args: ["uuid", "jsonb"], returns: "jsonb" },
    {
      name: "add_care_plan_problem",
      args: ["uuid", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "update_care_plan_problem",
      args: ["uuid", "jsonb"],
      returns: "jsonb",
    },
    { name: "add_care_plan_goal", args: ["uuid", "jsonb"], returns: "jsonb" },
    {
      name: "update_care_plan_goal",
      args: ["uuid", "jsonb"],
      returns: "jsonb",
    },
    { name: "add_care_plan_action", args: ["uuid", "jsonb"], returns: "jsonb" },
    {
      name: "update_care_plan_action",
      args: ["uuid", "jsonb"],
      returns: "jsonb",
    },
    { name: "publish_care_plan", args: ["uuid"], returns: "jsonb" },
    { name: "archive_care_plan", args: ["uuid"], returns: "jsonb" },
    { name: "get_care_plan", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_care_plans",
      args: ["text", "text", "boolean"],
      returns: "jsonb",
    },
    {
      name: "record_care_plan_evaluation",
      args: ["uuid", "text", "text", "uuid"],
      returns: "jsonb",
    },
    { name: "start_care_plan_action", args: ["uuid"], returns: "jsonb" },
    { name: "end_care_plan_action", args: ["uuid", "text"], returns: "jsonb" },
    {
      name: "review_care_plan_action",
      args: ["uuid", "text"],
      returns: "jsonb",
    },
    {
      name: "list_care_plan_measures",
      args: ["{id}", "boolean"],
      returns: "jsonb",
    },
    {
      name: "request_care_plan_agreement",
      args: ["uuid", "uuid[]", "text"],
      returns: "jsonb",
    },
    { name: "due_care_plan_reviews", args: [], returns: "integer" },
  ];
}

const CONTRIBUTES: BlockContributes = {
  approvals: (own) => [
    {
      subject: own.naming.rename("care_plan_action"),
      access: "declared",
      approve: ({ subjectId }) =>
        `perform ${own.fn("care_plan_action_approved")}(${subjectId}::uuid);`,
    },
  ],
};

export const CARE_PLANS: BlockSqlDefinition = {
  contributes: CONTRIBUTES,
  name: "care-plans",
  scopes: ["tenant"],
  title: "Care plans",
  description:
    "Care plans per client: problems with codes from your code systems, goals and the actions that reach them, evaluations over time, one active plan per client published as a version, agreement through a signature, and restrictive measures that start only once approved.",
  requires: ["memberships", "permissions", "subjects"],
  integrates: [
    "versions",
    "signatures",
    "approvals",
    "tasks",
    "guests",
    "notifications",
    "outbox",
    "audit",
  ],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
