import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { fail, SERVICE_CALLER } from "../shared.ts";
import { OPERATIONS } from "./permissions-model.ts";

/** The SQL pieces the appraisals files share. */
export interface AppraisalsSql {
  readonly fn: (name: string) => string;
  /** A column of the cycles table. */
  readonly y: (column: string) => string;
  /** A column of the appraisals table. */
  readonly a: (column: string) => string;
  /** A column of the reviews table. */
  readonly r: (column: string) => string;
  /** A column of the calibrations table. */
  readonly c: (column: string) => string;
  /** A column of the goal links table. */
  readonly g: (column: string) => string;
  /** A column of the competencies table. */
  readonly k: (column: string) => string;
  /** A column of the review ratings table. */
  readonly t: (column: string) => string;
  readonly cycles: string;
  readonly appraisals: string;
  readonly reviews: string;
  readonly calibrations: string;
  readonly goals: string;
  readonly competencies: string;
  readonly ratings: string;
  readonly subject: string;
  readonly read: string;
  readonly review: string;
  readonly manage: string;
  readonly allowed: (tenant: string, permission: string) => string;
  readonly invalid: (message: string) => string;
  readonly forbidden: (message: string) => string;
  readonly state: (message: string) => string;
  readonly cycleMissing: string;
  readonly appraisalMissing: string;
  readonly reviewMissing: string;
  readonly cycleJson: (row: string) => string;
  readonly recordCycle: (type: string, row: string, summary: string) => string;
  readonly recordAppraisal: (
    type: string,
    row: string,
    summary: string,
    extra?: string,
  ) => string;
  readonly recordReview: (type: string, row: string, summary: string) => string;
}

export function appraisalsSql(ctx: BlockSqlContext): AppraisalsSql {
  const y = (column: string): string => ctx.col("cycles", column);
  const a = (column: string): string => ctx.col("appraisals", column);
  const r = (column: string): string => ctx.col("reviews", column);
  const c = (column: string): string => ctx.col("calibrations", column);
  const g = (column: string): string => ctx.col("goals", column);
  const k = (column: string): string => ctx.col("competencies", column);
  const t = (column: string): string => ctx.col("ratings", column);

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or (${tenant} is not null and ${ctx.can("tenant", tenant, permission)}))`;

  const appraisalPayload = (row: string, extra: string): string =>
    `jsonb_build_object('organizationId', ${row}.${a("tenant")}, 'id', ${row}.${a("id")}, 'cycleId', ${row}.${a("cycle")}, 'subjectUserId', ${row}.${a("subjectUser")}, 'status', ${row}.${a("status")}${extra})`;

  return {
    fn: (name) => ctx.fn(name),
    y,
    a,
    r,
    c,
    g,
    k,
    t,
    competencies: ctx.table("competencies"),
    ratings: ctx.table("ratings"),
    cycles: ctx.table("cycles"),
    appraisals: ctx.table("appraisals"),
    reviews: ctx.table("reviews"),
    calibrations: ctx.table("calibrations"),
    goals: ctx.table("goals"),
    subject: sqlString(ctx.naming.rename("appraisal")),
    read: ctx.permission("read", OPERATIONS["appraisals.read"]),
    review: ctx.permission("review", OPERATIONS["appraisals.review"]),
    manage: ctx.permission("manage", OPERATIONS["appraisals.manage"]),
    allowed,
    invalid: (message) => fail("APPRAISALS_INVALID", message, "22023"),
    forbidden: (message) => fail("APPRAISALS_FORBIDDEN", message),
    state: (message) => fail("APPRAISALS_STATE", message, "55000"),
    cycleMissing: fail(
      "APPRAISALS_CYCLE_NOT_FOUND",
      "no such review cycle",
      "P0002",
    ),
    appraisalMissing: fail(
      "APPRAISALS_NOT_FOUND",
      "no such appraisal",
      "P0002",
    ),
    reviewMissing: fail(
      "APPRAISALS_REVIEW_NOT_FOUND",
      "no such review",
      "P0002",
    ),
    cycleJson: (row) =>
      `jsonb_build_object('id', ${row}.${y("id")}, 'organizationId', ${row}.${y("tenant")}, 'name', ${row}.${y("name")}, 'startsOn', ${row}.${y("startsOn")}, 'endsOn', ${row}.${y("endsOn")}, 'program', ${row}.${y("program")}, 'status', ${row}.${y("status")}, 'anonymity', ${row}.${y("anonymity")}, 'shareFeedback', ${row}.${y("shareFeedback")}, 'openedAt', ${row}.${y("openedAt")}, 'closedAt', ${row}.${y("closedAt")}, 'createdAt', ${row}.${y("createdAt")}, 'competencies', coalesce((select jsonb_agg(jsonb_build_object('key', w.${k("key")}, 'name', w.${k("name")}, 'weight', w.${k("weight")}) order by w.${k("position")}) from ${ctx.table("competencies")} w where w.${k("cycle")} = ${row}.${y("id")}), '[]'::jsonb))`,
    recordCycle: (type, row, summary) =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${row}.${y("tenant")}, 'id', ${row}.${y("id")}, 'name', ${row}.${y("name")}, 'status', ${row}.${y("status")})`,
        subject: `'appraisal-cycles/' || ${row}.${y("id")}::text`,
        tenant: `${row}.${y("tenant")}`,
        audit: {
          category: "data",
          targetType: "appraisal_cycle",
          recordId: `${row}.${y("id")}::text`,
          targetLabel: `${row}.${y("name")}`,
          summary: sqlString(summary),
        },
      }),
    recordAppraisal: (type, row, summary, extra = "") =>
      ctx.record({
        type,
        payload: appraisalPayload(row, extra),
        subject: `'appraisals/' || ${row}.${a("id")}::text`,
        tenant: `${row}.${a("tenant")}`,
        audit: {
          category: "data",
          targetType: "appraisal",
          recordId: `${row}.${a("id")}::text`,
          summary: sqlString(summary),
        },
      }),
    recordReview: (type, row, summary) =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${row}.${r("tenant")}, 'id', ${row}.${r("id")}, 'appraisalId', ${row}.${r("appraisal")}, 'reviewerId', case when ${row}.${r("kind")} = 'peer' and (select y.${y("anonymity")} from ${ctx.table("cycles")} y join ${ctx.table("appraisals")} p on p.${a("cycle")} = y.${y("id")} where p.${a("id")} = ${row}.${r("appraisal")}) <> 'none' then null else ${row}.${r("reviewer")} end, 'kind', ${row}.${r("kind")}, 'rating', ${row}.${r("rating")})`,
        subject: `'appraisals/' || ${row}.${r("appraisal")}::text`,
        tenant: `${row}.${r("tenant")}`,
        audit: {
          category: "data",
          targetType: "appraisal_review",
          recordId: `${row}.${r("id")}::text`,
          summary: sqlString(summary),
        },
      }),
  };
}
