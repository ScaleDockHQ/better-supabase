import type { ExtraColumn, BlockSqlContext } from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import {
  WORK_ORDER_PRIORITIES,
  WORK_ORDER_STATUSES,
} from "../../blocks/dispatch/statuses.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  addExtraColumns,
  addForeignKey,
  extraFieldsArg,
  fail,
  lockTable,
  pageSize,
  schemaPreamble,
  SERVICE_CALLER,
  userGrant,
  withExtraFields,
  writeExtraColumns,
} from "../shared.ts";
import { subjectTenant } from "../subject-check-sql.ts";
import { moveSubjectRows, subjectMergeHandler } from "../subject-merge-sql.ts";
import { registeredSubjects } from "../subject-registry.ts";
import { DISPATCH_NAMES, dispatchContract } from "./dispatch-names.ts";
import { locationsOf } from "./inventory-stock.ts";
import { moduleOperations } from "./permissions-model.ts";

/** The statuses that hold a technician's slot. */
const BUSY = ["scheduled", "en_route", "on_site"] as const;

/** The longest span `dispatch_board` reads, in days. */
const BOARD_DAYS = 31;

const list = (values: readonly string[]): string =>
  values.map((value) => sqlString(value)).join(", ");

interface Linked {
  readonly assets: BlockSqlContext | undefined;
  readonly bookings: BlockSqlContext | undefined;
  readonly catalog: BlockSqlContext | undefined;
  readonly inventory: BlockSqlContext | undefined;
}

const linked = (ctx: BlockSqlContext): Linked => ({
  assets: ctx.installed("assets") ? ctx.of("assets") : undefined,
  bookings: ctx.installed("bookings") ? ctx.of("bookings") : undefined,
  catalog: ctx.installed("catalog") ? ctx.of("catalog") : undefined,
  inventory: ctx.installed("inventory") ? ctx.of("inventory") : undefined,
});

function tables(ctx: BlockSqlContext, extras: readonly ExtraColumn[]): string {
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
    assets &&
      key(
        orders,
        "workOrders",
        w("location"),
        "location",
        `${assets.table("locations")} (${assets.col("locations", "id")})`,
      ),
    assets &&
      key(
        orders,
        "workOrders",
        w("asset"),
        "asset",
        `${assets.table("assets")} (${assets.col("assets", "id")})`,
      ),
    bookings &&
      key(
        orders,
        "workOrders",
        w("booking"),
        "booking",
        `${bookings.table("bookings")} (${bookings.col("bookings", "id")})`,
      ),
    assets &&
      key(
        parts,
        "parts",
        q("asset"),
        "asset",
        `${assets.table("assets")} (${assets.col("assets", "id")})`,
      ),
    catalog &&
      key(
        parts,
        "parts",
        q("variant"),
        "variant",
        `${catalog.table("variants")} (${catalog.col("variants", "id")})`,
      ),
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
  ${w("title")} text not null check (length(${w("title")}) >= 1 and length(${w("title")}) <= 200),
  ${w("description")} text check (${w("description")} is null or length(${w("description")}) <= 10000),
  ${w("priority")} text not null default 'normal' check (${w("priority")} in (${list(WORK_ORDER_PRIORITIES)})),
  ${w("status")} text not null default 'unscheduled' check (${w("status")} in (${list(WORK_ORDER_STATUSES)})),
  ${w("technician")} uuid references auth.users (id) on delete set null,
  ${w("startsAt")} timestamptz,
  ${w("endsAt")} timestamptz,
  ${w("location")} uuid,
  ${w("asset")} uuid,
  ${w("booking")} uuid,
  ${w("subjectType")} text check (${w("subjectType")} is null or ${w("subjectType")} ~ '^[a-z][a-z0-9_-]{0,62}$'),
  ${w("subjectId")} text check (${w("subjectId")} is null or length(${w("subjectId")}) >= 1 and length(${w("subjectId")}) <= 200),
  ${w("address")} text check (${w("address")} is null or length(${w("address")}) >= 1 and length(${w("address")}) <= 500),
  ${w("enRouteAt")} timestamptz,
  ${w("arrivedAt")} timestamptz,
  ${w("completedAt")} timestamptz,
  ${w("cancelledAt")} timestamptz,
  ${w("cancelReason")} text check (${w("cancelReason")} is null or length(${w("cancelReason")}) <= 1000),
  ${w("completionNote")} text check (${w("completionNote")} is null or length(${w("completionNote")}) <= 10000),
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
create index if not exists ${index("workOrders", "booking_idx")} on ${orders} (${w("booking")});
create index if not exists ${index("workOrders", "subject_idx")} on ${orders} (${w("tenant")}, ${w("subjectType")}, ${w("subjectId")});
${lockTable(orders, { read: true })}
drop policy if exists ${index("workOrders", "read")} on ${orders};
create policy ${index("workOrders", "read")} on ${orders} for select to authenticated
  using (${w("technician")} = (select auth.uid()) or ${readable(w("tenant"))});
-- A technician's plan for one day: the work orders in the order they drive to
-- them.
create table if not exists ${routes} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("tenant")} ${ctx.idType} not null,
  ${r("technician")} uuid not null references auth.users (id) on delete cascade,
  ${r("routeDate")} date not null,
  ${r("plannedBy")} uuid,
  ${r("createdAt")} timestamptz not null default now(),
  ${r("updatedAt")} timestamptz not null default now(),
  unique (${r("tenant")}, ${r("technician")}, ${r("routeDate")})
);
create index if not exists ${index("routes", "technician_idx")} on ${routes} (${r("technician")}, ${r("routeDate")});
${lockTable(routes, { read: true })}
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
${lockTable(stops, { read: true })}
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
  ${q("quantity")} numeric(14, 3) not null check (${q("quantity")} > 0),
  ${q("unit")} text check (${q("unit")} is null or length(${q("unit")}) >= 1 and length(${q("unit")}) <= 20),
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
${lockTable(parts, { read: true })}
drop policy if exists ${index("parts", "read")} on ${parts};
create policy ${index("parts", "read")} on ${parts} for select to authenticated
  using (${readable(q("tenant"))});
