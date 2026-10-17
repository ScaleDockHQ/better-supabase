import type { ExtraColumn, ModuleContext } from "../context.ts";
import type { ModuleScope } from "../scope.ts";

import {
  fail,
  serviceGrant,
  userGrant,
  withExtraFields,
  writeExtraColumns,
} from "../shared.ts";

export interface InventoryNames {
  /** The block's scope checks. */
  readonly scope: ModuleScope;
  readonly fn: (name: string) => string;
  readonly manage: string;
  readonly read: string;
  readonly reserve: string;
  readonly purchase: string;
  /** `options.extraColumns` on the locations table, which `save_location` writes from `fields`. */
  readonly extras: readonly ExtraColumn[];
}

/** The reasons `adjust_stock` accepts; the other functions write their own. */
const ADJUST_REASONS = [
  "adjustment",
  "damage",
  "loss",
  "return",
  "receipt",
] as const;

export function guard(
  scope: ModuleScope,
  permission: string,
  tenant: string,
): string {
  return `if not (auth.role() = 'service_role' or ${scope.can(tenant, permission)}) then
    ${fail("INVENTORY_FORBIDDEN", "not allowed to change this inventory")}
  end if;`;
}

/** Column accessors for one logical table. */
export const columns =
  (ctx: ModuleContext, table: string) =>
  (column: string): string =>
    ctx.col(table, column);

/**
 * Whether a variant's stock can't go below zero: catalog's
 * `track_inventory` is on and `allow_backorder` off.
 */
export function strict(ctx: ModuleContext, variant: string): string {
  const catalog = ctx.of("catalog");
  const v = columns(catalog, "variants");

  return `exists (select 1 from ${catalog.table("variants")} cv where cv.${v("id")} = ${variant} and cv.${v("trackInventory")} and not cv.${v("allowBackorder")})`;
}

/**
 * Raises unless the variant is in the tenant, so a level never joins a
 * variant and a location from two organizations.
 */
function variantCheck(
  ctx: ModuleContext,
  variant: string,
  tenant: string,
): string {
  const catalog = ctx.of("catalog");
  const v = columns(catalog, "variants");

  return `if not exists (select 1 from ${catalog.table("variants")} cv where cv.${v("id")} = ${variant} and cv.${v("tenant")} = ${tenant}) then
    ${fail("INVENTORY_VARIANT_NOT_FOUND", "variant not found in this organization", "P0002")}
  end if;`;
}

/** Records `stock.reorder_point_reached` when available drops to the reorder point. */
export function threshold(
  ctx: ModuleContext,
  values: {
    readonly tenant: string;
    readonly variant: string;
    readonly location: string;
    readonly before: string;
    readonly after: string;
    readonly point: string;
  },
): string {
  const record = ctx.record({
    type: "stock.reorder_point_reached",
    payload: `jsonb_build_object('organizationId', ${values.tenant}, 'subjectType', 'product_variant', 'subjectId', ${values.variant}::text, 'variantId', ${values.variant}, 'locationId', ${values.location}, 'available', ${values.after}::text, 'reorderPoint', ${values.point}::text)`,
    subject: `'stock-levels/' || ${values.variant}::text || '/' || ${values.location}::text`,
    tenant: values.tenant,
    audit: false,
  });

  if (record.trim() === "") {
    return "";
  }

  return `if ${values.point} is not null and ${values.before} > ${values.point} and ${values.after} <= ${values.point} then
    ${record}
  end if;`;
}

/** Loads a location's tenant into `v_tenant`, raising when it doesn't exist. */
function loadLocation(ctx: ModuleContext, location: string): string {
  const l = columns(ctx, "locations");

  return `select x.${l("tenant")}, x.${l("active")} into v_tenant, v_active from ${ctx.table("locations")} x where x.${l("id")} = ${location};
  if v_tenant is null then
    ${fail("INVENTORY_LOCATION_NOT_FOUND", "location not found", "P0002")}
  end if;`;
}

