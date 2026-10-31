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
    planJson: (row) =>
      `jsonb_build_object('id', ${row}.${p("id")}, 'organizationId', ${row}.${p("tenant")}, 'title', ${row}.${p("title")}, 'kind', ${row}.${p("kind")}, 'assetId', ${row}.${p("asset")}, 'everyDays', ${row}.${p("everyDays")}, 'meterId', ${row}.${p("meter")}, 'everyValue', ${row}.${p("everyValue")}::text, 'priority', ${row}.${p("priority")}, 'status', ${row}.${p("status")}, 'lastDoneAt', ${row}.${p("lastDoneAt")}, 'lastDoneValue', ${row}.${p("lastDoneValue")}::text, 'nextDueAt', ${row}.${p("nextDueAt")}, 'workOrderId', ${row}.${p("workOrder")}, 'createdAt', ${row}.${p("createdAt")}, 'updatedAt', ${row}.${p("updatedAt")})`,
    meterJson: (row) =>
      `jsonb_build_object('id', ${row}.${m("id")}, 'organizationId', ${row}.${m("tenant")}, 'name', ${row}.${m("name")}, 'unit', ${row}.${m("unit")}, 'assetId', ${row}.${m("asset")}, 'reading', ${row}.${m("reading")}::text, 'readAt', ${row}.${m("readAt")}, 'createdAt', ${row}.${m("createdAt")})`,
    calibrationJson: (row) =>
      `jsonb_build_object('id', ${row}.${c("id")}, 'organizationId', ${row}.${c("tenant")}, 'assetId', ${row}.${c("asset")}, 'instrument', ${row}.${c("instrument")}, 'performedAt', ${row}.${c("performedAt")}, 'dueAt', ${row}.${c("dueAt")}, 'result', ${row}.${c("result")}, 'reference', ${row}.${c("reference")}, 'performedBy', ${row}.${c("performedBy")})`,
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
