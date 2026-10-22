import type { BlockSqlContext } from "../context.ts";
import type { InventoryNames } from "./inventory-stock.ts";

import { fail, userGrant } from "../shared.ts";
import { columns, guard, moveStock } from "./inventory-stock.ts";

const UUID =
  "'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'";

const COUNT = "'^[1-9][0-9]{0,8}$'";

/**
 * Raises unless `lines` is a non-empty array of objects whose `key` is a uuid
 * (once each) and whose `quantity` is a positive whole number.
 */
function linesCheck(lines: string, key: string, extra = ""): string {
  return `if jsonb_typeof(${lines}) is distinct from 'array' or jsonb_array_length(${lines}) = 0
    or exists (
      select 1 from jsonb_array_elements(${lines}) e
      where jsonb_typeof(e) <> 'object'
        or coalesce(e ->> '${key}', '') !~ ${UUID}
        or coalesce(e ->> 'quantity', '') !~ ${COUNT}${extra}
    )
    or (select count(distinct e ->> '${key}') from jsonb_array_elements(${lines}) e) <> jsonb_array_length(${lines}) then
    ${fail("INVENTORY_LINES_INVALID", `lines must be a non-empty list with a unique ${key} and a positive whole quantity each`, "22023")}
  end if;`;
}

/** Raises unless every line's `variantId` is a variant of the tenant. */
function linesVariantCheck(
  ctx: BlockSqlContext,
  lines: string,
  tenant: string,
): string {
  const catalog = ctx.of("catalog");
  const v = columns(catalog, "variants");

  return `if exists (
    select 1 from jsonb_array_elements(${lines}) e
    where not exists (select 1 from ${catalog.table("variants")} cv where cv.${v("id")} = (e ->> 'variantId')::uuid and cv.${v("tenant")} = ${tenant})
  ) then
    ${fail("INVENTORY_VARIANT_NOT_FOUND", "a line names a variant outside this organization", "P0002")}
  end if;`;
}

