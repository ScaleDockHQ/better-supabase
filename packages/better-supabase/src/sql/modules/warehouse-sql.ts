import type { BlockSqlContext } from "../context.ts";
import type { InventoryLocations } from "./inventory-stock.ts";

import { sqlString } from "../../core/template.ts";
import { entityType } from "../resolved-names.ts";
import { fail, SERVICE_CALLER } from "../shared.ts";
import { locationsOf } from "./inventory-stock.ts";
import { OPERATIONS } from "./permissions-model.ts";

/** The SQL pieces the warehouse files share. */
export interface WarehouseSql {
  readonly fn: (name: string) => string;
  /** A column of the waves table. */
  readonly w: (column: string) => string;
  /** A column of the pick lists table. */
  readonly p: (column: string) => string;
  /** A column of the pick lines table. */
  readonly l: (column: string) => string;
  /** A column of the count plans table. */
  readonly n: (column: string) => string;
  readonly waves: string;
  readonly lists: string;
  readonly lines: string;
  readonly plans: string;
  /** The inventory block's context. */
  readonly inventory: BlockSqlContext;
  /** The stock locations, the inventory block's or the assets block's. */
  readonly locations: InventoryLocations;
  /** The tasks block's context, when it is installed with its tables. */
  readonly tasks: BlockSqlContext | undefined;
  readonly taskType: string;
  readonly subject: string;
  readonly read: string;
  readonly pick: string;
  readonly manage: string;
  readonly allowed: (tenant: string, permission: string) => string;
  readonly invalid: (message: string) => string;
  readonly forbidden: (message: string) => string;
  readonly state: (message: string) => string;
  readonly waveMissing: string;
  readonly listMissing: string;
  readonly lineMissing: string;
  readonly planMissing: string;
  readonly waveJson: (row: string) => string;
  readonly planJson: (row: string) => string;
  readonly recordWave: (type: string, row: string, summary: string) => string;
  readonly recordList: (
    type: string,
    row: string,
    summary: string,
    extra?: string,
  ) => string;
  readonly recordPlan: (
    type: string,
    row: string,
    summary: string,
    extra?: string,
  ) => string;
}

export function warehouseSql(ctx: BlockSqlContext): WarehouseSql {
  const w = (column: string): string => ctx.col("waves", column);
  const p = (column: string): string => ctx.col("lists", column);
  const l = (column: string): string => ctx.col("lines", column);
  const n = (column: string): string => ctx.col("plans", column);
  const inventory = ctx.of("inventory");

  const tasks =
    ctx.installed("tasks") && ctx.of("tasks").mode !== "custom"
      ? ctx.of("tasks")
      : undefined;

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or (${tenant} is not null and ${ctx.can("tenant", tenant, permission)}))`;

  return {
    fn: (name) => ctx.fn(name),
    w,
    p,
    l,
    n,
    waves: ctx.table("waves"),
    lists: ctx.table("lists"),
    lines: ctx.table("lines"),
    plans: ctx.table("plans"),
    inventory,
    locations: locationsOf(inventory),
    tasks,
    taskType: tasks === undefined ? "task" : entityType(tasks.resolved, "task"),
    subject: sqlString(ctx.naming.rename("pick_list")),
    read: ctx.permission("read", OPERATIONS["warehouse.read"]),
    pick: ctx.permission("pick", OPERATIONS["warehouse.pick"]),
    manage: ctx.permission("manage", OPERATIONS["warehouse.manage"]),
    allowed,
    invalid: (message) => fail("WAREHOUSE_INVALID", message, "22023"),
    forbidden: (message) => fail("WAREHOUSE_FORBIDDEN", message),
    state: (message) => fail("WAREHOUSE_STATE", message, "55000"),
    waveMissing: fail("WAREHOUSE_WAVE_NOT_FOUND", "no such pick wave", "P0002"),
    listMissing: fail(
      "WAREHOUSE_PICK_LIST_NOT_FOUND",
      "no such pick list",
      "P0002",
    ),
    lineMissing: fail(
      "WAREHOUSE_PICK_LINE_NOT_FOUND",
      "no such pick line",
      "P0002",
    ),
    planMissing: fail(
      "WAREHOUSE_COUNT_PLAN_NOT_FOUND",
      "no such count plan",
      "P0002",
    ),
    waveJson: (row) =>
      `jsonb_build_object('id', ${row}.${w("id")}, 'organizationId', ${row}.${w("tenant")}, 'name', ${row}.${w("name")}, 'locationId', ${row}.${w("location")}, 'status', ${row}.${w("status")}, 'releasedAt', ${row}.${w("releasedAt")}, 'completedAt', ${row}.${w("completedAt")}, 'createdAt', ${row}.${w("createdAt")})`,
    planJson: (row) =>
      `jsonb_build_object('id', ${row}.${n("id")}, 'organizationId', ${row}.${n("tenant")}, 'name', ${row}.${n("name")}, 'locationId', ${row}.${n("location")}, 'everyDays', ${row}.${n("everyDays")}, 'variantIds', to_jsonb(coalesce(${row}.${n("variants")}, '{}'::uuid[])), 'varianceLimitPct', ${row}.${n("varianceLimit")}::text, 'nextRunOn', ${row}.${n("nextRunOn")}, 'lastRunAt', ${row}.${n("lastRunAt")}, 'lastCountId', ${row}.${n("lastCount")}, 'active', ${row}.${n("active")}, 'createdAt', ${row}.${n("createdAt")})`,
    recordWave: (type, row, summary) =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${row}.${w("tenant")}, 'id', ${row}.${w("id")}, 'name', ${row}.${w("name")}, 'locationId', ${row}.${w("location")}, 'status', ${row}.${w("status")})`,
        subject: `'pick-waves/' || ${row}.${w("id")}::text`,
        tenant: `${row}.${w("tenant")}`,
        audit: {
          category: "data",
          targetType: "pick_wave",
          recordId: `${row}.${w("id")}::text`,
          targetLabel: `${row}.${w("name")}`,
          summary: sqlString(summary),
        },
      }),
    recordList: (type, row, summary, extra = "") =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${row}.${p("tenant")}, 'id', ${row}.${p("id")}, 'waveId', ${row}.${p("wave")}, 'locationId', ${row}.${p("location")}, 'documentType', ${row}.${p("documentType")}, 'documentId', ${row}.${p("documentId")}, 'status', ${row}.${p("status")}${extra})`,
        subject: `'pick-lists/' || ${row}.${p("id")}::text`,
        tenant: `${row}.${p("tenant")}`,
        audit: {
          category: "data",
          targetType: "pick_list",
          recordId: `${row}.${p("id")}::text`,
          summary: sqlString(summary),
        },
      }),
    recordPlan: (type, row, summary, extra = "") =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${row}.${n("tenant")}, 'id', ${row}.${n("id")}, 'name', ${row}.${n("name")}, 'locationId', ${row}.${n("location")}${extra})`,
        subject: `'count-plans/' || ${row}.${n("id")}::text`,
        tenant: `${row}.${n("tenant")}`,
        audit: {
          category: "data",
          targetType: "count_plan",
          recordId: `${row}.${n("id")}::text`,
          targetLabel: `${row}.${n("name")}`,
          summary: sqlString(summary),
        },
      }),
  };
}
