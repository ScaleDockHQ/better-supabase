import type { AppraisalsEvents } from "../../blocks/appraisals/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockContributes } from "../contributions.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { lockTable, schemaPreamble } from "../shared.ts";
import { appraisalsFunctions } from "./appraisals-functions.ts";
import { reviewHiddenFunction } from "./appraisals-rubrics.ts";
import { appraisalsSql } from "./appraisals-sql.ts";
import {
  APPRAISAL_ANONYMITY,
  APPRAISAL_CYCLE_STATUSES,
  APPRAISAL_REVIEW_KINDS,
  APPRAISAL_STATUSES,
} from "./appraisals-values.ts";

const CYCLE = ["organizationId", "id", "name", "status"] as const;

const APPRAISAL = [
  "organizationId",
  "id",
  "cycleId",
  "subjectUserId",
  "status",
] as const;

const EVENTS: BlockSqlEvents<AppraisalsEvents> = {
  "appraisal_cycle.created": { subject: "appraisal-cycles", payload: CYCLE },
  "appraisal_cycle.opened": { subject: "appraisal-cycles", payload: CYCLE },
  "appraisal_cycle.closed": { subject: "appraisal-cycles", payload: CYCLE },
  "appraisal.created": { subject: "appraisals", payload: APPRAISAL },
  "appraisal.calibrated": {
    subject: "appraisals",
    payload: [...APPRAISAL, "rating"],
  },
  "appraisal.finalized": {
    subject: "appraisals",
    payload: [...APPRAISAL, "rating"],
  },
  "appraisal_review.submitted": {
    subject: "appraisals",
    payload: [
      "organizationId",
      "id",
      "appraisalId",
      "reviewerId",
      "kind",
      "rating",
    ],
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    appraisal: { table: "appraisals", singular: "appraisal", primary: true },
    appraisal_cycle: { table: "cycles", singular: "appraisal_cycle" },
    appraisal_review: { table: "reviews", singular: "appraisal_review" },
    appraisal_calibration: {
      table: "calibrations",
      singular: "appraisal_calibration",
    },
    appraisal_goal: { table: "goals", singular: "appraisal_goal" },
    appraisal_competency: {
      table: "competencies",
      singular: "appraisal_competency",
    },
    appraisal_review_rating: {
      table: "ratings",
      singular: "appraisal_review_rating",
    },
  },
  events: EVENTS,
  hooks: ["before_appraisal_cycle_create", "after_appraisal_cycle_create"],
  options: [],
  tables: {
    cycles: {
      name: "appraisal_cycles",
      app: {},
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        name: "name",
        startsOn: "starts_on",
        endsOn: "ends_on",
        program: "program",
        status: "status",
        anonymity: "anonymity",
        shareFeedback: "share_feedback",
        openedAt: "opened_at",
        closedAt: "closed_at",
        createdBy: "created_by",
        createdAt: "created_at",
      },
    },
    appraisals: {
      name: "appraisals",
      app: {},
      lifecycle: { tenant: "tenant", user: "subjectUser", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        cycle: "cycle_id",
        subjectUser: "subject_user_id",
        manager: "manager_id",
        status: "status",
        rating: "rating",
        calibratedRating: "calibrated_rating",
        calibratedCompetencies: "calibrated_competencies",
        approval: "approval_id",
        signedOffAt: "signed_off_at",
        signedOffBy: "signed_off_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    reviews: {
      name: "appraisal_reviews",
      app: {},
      lifecycle: { tenant: "tenant", user: "reviewer", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        appraisal: "appraisal_id",
        reviewer: "reviewer_id",
        kind: "kind",
        rating: "rating",
        comments: "comments",
        submission: "submission_id",
        submittedAt: "submitted_at",
      },
    },
    calibrations: {
      name: "appraisal_calibrations",
      app: {},
      lifecycle: { tenant: "tenant", user: "calibratedBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        appraisal: "appraisal_id",
        fromRating: "from_rating",
        toRating: "to_rating",
        competencyRatings: "competency_ratings",
        reason: "reason",
        calibratedBy: "calibrated_by",
        calibratedAt: "calibrated_at",
      },
    },
    competencies: {
      name: "appraisal_competencies",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        cycle: "cycle_id",
        key: "key",
        name: "name",
        weight: "weight",
        position: "position",
      },
    },
    ratings: {
      name: "appraisal_review_ratings",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        review: "review_id",
        competency: "competency_id",
        rating: "rating",
        comment: "comment",
      },
    },
    goals: {
      name: "appraisal_goals",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        appraisal: "appraisal_id",
        goal: "goal_id",
      },
    },
  },
};