export function transferFunctions(
  ctx: BlockSqlContext,
  names: InventoryNames,
): string {
  if (!ctx.hasTable("transfers") || !ctx.hasTable("transferLines")) {
    return "";
  }

  const { fn } = names;
  const transfers = ctx.table("transfers");
  const lines = ctx.table("transferLines");
  const locations = ctx.table("locations");
  const t = columns(ctx, "transfers");
  const tl = columns(ctx, "transferLines");
  const l = columns(ctx, "locations");

  const load = (
    name: string,
  ): string => `select x.${t("tenant")} as tenant, x.${t("from")} as from_location, x.${t("to")} as to_location, x.${t("status")} as status
  into v_row from ${transfers} x where x.${t("id")} = ${name}.transfer for update;
  if not found then
    ${fail("INVENTORY_TRANSFER_NOT_FOUND", "transfer not found", "P0002")}
  end if;
  ${guard(names.scope, names.manage, "v_row.tenant")}`;

  const move = (
    name: string,
    location: string,
    sign: string,
    reason: string,
  ): string =>
    `perform ${moveStock(ctx, { tenant: "v_row.tenant", variant: `x.${tl("variant")}`, location, quantity: `${sign}x.${tl("quantity")}`, reason: `'${reason}'`, referenceType: "'transfer'", referenceId: `${name}.transfer::text` })}
  from ${lines} x where x.${tl("transfer")} = ${name}.transfer;`;

  const event = (type: string, name: string, status: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', v_row.tenant, 'id', ${name}.transfer, 'from', v_row.from_location, 'to', v_row.to_location, 'status', ${status})`,
      subject: `'stock-transfers/' || ${name}.transfer::text`,
      tenant: "v_row.tenant",
      audit: false,
    });

  const statusError = fail(
    "INVENTORY_TRANSFER_STATUS",
    "the transfer can't do this in its current status",
    "55000",
  );

  return `
-- Drafts a transfer of stock between two locations of one organization.
-- lines: [{ "variantId": uuid, "quantity": n }].
create or replace function ${fn("create_transfer")}(tenant ${ctx.idType}, from_location uuid, to_location uuid, lines jsonb, note text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  ${guard(names.scope, names.manage, "create_transfer.tenant")}
  if create_transfer.from_location is not distinct from create_transfer.to_location then
    ${fail("INVENTORY_TRANSFER_SAME_LOCATION", "a transfer needs two different locations", "22023")}
  end if;
  if (select count(*) from ${locations} x where x.${l("id")} in (create_transfer.from_location, create_transfer.to_location) and x.${l("tenant")} = create_transfer.tenant) <> 2 then
    ${fail("INVENTORY_LOCATION_NOT_FOUND", "location not found in this organization", "P0002")}
  end if;
  ${linesCheck("create_transfer.lines", "variantId")}
  ${linesVariantCheck(ctx, "create_transfer.lines", "create_transfer.tenant")}
  insert into ${transfers} (${t("tenant")}, ${t("from")}, ${t("to")}, ${t("note")})
  values (create_transfer.tenant, create_transfer.from_location, create_transfer.to_location, create_transfer.note)
  returning ${t("id")} into v_id;
  insert into ${lines} (${tl("tenant")}, ${tl("transfer")}, ${tl("variant")}, ${tl("quantity")})
  select create_transfer.tenant, v_id, (e ->> 'variantId')::uuid, (e ->> 'quantity')::integer
  from jsonb_array_elements(create_transfer.lines) e;
  return jsonb_build_object('id', v_id, 'status', 'draft');
end;
$$;
${userGrant(`${fn("create_transfer")}(${ctx.idType}, uuid, uuid, jsonb, text)`)}

-- Takes a draft transfer's stock out of its source location.
create or replace function ${fn("ship_transfer")}(transfer uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
begin
  ${load("ship_transfer")}
  if v_row.status <> 'draft' then
    ${statusError}
  end if;
  ${move("ship_transfer", "v_row.from_location", "-", "transfer_out")}
  update ${transfers} x set ${t("status")} = 'in_transit', ${t("shippedAt")} = now() where x.${t("id")} = ship_transfer.transfer;
  ${event("transfer.shipped", "ship_transfer", "'in_transit'")}
  return true;
end;
$$;
${userGrant(`${fn("ship_transfer")}(uuid)`)}

-- Puts an in-transit transfer's stock into its destination.
create or replace function ${fn("receive_transfer")}(transfer uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
begin
  ${load("receive_transfer")}
  if v_row.status <> 'in_transit' then
    ${statusError}
  end if;
  ${move("receive_transfer", "v_row.to_location", "", "transfer_in")}
  update ${transfers} x set ${t("status")} = 'received', ${t("receivedAt")} = now() where x.${t("id")} = receive_transfer.transfer;
  ${event("transfer.received", "receive_transfer", "'received'")}
  return true;
end;
$$;
${userGrant(`${fn("receive_transfer")}(uuid)`)}

-- Cancels a draft or in-transit transfer; in-transit stock goes back to the source.
create or replace function ${fn("cancel_transfer")}(transfer uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
begin
  ${load("cancel_transfer")}
  if v_row.status not in ('draft', 'in_transit') then
    ${statusError}
  end if;
  if v_row.status = 'in_transit' then
    ${move("cancel_transfer", "v_row.from_location", "", "transfer_in")}
  end if;
  update ${transfers} x set ${t("status")} = 'cancelled' where x.${t("id")} = cancel_transfer.transfer;
  ${event("transfer.cancelled", "cancel_transfer", "'cancelled'")}
  return true;
end;
$$;
${userGrant(`${fn("cancel_transfer")}(uuid)`)}
`;
}

