import type { BlockSqlContext, ExtraColumn } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { extraFieldsJson, fail, SERVICE_CALLER } from "../shared.ts";
import { OPERATIONS } from "./permissions-model.ts";

const WHERE = "blocks.care-plans.options";

/** The statuses a care plan moves through. */
export const CARE_PLAN_STATUSES = ["draft", "active", "archived"] as const;

/** The statuses of a problem on a plan. */
export const CARE_PLAN_PROBLEM_STATUSES = ["active", "resolved"] as const;

/** The statuses of a goal. */
export const CARE_PLAN_GOAL_STATUSES = [
  "planned",
  "in_progress",
  "achieved",
  "not_achieved",
  "canceled",
] as const;

/** What an action is. */
export const CARE_PLAN_ACTION_KINDS = [
  "intervention",
  "appointment",
  "task",
  "measure",
] as const;

/** The statuses of an action. */
export const CARE_PLAN_ACTION_STATUSES = [
  "planned",
  "active",
  "ended",
] as const;

/** The keys the plan reads return next to the extra columns. */
const PLAN_RESERVED = ["fields", "problems", "evaluations"] as const;

/**
 * An interval as an ISO 8601 duration, such as `P0Y3M0DT0H0M0S`; null stays
 * null.
 */
const isoInterval = (value: string): string =>
  `case when ${value} is null then null else format('P%sY%sM%sDT%sH%sM%sS', extract(year from ${value})::int, extract(month from ${value})::int, extract(day from ${value})::int, extract(hour from ${value})::int, extract(minute from ${value})::int, trim_scale(extract(second from ${value}))) end`;

const NAME = /^[a-z][a-z0-9_.-]{0,62}$/;

/** A lowercase name list option, checked. */
function namesOf(
  ctx: BlockSqlContext,
  option: string,
  fallback: readonly string[],
  minimum: number,
): readonly string[] {
  const values = ctx.list(option, fallback);

  if (values.length < minimum) {
    throw new TypeError(`${WHERE}.${option} must name at least one value`);
  }

  for (const value of values) {
    if (!NAME.test(value)) {
      throw new TypeError(
        `${WHERE}.${option}: "${value}" must be lowercase letters, digits, dots, dashes and underscores`,
      );
    }
  }

  if (new Set(values).size !== values.length) {
    throw new TypeError(`${WHERE}.${option} lists a value twice`);
  }

  return values;
}

/** The SQL pieces the care plans files share. */
export interface CarePlansSql {
  readonly ctx: BlockSqlContext;
  readonly fn: (name: string) => string;
  /** A column of the plans table. */
  readonly p: (column: string) => string;
  /** A column of the problems table. */
  readonly pr: (column: string) => string;
  /** A column of the goals table. */
  readonly g: (column: string) => string;
  /** A column of the actions table. */
  readonly a: (column: string) => string;
  /** A column of the evaluations table. */
  readonly e: (column: string) => string;
  readonly plans: string;
  readonly problems: string;
  readonly goals: string;
  readonly actions: string;
  readonly evaluations: string;
  readonly extras: readonly ExtraColumn[];
  /** The plans' subject type, after renames, as a SQL literal. */
  readonly subject: string;
  /** The actions' approval subject type, as a SQL literal. */
  readonly actionSubject: string;
  /** `options.codeSystems` as a SQL `text[]` literal. */
  readonly codeSystems: string;
  /** `options.measureKinds` as a SQL `text[]` literal, empty for any. */
  readonly measureKinds: string;
  readonly measureKindList: readonly string[];
  /** Whether a guest with a read grant on the client reads its plans. */
  readonly guestRead: boolean;
  readonly read: string;
  readonly write: string;
  readonly evaluate: string;
  readonly publish: string;
  readonly manage: string;
  /** Whether the caller holds `permission` in `tenant`, or is the service role. */
  readonly allowed: (tenant: string, permission: string) => string;
  /** Whether the caller can read client `type` `id` (text SQL expressions). */
  readonly canClient: (type: string, id: string) => string;
  /** Whether the caller can read the client of plans row `row`. */
  readonly clientReadable: (row: string) => string;
  /**
   * Whether the caller reads plans row `row`: read permission and the client,
   * or a guest's read grant on the client when `options.guestRead` is on.
   */
  readonly visible: (row: string) => string;
  readonly invalid: (message: string) => string;
  readonly forbidden: (message: string) => string;
  readonly missing: string;
  readonly notDraft: string;
  readonly archived: string;
  readonly goalMissing: string;
  readonly planJson: (row: string) => string;
  readonly problemJson: (row: string) => string;
  readonly goalJson: (row: string) => string;
  readonly actionJson: (row: string) => string;
  readonly evaluationJson: (row: string) => string;
  /**
   * Records a `care_plan.*` event of plans row `row` with `extra` keys added to
   * the payload; `summary` false leaves it out of the audit log.
   */
  readonly record: (
    type: string,
    row: string,
    summary: string | false,
    extra?: string,
  ) => string;
  /** Records an event of a goal, action or evaluation row on plan `plan`. */
  readonly recordChild: (
    type: string,
    plan: string,
    payload: string,
    summary: string,
  ) => string;
}