/** Creates the level row when missing and locks it. */
function lockLevel(
  ctx: ModuleContext,
  variant: string,
  location: string,
): string {
  const lv = columns(ctx, "levels");
  const levels = ctx.table("levels");

  return `insert into ${levels} (${lv("tenant")}, ${lv("variant")}, ${lv("location")})
  values (v_tenant, ${variant}, ${location})
  on conflict (${lv("variant")}, ${lv("location")}) do nothing;
  perform 1 from ${levels} x where x.${lv("variant")} = ${variant} and x.${lv("location")} = ${location} for update;`;
}

export function locationFunctions(
  ctx: ModuleContext,
  names: InventoryNames,
): string {
  const { fn } = names;
  const locations = ctx.table("locations");
  const l = columns(ctx, "locations");
  const m = columns(ctx, "movements");
  const r = columns(ctx, "reservations");

  return `
-- Creates a location (location null) or updates one, with the extra columns
-- in fields by name. Returns its id, code and active flag.
drop function if exists ${fn("save_location")}(${ctx.idType}, uuid, text, text, text);
create or replace function ${fn("save_location")}(tenant ${ctx.idType}, location uuid, code text, name text, kind text, fields jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_location.location;
  v_active boolean;
begin
  ${guard(names.scope, names.manage, "save_location.tenant")}
  if save_location.code is null or save_location.code !~ '^[A-Za-z0-9][A-Za-z0-9_.-]{0,39}$' then
    ${fail("INVENTORY_LOCATION_CODE_INVALID", "the code must be 1 to 40 letters, digits, dots, dashes or underscores", "22023")}
  end if;
  if coalesce(save_location.kind, 'warehouse') not in ('warehouse', 'store', 'virtual') then
    ${fail("INVENTORY_LOCATION_KIND_INVALID", "the kind must be warehouse, store or virtual", "22023")}
  end if;
  begin
    if v_id is null then
      insert into ${locations} (${l("tenant")}, ${l("code")}, ${l("name")}, ${l("kind")})
      values (save_location.tenant, save_location.code, save_location.name, coalesce(save_location.kind, 'warehouse'))
      returning ${l("id")}, ${l("active")} into v_id, v_active;
    else
      update ${locations} x set ${l("code")} = save_location.code, ${l("name")} = save_location.name,
        ${l("kind")} = coalesce(save_location.kind, x.${l("kind")}), ${l("updatedAt")} = now()
      where x.${l("id")} = save_location.location and x.${l("tenant")} = save_location.tenant
      returning x.${l("active")} into v_active;
      if not found then
        ${fail("INVENTORY_LOCATION_NOT_FOUND", "location not found", "P0002")}
      end if;
    end if;
  exception when unique_violation then
    ${fail("INVENTORY_LOCATION_CODE_TAKEN", "another location has this code", "23505")}
  end;${writeExtraColumns(locations, names.extras, "save_location.fields", `x.${l("id")} = v_id`)}
  return ${
    names.extras.length === 0
      ? "jsonb_build_object('id', v_id, 'code', save_location.code, 'active', v_active)"
      : `(select ${withExtraFields("jsonb_build_object('id', v_id, 'code', save_location.code, 'active', v_active)", "x", names.extras)} from ${locations} x where x.${l("id")} = v_id)`
  };
end;
$$;
${userGrant(`${fn("save_location")}(${ctx.idType}, uuid, text, text, text, jsonb)`)}

-- Turns a location on or off. Reservations need an active location.
create or replace function ${fn("set_location_active")}(location uuid, active boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_active boolean;
begin
  ${loadLocation(ctx, "set_location_active.location")}
  ${guard(names.scope, names.manage, "v_tenant")}
  update ${locations} x set ${l("active")} = coalesce(set_location_active.active, true), ${l("updatedAt")} = now()
  where x.${l("id")} = set_location_active.location;
  return true;
end;
$$;
${userGrant(`${fn("set_location_active")}(uuid, boolean)`)}

-- Deletes a location without stock history. Deactivate one that has some.
create or replace function ${fn("delete_location")}(location uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_active boolean;
begin
  select x.${l("tenant")} into v_tenant from ${locations} x where x.${l("id")} = delete_location.location;
  if v_tenant is null then
    return false;
  end if;
  ${guard(names.scope, names.manage, "v_tenant")}
  if exists (select 1 from ${ctx.table("movements")} x where x.${m("location")} = delete_location.location)
    or exists (select 1 from ${ctx.table("reservations")} x where x.${r("location")} = delete_location.location and x.${r("status")} = 'active') then
    ${fail("INVENTORY_LOCATION_IN_USE", "the location has stock history; deactivate it instead", "23503")}
  end if;
  delete from ${locations} x where x.${l("id")} = delete_location.location;
  return true;
end;
$$;
${userGrant(`${fn("delete_location")}(uuid)`)}
`;
}

