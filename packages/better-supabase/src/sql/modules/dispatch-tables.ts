import type { ExtraColumn, BlockSqlContext } from "../context.ts";

import {
  WORK_ORDER_PRIORITIES,
  WORK_ORDER_STATUSES,
} from "../../blocks/dispatch/statuses.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";
import { addExtraColumns, addForeignKey } from "../shared.ts";
import { locationsOf } from "./inventory-stock.ts";
import { appUniqueIndex, lockModuleTable } from "./over-app.ts";
import { moduleOperations } from "./permissions-model.ts";

/** The statuses that hold a technician's slot. */
export const BUSY = ["scheduled", "en_route", "on_site"] as const;

export const list = (values: readonly string[]): string =>
  values.map((value) => sqlString(value)).join(", ");

interface Linked {
  readonly assets: BlockSqlContext | undefined;
  readonly bookings: BlockSqlContext | undefined;
  readonly catalog: BlockSqlContext | undefined;
  readonly inventory: BlockSqlContext | undefined;
}

export const linked = (ctx: BlockSqlContext): Linked => ({
  assets: ctx.installed("assets") ? ctx.of("assets") : undefined,
  bookings: ctx.installed("bookings") ? ctx.of("bookings") : undefined,
  catalog: ctx.installed("catalog") ? ctx.of("catalog") : undefined,
  inventory: ctx.installed("inventory") ? ctx.of("inventory") : undefined,
});

