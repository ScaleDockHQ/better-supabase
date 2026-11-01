import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { fail, SERVICE_CALLER } from "../shared.ts";
import { OPERATIONS } from "./permissions-model.ts";

/** The SQL pieces the maintenance files share. */
export interface MaintenanceSql {
  readonly fn: (name: string) => string;
  /** A column of the plans table. */
  readonly p: (column: string) => string;
  /** A column of the plan parts table. */
  readonly s: (column: string) => string;
  /** A column of the meters table. */
  readonly m: (column: string) => string;
  /** A column of the meter readings table. */
  readonly r: (column: string) => string;
  /** A column of the calibrations table. */
  readonly c: (column: string) => string;
  readonly plans: string;
  readonly parts: string;
  readonly meters: string;
  readonly readings: string;
  readonly calibrations: string;
  readonly subject: string;
  readonly read: string;
  readonly record: string;
  readonly manage: string;
  readonly allowed: (tenant: string, permission: string) => string;
  readonly invalid: (message: string) => string;
  readonly forbidden: (message: string) => string;
  readonly planMissing: string;
  readonly meterMissing: string;
  readonly planJson: (row: string) => string;
  readonly meterJson: (row: string) => string;
  readonly calibrationJson: (row: string) => string;
  /** The statement that raises when a technician lacks a qualification. */
  readonly unqualified: string;
  /**
   * A plpgsql block that raises unless every key in `keys` (a text[]
   * expression) is a qualification type of `tenant`.
   */
  readonly knownQualifications: (tenant: string, keys: string) => string;
  /**
   * A plpgsql block that raises unless the member `holder` (a uuid expression)
   * holds every key in `keys` on the date `onDate`.
   */
  readonly holdsQualifications: (
    tenant: string,
    keys: string,
    holder: string,
    onDate: string,
  ) => string;
  /** The first occurrence of an rrule plan after an instant, or null. */
  readonly nextOccurrence: (
    dtstart: string,
    tz: string,
    rrule: string,
    after: string,
  ) => string;
  /** Records a `maintenance_plan.*` event of a plans row. */
  readonly recordPlan: (
    type: string,
    row: string,
    summary: string,
    extra?: string,
  ) => string;
}