export function stockFunctions(
  ctx: ModuleContext,
  names: InventoryNames,
): string {
  const { fn } = names;
  const levels = ctx.table("levels");
  const movements = ctx.table("movements");
  const lv = columns(ctx, "levels");
  const m = columns(ctx, "movements");
  const reasons = ADJUST_REASONS.map((reason) => `'${reason}'`).join(", ");

  return `
-- Adds or removes stock at a location through the ledger. Returns the
-- movement id and the level's on-hand and available quantities.
create or replace function ${fn("adjust_stock")}(variant uuid, location uuid, quantity integer, reason text, note text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_active boolean;
  v_movement uuid;
  v_on_hand integer;
  v_available integer;
begin
  ${loadLocation(ctx, "adjust_stock.location")}
  ${guard(names.scope, names.manage, "v_tenant")}
  ${variantCheck(ctx, "adjust_stock.variant", "v_tenant")}
  if adjust_stock.quantity is null or adjust_stock.quantity = 0 then
    ${fail("INVENTORY_QUANTITY_INVALID", "the quantity must be a non-zero whole number", "22023")}
  end if;
  if adjust_stock.reason is null or adjust_stock.reason not in (${reasons}) then
    ${fail("INVENTORY_REASON_INVALID", `the reason must be one of ${ADJUST_REASONS.join(", ")}`, "22023")}
  end if;
  ${ctx.hook("before_stock_adjust", [
    ["uuid", "adjust_stock.variant"],
    ["uuid", "adjust_stock.location"],
    ["integer", "adjust_stock.quantity"],
    ["text", "adjust_stock.reason"],
  ])}
  insert into ${movements} (${m("tenant")}, ${m("variant")}, ${m("location")}, ${m("quantity")}, ${m("reason")}, ${m("note")})
  values (v_tenant, adjust_stock.variant, adjust_stock.location, adjust_stock.quantity, adjust_stock.reason, adjust_stock.note)
  returning ${m("id")} into v_movement;
  select x.${lv("onHand")}, x.${lv("available")} into v_on_hand, v_available from ${levels} x
  where x.${lv("variant")} = adjust_stock.variant and x.${lv("location")} = adjust_stock.location;
  ${ctx.record({
    type: "stock.adjusted",
    payload: `jsonb_build_object('organizationId', v_tenant, 'id', v_movement, 'variantId', adjust_stock.variant, 'locationId', adjust_stock.location, 'quantity', adjust_stock.quantity::text, 'reason', adjust_stock.reason, 'available', v_available::text)`,
    subject: `'stock-movements/' || v_movement::text`,
    tenant: "v_tenant",
    audit: false,
  })}
  ${ctx.hook("after_stock_adjust", [["uuid", "v_movement"]])}
  return jsonb_build_object('movementId', v_movement, 'onHand', v_on_hand, 'available', v_available);
end;
$$;
${userGrant(`${fn("adjust_stock")}(uuid, uuid, integer, text, text)`)}

-- Sets on-hand to a counted quantity, writing the difference to the ledger.
create or replace function ${fn("count_stock")}(variant uuid, location uuid, counted integer, note text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_active boolean;
  v_movement uuid;
  v_delta integer;
  v_available integer;
begin
  ${loadLocation(ctx, "count_stock.location")}
  ${guard(names.scope, names.manage, "v_tenant")}
  ${variantCheck(ctx, "count_stock.variant", "v_tenant")}
  if count_stock.counted is null or count_stock.counted < 0 then
    ${fail("INVENTORY_QUANTITY_INVALID", "the counted quantity must be zero or more", "22023")}
  end if;
  ${lockLevel(ctx, "count_stock.variant", "count_stock.location")}
  select count_stock.counted - x.${lv("onHand")} into v_delta from ${levels} x
  where x.${lv("variant")} = count_stock.variant and x.${lv("location")} = count_stock.location;
  if v_delta <> 0 then
    insert into ${movements} (${m("tenant")}, ${m("variant")}, ${m("location")}, ${m("quantity")}, ${m("reason")}, ${m("note")})
    values (v_tenant, count_stock.variant, count_stock.location, v_delta, 'count', count_stock.note)
    returning ${m("id")} into v_movement;
    select x.${lv("available")} into v_available from ${levels} x
    where x.${lv("variant")} = count_stock.variant and x.${lv("location")} = count_stock.location;
    ${ctx.record({
      type: "stock.adjusted",
      payload: `jsonb_build_object('organizationId', v_tenant, 'id', v_movement, 'variantId', count_stock.variant, 'locationId', count_stock.location, 'quantity', v_delta::text, 'reason', 'count', 'available', v_available::text)`,
      subject: `'stock-movements/' || v_movement::text`,
      tenant: "v_tenant",
      audit: false,
    })}
  end if;
  return jsonb_build_object('movementId', v_movement, 'delta', v_delta, 'onHand', count_stock.counted);
end;
$$;
${userGrant(`${fn("count_stock")}(uuid, uuid, integer, text)`)}

-- Sets the available quantity at or below which stock.reorder_point_reached fires.
create or replace function ${fn("set_reorder_point")}(variant uuid, location uuid, reorder_point integer)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_active boolean;
begin
  ${loadLocation(ctx, "set_reorder_point.location")}
  ${guard(names.scope, names.manage, "v_tenant")}
  ${variantCheck(ctx, "set_reorder_point.variant", "v_tenant")}
  if set_reorder_point.reorder_point < 0 then
    ${fail("INVENTORY_QUANTITY_INVALID", "the reorder point must be zero or more", "22023")}
  end if;
  insert into ${levels} as x (${lv("tenant")}, ${lv("variant")}, ${lv("location")}, ${lv("reorderPoint")})
  values (v_tenant, set_reorder_point.variant, set_reorder_point.location, set_reorder_point.reorder_point)
  on conflict (${lv("variant")}, ${lv("location")}) do update
    set ${lv("reorderPoint")} = excluded.${lv("reorderPoint")}, ${lv("updatedAt")} = now();
  return true;
end;
$$;
${userGrant(`${fn("set_reorder_point")}(uuid, uuid, integer)`)}
`;
}