export function purchaseOrderFunctions(
  ctx: BlockSqlContext,
  names: InventoryNames,
): string {
  if (!ctx.hasTable("purchaseOrders") || !ctx.hasTable("purchaseOrderLines")) {
    return "";
  }

  const { fn } = names;
  const orders = ctx.table("purchaseOrders");
  const lines = ctx.table("purchaseOrderLines");
  const levels = ctx.table("levels");
  const locations = ctx.table("locations");
  const po = columns(ctx, "purchaseOrders");
  const pl = columns(ctx, "purchaseOrderLines");
  const lv = columns(ctx, "levels");
  const l = columns(ctx, "locations");
  const currencyUnits = ctx.of("catalog").fn("currency_minor_units");

  const load = (
    name: string,
  ): string => `select x.${po("tenant")} as tenant, x.${po("location")} as location, x.${po("status")} as status,
    x.${po("supplierType")} as supplier_type, x.${po("supplierId")} as supplier_id
  into v_row from ${orders} x where x.${po("id")} = ${name}.purchase_order for update;
  if not found then
    ${fail("INVENTORY_PURCHASE_ORDER_NOT_FOUND", "purchase order not found", "P0002")}
  end if;
  ${guard(names.scope, names.purchase, "v_row.tenant")}`;

  const event = (type: string, name: string, status: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', v_row.tenant, 'id', ${name}.purchase_order, 'locationId', v_row.location, 'status', ${status}, 'supplierType', v_row.supplier_type, 'supplierId', v_row.supplier_id)`,
      subject: `'purchase-orders/' || ${name}.purchase_order::text`,
      tenant: "v_row.tenant",
      audit: false,
    });

  const statusError = fail(
    "INVENTORY_PURCHASE_ORDER_STATUS",
    "the purchase order can't do this in its current status",
    "55000",
  );

  return `
-- Creates a draft purchase order (purchase_order null) or replaces a draft's
-- fields and lines. lines: [{ "variantId": uuid, "quantity": n, "unitCost": "minor units" }].
-- supplier_type and supplier_id name a config.records record, or are both null.
create or replace function ${fn("save_purchase_order")}(tenant ${ctx.idType}, purchase_order uuid, location uuid, supplier_type text, supplier_id text, currency text, expected_at timestamptz, lines jsonb, note text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_purchase_order.purchase_order;
begin
  ${guard(names.scope, names.purchase, "save_purchase_order.tenant")}
  if not exists (select 1 from ${locations} x where x.${l("id")} = save_purchase_order.location and x.${l("tenant")} = save_purchase_order.tenant) then
    ${fail("INVENTORY_LOCATION_NOT_FOUND", "location not found in this organization", "P0002")}
  end if;
  if (save_purchase_order.supplier_type is null) <> (save_purchase_order.supplier_id is null) then
    ${fail("INVENTORY_SUPPLIER_INVALID", "supplier_type and supplier_id go together", "22023")}
  end if;
  if save_purchase_order.currency is null or ${currencyUnits}(save_purchase_order.currency) is null then
    ${fail("INVENTORY_CURRENCY_INVALID", "the currency must be an ISO 4217 code", "22023")}
  end if;
  ${linesCheck("save_purchase_order.lines", "variantId", "\n        or coalesce(e ->> 'unitCost', '') !~ '^[0-9]{1,18}$'")}
  ${linesVariantCheck(ctx, "save_purchase_order.lines", "save_purchase_order.tenant")}
  if v_id is null then
    insert into ${orders} (${po("tenant")}, ${po("location")}, ${po("supplierType")}, ${po("supplierId")}, ${po("currency")}, ${po("expectedAt")}, ${po("note")})
    values (save_purchase_order.tenant, save_purchase_order.location, save_purchase_order.supplier_type, save_purchase_order.supplier_id,
      save_purchase_order.currency, save_purchase_order.expected_at, save_purchase_order.note)
    returning ${po("id")} into v_id;
  else
    perform 1 from ${orders} x where x.${po("id")} = v_id and x.${po("tenant")} = save_purchase_order.tenant for update;
    if not found then
      ${fail("INVENTORY_PURCHASE_ORDER_NOT_FOUND", "purchase order not found", "P0002")}
    end if;
    update ${orders} x set ${po("location")} = save_purchase_order.location, ${po("supplierType")} = save_purchase_order.supplier_type,
      ${po("supplierId")} = save_purchase_order.supplier_id, ${po("currency")} = save_purchase_order.currency,
      ${po("expectedAt")} = save_purchase_order.expected_at, ${po("note")} = save_purchase_order.note, ${po("updatedAt")} = now()
    where x.${po("id")} = v_id and x.${po("status")} = 'draft';
    if not found then
      ${fail("INVENTORY_PURCHASE_ORDER_LOCKED", "only a draft purchase order can change", "55000")}
    end if;
    delete from ${lines} x where x.${pl("order")} = v_id;
  end if;
  insert into ${lines} (${pl("tenant")}, ${pl("order")}, ${pl("variant")}, ${pl("quantity")}, ${pl("unitCost")})
  select save_purchase_order.tenant, v_id, (e ->> 'variantId')::uuid, (e ->> 'quantity')::integer, (e ->> 'unitCost')::bigint
  from jsonb_array_elements(save_purchase_order.lines) e;
  return jsonb_build_object('id', v_id, 'status', 'draft');
end;
$$;
${userGrant(`${fn("save_purchase_order")}(${ctx.idType}, uuid, uuid, text, text, text, timestamptz, jsonb, text)`)}

-- Sends a draft purchase order: its quantities count as incoming at its location.
create or replace function ${fn("place_purchase_order")}(purchase_order uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
begin
  ${load("place_purchase_order")}
  if v_row.status <> 'draft' then
    ${statusError}
  end if;
  insert into ${levels} as x (${lv("tenant")}, ${lv("variant")}, ${lv("location")}, ${lv("incoming")})
  select v_row.tenant, y.${pl("variant")}, v_row.location, y.${pl("quantity")}
  from ${lines} y where y.${pl("order")} = place_purchase_order.purchase_order
  on conflict (${lv("variant")}, ${lv("location")}) do update
    set ${lv("incoming")} = x.${lv("incoming")} + excluded.${lv("incoming")}, ${lv("updatedAt")} = now();
  update ${orders} x set ${po("status")} = 'ordered', ${po("placedAt")} = now(), ${po("updatedAt")} = now()
  where x.${po("id")} = place_purchase_order.purchase_order;
  ${event("purchase_order.placed", "place_purchase_order", "'ordered'")}
  return true;
end;
$$;
${userGrant(`${fn("place_purchase_order")}(uuid)`)}

-- Receives some or all of a placed order's lines into stock.
-- lines: [{ "lineId": uuid, "quantity": n }]. Lines left short stay on
-- backorder until a later receipt or a cancel. Returns the new status and
-- the quantity still on backorder.
create or replace function ${fn("receive_purchase_order")}(purchase_order uuid, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_line record;
  v_backordered bigint;
  v_status text;
begin
  ${load("receive_purchase_order")}
  if v_row.status not in ('ordered', 'partially_received') then
    ${statusError}
  end if;
  ${linesCheck("receive_purchase_order.lines", "lineId")}
  for v_line in
    select y.${pl("id")} as id, y.${pl("variant")} as variant, y.${pl("quantity")} as ordered,
      y.${pl("received")} as received, (e ->> 'quantity')::integer as quantity
    from jsonb_array_elements(receive_purchase_order.lines) e
    left join ${lines} y on y.${pl("id")} = (e ->> 'lineId')::uuid and y.${pl("order")} = receive_purchase_order.purchase_order
  loop
    if v_line.id is null then
      ${fail("INVENTORY_LINE_NOT_FOUND", "a line isn't on this purchase order", "P0002")}
    end if;
    if v_line.received + v_line.quantity > v_line.ordered then
      ${fail("INVENTORY_OVER_RECEIPT", "a line would receive more than was ordered", "22023")}
    end if;
    update ${lines} y set ${pl("received")} = y.${pl("received")} + v_line.quantity where y.${pl("id")} = v_line.id;
    update ${levels} x set ${lv("incoming")} = greatest(x.${lv("incoming")} - v_line.quantity, 0), ${lv("updatedAt")} = now()
    where x.${lv("variant")} = v_line.variant and x.${lv("location")} = v_row.location;
    perform ${moveStock(ctx, { tenant: "v_row.tenant", variant: "v_line.variant", location: "v_row.location", quantity: "v_line.quantity", reason: "'receipt'", referenceType: "'purchase_order'", referenceId: "receive_purchase_order.purchase_order::text" })};
  end loop;
  select coalesce(sum(y.${pl("quantity")} - y.${pl("received")}), 0) into v_backordered
  from ${lines} y where y.${pl("order")} = receive_purchase_order.purchase_order;
  v_status := case when v_backordered = 0 then 'received' else 'partially_received' end;
  update ${orders} x set ${po("status")} = v_status, ${po("updatedAt")} = now()
  where x.${po("id")} = receive_purchase_order.purchase_order;
  ${event("purchase_order.received", "receive_purchase_order", "v_status")}
  return jsonb_build_object('status', v_status, 'backordered', v_backordered);
end;
$$;
${userGrant(`${fn("receive_purchase_order")}(uuid, jsonb)`)}

-- Cancels a purchase order that isn't fully received; what's still on
-- backorder stops counting as incoming.
create or replace function ${fn("cancel_purchase_order")}(purchase_order uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
begin
  ${load("cancel_purchase_order")}
  if v_row.status not in ('draft', 'ordered', 'partially_received') then
    ${statusError}
  end if;
  if v_row.status <> 'draft' then
    update ${levels} x set ${lv("incoming")} = greatest(x.${lv("incoming")} - (y.${pl("quantity")} - y.${pl("received")}), 0), ${lv("updatedAt")} = now()
    from ${lines} y
    where y.${pl("order")} = cancel_purchase_order.purchase_order
      and x.${lv("variant")} = y.${pl("variant")} and x.${lv("location")} = v_row.location;
  end if;
  update ${orders} x set ${po("status")} = 'cancelled', ${po("updatedAt")} = now()
  where x.${po("id")} = cancel_purchase_order.purchase_order;
  ${event("purchase_order.cancelled", "cancel_purchase_order", "'cancelled'")}
  return true;
end;
$$;
${userGrant(`${fn("cancel_purchase_order")}(uuid)`)}
`;
}