${keys}
`;
}

function functions(
  ctx: BlockSqlContext,
  extras: readonly ExtraColumn[],
): string {
  const orders = ctx.table("workOrders");
  const routes = ctx.table("routes");
  const stops = ctx.table("stops");
  const parts = ctx.table("parts");
  const w = (column: string): string => ctx.col("workOrders", column);
  const r = (column: string): string => ctx.col("routes", column);
  const s = (column: string): string => ctx.col("stops", column);
  const q = (column: string): string => ctx.col("parts", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const keys = moduleOperations("dispatch");
  const read = ctx.permission("read", keys.read);
  const manage = ctx.permission("manage", keys.manage);
  const work = ctx.permission("work", keys.work);
  const zone = sqlString(ctx.text("timeZone", "UTC"));
  const duration = sqlString(ctx.text("defaultDuration", "1 hour"));
  const { assets, bookings, catalog, inventory } = linked(ctx);
  const fields = extraFieldsArg(extras);

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, permission)})`;

  // The technician themselves, holding dispatch.work, or a dispatcher.
  const worker = (row: string): string =>
    `(${allowed(`${row}.${w("tenant")}`, manage)} or (${row}.${w("technician")} = auth.uid() and ${ctx.can("tenant", `${row}.${w("tenant")}`, work)}))`;

  const busy = list(BUSY);

  const orderJson = (row: string): string =>
    withExtraFields(
      `jsonb_build_object('id', ${row}.${w("id")}, 'organizationId', ${row}.${w("tenant")}::text, 'title', ${row}.${w("title")}, 'description', ${row}.${w("description")}, 'priority', ${row}.${w("priority")}, 'status', ${row}.${w("status")}, 'technicianId', ${row}.${w("technician")}, 'startsAt', ${row}.${w("startsAt")}, 'endsAt', ${row}.${w("endsAt")}, 'day', (${row}.${w("startsAt")} at time zone ${zone})::date, 'locationId', ${row}.${w("location")}, 'assetId', ${row}.${w("asset")}, 'bookingId', ${row}.${w("booking")}, 'subjectType', ${row}.${w("subjectType")}, 'subjectId', ${row}.${w("subjectId")}, 'address', ${row}.${w("address")}, 'enRouteAt', ${row}.${w("enRouteAt")}, 'arrivedAt', ${row}.${w("arrivedAt")}, 'completedAt', ${row}.${w("completedAt")}, 'cancelledAt', ${row}.${w("cancelledAt")}, 'cancelReason', ${row}.${w("cancelReason")}, 'completionNote', ${row}.${w("completionNote")}, 'createdBy', ${row}.${w("createdBy")}, 'createdAt', ${row}.${w("createdAt")}, 'updatedAt', ${row}.${w("updatedAt")})`,
      row,
      extras,
    );

  const partJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${q("id")}, 'organizationId', ${row}.${q("tenant")}::text, 'workOrderId', ${row}.${q("workOrder")}, 'name', ${row}.${q("name")}, 'quantity', ${row}.${q("quantity")}::text, 'unit', ${row}.${q("unit")}, 'assetId', ${row}.${q("asset")}, 'variantId', ${row}.${q("variant")}, 'locationId', ${row}.${q("location")}, 'recordedBy', ${row}.${q("recordedBy")}, 'createdAt', ${row}.${q("createdAt")})`;

  const subject = (row: string): string =>
    `'work-orders/' || ${row}.${w("id")}::text`;

  const base = (row: string): string =>
    `'organizationId', ${row}.${w("tenant")}::text, 'id', ${row}.${w("id")}`;

  const audited = (row: string, summary: string) => ({
    category: "data" as const,
    targetType: "work_order",
    recordId: `${row}.${w("id")}::text`,
    targetLabel: `${row}.${w("title")}`,
    summary: sqlString(summary),
  });

  // The day of `instant` in the block's time zone.
  const dayStart = (day: string): string =>
    `(${day}::timestamp at time zone ${zone})`;

  // Fails unless the technician holds dispatch.work in the tenant and the slot
  // is free; the advisory lock serializes writes for one technician.
  const slotChecks = (
    tenant: string,
    technician: string,
    starts: string,
    ends: string,
    except: string,
  ): string => `  if not ${ctx.scope.canUser(technician, tenant, work)} then
    ${fail("DISPATCH_TECHNICIAN_INVALID", "the technician is not a member who can do field work here", "22023")}
  end if;
  if ${ends} <= ${starts} then
    ${fail("DISPATCH_SLOT_INVALID", "a slot ends after it starts", "22023")}
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bsb:dispatch:' || ${technician}::text, 0));
  if exists (
    select 1 from ${orders} o
    where o.${w("tenant")} = ${tenant} and o.${w("technician")} = ${technician}
      and o.${w("id")} is distinct from ${except}
      and o.${w("status")} in (${busy})
      and o.${w("startsAt")} < ${ends} and o.${w("endsAt")} > ${starts}
  ) then
    ${fail("DISPATCH_SLOT_TAKEN", "the technician already has a work order in that slot", "23P01")}
  end if;`;

  const missing = (module: string, hint: string, column: string): string =>
    `  if ${column} is not null then
    ${fail(hint, `install the ${module} block to link work orders to it`, "22023")}
  end if;`;

  // Checks that the linked location, asset and booking belong to the tenant.
  const placeChecks = (
    tenant: string,
    location: string,
    asset: string,
    booking: string | undefined,
  ): string =>
    [
      assets === undefined
        ? missing(
            "assets",
            "DISPATCH_ASSETS_MISSING",
            `coalesce(${location}, ${asset})`,
          )
        : `  if ${location} is not null and not exists (
    select 1 from ${assets.table("locations")} l
    where l.${assets.col("locations", "id")} = ${location} and l.${assets.col("locations", "tenant")} = ${tenant}
  ) then
    ${fail("DISPATCH_LOCATION_NOT_FOUND", "the location does not exist in this organization", "P0002")}
  end if;
  if ${asset} is not null and not exists (
    select 1 from ${assets.table("assets")} a
    where a.${assets.col("assets", "id")} = ${asset} and a.${assets.col("assets", "tenant")} = ${tenant}
  ) then
    ${fail("DISPATCH_ASSET_NOT_FOUND", "the asset does not exist in this organization", "P0002")}
  end if;`,
      booking === undefined
        ? ""
        : bookings === undefined
          ? missing("bookings", "DISPATCH_BOOKINGS_MISSING", booking)
          : `  if ${booking} is not null then
    select bk.${bookings.col("bookings", "during")} into v_during from ${bookings.table("bookings")} bk
      where bk.${bookings.col("bookings", "id")} = ${booking} and bk.${bookings.col("bookings", "tenant")} = ${tenant};
    if not found then
      ${fail("DISPATCH_BOOKING_NOT_FOUND", "the booking does not exist in this organization", "P0002")}
    end if;
  end if;`,
    ]
      .filter((sql) => sql !== "")
      .join("\n");

  const partChecks = (tenant: string): string =>
    [
      assets === undefined
        ? missing(
            "assets",
            "DISPATCH_ASSETS_MISSING",
            "record_work_order_part.asset_id",
          )
        : `  if record_work_order_part.asset_id is not null and not exists (
    select 1 from ${assets.table("assets")} a
    where a.${assets.col("assets", "id")} = record_work_order_part.asset_id and a.${assets.col("assets", "tenant")} = ${tenant}
  ) then
    ${fail("DISPATCH_ASSET_NOT_FOUND", "the asset does not exist in this organization", "P0002")}
  end if;`,
      catalog === undefined
        ? missing(
            "catalog",
            "DISPATCH_CATALOG_MISSING",
            "record_work_order_part.variant_id",
          )
        : `  if record_work_order_part.variant_id is not null and not exists (
    select 1 from ${catalog.table("variants")} v
    where v.${catalog.col("variants", "id")} = record_work_order_part.variant_id and v.${catalog.col("variants", "tenant")} = ${tenant}
  ) then
    ${fail("DISPATCH_VARIANT_NOT_FOUND", "the product variant does not exist in this organization", "P0002")}
  end if;`,
      inventory === undefined
        ? missing(
            "inventory",
            "DISPATCH_INVENTORY_MISSING",
            "record_work_order_part.location_id",
          )
        : `  if record_work_order_part.location_id is not null and not exists (
    select 1 from ${locationsOf(inventory).table} il
    where il.${locationsOf(inventory).col("id")} = record_work_order_part.location_id and il.${locationsOf(inventory).col("tenant")} = ${tenant}
  ) then
    ${fail("DISPATCH_INVENTORY_LOCATION_NOT_FOUND", "the inventory location does not exist in this organization", "P0002")}
  end if;`,
    ].join("\n");

  const createdRecord = ctx.record({
    type: "work_order.created",
    payload: `jsonb_build_object(${base("v_row")}, 'status', v_row.${w("status")}, 'technicianId', v_row.${w("technician")}, 'subjectType', v_row.${w("subjectType")}, 'subjectId', v_row.${w("subjectId")})`,
    subject: subject("v_row"),
    tenant: `v_row.${w("tenant")}`,
    audit: audited("v_row", "created work order"),
  });

  const scheduledRecord = ctx.record({
    type: "work_order.scheduled",
    payload: `jsonb_build_object(${base("v_row")}, 'technicianId', v_row.${w("technician")}, 'startsAt', v_row.${w("startsAt")}, 'endsAt', v_row.${w("endsAt")})`,
    subject: subject("v_row"),
    tenant: `v_row.${w("tenant")}`,
    audit: audited("v_row", "scheduled work order"),
  });

  const createDrop = fields.drop(
    fn("create_work_order"),
    `${idType}, text, text, text, uuid, uuid, uuid, text, text, text, uuid, timestamptz, timestamptz`,
  );

  const updateDrop = fields.drop(
    fn("update_work_order"),
    "uuid, text, text, text, uuid, uuid, text",
  );

  const bookingDeclare =
    bookings === undefined ? "" : "\n  v_during tstzrange;";

  const bookingSlot =
    bookings === undefined
      ? ""
      : `
  if create_work_order.booking_id is not null and v_starts is null then
    v_starts := lower(v_during);
    v_ends := upper(v_during);
  end if;`;

  return `