export function reservationFunctions(
  ctx: ModuleContext,
  names: InventoryNames,
): string {
  const { fn } = names;
  const levels = ctx.table("levels");
  const movements = ctx.table("movements");
  const reservations = ctx.table("reservations");
  const lv = columns(ctx, "levels");
  const m = columns(ctx, "movements");
  const r = columns(ctx, "reservations");

  const releaseLevel = (
    variant: string,
    location: string,
    quantity: string,
  ): string =>
    `update ${levels} x set ${lv("reserved")} = greatest(x.${lv("reserved")} - ${quantity}, 0), ${lv("updatedAt")} = now()
  where x.${lv("variant")} = ${variant} and x.${lv("location")} = ${location};`;

  const released = (row: string, reason: string): string =>
    ctx.record({
      type: "reservation.released",
      payload: `jsonb_build_object('organizationId', ${row}tenant, 'id', ${row}id, 'variantId', ${row}variant, 'locationId', ${row}location, 'quantity', ${row}quantity::text, 'reason', '${reason}')`,
      subject: `'stock-reservations/' || ${row}id::text`,
      tenant: `${row}tenant`,
      audit: false,
    });

  return `
-- Holds stock for a cart or an order until expires_at (15 minutes by default).
-- Releases the level's expired reservations first. Returns the reservation id,
-- its expiry and the level's available quantity.
create or replace function ${fn("reserve_stock")}(variant uuid, location uuid, quantity integer, reference_type text, reference_id text, expires_at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_active boolean;
  v_id uuid;
  v_before integer;
  v_after integer;
  v_point integer;
  v_expires timestamptz := coalesce(reserve_stock.expires_at, now() + interval '15 minutes');
begin
  ${loadLocation(ctx, "reserve_stock.location")}
  ${guard(names.scope, names.reserve, "v_tenant")}
  if not v_active then
    ${fail("INVENTORY_LOCATION_INACTIVE", "the location is inactive", "55000")}
  end if;
  ${variantCheck(ctx, "reserve_stock.variant", "v_tenant")}
  if reserve_stock.quantity is null or reserve_stock.quantity <= 0 then
    ${fail("INVENTORY_QUANTITY_INVALID", "the quantity must be a positive whole number", "22023")}
  end if;
  if v_expires <= now() then
    ${fail("INVENTORY_EXPIRY_INVALID", "the reservation must expire in the future", "22023")}
  end if;
  ${ctx.hook("before_stock_reserve", [
    ["uuid", "reserve_stock.variant"],
    ["uuid", "reserve_stock.location"],
    ["integer", "reserve_stock.quantity"],
    ["text", "reserve_stock.reference_type"],
    ["text", "reserve_stock.reference_id"],
  ])}
  ${lockLevel(ctx, "reserve_stock.variant", "reserve_stock.location")}
  with expired as (
    update ${reservations} x set ${r("status")} = 'expired', ${r("updatedAt")} = now()
    where x.${r("variant")} = reserve_stock.variant and x.${r("location")} = reserve_stock.location
      and x.${r("status")} = 'active' and x.${r("expiresAt")} <= now()
    returning x.${r("quantity")} as quantity
  )
  update ${levels} x set ${lv("reserved")} = greatest(x.${lv("reserved")} - (select coalesce(sum(e.quantity), 0)::integer from expired e), 0)
  where x.${lv("variant")} = reserve_stock.variant and x.${lv("location")} = reserve_stock.location;
  select x.${lv("available")}, x.${lv("reorderPoint")} into v_before, v_point from ${levels} x
  where x.${lv("variant")} = reserve_stock.variant and x.${lv("location")} = reserve_stock.location;
  if v_before < reserve_stock.quantity and ${strict(ctx, "reserve_stock.variant")} then
    ${fail("INVENTORY_INSUFFICIENT", "not enough stock available", "23514")}
  end if;
  insert into ${reservations} (${r("tenant")}, ${r("variant")}, ${r("location")}, ${r("quantity")}, ${r("referenceType")}, ${r("referenceId")}, ${r("expiresAt")})
  values (v_tenant, reserve_stock.variant, reserve_stock.location, reserve_stock.quantity, reserve_stock.reference_type, reserve_stock.reference_id, v_expires)
  returning ${r("id")} into v_id;
  update ${levels} x set ${lv("reserved")} = x.${lv("reserved")} + reserve_stock.quantity, ${lv("updatedAt")} = now()
  where x.${lv("variant")} = reserve_stock.variant and x.${lv("location")} = reserve_stock.location
  returning x.${lv("available")} into v_after;
  ${threshold(ctx, {
    tenant: "v_tenant",
    variant: "reserve_stock.variant",
    location: "reserve_stock.location",
    before: "v_before",
    after: "v_after",
    point: "v_point",
  })}
  ${ctx.record({
    type: "reservation.created",
    payload: `jsonb_build_object('organizationId', v_tenant, 'id', v_id, 'variantId', reserve_stock.variant, 'locationId', reserve_stock.location, 'quantity', reserve_stock.quantity::text)`,
    subject: `'stock-reservations/' || v_id::text`,
    tenant: "v_tenant",
    audit: false,
  })}
  ${ctx.hook("after_stock_reserve", [["uuid", "v_id"]])}
  return jsonb_build_object('id', v_id, 'expiresAt', v_expires, 'available', v_after);
end;
$$;
${userGrant(`${fn("reserve_stock")}(uuid, uuid, integer, text, text, timestamptz)`)}

-- Turns an active reservation into a sale: the ledger takes the stock out.
create or replace function ${fn("commit_reservation")}(reservation uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_movement uuid;
begin
  select x.${r("tenant")} as tenant, x.${r("variant")} as variant, x.${r("location")} as location,
    x.${r("quantity")} as quantity, x.${r("status")} as status, x.${r("expiresAt")} as expires_at,
    x.${r("referenceType")} as reference_type, x.${r("referenceId")} as reference_id
  into v_row from ${reservations} x where x.${r("id")} = commit_reservation.reservation for update;
  if not found then
    ${fail("INVENTORY_RESERVATION_NOT_FOUND", "reservation not found", "P0002")}
  end if;
  ${guard(names.scope, names.reserve, "v_row.tenant")}
  if v_row.status <> 'active' then
    ${fail("INVENTORY_RESERVATION_CLOSED", "the reservation is no longer active", "55000")}
  end if;
  if v_row.expires_at <= now() then
    ${fail("INVENTORY_RESERVATION_EXPIRED", "the reservation has expired", "55000")}
  end if;
  ${releaseLevel("v_row.variant", "v_row.location", "v_row.quantity")}
  update ${reservations} x set ${r("status")} = 'committed', ${r("updatedAt")} = now()
  where x.${r("id")} = commit_reservation.reservation;
  insert into ${movements} (${m("tenant")}, ${m("variant")}, ${m("location")}, ${m("quantity")}, ${m("reason")}, ${m("referenceType")}, ${m("referenceId")})
  values (v_row.tenant, v_row.variant, v_row.location, -v_row.quantity, 'sale', v_row.reference_type, v_row.reference_id)
  returning ${m("id")} into v_movement;
  ${ctx.record({
    type: "reservation.committed",
    payload: `jsonb_build_object('organizationId', v_row.tenant, 'id', commit_reservation.reservation, 'variantId', v_row.variant, 'locationId', v_row.location, 'quantity', v_row.quantity::text)`,
    subject: `'stock-reservations/' || commit_reservation.reservation::text`,
    tenant: "v_row.tenant",
    audit: false,
  })}
  return jsonb_build_object('id', commit_reservation.reservation, 'movementId', v_movement);
end;
$$;
${userGrant(`${fn("commit_reservation")}(uuid)`)}

-- Gives an active reservation's stock back. False when it isn't active.
create or replace function ${fn("release_reservation")}(reservation uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
begin
  select x.${r("id")} as id, x.${r("tenant")} as tenant, x.${r("variant")} as variant, x.${r("location")} as location,
    x.${r("quantity")} as quantity, x.${r("status")} as status
  into v_row from ${reservations} x where x.${r("id")} = release_reservation.reservation for update;
  if not found then
    return false;
  end if;
  ${guard(names.scope, names.reserve, "v_row.tenant")}
  if v_row.status <> 'active' then
    return false;
  end if;
  ${releaseLevel("v_row.variant", "v_row.location", "v_row.quantity")}
  update ${reservations} x set ${r("status")} = 'released', ${r("updatedAt")} = now()
  where x.${r("id")} = release_reservation.reservation;
  ${released("v_row.", "released")}
  return true;
end;
$$;
${userGrant(`${fn("release_reservation")}(uuid)`)}

-- Releases active reservations past their expiry, oldest first, up to
-- max_rows. Service only; run it on a schedule. Returns how many it released.
create or replace function ${fn("expire_reservations")}(max_rows integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
begin
  for v_row in
    select x.${r("id")} as id, x.${r("tenant")} as tenant, x.${r("variant")} as variant,
      x.${r("location")} as location, x.${r("quantity")} as quantity
    from ${reservations} x
    where x.${r("status")} = 'active' and x.${r("expiresAt")} <= now()
    order by x.${r("expiresAt")}
    limit greatest(coalesce(expire_reservations.max_rows, 500), 1)
    for update skip locked
  loop
    update ${reservations} x set ${r("status")} = 'expired', ${r("updatedAt")} = now() where x.${r("id")} = v_row.id;
    ${releaseLevel("v_row.variant", "v_row.location", "v_row.quantity")}
    ${released("v_row.", "expired")}
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
${serviceGrant(`${fn("expire_reservations")}(integer)`)}
`;
}
