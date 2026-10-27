import type { ExtraColumn, BlockSqlContext } from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { WORK_ORDER_PRIORITIES } from "../../blocks/dispatch/statuses.ts";
import { sqlString } from "../../core/template.ts";
import {
  extraFieldsArg,
  fail,
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
import { BUSY, dispatchTables, linked, list } from "./dispatch-tables.ts";
import { locationsOf } from "./inventory-stock.ts";
import { asText } from "./over-app.ts";
import { moduleOperations } from "./permissions-model.ts";

/** The longest span `dispatch_board` reads, in days. */
const BOARD_DAYS = 31;

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

  // `<row>.<column>`, or null when the app maps the column to null.
  const or = (table: string, row: string, logical: string): string =>
    ctx.has(table, logical) ? `${row}.${ctx.col(table, logical)}` : "null";

  // ", <column>" for an insert list, when the column exists.
  const also = (table: string, logical: string): string =>
    ctx.has(table, logical) ? `, ${ctx.col(table, logical)}` : "";

  // ", <value>" for an insert's values, when the column exists.
  const alsoValue = (table: string, logical: string, value: string): string =>
    ctx.has(table, logical) ? `, ${value}` : "";

  // Sets a work order column to value when the new status is to, and keeps
  // it otherwise; left out when the app maps the column to null.
  const set = (logical: string, to: string, value: string): string =>
    ctx.has("workOrders", logical)
      ? `\n    ${w(logical)} = case when set_work_order_status.status = '${to}' then ${value} else x.${w(logical)} end,`
      : "";

  const status = (row: string): string =>
    asText(ctx, "workOrders", `${row}.${w("status")}`);

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
    `(${allowed(`${row}.${w("tenant")}`, manage)} or (coalesce(${row}.${w("technician")} = auth.uid(), false) and ${ctx.can("tenant", `${row}.${w("tenant")}`, work)}))`;

  const busy = list(BUSY);

  const orderJson = (row: string): string =>
    withExtraFields(
      `jsonb_build_object('id', ${row}.${w("id")}, 'organizationId', ${row}.${w("tenant")}::text, 'title', ${row}.${w("title")}, 'description', ${or("workOrders", row, "description")}, 'priority', ${row}.${w("priority")}, 'status', ${row}.${w("status")}, 'technicianId', ${row}.${w("technician")}, 'startsAt', ${row}.${w("startsAt")}, 'endsAt', ${row}.${w("endsAt")}, 'day', (${row}.${w("startsAt")} at time zone ${zone})::date, 'locationId', ${row}.${w("location")}, 'assetId', ${row}.${w("asset")}, 'bookingId', ${or("workOrders", row, "booking")}, 'subjectType', ${row}.${w("subjectType")}, 'subjectId', ${row}.${w("subjectId")}, 'address', ${or("workOrders", row, "address")}, 'enRouteAt', ${or("workOrders", row, "enRouteAt")}, 'arrivedAt', ${or("workOrders", row, "arrivedAt")}, 'completedAt', ${row}.${w("completedAt")}, 'cancelledAt', ${row}.${w("cancelledAt")}, 'cancelReason', ${or("workOrders", row, "cancelReason")}, 'completionNote', ${or("workOrders", row, "completionNote")}, 'createdBy', ${row}.${w("createdBy")}, 'createdAt', ${row}.${w("createdAt")}, 'updatedAt', ${row}.${w("updatedAt")})`,
      row,
      extras,
    );

  const partJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${q("id")}, 'organizationId', ${row}.${q("tenant")}::text, 'workOrderId', ${row}.${q("workOrder")}, 'name', ${row}.${q("name")}, 'quantity', ${row}.${q("quantity")}::text, 'unit', ${or("parts", row, "unit")}, 'assetId', ${row}.${q("asset")}, 'variantId', ${row}.${q("variant")}, 'locationId', ${row}.${q("location")}, 'recordedBy', ${row}.${q("recordedBy")}, 'createdAt', ${row}.${q("createdAt")})`;

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
    insert into ${orders} (${w("tenant")}, ${w("title")}${also("workOrders", "description")}, ${w("priority")}, ${w("status")}, ${w("technician")}, ${w("startsAt")}, ${w("endsAt")}, ${w("location")}, ${w("asset")}${also("workOrders", "booking")}, ${w("subjectType")}, ${w("subjectId")}${also("workOrders", "address")}, ${w("createdBy")})
    values (create_work_order.tenant, btrim(create_work_order.title)${alsoValue("workOrders", "description", "create_work_order.description")}, ${ctx.cast("workOrders", "priority", "coalesce(create_work_order.priority, 'normal')")},
      ${ctx.cast("workOrders", "status", "case when v_starts is null then 'unscheduled' else 'scheduled' end")}, create_work_order.technician, v_starts, v_ends,
      create_work_order.location_id, create_work_order.asset_id${alsoValue("workOrders", "booking", "create_work_order.booking_id")},
      create_work_order.subject_type, create_work_order.subject_id${alsoValue("workOrders", "address", "nullif(btrim(create_work_order.address), '')")}, auth.uid())
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
      ${w("title")} = coalesce(btrim(update_work_order.title), x.${w("title")}),${ctx.has("workOrders", "description") ? `\n      ${w("description")} = coalesce(update_work_order.description, x.${w("description")}),` : ""}
      ${w("priority")} = ${ctx.cast("workOrders", "priority", `coalesce(update_work_order.priority, ${asText(ctx, "workOrders", `x.${w("priority")}`)})`)},
      ${w("location")} = coalesce(update_work_order.location_id, x.${w("location")}),
      ${w("asset")} = coalesce(update_work_order.asset_id, x.${w("asset")}),${ctx.has("workOrders", "address") ? `\n      ${w("address")} = coalesce(nullif(btrim(update_work_order.address), ''), x.${w("address")}),` : ""}
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
  v_from := ${status("v_row")};
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
    ${w("status")} = ${ctx.cast("workOrders", "status", "set_work_order_status.status")},${set("enRouteAt", "en_route", "now()")}${set("arrivedAt", "on_site", "now()")}
    ${w("completedAt")} = case when set_work_order_status.status = 'done' then now() else x.${w("completedAt")} end,${set("completionNote", "done", "set_work_order_status.note")}
    ${w("cancelledAt")} = case when set_work_order_status.status = 'cancelled' then now() else x.${w("cancelledAt")} end,${set("cancelReason", "cancelled", "set_work_order_status.note")}
    ${w("updatedAt")} = now()
  where x.${w("id")} = v_row.${w("id")}
  returning * into v_row;
  ${ctx.record({
    type: "work_order.status_changed",
    payload: `jsonb_build_object(${base("v_row")}, 'from', v_from, 'to', ${status("v_row")}, 'technicianId', v_row.${w("technician")})`,
    subject: subject("v_row"),
    tenant: `v_row.${w("tenant")}`,
    audit: {
      ...audited("v_row", "work order"),
      summary: `'work order ' || replace(${status("v_row")}, '_', ' ')`,
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
        and (list_work_orders.status is null or ${status("x")} = list_work_orders.status)
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
        select ${orderJson("b")} as item, array_position(array[${list(WORK_ORDER_PRIORITIES)}], ${asText(ctx, "workOrders", `b.${w("priority")}`)}) as rank,
          b.${w("createdAt")} as created, b.${w("id")} as id
        from ${orders} b
        where b.${w("tenant")} = dispatch_board.tenant and b.${w("status")} = 'unscheduled'
        order by array_position(array[${list(WORK_ORDER_PRIORITIES)}], ${asText(ctx, "workOrders", `b.${w("priority")}`)}) desc, b.${w("createdAt")}, b.${w("id")}
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
    or (coalesce(v_technician = auth.uid(), false) and ${ctx.can("tenant", "technician_day.tenant", work)})
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
    or (coalesce(plan_dispatch_route.technician = auth.uid(), false) and ${ctx.can("tenant", "plan_dispatch_route.tenant", work)})
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
  insert into ${routes} (${r("tenant")}, ${r("technician")}, ${r("routeDate")}${also("routes", "plannedBy")})
  values (plan_dispatch_route.tenant, plan_dispatch_route.technician, plan_dispatch_route.route_date${alsoValue("routes", "plannedBy", "auth.uid()")})
  on conflict (${r("tenant")}, ${r("technician")}, ${r("routeDate")})
    do update set ${ctx.has("routes", "plannedBy") ? `${r("plannedBy")} = excluded.${r("plannedBy")}, ` : ""}${r("updatedAt")} = now()
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
    insert into ${parts} (${q("tenant")}, ${q("workOrder")}, ${q("name")}, ${q("quantity")}${also("parts", "unit")}, ${q("asset")}, ${q("variant")}, ${q("location")}, ${q("recordedBy")})
    values (v_order.${w("tenant")}, v_order.${w("id")}, btrim(record_work_order_part.name), coalesce(record_work_order_part.quantity, 1),
      ${ctx.has("parts", "unit") ? "record_work_order_part.unit, " : ""}record_work_order_part.asset_id, record_work_order_part.variant_id, record_work_order_part.location_id, auth.uid())
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
    or (coalesce(v_row.${q("recordedBy")} = auth.uid(), false) and ${ctx.can("tenant", `v_row.${q("tenant")}`, work)})
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
${dispatchTables(ctx, extras)}${functions(ctx, extras)}${workOrderMerges(ctx)}`;
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
