import type { BlockSqlContext, ExtraColumn } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { extraFieldsJson, fail, SERVICE_CALLER } from "../shared.ts";
import { OPERATIONS } from "./permissions-model.ts";

/** A block the manufacturing functions read, when it's there and managed. */
export function linked(
  ctx: BlockSqlContext,
  module: string,
): BlockSqlContext | undefined {
  return ctx.installed(module) && ctx.of(module).mode !== "custom"
    ? ctx.of(module)
    : undefined;
}

/** The keys the production order reads return next to the extra columns. */
const ORDER_RESERVED = [
  "fields",
  "operations",
  "components",
  "consumptions",
] as const;

/** The SQL pieces the manufacturing files share. */
export interface ManufacturingSql {
  readonly fn: (name: string) => string;
  /** Columns of boms, bom_components, work_centers and bom_operations. */
  readonly b: (column: string) => string;
  readonly c: (column: string) => string;
  readonly w: (column: string) => string;
  readonly o: (column: string) => string;
  /** Columns of production_orders and production_order_operations. */
  readonly po: (column: string) => string;
  readonly op: (column: string) => string;
  /** Columns of production_consumptions and stock_lot_links. */
  readonly pc: (column: string) => string;
  readonly ll: (column: string) => string;
  readonly boms: string;
  readonly components: string;
  readonly workCenters: string;
  readonly operations: string;
  readonly orders: string;
  readonly orderOperations: string;
  readonly consumptions: string;
  readonly lotLinks: string;
  /** `options.extraColumns` on the production orders table. */
  readonly extras: readonly ExtraColumn[];
  readonly inventory: BlockSqlContext;
  readonly catalog: BlockSqlContext;
  readonly read: string;
  readonly write: string;
  readonly produce: string;
  readonly manage: string;
  /** The service role, or a member of `tenant` with `permission`. */
  readonly allowed: (tenant: string, permission: string) => string;
  readonly forbidden: (message: string) => string;
  readonly bomInvalid: (message: string) => string;
  readonly orderInvalid: (message: string) => string;
  readonly bomMissing: string;
  readonly orderMissing: string;
  readonly operationMissing: string;
  readonly workCenterMissing: string;
  /** Refuses moving the order `row` from its status to `to`. */
  readonly statusInvalid: (row: string, to: string) => string;
  /** The production order's subject type, as a SQL literal. */
  readonly orderSubject: string;
  readonly bomJson: (row: string) => string;
  readonly workCenterJson: (row: string) => string;
  readonly orderJson: (row: string) => string;
  readonly orderOperationJson: (row: string) => string;
  /** Records a `bom.*` event of a boms row. */
  readonly recordBom: (type: string, row: string, summary: string) => string;
  /** Records a `production_order.*` event of a production_orders row. */
  readonly recordOrder: (
    type: string,
    row: string,
    summary: string,
    extra?: string,
  ) => string;
}

