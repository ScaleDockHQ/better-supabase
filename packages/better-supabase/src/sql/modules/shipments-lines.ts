import type { BlockSqlContext } from "../context.ts";

import {
  LINE_DIRECTIONS,
  RETURN_DISPOSITIONS,
} from "../../blocks/shipments/statuses.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { fail, userGrant } from "../shared.ts";
import { movementLots } from "./inventory-ledger.ts";
import { columns, locationsOf, moveStock } from "./inventory-stock.ts";
import { asService } from "./orders-shared.ts";
import { lockModuleTable } from "./over-app.ts";
import { moduleOperations } from "./permissions-model.ts";

/** The shipment lines table, for the module's names. */
export const LINES_TABLE = {
  name: "shipment_lines",
  app: {},
  lifecycle: { tenant: "tenant", export: true },
  columns: {
    id: "id",
    tenant: "tenant_id",
    shipment: "shipment_id",
    position: "position",
    direction: "direction",
    variant: "variant_id",
    location: "location_id",
    quantity: "quantity",
    allocation: "allocation_id",
    detail: "detail",
    disposition: "disposition",
    movement: "movement_id",
    movedAt: "moved_at",
    createdAt: "created_at",
  },
  optional: ["allocation"],
} as const;

const list = (values: readonly string[]): string =>
  values.map((value) => sqlString(value)).join(", ");

const QUANTITY = "'^[0-9]{1,14}([.][0-9]{1,6})?$'";

const UUID =
  "'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'";

/** The JSON array of shipment `row`'s lines, in position order. */
export function linesJson(ctx: BlockSqlContext, row: string): string {
  const l = columns(ctx, "lines");

  const allocation = ctx.has("lines", "allocation")
    ? `sl.${l("allocation")}`
    : "null::uuid";

  return `(select coalesce(jsonb_agg(jsonb_build_object('id', sl.${l("id")}, 'position', sl.${l("position")}, 'direction', sl.${l("direction")},
    'variantId', sl.${l("variant")}, 'locationId', sl.${l("location")}, 'quantity', sl.${l("quantity")}::text, 'allocationId', ${allocation},
    'detail', sl.${l("detail")}, 'disposition', sl.${l("disposition")}, 'movementId', sl.${l("movement")}, 'movedAt', sl.${l("movedAt")})
    order by sl.${l("position")}), '[]'::jsonb) from ${ctx.table("lines")} sl where sl.${l("shipment")} = ${row}.${ctx.col("shipments", "id")})`;
}

/**
 * The shipment lines table. Its variant, location and allocation reference the
 * inventory block's tables when it is installed.
 */
export function linesTable(ctx: BlockSqlContext): string {
  const lines = ctx.table("lines");
  const l = columns(ctx, "lines");
  const h = columns(ctx, "shipments");
  const name = ctx.tableName("lines").name;
  const read = ctx.permission("read", moduleOperations("shipments").read);
  const policyName = sqlIdent(`${name}_read`);

  const inventory = ctx.installed("inventory")
    ? ctx.of("inventory")
    : undefined;

  const catalog = inventory?.of("catalog");

  const variantKey =
    catalog === undefined
      ? ""
      : ` references ${catalog.table("variants")} (${catalog.col("variants", "id")}) on delete restrict`;

  const locationKey =
    inventory === undefined
      ? ""
      : ` references ${locationsOf(inventory).table} (${locationsOf(inventory).col("id")}) on delete restrict`;

  const allocation = ctx.has("lines", "allocation")
    ? `\n  ${l("allocation")} uuid${inventory === undefined ? "" : ` references ${inventory.table("allocations")} (${inventory.col("allocations", "id")}) on delete set null`},`
    : "";

  const allocationIndex = ctx.has("lines", "allocation")
    ? `\ncreate index if not exists ${sqlIdent(`${name}_allocation_idx`)} on ${lines} (${l("allocation")});`
    : "";

  return `
-- The stock a shipment carries out, and what comes back. An outbound line
-- leaves stock when the shipment gets its label; a return line comes back
-- with a disposition.
create table if not exists ${lines} (
  ${l("id")} uuid primary key default gen_random_uuid(),
  ${l("tenant")} ${ctx.idType} not null,
  ${l("shipment")} uuid not null references ${ctx.table("shipments")} (${h("id")}) on delete cascade,
  ${l("position")} integer not null check (${l("position")} >= 1),
  ${l("direction")} text not null default 'outbound' check (${l("direction")} in (${list(LINE_DIRECTIONS)})),
  ${l("variant")} uuid not null${variantKey},
  ${l("location")} uuid not null${locationKey},
  ${l("quantity")} numeric(20, 6) not null check (${l("quantity")} > 0),${allocation}
  ${l("detail")} jsonb check (${l("detail")} is null or jsonb_typeof(${l("detail")}) = 'object'),
  ${l("disposition")} text check (${l("disposition")} is null or ${l("disposition")} in (${list(RETURN_DISPOSITIONS)})),
  ${l("movement")} uuid,
  ${l("movedAt")} timestamptz,
  ${l("createdAt")} timestamptz not null default now(),
  check ((${l("direction")} = 'return') = (${l("disposition")} is not null)),
  unique (${l("shipment")}, ${l("position")})
);
create index if not exists ${sqlIdent(`${name}_variant_idx`)} on ${lines} (${l("variant")}, ${l("location")});
create index if not exists ${sqlIdent(`${name}_location_idx`)} on ${lines} (${l("location")});${allocationIndex}
${lockModuleTable(ctx, "lines", { read: true })}
drop policy if exists ${policyName} on ${lines};
${renderPolicy(makePolicy({ table: lines, name: policyName, command: "select", roles: ["authenticated"], using: ctx.scope.check(l("tenant"), read) }), { target: lines })}
`;
}