/** The dispatch tables, their indexes, policies and links to other blocks. */
export function dispatchTables(
  ctx: BlockSqlContext,
  extras: readonly ExtraColumn[],
): string {
  if (!ctx.manages) {
    return "";
  }

  const orders = ctx.table("workOrders");
  const routes = ctx.table("routes");
  const stops = ctx.table("stops");
  const parts = ctx.table("parts");
  const w = (column: string): string => ctx.col("workOrders", column);
  const r = (column: string): string => ctx.col("routes", column);
  const s = (column: string): string => ctx.col("stops", column);
  const q = (column: string): string => ctx.col("parts", column);
  const { assets, bookings, catalog, inventory } = linked(ctx);
  const read = ctx.permission("read", moduleOperations("dispatch").read);
  const readable = (tenant: string): string => ctx.scope.check(tenant, read);

  const index = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  // A column definition, left out when the app maps the column to null.
  const column = (
    table: string,
    logical: string,
    definition: (name: string) => string,
  ): string =>
    ctx.has(table, logical)
      ? `\n  ${definition(ctx.col(table, logical))},`
      : "";

  const owns = { orders: ctx.owns("workOrders"), parts: ctx.owns("parts") };

  const key = (
    table: string,
    logical: string,
    column: string,
    suffix: string,
    references: string,
  ): string =>
    addForeignKey({
      table,
      name: `${ctx.tableName(logical).name}_${suffix}_fkey`,
      column,
      references,
      onDelete: "set null",
    });

  const keys = [
    owns.orders &&
      assets &&
      key(
        orders,
        "workOrders",
        w("location"),
        "location",
        `${assets.table("locations")} (${assets.col("locations", "id")})`,
      ),
    owns.orders &&
      assets &&
      key(
        orders,
        "workOrders",
        w("asset"),
        "asset",
        `${assets.table("assets")} (${assets.col("assets", "id")})`,
      ),
    owns.orders &&
      bookings &&
      key(
        orders,
        "workOrders",
        w("booking"),
        "booking",
        `${bookings.table("bookings")} (${bookings.col("bookings", "id")})`,
      ),
    owns.parts &&
      assets &&
      key(
        parts,
        "parts",
        q("asset"),
        "asset",
        `${assets.table("assets")} (${assets.col("assets", "id")})`,
      ),
    owns.parts &&
      catalog &&
      key(
        parts,
        "parts",
        q("variant"),
        "variant",
        `${catalog.table("variants")} (${catalog.col("variants", "id")})`,
      ),
    owns.parts &&
      inventory &&
      key(
        parts,
        "parts",
        q("location"),
        "location",
        `${locationsOf(inventory).table} (${locationsOf(inventory).col("id")})`,
      ),
  ]
    .filter((sql): sql is string => typeof sql === "string")
    .join("\n");

  return `
-- Work orders: a job at a place (an asset location or an address), for an
-- asset or a record, scheduled into a technician's slot and worked through
-- en route, on site and done.
create table if not exists ${orders} (
  ${w("id")} uuid primary key default gen_random_uuid(),
  ${w("tenant")} ${ctx.idType} not null,
  ${w("title")} text not null check (length(${w("title")}) >= 1 and length(${w("title")}) <= 200),${column("workOrders", "description", (name) => `${name} text check (${name} is null or length(${name}) <= 10000)`)}
  ${w("priority")} text not null default 'normal' check (${w("priority")} in (${list(WORK_ORDER_PRIORITIES)})),
  ${w("status")} text not null default 'unscheduled' check (${w("status")} in (${list(WORK_ORDER_STATUSES)})),
  ${w("technician")} uuid references auth.users (id) on delete set null,
  ${w("startsAt")} timestamptz,
  ${w("endsAt")} timestamptz,
  ${w("location")} uuid,
  ${w("asset")} uuid,${column("workOrders", "booking", (name) => `${name} uuid`)}
  ${w("subjectType")} text check (${w("subjectType")} is null or ${w("subjectType")} ~ '^[a-z][a-z0-9_-]{0,62}$'),
  ${w("subjectId")} text check (${w("subjectId")} is null or length(${w("subjectId")}) >= 1 and length(${w("subjectId")}) <= 200),${column("workOrders", "address", (name) => `${name} text check (${name} is null or length(${name}) >= 1 and length(${name}) <= 500)`)}${column("workOrders", "enRouteAt", (name) => `${name} timestamptz`)}${column("workOrders", "arrivedAt", (name) => `${name} timestamptz`)}
  ${w("completedAt")} timestamptz,
  ${w("cancelledAt")} timestamptz,${column("workOrders", "cancelReason", (name) => `${name} text check (${name} is null or length(${name}) <= 1000)`)}${column("workOrders", "completionNote", (name) => `${name} text check (${name} is null or length(${name}) <= 10000)`)}
  ${w("createdBy")} uuid,
  ${w("createdAt")} timestamptz not null default now(),
  ${w("updatedAt")} timestamptz not null default now(),
  check ((${w("subjectType")} is null) = (${w("subjectId")} is null)),
  check ((${w("startsAt")} is null) = (${w("endsAt")} is null)),
  check (${w("endsAt")} is null or ${w("endsAt")} > ${w("startsAt")}),
  check (${w("status")} not in (${list(BUSY)}) or (${w("technician")} is not null and ${w("startsAt")} is not null))
);${addExtraColumns(orders, extras)}
create index if not exists ${index("workOrders", "tenant_idx")} on ${orders} (${w("tenant")}, ${w("createdAt")} desc);
create index if not exists ${index("workOrders", "slot_idx")} on ${orders} (${w("technician")}, ${w("startsAt")}) where ${w("startsAt")} is not null;
create index if not exists ${index("workOrders", "board_idx")} on ${orders} (${w("tenant")}, ${w("startsAt")}) where ${w("startsAt")} is not null;
create index if not exists ${index("workOrders", "backlog_idx")} on ${orders} (${w("tenant")}, ${w("createdAt")}) where ${w("status")} = 'unscheduled';
create index if not exists ${index("workOrders", "location_idx")} on ${orders} (${w("location")});
create index if not exists ${index("workOrders", "asset_idx")} on ${orders} (${w("asset")});
${ctx.has("workOrders", "booking") ? `create index if not exists ${index("workOrders", "booking_idx")} on ${orders} (${w("booking")});\n` : ""}create index if not exists ${index("workOrders", "subject_idx")} on ${orders} (${w("tenant")}, ${w("subjectType")}, ${w("subjectId")});
${lockModuleTable(ctx, "workOrders", { read: true })}
drop policy if exists ${index("workOrders", "read")} on ${orders};
create policy ${index("workOrders", "read")} on ${orders} for select to authenticated
  using (${w("technician")} = (select auth.uid()) or ${readable(w("tenant"))});
-- A technician's plan for one day: the work orders in the order they drive to
-- them.
create table if not exists ${routes} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("tenant")} ${ctx.idType} not null,
  ${r("technician")} uuid not null references auth.users (id) on delete cascade,
  ${r("routeDate")} date not null,${column("routes", "plannedBy", (name) => `${name} uuid`)}${column("routes", "createdAt", (name) => `${name} timestamptz not null default now()`)}
  ${r("updatedAt")} timestamptz not null default now(),
  unique (${r("tenant")}, ${r("technician")}, ${r("routeDate")})
);${appUniqueIndex(ctx, "routes", ["tenant", "technician", "routeDate"])}
create index if not exists ${index("routes", "technician_idx")} on ${routes} (${r("technician")}, ${r("routeDate")});
${lockModuleTable(ctx, "routes", { read: true })}
drop policy if exists ${index("routes", "read")} on ${routes};
create policy ${index("routes", "read")} on ${routes} for select to authenticated
  using (${r("technician")} = (select auth.uid()) or ${readable(r("tenant"))});
create table if not exists ${stops} (
  ${s("id")} uuid primary key default gen_random_uuid(),
  ${s("tenant")} ${ctx.idType} not null,
  ${s("route")} uuid not null references ${routes} (${r("id")}) on delete cascade,
  ${s("workOrder")} uuid not null references ${orders} (${w("id")}) on delete cascade,
  ${s("position")} integer not null check (${s("position")} >= 1),
  unique (${s("route")}, ${s("position")}),
  unique (${s("route")}, ${s("workOrder")})
);
create index if not exists ${index("stops", "job_idx")} on ${stops} (${s("workOrder")});
${lockModuleTable(ctx, "stops", { read: true })}
drop policy if exists ${index("stops", "read")} on ${stops};
create policy ${index("stops", "read")} on ${stops} for select to authenticated
  using (${readable(s("tenant"))});
-- The parts a job used: free text, or an asset, or a catalog variant taken
-- from an inventory location.
create table if not exists ${parts} (
  ${q("id")} uuid primary key default gen_random_uuid(),
  ${q("tenant")} ${ctx.idType} not null,
  ${q("workOrder")} uuid not null references ${orders} (${w("id")}) on delete cascade,
  ${q("name")} text not null check (length(${q("name")}) >= 1 and length(${q("name")}) <= 200),
  ${q("quantity")} numeric(14, 3) not null check (${q("quantity")} > 0),${column("parts", "unit", (name) => `${name} text check (${name} is null or length(${name}) >= 1 and length(${name}) <= 20)`)}
  ${q("asset")} uuid,
  ${q("variant")} uuid,
  ${q("location")} uuid,
  ${q("recordedBy")} uuid,
  ${q("createdAt")} timestamptz not null default now()
);
create index if not exists ${index("parts", "job_idx")} on ${parts} (${q("workOrder")}, ${q("createdAt")});
create index if not exists ${index("parts", "asset_idx")} on ${parts} (${q("asset")});
create index if not exists ${index("parts", "variant_idx")} on ${parts} (${q("variant")});
create index if not exists ${index("parts", "location_idx")} on ${parts} (${q("location")});
${lockModuleTable(ctx, "parts", { read: true })}
drop policy if exists ${index("parts", "read")} on ${parts};
create policy ${index("parts", "read")} on ${parts} for select to authenticated
  using (${readable(q("tenant"))});
${keys}
`;
}