export function maintenanceSql(ctx: BlockSqlContext): MaintenanceSql {
  const p = (column: string): string => ctx.col("plans", column);
  const s = (column: string): string => ctx.col("parts", column);
  const m = (column: string): string => ctx.col("meters", column);
  const r = (column: string): string => ctx.col("readings", column);
  const c = (column: string): string => ctx.col("calibrations", column);

  const needsBlock = fail(
    "MAINTENANCE_INVALID",
    "required qualifications need the qualifications block",
    "22023",
  );

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or (${tenant} is not null and ${ctx.can("tenant", tenant, permission)}))`;

  return {
    fn: (name) => ctx.fn(name),
    p,
    s,
    m,
    r,
    c,
    plans: ctx.table("plans"),
    parts: ctx.table("parts"),
    meters: ctx.table("meters"),
    readings: ctx.table("readings"),
    calibrations: ctx.table("calibrations"),
    subject: sqlString(ctx.naming.rename("maintenance_plan")),
    read: ctx.permission("read", OPERATIONS["maintenance.read"]),
    record: ctx.permission("record", OPERATIONS["maintenance.record"]),
    manage: ctx.permission("manage", OPERATIONS["maintenance.manage"]),
    allowed,
    invalid: (message) => fail("MAINTENANCE_INVALID", message, "22023"),
    forbidden: (message) => fail("MAINTENANCE_FORBIDDEN", message),
    planMissing: fail(
      "MAINTENANCE_PLAN_NOT_FOUND",
      "no such maintenance plan",
      "P0002",
    ),
    meterMissing: fail("MAINTENANCE_METER_NOT_FOUND", "no such meter", "P0002"),
    unqualified: fail(
      "MAINTENANCE_UNQUALIFIED",
      "the person doesn't hold a qualification the work requires",
    ),
    knownQualifications: (tenant, keys) => {
      if (!ctx.installed("qualifications")) {
        return `if cardinality(${keys}) > 0 then
    ${needsBlock}
  end if;`;
      }

      const qualifications = ctx.of("qualifications");

      return `if exists (
    select 1 from unnest(${keys}) k
    where not exists (
      select 1 from ${qualifications.table("types")} o
      where o.${qualifications.col("types", "tenant")} = ${tenant} and o.${qualifications.col("types", "key")} = k and o.${qualifications.col("types", "archivedAt")} is null
    )
  ) then
    ${fail("MAINTENANCE_INVALID", "every required qualification is a qualification type key of this organization", "22023")}
  end if;`;
    },
    holdsQualifications: (tenant, keys, holder, onDate) => {
      if (!ctx.installed("qualifications")) {
        return `if cardinality(${keys}) > 0 then
    ${needsBlock}
  end if;`;
      }

      const qualifications = ctx.of("qualifications");

      return `foreach v_key in array ${keys} loop
    if not coalesce(${qualifications.fn("qualified_holders")}(${tenant}, v_key, 'member', ${onDate}) ? (${holder})::text, false) then
      ${fail("MAINTENANCE_UNQUALIFIED", "the person doesn't hold a qualification the work requires")}
    end if;
  end loop;`;
    },
    nextOccurrence: (dtstart, tz, rrule, after) =>
      `${ctx.fn("maintenance_next_occurrence")}(${dtstart}, ${tz}, ${rrule}, ${after})`,
    planJson: (row) =>
      `jsonb_build_object('id', ${row}.${p("id")}, 'organizationId', ${row}.${p("tenant")}, 'title', ${row}.${p("title")}, 'kind', ${row}.${p("kind")}, 'assetId', ${row}.${p("asset")}, 'everyDays', ${row}.${p("everyDays")}, 'meterId', ${row}.${p("meter")}, 'everyValue', ${row}.${p("everyValue")}::text, 'priority', ${row}.${p("priority")}, 'status', ${row}.${p("status")}, 'lastDoneAt', ${row}.${p("lastDoneAt")}, 'lastDoneValue', ${row}.${p("lastDoneValue")}::text, 'nextDueAt', ${row}.${p("nextDueAt")}, 'workOrderId', ${row}.${p("workOrder")}, 'rrule', ${row}.${p("rrule")}, 'dtstart', ${row}.${p("dtstart")}, 'tz', ${row}.${p("tz")}, 'requiredQualifications', to_jsonb(${row}.${p("requiredQualifications")}), 'createdAt', ${row}.${p("createdAt")}, 'updatedAt', ${row}.${p("updatedAt")})`,
    meterJson: (row) =>
      `jsonb_build_object('id', ${row}.${m("id")}, 'organizationId', ${row}.${m("tenant")}, 'name', ${row}.${m("name")}, 'unit', ${row}.${m("unit")}, 'assetId', ${row}.${m("asset")}, 'reading', ${row}.${m("reading")}::text, 'readAt', ${row}.${m("readAt")}, 'createdAt', ${row}.${m("createdAt")})`,
    calibrationJson: (row) =>
      `jsonb_build_object('id', ${row}.${c("id")}, 'organizationId', ${row}.${c("tenant")}, 'assetId', ${row}.${c("asset")}, 'instrument', ${row}.${c("instrument")}, 'performedAt', ${row}.${c("performedAt")}, 'dueAt', ${row}.${c("dueAt")}, 'result', ${row}.${c("result")}, 'reference', ${row}.${c("reference")}, 'performedBy', ${row}.${c("performedBy")}, 'qualifications', to_jsonb(${row}.${c("qualifications")}))`,
    recordPlan: (type, row, summary, extra = "") =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${row}.${p("tenant")}, 'id', ${row}.${p("id")}, 'title', ${row}.${p("title")}, 'kind', ${row}.${p("kind")}, 'status', ${row}.${p("status")}${extra})`,
        subject: `'maintenance-plans/' || ${row}.${p("id")}::text`,
        tenant: `${row}.${p("tenant")}`,
        audit: {
          category: "data",
          targetType: "maintenance_plan",
          recordId: `${row}.${p("id")}::text`,
          targetLabel: `${row}.${p("title")}`,
          summary: sqlString(summary),
        },
      }),
  };
}