/**
 * PL/pgSQL that takes the stock of shipment `v_ship`'s outbound lines out:
 * through the line's allocation when it has one, as a `sale` otherwise. Each
 * line keeps the lots it took. The function declares `v_line`, `v_movement` and
 * `v_claims`.
 */
export function shipLines(ctx: BlockSqlContext): string {
  if (!ctx.installed("inventory")) {
    return "";
  }

  const inventory = ctx.of("inventory");
  const l = columns(ctx, "lines");
  const h = columns(ctx, "shipments");
  const hasAllocation = ctx.has("lines", "allocation");

  const allocation = hasAllocation ? `x.${l("allocation")}` : "null::uuid";

  const sale = moveStock(inventory, {
    tenant: `v_ship.${h("tenant")}`,
    variant: "v_line.variant",
    location: "v_line.location",
    quantity: "-v_line.quantity",
    reason: "'sale'",
    referenceType: "'shipment'",
    referenceId: `v_ship.${h("id")}::text`,
    detail: "v_line.detail",
  });

  const move = hasAllocation
    ? `if v_line.allocation is not null then
      ${asService(`v_movement := (${inventory.fn("fulfill_allocation")}(v_line.allocation, v_line.quantity, v_line.detail) ->> 'movementId')::uuid;`)}
    else
      v_movement := ${sale};
    end if;`
    : `v_movement := ${sale};`;

  return `
  for v_line in
    select x.${l("id")} as id, x.${l("variant")} as variant, x.${l("location")} as location, x.${l("quantity")} as quantity,
      x.${l("detail")} as detail, ${allocation} as allocation
    from ${ctx.table("lines")} x
    where x.${l("shipment")} = v_ship.${h("id")} and x.${l("direction")} = 'outbound' and x.${l("movement")} is null
    order by x.${l("position")}
  loop
    ${move}
    update ${ctx.table("lines")} x set ${l("movement")} = v_movement, ${l("movedAt")} = now(),
      ${l("detail")} = jsonb_strip_nulls(coalesce(v_line.detail, '{}'::jsonb) || jsonb_build_object('parts', ${movementLots(inventory, "v_movement")}))
    where x.${l("id")} = v_line.id;
  end loop;`;
}

/**
 * PL/pgSQL that puts the stock of shipment `v_ship`'s shipped outbound lines
 * back, in the lots they took: a cancelled shipment. The function declares
 * `v_line`, `v_part` and `v_claims`.
 */