export function manufacturingSql(ctx: BlockSqlContext): ManufacturingSql {
  const col =
    (table: string) =>
    (column: string): string =>
      ctx.col(table, column);

  const b = col("boms");
  const w = col("workCenters");
  const po = col("orders");
  const op = col("orderOperations");
  const read = ctx.permission("read", OPERATIONS["manufacturing.read"]);
  const write = ctx.permission("write", OPERATIONS["manufacturing.write"]);

  const produce = ctx.permission(
    "produce",
    OPERATIONS["manufacturing.produce"],
  );

  const manage = ctx.permission("manage", OPERATIONS["manufacturing.manage"]);
  const extras = ctx.extraColumns("orders", ORDER_RESERVED);

  return {
    fn: (name) => ctx.fn(name),
    b,
    c: col("components"),
    w,
    o: col("operations"),
    po,
    op,
    pc: col("consumptions"),
    ll: col("lotLinks"),
    boms: ctx.table("boms"),
    components: ctx.table("components"),
    workCenters: ctx.table("workCenters"),
    operations: ctx.table("operations"),
    orders: ctx.table("orders"),
    orderOperations: ctx.table("orderOperations"),
    consumptions: ctx.table("consumptions"),
    lotLinks: ctx.table("lotLinks"),
    extras,
    inventory: ctx.of("inventory"),
    catalog: ctx.of("catalog"),
    read,
    write,
    produce,
    manage,
    allowed: (tenant, permission) =>
      `(${SERVICE_CALLER} or (${tenant} is not null and ${ctx.can("tenant", tenant, permission)}))`,
    forbidden: (message) => fail("MANUFACTURING_FORBIDDEN", message),
    bomInvalid: (message) => fail("BOM_INVALID", message, "22023"),
    orderInvalid: (message) =>
      fail("PRODUCTION_ORDER_INVALID", message, "22023"),
    bomMissing: fail("BOM_NOT_FOUND", "no such bill of materials", "P0002"),
    orderMissing: fail(
      "PRODUCTION_ORDER_NOT_FOUND",
      "no such production order",
      "P0002",
    ),
    operationMissing: fail(
      "PRODUCTION_OPERATION_NOT_FOUND",
      "no such production order operation",
      "P0002",
    ),
    workCenterMissing: fail(
      "WORK_CENTER_NOT_FOUND",
      "no such work center in this organization",
      "P0002",
    ),
    statusInvalid: (row, to) =>
      `raise exception 'the production order can''t move from % to %', ${row}.${po("status")}, ${sqlString(to)} using errcode = '55000', hint = 'PRODUCTION_ORDER_STATUS_INVALID', detail = jsonb_build_object('from', ${row}.${po("status")}, 'to', ${sqlString(to)})::text;`,
    orderSubject: sqlString(ctx.naming.rename("production_order")),
    bomJson: (row) =>
      `jsonb_build_object('id', ${row}.${b("id")}, 'organizationId', ${row}.${b("tenant")}, 'variantId', ${row}.${b("variant")}, 'version', ${row}.${b("version")}, 'status', ${row}.${b("status")}, 'quantity', ${row}.${b("quantity")}::text, 'note', ${row}.${b("note")}, 'activatedAt', ${row}.${b("activatedAt")}, 'createdAt', ${row}.${b("createdAt")}, 'updatedAt', ${row}.${b("updatedAt")})`,
    workCenterJson: (row) =>
      `jsonb_build_object('id', ${row}.${w("id")}, 'organizationId', ${row}.${w("tenant")}, 'name', ${row}.${w("name")}, 'assetId', ${row}.${w("asset")}, 'hoursPerDay', ${row}.${w("hoursPerDay")}::text, 'costRate', ${row}.${w("costRate")}::text, 'currency', ${row}.${w("currency")}, 'archivedAt', ${row}.${w("archivedAt")}, 'createdAt', ${row}.${w("createdAt")}, 'updatedAt', ${row}.${w("updatedAt")})`,
    orderJson: (row) =>
      `jsonb_build_object('id', ${row}.${po("id")}, 'organizationId', ${row}.${po("tenant")}, 'number', ${row}.${po("number")}, 'variantId', ${row}.${po("variant")}, 'bomId', ${row}.${po("bom")}, 'quantity', ${row}.${po("quantity")}::text, 'locationId', ${row}.${po("location")}, 'dueOn', ${row}.${po("dueOn")}, 'status', ${row}.${po("status")}, 'producedQuantity', ${row}.${po("produced")}::text, 'scrapQuantity', ${row}.${po("scrap")}::text, 'outputLotId', ${row}.${po("outputLot")}, 'materialCost', ${row}.${po("materialCost")}::text, 'laborCost', ${row}.${po("laborCost")}::text, 'currency', ${row}.${po("currency")}, 'note', ${row}.${po("note")}, 'releasedAt', ${row}.${po("releasedAt")}, 'startedAt', ${row}.${po("startedAt")}, 'completedAt', ${row}.${po("completedAt")}, 'canceledAt', ${row}.${po("canceledAt")}, 'createdBy', ${row}.${po("createdBy")}, 'createdAt', ${row}.${po("createdAt")}, 'updatedAt', ${row}.${po("updatedAt")}${extraFieldsJson(row, extras)})`,
    orderOperationJson: (row) =>
      `jsonb_build_object('id', ${row}.${op("id")}, 'orderId', ${row}.${op("order")}, 'operationId', ${row}.${op("operation")}, 'sequence', ${row}.${op("sequence")}, 'workCenterId', ${row}.${op("workCenter")}, 'title', ${row}.${op("title")}, 'plannedMinutes', ${row}.${op("plannedMinutes")}::text, 'status', ${row}.${op("status")}, 'startedAt', ${row}.${op("startedAt")}, 'finishedAt', ${row}.${op("finishedAt")}, 'operatorId', ${row}.${op("operator")}, 'minutes', ${row}.${op("minutes")}::text, 'inspectionId', ${row}.${op("inspection")})`,
    recordBom: (type, row, summary) =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${row}.${b("tenant")}, 'id', ${row}.${b("id")}, 'variantId', ${row}.${b("variant")}, 'version', ${row}.${b("version")}, 'status', ${row}.${b("status")})`,
        subject: `'boms/' || ${row}.${b("id")}::text`,
        tenant: `${row}.${b("tenant")}`,
        audit: {
          category: "data",
          targetType: "bom",
          recordId: `${row}.${b("id")}::text`,
          targetLabel: `'v' || ${row}.${b("version")}::text`,
          summary: sqlString(summary),
        },
      }),
    recordOrder: (type, row, summary, extra = "") =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${row}.${po("tenant")}, 'id', ${row}.${po("id")}, 'number', ${row}.${po("number")}, 'variantId', ${row}.${po("variant")}, 'quantity', ${row}.${po("quantity")}::text, 'status', ${row}.${po("status")}${extra})`,
        subject: `'production-orders/' || ${row}.${po("id")}::text`,
        tenant: `${row}.${po("tenant")}`,
        audit: {
          category: "data",
          targetType: "production_order",
          recordId: `${row}.${po("id")}::text`,
          targetLabel: `${row}.${po("number")}`,
          summary: sqlString(summary),
        },
      }),
  };
}