const textArray = (values: readonly string[]): string =>
  values.length === 0
    ? "'{}'::text[]"
    : `array[${values.map((value) => sqlString(value)).join(", ")}]::text[]`;

export function carePlansSql(ctx: BlockSqlContext): CarePlansSql {
  const p = (column: string): string => ctx.col("plans", column);
  const pr = (column: string): string => ctx.col("problems", column);
  const g = (column: string): string => ctx.col("goals", column);
  const a = (column: string): string => ctx.col("actions", column);
  const e = (column: string): string => ctx.col("evaluations", column);

  const extras = ctx.extraColumns("plans", PLAN_RESERVED);
  const measureKindList = namesOf(ctx, "measureKinds", [], 0);

  const planOf = (row: string, column: string): string =>
    ctx.has("plans", column) ? `${row}.${p(column)}` : "null";

  const subject = sqlString(ctx.naming.rename("care_plan"));
  const guestRead = ctx.flag("guestRead", false);

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or (${tenant} is not null and ${ctx.can("tenant", tenant, permission)}))`;

  const canClient = (type: string, id: string): string =>
    `(${SERVICE_CALLER} or coalesce(${ctx.of("subjects").fn("can_subject")}(${type}, ${id}, 'read'), false))`;

  const clientReadable = (row: string): string =>
    canClient(`${row}.${p("subjectType")}`, `${row}.${p("subjectId")}`);

  const read = ctx.permission("read", OPERATIONS["care-plans.read"]);

  const visible = (row: string): string => {
    const guest = ctx.scope.guest(
      `${row}.${p("tenant")}`,
      `${row}.${p("subjectType")}`,
      `${row}.${p("subjectId")}`,
      "read",
    );

    const member = `(${allowed(`${row}.${p("tenant")}`, read)} and ${clientReadable(row)})`;

    return guestRead && guest !== "false"
      ? `(${member} or (${row}.${p("status")} <> 'draft' and ${guest}))`
      : member;
  };

  return {
    ctx,
    fn: (name) => ctx.fn(name),
    p,
    pr,
    g,
    a,
    e,
    plans: ctx.table("plans"),
    problems: ctx.table("problems"),
    goals: ctx.table("goals"),
    actions: ctx.table("actions"),
    evaluations: ctx.table("evaluations"),
    extras,
    subject,
    actionSubject: sqlString(ctx.naming.rename("care_plan_action")),
    codeSystems: textArray(namesOf(ctx, "codeSystems", ["custom"], 1)),
    measureKinds: textArray(measureKindList),
    measureKindList,
    guestRead,
    read,
    write: ctx.permission("write", OPERATIONS["care-plans.write"]),
    evaluate: ctx.permission("evaluate", OPERATIONS["care-plans.evaluate"]),
    publish: ctx.permission("publish", OPERATIONS["care-plans.publish"]),
    manage: ctx.permission("manage", OPERATIONS["care-plans.manage"]),
    allowed,
    canClient,
    clientReadable,
    visible,
    invalid: (message) => fail("CARE_PLAN_INVALID", message, "22023"),
    forbidden: (message) => fail("CARE_PLAN_FORBIDDEN", message),
    missing: fail("CARE_PLAN_NOT_FOUND", "no such care plan", "P0002"),
    notDraft: fail(
      "CARE_PLAN_NOT_DRAFT",
      "only a draft care plan changes this way",
      "55000",
    ),
    archived: fail("CARE_PLAN_ARCHIVED", "the care plan is archived", "55000"),
    goalMissing: fail(
      "CARE_PLAN_GOAL_NOT_FOUND",
      "no such goal on a care plan",
      "P0002",
    ),
    planJson: (row) =>
      `jsonb_build_object('id', ${row}.${p("id")}, 'organizationId', ${row}.${p("tenant")}, 'subjectType', ${row}.${p("subjectType")}, 'subjectId', ${row}.${p("subjectId")}, 'title', ${row}.${p("title")}, 'status', ${row}.${p("status")}, 'version', ${row}.${p("version")}, 'startsOn', ${row}.${p("startsOn")}, 'reviewOn', ${row}.${p("reviewOn")}, 'ownerId', ${row}.${p("owner")}, 'signatureRequestId', ${row}.${p("signature")}, 'agreedAt', ${row}.${p("agreedAt")}, 'publishedVersionId', ${planOf(row, "publishedVersion")}, 'publishedAt', ${row}.${p("publishedAt")}, 'publishedBy', ${row}.${p("publishedBy")}, 'archivedAt', ${row}.${p("archivedAt")}, 'createdBy', ${planOf(row, "createdBy")}, 'createdAt', ${row}.${p("createdAt")}, 'updatedAt', ${row}.${p("updatedAt")}${extraFieldsJson(row, extras)})`,
    problemJson: (row) =>
      `jsonb_build_object('id', ${row}.${pr("id")}, 'planId', ${row}.${pr("plan")}, 'codeSystem', ${row}.${pr("codeSystem")}, 'code', ${row}.${pr("code")}, 'title', ${row}.${pr("title")}, 'description', ${row}.${pr("description")}, 'status', ${row}.${pr("status")}, 'rank', ${row}.${pr("rank")}, 'createdAt', ${row}.${pr("createdAt")}, 'updatedAt', ${row}.${pr("updatedAt")})`,
    goalJson: (row) =>
      `jsonb_build_object('id', ${row}.${g("id")}, 'planId', ${row}.${g("plan")}, 'problemId', ${row}.${g("problem")}, 'title', ${row}.${g("title")}, 'targetOn', ${row}.${g("targetOn")}, 'status', ${row}.${g("status")}, 'measure', ${row}.${g("measure")}, 'rank', ${row}.${g("rank")}, 'createdAt', ${row}.${g("createdAt")}, 'updatedAt', ${row}.${g("updatedAt")})`,
    actionJson: (row) =>
      `jsonb_build_object('id', ${row}.${a("id")}, 'planId', ${row}.${a("plan")}, 'goalId', ${row}.${a("goal")}, 'kind', ${row}.${a("kind")}, 'title', ${row}.${a("title")}, 'instructions', ${row}.${a("instructions")}, 'frequency', ${row}.${a("frequency")}, 'teamRole', ${row}.${a("teamRole")}, 'measureKind', ${row}.${a("measureKind")}, 'taskId', ${row}.${a("task")}, 'bookingSeriesId', ${row}.${a("bookingSeries")}, 'requiresApproval', ${row}.${a("requiresApproval")}, 'approvalId', ${row}.${a("approval")}, 'reviewEvery', ${isoInterval(`${row}.${a("reviewEvery")}`)}, 'reviewedAt', ${row}.${a("reviewedAt")}, 'startsOn', ${row}.${a("startsOn")}, 'endsOn', ${row}.${a("endsOn")}, 'status', ${row}.${a("status")}, 'startedAt', ${row}.${a("startedAt")}, 'endedAt', ${row}.${a("endedAt")}, 'endReason', ${row}.${a("endReason")}, 'rank', ${row}.${a("rank")}, 'createdAt', ${row}.${a("createdAt")}, 'updatedAt', ${row}.${a("updatedAt")})`,
    evaluationJson: (row) =>
      `jsonb_build_object('id', ${row}.${e("id")}, 'planId', ${row}.${e("plan")}, 'goalId', ${row}.${e("goal")}, 'evaluatedAt', ${row}.${e("evaluatedAt")}, 'status', ${row}.${e("status")}, 'outcome', ${row}.${e("outcome")}, 'submissionId', ${row}.${e("submission")}, 'authorId', ${row}.${e("author")})`,
    record: (type, row, summary, extra = "") =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${row}.${p("tenant")}, 'id', ${row}.${p("id")}, 'subjectType', ${row}.${p("subjectType")}, 'subjectId', ${row}.${p("subjectId")}, 'title', ${row}.${p("title")}, 'status', ${row}.${p("status")}, 'version', ${row}.${p("version")}${extra})`,
        subject: `'care-plans/' || ${row}.${p("id")}::text`,
        tenant: `${row}.${p("tenant")}`,
        audit:
          summary === false
            ? false
            : {
                category: "data",
                targetType: "care_plan",
                recordId: `${row}.${p("id")}::text`,
                targetLabel: `${row}.${p("title")}`,
                summary: sqlString(summary),
              },
      }),
    recordChild: (type, plan, payload, summary) =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${plan}.${p("tenant")}, 'planId', ${plan}.${p("id")}, 'subjectType', ${plan}.${p("subjectType")}, 'subjectId', ${plan}.${p("subjectId")}) || ${payload}`,
        subject: `'care-plans/' || ${plan}.${p("id")}::text`,
        tenant: `${plan}.${p("tenant")}`,
        audit: {
          category: "data",
          targetType: "care_plan",
          recordId: `${plan}.${p("id")}::text`,
          targetLabel: `${plan}.${p("title")}`,
          summary: sqlString(summary),
        },
      }),
  };
}