export function restoreLines(ctx: BlockSqlContext): string {
  if (!ctx.installed("inventory")) {
    return "";
  }

  const inventory = ctx.of("inventory");
  const l = columns(ctx, "lines");
  const h = columns(ctx, "shipments");
  const s = columns(inventory, "serials");
  const hasAllocation = ctx.has("lines", "allocation");
  const allocation = hasAllocation ? `x.${l("allocation")}` : "null::uuid";

  const detail = `jsonb_strip_nulls(jsonb_build_object('lotId', v_part.lot, 'serials', (select jsonb_agg(z.${s("serial")}) from ${inventory.table("serials")} z
          where z.${s("variant")} = v_line.variant and z.${s("serial")} in (select jsonb_array_elements_text(v_line.detail -> 'serials'))
            and z.${s("lot")} is not distinct from v_part.lot)))`;

  const back = moveStock(inventory, {
    tenant: `v_ship.${h("tenant")}`,
    variant: "v_line.variant",
    location: "v_line.location",
    quantity: "v_part.quantity",
    reason: "'return'",
    referenceType: "'shipment'",
    referenceId: `v_ship.${h("id")}::text`,
    detail,
  });

  const move = hasAllocation
    ? `if v_line.allocation is not null then
        ${asService(`perform ${inventory.fn("restore_allocation")}(v_line.allocation, v_part.quantity, ${detail});`)}
      else
        perform ${back};
      end if;`
    : `perform ${back};`;

  return `
  for v_line in
    select x.${l("id")} as id, x.${l("variant")} as variant, x.${l("location")} as location, x.${l("quantity")} as quantity,
      x.${l("detail")} as detail, ${allocation} as allocation
    from ${ctx.table("lines")} x
    where x.${l("shipment")} = v_ship.${h("id")} and x.${l("direction")} = 'outbound' and x.${l("movement")} is not null
  loop
    for v_part in
      select nullif(p ->> 'lotId', '')::uuid as lot, (p ->> 'quantity')::numeric as quantity
      from jsonb_array_elements(coalesce(v_line.detail -> 'parts', jsonb_build_array(jsonb_build_object('quantity', v_line.quantity)))) p
    loop
      ${move}
    end loop;
    update ${ctx.table("lines")} x set ${l("movement")} = null, ${l("movedAt")} = null where x.${l("id")} = v_line.id;
  end loop;`;
}

/**
 * `set_shipment_lines` and `receive_shipment_return`, over the inventory block.
 * `findForWrite` loads `v_ship` for a manager; `shipmentJson` is the shipment's
 * JSON.
 */