${createDrop}
-- Creates a work order in tenant. With a technician and starts_at (or a
-- booking to take the slot from) it is scheduled at once; otherwise it waits
-- in the backlog. ends_at defaults to starts_at plus the default duration.
create or replace function ${fn("create_work_order")}(tenant ${idType}, title text, description text default null, priority text default 'normal', location_id uuid default null, asset_id uuid default null, booking_id uuid default null, subject_type text default null, subject_id text default null, address text default null, technician uuid default null, starts_at timestamptz default null, ends_at timestamptz default null${fields.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${orders}%rowtype;
  v_starts timestamptz := create_work_order.starts_at;
  v_ends timestamptz := create_work_order.ends_at;${bookingDeclare}
begin
  if not ${allowed("create_work_order.tenant", manage)} then
    ${fail("DISPATCH_FORBIDDEN", "not allowed to manage work orders")}
  end if;
  if (create_work_order.subject_type is null) <> (create_work_order.subject_id is null) then
    ${fail("DISPATCH_SUBJECT_INVALID", "pass both subject_type and subject_id, or neither", "22023")}
  end if;
  if create_work_order.subject_type is not null
    and ${subjectTenant(ctx, "create_work_order.subject_type", "create_work_order.subject_id")} is distinct from create_work_order.tenant::text then
    ${fail("DISPATCH_SUBJECT_NOT_FOUND", "the record does not exist in this organization", "P0002")}
  end if;
${placeChecks("create_work_order.tenant", "create_work_order.location_id", "create_work_order.asset_id", "create_work_order.booking_id")}${bookingSlot}
  if v_starts is not null then
    if create_work_order.technician is null then
      ${fail("DISPATCH_TECHNICIAN_REQUIRED", "a scheduled work order needs a technician", "22023")}
    end if;
    v_ends := coalesce(v_ends, v_starts + ${duration}::interval);
${slotChecks("create_work_order.tenant", "create_work_order.technician", "v_starts", "v_ends", "null::uuid")}
  elsif create_work_order.technician is not null
    and not ${ctx.scope.canUser("create_work_order.technician", "create_work_order.tenant", work)} then
    ${fail("DISPATCH_TECHNICIAN_INVALID", "the technician is not a member who can do field work here", "22023")}
  end if;
  begin
    insert into ${orders} (${w("tenant")}, ${w("title")}, ${w("description")}, ${w("priority")}, ${w("status")}, ${w("technician")}, ${w("startsAt")}, ${w("endsAt")}, ${w("location")}, ${w("asset")}, ${w("booking")}, ${w("subjectType")}, ${w("subjectId")}, ${w("address")}, ${w("createdBy")})
    values (create_work_order.tenant, btrim(create_work_order.title), create_work_order.description, coalesce(create_work_order.priority, 'normal'),
      case when v_starts is null then 'unscheduled' else 'scheduled' end, create_work_order.technician, v_starts, v_ends,
      create_work_order.location_id, create_work_order.asset_id, create_work_order.booking_id,
      create_work_order.subject_type, create_work_order.subject_id, nullif(btrim(create_work_order.address), ''), auth.uid())
    returning * into v_row;
  exception when check_violation or not_null_violation then
    ${fail("DISPATCH_INVALID", "a work order needs a title of 1 to 200 characters and a known priority", "22023")}
  end;${writeExtraColumns(orders, extras, "create_work_order.fields", `x.${w("id")} = v_row.${w("id")}`, "v_row")}
  ${createdRecord}
  if v_row.${w("status")} = 'scheduled' then
    ${scheduledRecord}
  end if;
  return ${orderJson("v_row")};
end;
$$;
${userGrant(`${fn("create_work_order")}(${idType}, text, text, text, uuid, uuid, uuid, text, text, text, uuid, timestamptz, timestamptz${fields.type})`)}

${updateDrop}
-- Changes a work order's title, description, priority or place; null keeps a
-- value.
create or replace function ${fn("update_work_order")}(work_order_id uuid, title text default null, description text default null, priority text default null, location_id uuid default null, asset_id uuid default null, address text default null${fields.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${orders}%rowtype;
begin
  select * into v_row from ${orders} x where x.${w("id")} = update_work_order.work_order_id for update;
  if not found or not ${allowed(`v_row.${w("tenant")}`, manage)} then
    ${fail("DISPATCH_NOT_FOUND", "work order not found", "P0002")}
  end if;
${placeChecks(`v_row.${w("tenant")}`, "update_work_order.location_id", "update_work_order.asset_id", undefined)}
  begin
    update ${orders} x set
      ${w("title")} = coalesce(btrim(update_work_order.title), x.${w("title")}),
      ${w("description")} = coalesce(update_work_order.description, x.${w("description")}),
      ${w("priority")} = coalesce(update_work_order.priority, x.${w("priority")}),
      ${w("location")} = coalesce(update_work_order.location_id, x.${w("location")}),
      ${w("asset")} = coalesce(update_work_order.asset_id, x.${w("asset")}),
      ${w("address")} = coalesce(nullif(btrim(update_work_order.address), ''), x.${w("address")}),
      ${w("updatedAt")} = now()
    where x.${w("id")} = v_row.${w("id")}
    returning * into v_row;
  exception when check_violation then
    ${fail("DISPATCH_INVALID", "a work order needs a title of 1 to 200 characters and a known priority", "22023")}
  end;${writeExtraColumns(orders, extras, "update_work_order.fields", `x.${w("id")} = v_row.${w("id")}`, "v_row")}
  ${ctx.record({
    type: "work_order.updated",
    payload: `jsonb_build_object(${base("v_row")})`,
    subject: subject("v_row"),
    tenant: `v_row.${w("tenant")}`,
    audit: audited("v_row", "updated work order"),
  })}
  return ${orderJson("v_row")};
end;
$$;
${userGrant(`${fn("update_work_order")}(uuid, text, text, text, uuid, uuid, text${fields.type})`)}

-- Puts a work order in a technician's slot, or moves it to another one.
-- ends_at defaults to starts_at plus the default duration.
create or replace function ${fn("schedule_work_order")}(work_order_id uuid, technician uuid, starts_at timestamptz, ends_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${orders}%rowtype;
  v_ends timestamptz := coalesce(schedule_work_order.ends_at, schedule_work_order.starts_at + ${duration}::interval);
begin
  select * into v_row from ${orders} x where x.${w("id")} = schedule_work_order.work_order_id for update;
  if not found or not ${allowed(`v_row.${w("tenant")}`, manage)} then
    ${fail("DISPATCH_NOT_FOUND", "work order not found", "P0002")}
  end if;
  if v_row.${w("status")} not in ('unscheduled', 'scheduled') then
    ${fail("DISPATCH_STATUS_INVALID", "only a work order in the backlog or not started yet can be scheduled", "55000")}
  end if;
  if schedule_work_order.technician is null or schedule_work_order.starts_at is null then
    ${fail("DISPATCH_TECHNICIAN_REQUIRED", "a scheduled work order needs a technician and a start", "22023")}
  end if;
${slotChecks(`v_row.${w("tenant")}`, "schedule_work_order.technician", "schedule_work_order.starts_at", "v_ends", `v_row.${w("id")}`)}
  if v_row.${w("technician")} is distinct from schedule_work_order.technician then
    delete from ${stops} st where st.${s("workOrder")} = v_row.${w("id")};
  end if;
  update ${orders} x set ${w("status")} = 'scheduled', ${w("technician")} = schedule_work_order.technician,
    ${w("startsAt")} = schedule_work_order.starts_at, ${w("endsAt")} = v_ends, ${w("updatedAt")} = now()
    where x.${w("id")} = v_row.${w("id")}
    returning * into v_row;
  ${scheduledRecord}
  return ${orderJson("v_row")};
end;
$$;
${userGrant(`${fn("schedule_work_order")}(uuid, uuid, timestamptz, timestamptz)`)}

-- Takes a work order that hasn't started off the schedule, back to the
-- backlog, and off any route.
create or replace function ${fn("unschedule_work_order")}(work_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${orders}%rowtype;
  v_technician uuid;
begin
  select * into v_row from ${orders} x where x.${w("id")} = unschedule_work_order.work_order_id for update;
  if not found or not ${allowed(`v_row.${w("tenant")}`, manage)} then
    ${fail("DISPATCH_NOT_FOUND", "work order not found", "P0002")}
  end if;
  if v_row.${w("status")} = 'unscheduled' then
    return ${orderJson("v_row")};
  end if;
  if v_row.${w("status")} <> 'scheduled' then
    ${fail("DISPATCH_STATUS_INVALID", "only a work order that hasn't started can go back to the backlog", "55000")}
  end if;
  v_technician := v_row.${w("technician")};
  delete from ${stops} st where st.${s("workOrder")} = v_row.${w("id")};
  update ${orders} x set ${w("status")} = 'unscheduled', ${w("technician")} = null, ${w("startsAt")} = null,
    ${w("endsAt")} = null, ${w("updatedAt")} = now()
    where x.${w("id")} = v_row.${w("id")}
    returning * into v_row;
  ${ctx.record({
    type: "work_order.unscheduled",
    payload: `jsonb_build_object(${base("v_row")}, 'technicianId', v_technician)`,
    subject: subject("v_row"),
    tenant: `v_row.${w("tenant")}`,
    audit: audited("v_row", "unscheduled work order"),
  })}
  return ${orderJson("v_row")};
end;
$$;
${userGrant(`${fn("unschedule_work_order")}(uuid)`)}

-- Moves a work order along: scheduled to en_route, en_route or scheduled to
-- on_site, on_site to done, and anything not finished to cancelled. The
-- technician moves their own work orders; only a dispatcher cancels. note is
-- the completion note for done and the reason for cancelled.
create or replace function ${fn("set_work_order_status")}(work_order_id uuid, status text, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${orders}%rowtype;
  v_from text;
begin
  select * into v_row from ${orders} x where x.${w("id")} = set_work_order_status.work_order_id for update;
  if not found or not ${worker("v_row")} then
    ${fail("DISPATCH_NOT_FOUND", "work order not found", "P0002")}
  end if;
  v_from := v_row.${w("status")};
  if set_work_order_status.status = v_from then
    return ${orderJson("v_row")};
  end if;
  if not (
    (set_work_order_status.status = 'en_route' and v_from = 'scheduled')
    or (set_work_order_status.status = 'on_site' and v_from in ('scheduled', 'en_route'))
    or (set_work_order_status.status = 'done' and v_from = 'on_site')
    or (set_work_order_status.status = 'cancelled' and v_from in ('unscheduled', ${busy}))
  ) then
    ${fail("DISPATCH_TRANSITION_INVALID", "a work order can't move to that status from where it is", "55000")}
  end if;
  if set_work_order_status.status = 'cancelled' and not ${allowed(`v_row.${w("tenant")}`, manage)} then
    ${fail("DISPATCH_FORBIDDEN", "only a dispatcher can cancel a work order")}
  end if;
  update ${orders} x set
    ${w("status")} = set_work_order_status.status,
    ${w("enRouteAt")} = case when set_work_order_status.status = 'en_route' then now() else x.${w("enRouteAt")} end,
    ${w("arrivedAt")} = case when set_work_order_status.status = 'on_site' then now() else x.${w("arrivedAt")} end,
    ${w("completedAt")} = case when set_work_order_status.status = 'done' then now() else x.${w("completedAt")} end,
    ${w("completionNote")} = case when set_work_order_status.status = 'done' then set_work_order_status.note else x.${w("completionNote")} end,
    ${w("cancelledAt")} = case when set_work_order_status.status = 'cancelled' then now() else x.${w("cancelledAt")} end,
    ${w("cancelReason")} = case when set_work_order_status.status = 'cancelled' then set_work_order_status.note else x.${w("cancelReason")} end,
    ${w("updatedAt")} = now()
  where x.${w("id")} = v_row.${w("id")}
  returning * into v_row;
  ${ctx.record({
    type: "work_order.status_changed",
    payload: `jsonb_build_object(${base("v_row")}, 'from', v_from, 'to', v_row.${w("status")}, 'technicianId', v_row.${w("technician")})`,
    subject: subject("v_row"),
    tenant: `v_row.${w("tenant")}`,
    audit: {
      ...audited("v_row", "work order"),
      summary: `'work order ' || replace(v_row.${w("status")}, '_', ' ')`,
    },
  })}
  return ${orderJson("v_row")};
end;
$$;
${userGrant(`${fn("set_work_order_status")}(uuid, text, text)`)}

-- One work order, for a dispatcher, a reader or its technician; null
-- otherwise.
create or replace function ${fn("get_work_order")}(work_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${orders}%rowtype;
begin
  select * into v_row from ${orders} x where x.${w("id")} = get_work_order.work_order_id;
  if not found or not (${allowed(`v_row.${w("tenant")}`, read)} or ${worker("v_row")}) then
    return null;
  end if;
  return ${orderJson("v_row")};
end;
$$;
${userGrant(`${fn("get_work_order")}(uuid)`)}

-- A tenant's work orders, newest first, filtered by status, technician,
-- record or a window their slot overlaps.
create or replace function ${fn("list_work_orders")}(tenant ${idType}, status text default null, technician uuid default null, subject_type text default null, subject_id text default null, from_at timestamptz default null, until_at timestamptz default null, before timestamptz default null, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not ${allowed("list_work_orders.tenant", read)} then
    ${fail("DISPATCH_FORBIDDEN", "not allowed to read work orders")}
  end if;
  return (
    select coalesce(jsonb_agg(z.item order by z.created desc, z.id desc), '[]'::jsonb)
    from (
      select ${orderJson("x")} as item, x.${w("createdAt")} as created, x.${w("id")} as id
      from ${orders} x
      where x.${w("tenant")} = list_work_orders.tenant
        and (list_work_orders.status is null or x.${w("status")} = list_work_orders.status)
        and (list_work_orders.technician is null or x.${w("technician")} = list_work_orders.technician)
        and (list_work_orders.subject_type is null or (x.${w("subjectType")} = list_work_orders.subject_type and x.${w("subjectId")} = list_work_orders.subject_id))
        and (list_work_orders.from_at is null or x.${w("endsAt")} > list_work_orders.from_at)
        and (list_work_orders.until_at is null or x.${w("startsAt")} < list_work_orders.until_at)
        and (list_work_orders.before is null or x.${w("createdAt")} < list_work_orders.before)
      order by x.${w("createdAt")} desc, x.${w("id")} desc
      limit ${pageSize("list_work_orders.page_size", 50, 500)}
    ) z
  );
end;
$$;
${userGrant(`${fn("list_work_orders")}(${idType}, text, uuid, text, text, timestamptz, timestamptz, timestamptz, integer)`)}

-- The schedule board from from_date to to_date (at most ${BOARD_DAYS} days, in the
-- block's time zone): the scheduled work orders with their day, the
-- technicians (the ones passed, else the ones with work orders), and the
-- backlog by priority.
create or replace function ${fn("dispatch_board")}(tenant ${idType}, from_date date, to_date date, technicians uuid[] default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_from timestamptz;
  v_until timestamptz;
  v_orders jsonb;
begin
  if not ${allowed("dispatch_board.tenant", read)} then
    ${fail("DISPATCH_FORBIDDEN", "not allowed to read work orders")}
  end if;
  if dispatch_board.from_date is null or dispatch_board.to_date is null
    or dispatch_board.to_date < dispatch_board.from_date
    or dispatch_board.to_date - dispatch_board.from_date >= ${BOARD_DAYS} then
    ${fail("DISPATCH_RANGE_INVALID", `the board spans 1 to ${BOARD_DAYS} days`, "22023")}
  end if;
  v_from := ${dayStart("dispatch_board.from_date")};
  v_until := ${dayStart("(dispatch_board.to_date + 1)")};
  select coalesce(jsonb_agg(${orderJson("x")} order by x.${w("startsAt")}, x.${w("id")}), '[]'::jsonb) into v_orders
    from ${orders} x
    where x.${w("tenant")} = dispatch_board.tenant
      and x.${w("startsAt")} < v_until and x.${w("endsAt")} > v_from
      and x.${w("status")} <> 'cancelled'
      and (dispatch_board.technicians is null or x.${w("technician")} = any (dispatch_board.technicians));
  return jsonb_build_object(
    'from', dispatch_board.from_date,
    'to', dispatch_board.to_date,
    'timeZone', ${zone},
    'technicianIds', coalesce(
      to_jsonb(dispatch_board.technicians),
      (select coalesce(jsonb_agg(distinct e ->> 'technicianId'), '[]'::jsonb) from jsonb_array_elements(v_orders) e where e ->> 'technicianId' is not null)
    ),
    'scheduled', v_orders,
    'backlog', (
      select coalesce(jsonb_agg(z.item order by z.rank desc, z.created, z.id), '[]'::jsonb)
      from (
        select ${orderJson("b")} as item, array_position(array[${list(WORK_ORDER_PRIORITIES)}], b.${w("priority")}) as rank,
          b.${w("createdAt")} as created, b.${w("id")} as id
        from ${orders} b
        where b.${w("tenant")} = dispatch_board.tenant and b.${w("status")} = 'unscheduled'
        order by array_position(array[${list(WORK_ORDER_PRIORITIES)}], b.${w("priority")}) desc, b.${w("createdAt")}, b.${w("id")}
        limit 200
      ) z
    )
  );
end;
$$;
${userGrant(`${fn("dispatch_board")}(${idType}, date, date, uuid[])`)}

-- A technician's day plan: the stops of their route in order, then the other
-- work orders of the day by start. technician defaults to the caller.
create or replace function ${fn("technician_day")}(tenant ${idType}, day date, technician uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_technician uuid := coalesce(technician_day.technician, auth.uid());
  v_route ${routes}%rowtype;
begin
  if v_technician is null or not (
    ${allowed("technician_day.tenant", read)}
    or (v_technician = auth.uid() and ${ctx.can("tenant", "technician_day.tenant", work)})
  ) then
    ${fail("DISPATCH_FORBIDDEN", "not allowed to read this technician's day")}
  end if;
  select * into v_route from ${routes} rt
    where rt.${r("tenant")} = technician_day.tenant and rt.${r("technician")} = v_technician and rt.${r("routeDate")} = technician_day.day;
  return jsonb_build_object(
    'technicianId', v_technician,
    'date', technician_day.day,
    'routeId', v_route.${r("id")},
    'stops', (
      select coalesce(jsonb_agg(jsonb_build_object('position', z.position, 'workOrder', z.item) order by z.position), '[]'::jsonb)
      from (
        select row_number() over (order by y.planned nulls last, y.starts, y.id) as position, y.item
        from (
          select ${orderJson("x")} as item, st.${s("position")} as planned, x.${w("startsAt")} as starts, x.${w("id")} as id
          from ${orders} x
          left join ${stops} st on st.${s("workOrder")} = x.${w("id")} and st.${s("route")} = v_route.${r("id")}
          where x.${w("tenant")} = technician_day.tenant
            and (st.${s("id")} is not null or (
              x.${w("technician")} = v_technician and x.${w("status")} <> 'cancelled'
              and x.${w("startsAt")} >= ${dayStart("technician_day.day")}
              and x.${w("startsAt")} < ${dayStart("(technician_day.day + 1)")}
            ))
        ) y
      ) z
    )
  );
end;
$$;
${userGrant(`${fn("technician_day")}(${idType}, date, uuid)`)}

-- Sets the order a technician drives to work orders on a day. Each work order
-- must be theirs; the list replaces the route's stops. A dispatcher plans any
-- route, a technician their own.
create or replace function ${fn("plan_dispatch_route")}(tenant ${idType}, technician uuid, route_date date, work_orders uuid[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_route ${routes}%rowtype;
  v_count integer := coalesce(cardinality(plan_dispatch_route.work_orders), 0);
begin
  if plan_dispatch_route.technician is null or not (
    ${allowed("plan_dispatch_route.tenant", manage)}
    or (plan_dispatch_route.technician = auth.uid() and ${ctx.can("tenant", "plan_dispatch_route.tenant", work)})
  ) then
    ${fail("DISPATCH_FORBIDDEN", "not allowed to plan this technician's route")}
  end if;
  if plan_dispatch_route.route_date is null or v_count > 100
    or v_count <> (select count(distinct u) from unnest(plan_dispatch_route.work_orders) u where u is not null) then
    ${fail("DISPATCH_ROUTE_INVALID", "a route lists up to 100 different work orders for a day", "22023")}
  end if;
  if v_count <> (
    select count(*) from ${orders} x
    where x.${w("id")} = any (plan_dispatch_route.work_orders)
      and x.${w("tenant")} = plan_dispatch_route.tenant
      and x.${w("technician")} = plan_dispatch_route.technician
      and x.${w("status")} <> 'cancelled'
  ) then
    ${fail("DISPATCH_ROUTE_INVALID", "every stop must be a live work order of this technician", "22023")}
  end if;
  insert into ${routes} (${r("tenant")}, ${r("technician")}, ${r("routeDate")}, ${r("plannedBy")})
  values (plan_dispatch_route.tenant, plan_dispatch_route.technician, plan_dispatch_route.route_date, auth.uid())
  on conflict (${r("tenant")}, ${r("technician")}, ${r("routeDate")})
    do update set ${r("plannedBy")} = excluded.${r("plannedBy")}, ${r("updatedAt")} = now()
  returning * into v_route;
  delete from ${stops} st where st.${s("route")} = v_route.${r("id")};
  insert into ${stops} (${s("tenant")}, ${s("route")}, ${s("workOrder")}, ${s("position")})
  select plan_dispatch_route.tenant, v_route.${r("id")}, u.id, u.position
  from unnest(plan_dispatch_route.work_orders) with ordinality as u(id, position);
  ${ctx.record({
    type: "dispatch_route.planned",
    payload: `jsonb_build_object('organizationId', v_route.${r("tenant")}::text, 'id', v_route.${r("id")}, 'technicianId', v_route.${r("technician")}, 'routeDate', v_route.${r("routeDate")}, 'stops', v_count)`,
    subject: `'dispatch-routes/' || v_route.${r("id")}::text`,
    tenant: `v_route.${r("tenant")}`,
    audit: false,
  })}
  return jsonb_build_object('id', v_route.${r("id")}, 'organizationId', v_route.${r("tenant")}::text,
    'technicianId', v_route.${r("technician")}, 'routeDate', v_route.${r("routeDate")},
    'stops', coalesce(to_jsonb(plan_dispatch_route.work_orders), '[]'::jsonb));
end;
$$;
${userGrant(`${fn("plan_dispatch_route")}(${idType}, uuid, date, uuid[])`)}

-- Records a part a work order used: free text, an asset, or a catalog variant
-- from an inventory location. Recording moves no stock.
create or replace function ${fn("record_work_order_part")}(work_order_id uuid, name text, quantity numeric default 1, unit text default null, asset_id uuid default null, variant_id uuid default null, location_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_order ${orders}%rowtype;
  v_row ${parts}%rowtype;
begin
  select * into v_order from ${orders} x where x.${w("id")} = record_work_order_part.work_order_id;
  if not found or not ${worker("v_order")} then
    ${fail("DISPATCH_NOT_FOUND", "work order not found", "P0002")}
  end if;
  if v_order.${w("status")} = 'cancelled' then
    ${fail("DISPATCH_STATUS_INVALID", "a cancelled work order takes no parts", "55000")}
  end if;
${partChecks(`v_order.${w("tenant")}`)}
  begin
    insert into ${parts} (${q("tenant")}, ${q("workOrder")}, ${q("name")}, ${q("quantity")}, ${q("unit")}, ${q("asset")}, ${q("variant")}, ${q("location")}, ${q("recordedBy")})
    values (v_order.${w("tenant")}, v_order.${w("id")}, btrim(record_work_order_part.name), coalesce(record_work_order_part.quantity, 1),
      record_work_order_part.unit, record_work_order_part.asset_id, record_work_order_part.variant_id, record_work_order_part.location_id, auth.uid())
    returning * into v_row;
  exception when check_violation or not_null_violation or numeric_value_out_of_range then
    ${fail("DISPATCH_PART_INVALID", "a part needs a name of 1 to 200 characters and a positive quantity", "22023")}
  end;
  ${ctx.record({
    type: "work_order.part_used",
    payload: `jsonb_build_object('organizationId', v_row.${q("tenant")}::text, 'id', v_row.${q("workOrder")}, 'partId', v_row.${q("id")}, 'assetId', v_row.${q("asset")}, 'variantId', v_row.${q("variant")}, 'quantity', v_row.${q("quantity")}::text)`,
    subject: `'work-orders/' || v_row.${q("workOrder")}::text`,
    tenant: `v_row.${q("tenant")}`,
    audit: false,
  })}
  return ${partJson("v_row")};
end;
$$;
${userGrant(`${fn("record_work_order_part")}(uuid, text, numeric, text, uuid, uuid, uuid)`)}

-- A work order's parts, oldest first.
create or replace function ${fn("list_work_order_parts")}(work_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_order ${orders}%rowtype;
begin
  select * into v_order from ${orders} x where x.${w("id")} = list_work_order_parts.work_order_id;
  if not found or not (${allowed(`v_order.${w("tenant")}`, read)} or ${worker("v_order")}) then
    return '[]'::jsonb;
  end if;
  return (
    select coalesce(jsonb_agg(${partJson("y")} order by y.${q("createdAt")}, y.${q("id")}), '[]'::jsonb)
    from ${parts} y where y.${q("workOrder")} = v_order.${w("id")}
  );
end;
$$;
${userGrant(`${fn("list_work_order_parts")}(uuid)`)}

-- Removes a part recorded by mistake: the dispatcher, or the technician who
-- recorded it.
create or replace function ${fn("remove_work_order_part")}(part_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${parts}%rowtype;
begin
  select * into v_row from ${parts} y where y.${q("id")} = remove_work_order_part.part_id for update;
  if not found or not (
    ${allowed(`v_row.${q("tenant")}`, manage)}
    or (v_row.${q("recordedBy")} = auth.uid() and ${ctx.can("tenant", `v_row.${q("tenant")}`, work)})
  ) then
    return false;
  end if;
  delete from ${parts} y where y.${q("id")} = v_row.${q("id")};
  return true;
end;
$$;
${userGrant(`${fn("remove_work_order_part")}(uuid)`)}
`;
}

/**
 * Moves the work orders on a merged registered subject to the record it merged
 * into.
 */
function workOrderMerges(ctx: BlockSqlContext): string {
  const subjects = registeredSubjects(ctx.subjects, ctx.naming).map(
    (subject) =>
      [
        subject.type,
        { table: `${subject.schema}.${subject.table}`, extra: {} },
      ] as const,
  );

  return subjectMergeHandler(
    ctx,
    subjects,
    moveSubjectRows(
      {
        table: ctx.table("workOrders"),
        type: ctx.col("workOrders", "subjectType"),
        id: ctx.col("workOrders", "subjectId"),
      },
      "v_type",
    ),
  );
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const extras = ctx.extraColumns("workOrders", ["fields", "day"]);

  return `${schemaPreamble(ctx)}
-- Dispatch: work orders at asset locations, scheduled into technicians'
-- slots on a board, worked through a status lifecycle, with day routes and
-- the parts each job used.
${tables(ctx, extras)}${functions(ctx, extras)}${workOrderMerges(ctx)}`;
}

export const DISPATCH: BlockSqlDefinition = {
  name: "dispatch",
  scopes: ["tenant"],
  title: "Dispatch",
  description:
    "Field service work orders at asset locations: a schedule board of technicians' slots, a status lifecycle from scheduled to done, day routes with ordered stops, and the parts each job used, linked to assets or inventory when those blocks are installed.",
  requires: ["memberships", "permissions"],
  integrates: ["outbox", "audit", "assets", "bookings", "catalog", "inventory"],
  target: "schema",
  modes: ["managed", "custom"],
  names: DISPATCH_NAMES,
  contract: dispatchContract,
  build,
};