const list = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

function tables(ctx: BlockSqlContext): string {
  const q = appraisalsSql(ctx);

  const {
    y,
    a,
    r,
    c,
    g,
    k,
    t,
    cycles,
    appraisals,
    reviews,
    calibrations,
    goals,
    competencies,
    ratings,
  } = q;

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  const appKey = (logical: string, columns: string): string =>
    ctx.owns(logical)
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName(logical).name}_tenant_id_key`)} on ${ctx.table(logical)} (${columns});`;

  const readPolicy = (
    logical: string,
    tenant: string,
    extra?: string,
  ): string =>
    renderPolicy(
      makePolicy({
        table: ctx.table(logical),
        name: ctx.owns(logical)
          ? name(logical, "read")
          : sqlIdent(`bsb_${ctx.tableName(logical).name}_read`),
        command: "select",
        roles: ["authenticated"],
        using:
          extra === undefined
            ? ctx.scope.check(tenant, q.read)
            : `${ctx.scope.check(tenant, q.read)} and ${extra}`,
      }),
      { drop: true, target: ctx.table(logical) },
    );

  return `
${reviewHiddenFunction(q)}
create table if not exists ${cycles} (
  ${y("id")} uuid primary key default gen_random_uuid(),
  ${y("tenant")} ${ctx.idType} not null,
  ${y("name")} text not null check (length(${y("name")}) between 1 and 200),
  ${y("startsOn")} date not null,
  ${y("endsOn")} date not null,
  -- The key of the enrollment program the cycle's appraisals follow, when set.
  ${y("program")} text,
  ${y("status")} text not null default 'draft' check (${y("status")} in (${list(APPRAISAL_CYCLE_STATUSES)})),
  -- Who learns which peer wrote a review: everyone who sees it (none), anyone
  -- but the appraised person (subject), or only the reviewer (all).
  ${y("anonymity")} text not null default 'subject' check (${y("anonymity")} in (${list(APPRAISAL_ANONYMITY)})),
  -- Whether the appraised person reads the manager and peer reviews once the
  -- appraisal is signed off.
  ${y("shareFeedback")} boolean not null default false,
  ${y("openedAt")} timestamptz,
  ${y("closedAt")} timestamptz,
  ${y("createdBy")} uuid,
  ${y("createdAt")} timestamptz not null default now(),
  unique (${y("tenant")}, ${y("id")}),
  check (${y("endsOn")} >= ${y("startsOn")})
);${appKey("cycles", `${y("tenant")}, ${y("id")}`)}
create index if not exists ${name("cycles", "tenant_idx")} on ${cycles} (${y("tenant")}, ${y("startsOn")} desc);
${lockTable(cycles, { read: true })}
${readPolicy("cycles", y("tenant"))}

create table if not exists ${appraisals} (
  ${a("id")} uuid primary key default gen_random_uuid(),
  ${a("tenant")} ${ctx.idType} not null,
  ${a("cycle")} uuid not null,
  ${a("subjectUser")} uuid not null,
  ${a("manager")} uuid,
  ${a("status")} text not null default 'pending' check (${a("status")} in (${list(APPRAISAL_STATUSES)})),
  -- The average of the submitted reviews.
  ${a("rating")} numeric(3, 2) check (${a("rating")} is null or ${a("rating")} between 1 and 5),
  -- The rating a calibration session set, when it moved.
  ${a("calibratedRating")} smallint check (${a("calibratedRating")} is null or ${a("calibratedRating")} between 1 and 5),
  -- Calibrated competency ratings by competency key, when a session moved them.
  ${a("calibratedCompetencies")} jsonb not null default '{}'::jsonb check (jsonb_typeof(${a("calibratedCompetencies")}) = 'object'),
  -- The approvals request that signs the appraisal off.
  ${a("approval")} uuid,
  ${a("signedOffAt")} timestamptz,
  ${a("signedOffBy")} uuid,
  ${a("createdAt")} timestamptz not null default now(),
  ${a("updatedAt")} timestamptz not null default now(),
  unique (${a("tenant")}, ${a("id")}),
  unique (${a("cycle")}, ${a("subjectUser")}),
  foreign key (${a("tenant")}, ${a("cycle")}) references ${cycles} (${y("tenant")}, ${y("id")}) on delete cascade,
  check ((${a("status")} = 'signed_off') = (${a("signedOffAt")} is not null))
);${appKey("appraisals", `${a("tenant")}, ${a("id")}`)}
create index if not exists ${name("appraisals", "cycle_idx")} on ${appraisals} (${a("tenant")}, ${a("cycle")}, ${a("status")});
create index if not exists ${name("appraisals", "subject_idx")} on ${appraisals} (${a("tenant")}, ${a("subjectUser")});
create index if not exists ${name("appraisals", "approval_idx")} on ${appraisals} (${a("approval")}) where ${a("approval")} is not null;
${lockTable(appraisals, { read: true })}
${readPolicy("appraisals", a("tenant"))}

create table if not exists ${reviews} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("tenant")} ${ctx.idType} not null,
  ${r("appraisal")} uuid not null,
  ${r("reviewer")} uuid not null,
  ${r("kind")} text not null check (${r("kind")} in (${list(APPRAISAL_REVIEW_KINDS)})),
  ${r("rating")} smallint check (${r("rating")} is null or ${r("rating")} between 1 and 5),
  ${r("comments")} text check (${r("comments")} is null or length(${r("comments")}) <= 10000),
  -- The forms submission with the longer answers, when the review uses a form.
  ${r("submission")} uuid,
  ${r("submittedAt")} timestamptz,
  unique (${r("tenant")}, ${r("id")}),
  unique (${r("appraisal")}, ${r("reviewer")}, ${r("kind")}),
  foreign key (${r("tenant")}, ${r("appraisal")}) references ${appraisals} (${a("tenant")}, ${a("id")}) on delete cascade,
  check ((${r("submittedAt")} is not null) = (${r("rating")} is not null))
);
create index if not exists ${name("reviews", "parent_idx")} on ${reviews} (${r("tenant")}, ${r("appraisal")});
create index if not exists ${name("reviews", "reviewer_idx")} on ${reviews} (${r("tenant")}, ${r("reviewer")}) where ${r("submittedAt")} is null;
${lockTable(reviews, { read: true })}
${readPolicy("reviews", r("tenant"), `not ${q.fn("appraisal_review_hidden")}(${r("id")})`)}

create table if not exists ${calibrations} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${ctx.idType} not null,
  ${c("appraisal")} uuid not null,
  ${c("fromRating")} numeric(3, 2),
  ${c("toRating")} smallint not null check (${c("toRating")} between 1 and 5),
  -- The competency ratings the session set, by competency key.
  ${c("competencyRatings")} jsonb not null default '{}'::jsonb check (jsonb_typeof(${c("competencyRatings")}) = 'object'),
  ${c("reason")} text not null check (length(${c("reason")}) between 1 and 2000),
  ${c("calibratedBy")} uuid,
  ${c("calibratedAt")} timestamptz not null default now(),
  foreign key (${c("tenant")}, ${c("appraisal")}) references ${appraisals} (${a("tenant")}, ${a("id")}) on delete cascade
);
create index if not exists ${name("calibrations", "parent_idx")} on ${calibrations} (${c("tenant")}, ${c("appraisal")}, ${c("calibratedAt")});
${lockTable(calibrations, { read: true })}
${readPolicy("calibrations", c("tenant"))}

-- The competencies of a cycle's rubric. Their weights weigh the ratings when
-- the appraisal's rating is computed, and they don't change once the cycle is
-- open.
create table if not exists ${competencies} (
  ${k("id")} uuid primary key default gen_random_uuid(),
  ${k("tenant")} ${ctx.idType} not null,
  ${k("cycle")} uuid not null,
  ${k("key")} text not null check (${k("key")} ~ '^[a-z][a-z0-9_]{0,62}$'),
  ${k("name")} text not null check (length(${k("name")}) between 1 and 200),
  ${k("weight")} numeric(6, 2) not null default 1 check (${k("weight")} > 0 and ${k("weight")} <= 1000),
  ${k("position")} integer not null default 0,
  unique (${k("tenant")}, ${k("id")}),
  unique (${k("cycle")}, ${k("key")}),
  foreign key (${k("tenant")}, ${k("cycle")}) references ${cycles} (${y("tenant")}, ${y("id")}) on delete cascade
);
create index if not exists ${name("competencies", "parent_idx")} on ${competencies} (${k("tenant")}, ${k("cycle")}, ${k("position")});
${lockTable(competencies, { read: true })}
${readPolicy("competencies", k("tenant"))}

-- One review's rating of one competency. A row is as hidden as its review.
create table if not exists ${ratings} (
  ${t("id")} uuid primary key default gen_random_uuid(),
  ${t("tenant")} ${ctx.idType} not null,
  ${t("review")} uuid not null,
  ${t("competency")} uuid not null,
  ${t("rating")} smallint not null check (${t("rating")} between 1 and 5),
  ${t("comment")} text check (${t("comment")} is null or length(${t("comment")}) <= 2000),
  unique (${t("review")}, ${t("competency")}),
  foreign key (${t("tenant")}, ${t("review")}) references ${reviews} (${r("tenant")}, ${r("id")}) on delete cascade,
  foreign key (${t("tenant")}, ${t("competency")}) references ${competencies} (${k("tenant")}, ${k("id")}) on delete cascade
);
create index if not exists ${name("ratings", "parent_idx")} on ${ratings} (${t("tenant")}, ${t("review")});
create index if not exists ${name("ratings", "competency_idx")} on ${ratings} (${t("tenant")}, ${t("competency")});
${lockTable(ratings, { read: true })}
${readPolicy("ratings", t("tenant"), `not ${q.fn("appraisal_review_hidden")}(${t("review")})`)}

-- The goals an appraisal looks back on. goal_id points at the goals block's
-- goals or at a table of your own, so there is no foreign key.
create table if not exists ${goals} (
  ${g("id")} uuid primary key default gen_random_uuid(),
  ${g("tenant")} ${ctx.idType} not null,
  ${g("appraisal")} uuid not null,
  ${g("goal")} uuid not null,
  unique (${g("appraisal")}, ${g("goal")}),
  foreign key (${g("tenant")}, ${g("appraisal")}) references ${appraisals} (${a("tenant")}, ${a("id")}) on delete cascade
);
create index if not exists ${name("goals", "parent_idx")} on ${goals} (${g("tenant")}, ${g("appraisal")});
${lockTable(goals, { read: true })}
${readPolicy("goals", g("tenant"))}
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  return `${schemaPreamble(ctx)}
-- Performance appraisals per organization: review cycles, one appraisal per
-- person with self, peer and manager reviews (rated per weighted competency
-- when the cycle has a rubric, peer reviewers hidden when it says so),
-- calibration sessions that keep their reason, and sign-off through approvals. Cycles follow an enrollment
-- program when you name one.
${tables(ctx)}
${appraisalsFunctions(ctx)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "create_appraisal_cycle",
      args: ["{id}", "jsonb"],
      returns: "jsonb",
    },
    { name: "open_appraisal_cycle", args: ["uuid", "jsonb"], returns: "jsonb" },
    { name: "close_appraisal_cycle", args: ["uuid"], returns: "jsonb" },
    { name: "list_appraisal_cycles", args: ["{id}"], returns: "jsonb" },
    {
      name: "submit_appraisal_review",
      args: ["uuid", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "calibrate_appraisal",
      args: ["uuid", "integer", "text"],
      returns: "jsonb",
    },
    { name: "set_appraisal_goals", args: ["uuid", "uuid[]"], returns: "jsonb" },
    {
      name: "set_appraisal_competencies",
      args: ["uuid", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "calibrate_appraisal_competencies",
      args: ["uuid", "jsonb", "text"],
      returns: "jsonb",
    },
    { name: "appraisal_review_hidden", args: ["uuid"], returns: "boolean" },
    { name: "sign_off_appraisal", args: ["uuid"], returns: "jsonb" },
    { name: "get_appraisal", args: ["uuid"], returns: "jsonb" },
    { name: "list_appraisals", args: ["{id}", "jsonb"], returns: "jsonb" },
  ];
}

const CONTRIBUTES: BlockContributes = {
  approvals: (own) => [
    {
      subject: own.naming.rename("appraisal"),
      access: "declared",
      approve: ({ subjectId }) =>
        `perform ${own.fn("appraisal_approved")}(${subjectId}::uuid);`,
      reject: ({ subjectId }) =>
        `perform ${own.fn("appraisal_rejected")}(${subjectId}::uuid);`,
    },
  ],
};

export const APPRAISALS: BlockSqlDefinition = {
  contributes: CONTRIBUTES,
  name: "appraisals",
  scopes: ["tenant"],
  title: "Appraisals",
  description:
    "Performance appraisals: review cycles that can follow an enrollment program and carry a rubric of weighted competencies, one appraisal per person with self, peer and manager reviews, anonymous peer reviewers, goals, calibration sessions that keep their reason, and sign-off through approvals.",
  requires: ["memberships", "permissions", "subjects"],
  integrates: ["enrollments", "forms", "goals", "approvals", "outbox", "audit"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