export function lineFunctions(
  ctx: BlockSqlContext,
  findForWrite: (arg: string) => string,
  shipmentJson: (row: string) => string,
): string {
  const fn = (name: string): string => ctx.fn(name);
  const lines = ctx.table("lines");
  const l = columns(ctx, "lines");
  const h = columns(ctx, "shipments");

  const inventory = ctx.installed("inventory")
    ? ctx.of("inventory")
    : undefined;

  const st = (row: string, labels: readonly string[], negate = false): string =>
    ctx.is("shipments", "status", `${row}.${h("status")}`, labels, negate);

  const missing = fail(
    "SHIPMENT_INVENTORY_MISSING",
    "install the inventory block to ship stock",
    "22023",
  );

  const linesInvalid = (key: string): string =>
    fail(
      "SHIPMENT_LINES_INVALID",
      `each line needs a variantId, a locationId and a positive quantity${key}`,
      "22023",
    );

  const linesCheck = (input: string, extra: string, hint: string): string =>
    `if jsonb_typeof(${input}) is distinct from 'array' or jsonb_array_length(${input}) > 500 or exists (
    select 1 from jsonb_array_elements(${input}) e
    where jsonb_typeof(e) <> 'object' or coalesce(e ->> 'variantId', '') !~ ${UUID} or coalesce(e ->> 'locationId', '') !~ ${UUID}
      or case when coalesce(e ->> 'quantity', '') ~ ${QUANTITY} then (e ->> 'quantity')::numeric <= 0 else true end
      or (e ? 'detail' and jsonb_typeof(e -> 'detail') <> 'object')${extra}
  ) then
    ${linesInvalid(hint)}
  end if;`;

  if (inventory === undefined) {
    return `
create or replace function ${fn("set_shipment_lines")}(shipment_id uuid, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  ${missing}
end;
$$;
${userGrant(`${fn("set_shipment_lines")}(uuid, jsonb)`)}

create or replace function ${fn("receive_shipment_return")}(shipment_id uuid, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  ${missing}
end;
$$;
${userGrant(`${fn("receive_shipment_return")}(uuid, jsonb)`)}
`;
  }

  const catalog = inventory.of("catalog");
  const v = columns(catalog, "variants");
  const loc = locationsOf(inventory);
  const a = columns(inventory, "allocations");
  const b = columns(inventory, "bins");
  const hasAllocation = ctx.has("lines", "allocation");

  const ownership = (input: string): string => `if exists (
    select 1 from jsonb_array_elements(${input}) e
    where not exists (select 1 from ${catalog.table("variants")} cv where cv.${v("id")} = (e ->> 'variantId')::uuid and cv.${v("tenant")} = v_ship.${h("tenant")})
      or not exists (select 1 from ${loc.table} x where x.${loc.col("id")} = (e ->> 'locationId')::uuid and x.${loc.col("tenant")} = v_ship.${h("tenant")})
  ) then
    ${fail("SHIPMENT_LINE_NOT_FOUND", "a line names a variant or location outside this organization", "P0002")}
  end if;`;

  const allocationCheck = hasAllocation
    ? `
  if exists (
    select 1 from jsonb_array_elements(set_shipment_lines.lines) e
    where e ? 'allocationId' and not exists (
      select 1 from ${inventory.table("allocations")} y
      where y.${a("id")}::text = e ->> 'allocationId' and y.${a("tenant")} = v_ship.${h("tenant")}
        and y.${a("variant")} = (e ->> 'variantId')::uuid and y.${a("location")} = (e ->> 'locationId')::uuid and y.${a("status")} = 'open')
  ) then
    ${fail("SHIPMENT_ALLOCATION_INVALID", "an allocation must be open and hold the line's variant at its location", "22023")}
  end if;`
    : `
  if exists (select 1 from jsonb_array_elements(set_shipment_lines.lines) e where e ? 'allocationId') then
    ${fail("SHIPMENT_ALLOCATION_UNSUPPORTED", "this shipment lines table has no allocation column", "22023")}
  end if;`;

  const position = `coalesce((select max(z.${l("position")}) from ${lines} z where z.${l("shipment")} = v_ship.${h("id")}), 0)`;

  const disposition = (
    row: string,
    reason: string,
    quantity: string,
    detail: string,
  ): string =>
    moveStock(inventory, {
      tenant: `v_ship.${h("tenant")}`,
      variant: `(${row} ->> 'variantId')::uuid`,
      location: `(${row} ->> 'locationId')::uuid`,
      quantity,
      reason,
      referenceType: "'shipment'",
      referenceId: `v_ship.${h("id")}::text`,
      detail,
    });

  const detailOf =
    "case when jsonb_typeof(v_item -> 'detail') = 'object' then v_item -> 'detail' end";

  return `
-- Replaces the outbound lines of a draft shipment: [{ variantId, locationId,
-- quantity, allocationId?, detail? { binId, lotId, serials } }]. The stock
-- leaves when the shipment gets its label.
create or replace function ${fn("set_shipment_lines")}(shipment_id uuid, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ship ${ctx.table("shipments")}%rowtype;
begin
${findForWrite("set_shipment_lines.shipment_id")}
  if ${st("v_ship", ["draft"], true)} then
    ${fail("SHIPMENT_NOT_DRAFT", "only a draft shipment changes its lines", "55000")}
  end if;
  ${linesCheck("set_shipment_lines.lines", ` or (e ? 'allocationId' and coalesce(e ->> 'allocationId', '') !~ ${UUID})`, "")}
  ${ownership("set_shipment_lines.lines")}${allocationCheck}
  delete from ${lines} x where x.${l("shipment")} = v_ship.${h("id")} and x.${l("direction")} = 'outbound';
  insert into ${lines} (${l("tenant")}, ${l("shipment")}, ${l("position")}, ${l("direction")}, ${l("variant")}, ${l("location")}, ${l("quantity")}${hasAllocation ? `, ${l("allocation")}` : ""}, ${l("detail")})
  select v_ship.${h("tenant")}, v_ship.${h("id")}, ${position} + e.n, 'outbound', (e.l ->> 'variantId')::uuid, (e.l ->> 'locationId')::uuid,
    (e.l ->> 'quantity')::numeric${hasAllocation ? ", nullif(e.l ->> 'allocationId', '')::uuid" : ""}, case when jsonb_typeof(e.l -> 'detail') = 'object' then e.l -> 'detail' end
  from jsonb_array_elements(set_shipment_lines.lines) with ordinality e(l, n);
  return ${shipmentJson("v_ship")};
end;
$$;
${userGrant(`${fn("set_shipment_lines")}(uuid, jsonb)`)}

-- Receives stock a recipient sent back on a shipment that left: [{
-- variantId, locationId, quantity, disposition, detail? }]. restock puts it
-- back in stock, hold puts it in the hold bin detail.binId names, and scrap
-- writes it off. A variant comes back at most as often as it went out.
create or replace function ${fn("receive_shipment_return")}(shipment_id uuid, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ship ${ctx.table("shipments")}%rowtype;
  v_item jsonb;
  v_detail jsonb;
  v_movement uuid;
  v_quantity numeric := 0;
  v_count integer := 0;
begin
${findForWrite("receive_shipment_return.shipment_id")}
  if ${st("v_ship", ["draft", "cancelled"])} then
    ${fail("SHIPMENT_NOT_SHIPPED", "only a shipment that left takes returns", "55000")}
  end if;
  ${linesCheck("receive_shipment_return.lines", ` or coalesce(e ->> 'disposition', '') not in (${list(RETURN_DISPOSITIONS)})`, " and a disposition of restock, hold or scrap")}
  if jsonb_array_length(receive_shipment_return.lines) = 0 then
    ${linesInvalid("")}
  end if;
  ${ownership("receive_shipment_return.lines")}
  if exists (
    select 1 from (
      select (e ->> 'variantId')::uuid as variant, sum((e ->> 'quantity')::numeric) as quantity
      from jsonb_array_elements(receive_shipment_return.lines) e group by 1
    ) r
    where r.quantity > coalesce((select sum(case when x.${l("direction")} = 'outbound' then x.${l("quantity")} else -x.${l("quantity")} end)
      from ${lines} x where x.${l("shipment")} = v_ship.${h("id")} and x.${l("variant")} = r.variant
        and (x.${l("direction")} = 'return' or x.${l("movement")} is not null)), 0)
  ) then
    ${fail("SHIPMENT_RETURN_EXCEEDS", "a variant comes back at most as often as the shipment carried it out", "22023")}
  end if;
  for v_item in select e from jsonb_array_elements(receive_shipment_return.lines) e
  loop
    v_detail := ${detailOf};
    if v_item ->> 'disposition' = 'hold' and not exists (
      select 1 from ${inventory.table("bins")} y
      where y.${b("id")}::text = v_detail ->> 'binId' and y.${b("location")} = (v_item ->> 'locationId')::uuid and y.${b("hold")}
    ) then
      ${fail("SHIPMENT_HOLD_BIN_REQUIRED", "a held return goes into a hold bin at its location: pass detail.binId", "22023")}
    end if;
    v_movement := ${disposition("v_item", "'return'", "(v_item ->> 'quantity')::numeric", "v_detail")};
    if v_item ->> 'disposition' = 'scrap' then
      v_movement := ${disposition("v_item", "'scrap'", "-(v_item ->> 'quantity')::numeric", "v_detail")};
    end if;
    v_count := v_count + 1;
    insert into ${lines} (${l("tenant")}, ${l("shipment")}, ${l("position")}, ${l("direction")}, ${l("variant")}, ${l("location")}, ${l("quantity")}, ${l("detail")}, ${l("disposition")}, ${l("movement")}, ${l("movedAt")})
    values (v_ship.${h("tenant")}, v_ship.${h("id")}, ${position} + 1, 'return', (v_item ->> 'variantId')::uuid, (v_item ->> 'locationId')::uuid,
      (v_item ->> 'quantity')::numeric, v_detail, v_item ->> 'disposition', v_movement, now());
    v_quantity := v_quantity + (v_item ->> 'quantity')::numeric;
  end loop;
  ${ctx.record({
    type: "shipment.return_received",
    payload: `jsonb_build_object('organizationId', v_ship.${h("tenant")}::text, 'id', v_ship.${h("id")}, 'lines', v_count, 'quantity', v_quantity::text)`,
    subject: `'shipments/' || v_ship.${h("id")}::text`,
    tenant: `v_ship.${h("tenant")}`,
    audit: {
      category: "data",
      targetType: "shipment",
      recordId: `v_ship.${h("id")}::text`,
      targetLabel: `v_ship.${h("reference")}`,
      summary: sqlString("received a shipment return"),
    },
  })}
  return ${shipmentJson("v_ship")};
end;
$$;
${userGrant(`${fn("receive_shipment_return")}(uuid, jsonb)`)}
`;
}
