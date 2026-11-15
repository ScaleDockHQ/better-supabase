import type { BlockSqlContext } from "../context.ts";

import {
  filterAny,
  listBody,
  listDeclare,
  searchPattern,
} from "../list-template.ts";
import { fail, SERVICE_CALLER, userGrant } from "../shared.ts";
import { columns } from "./inventory-stock.ts";
import { OPERATIONS } from "./permissions-model.ts";

/** Days before a lot's expiry date that it counts as `soon`. */
const EXPIRY_SOON_DAYS = 30;

/**
 * The block list contract (ADR 1077) for inventory's three lists: the stock
 * levels, the ledger movements and the lots with stock. Each has a keyset
 * `page_inventory_*` function with `q`, a sort list, array filters, facets and
 * a count, and a `get_inventory_*` read by id.
 */
export function inventoryPages(ctx: BlockSqlContext): string {
  const fn = (name: string): string => ctx.fn(name);

  const lv = columns(ctx, "levels");

  const ledger = ctx.of("ledger");

  const transactions = ledger.table("transactions");

  const tx = (column: string): string => ledger.col("transactions", column);

  const read = ctx.permission("read", OPERATIONS["inventory.read"]);

  const levelStatus = `case when x.${lv("available")} <= 0 then 'out' when x.${lv("reorderPoint")} is not null and x.${lv("available")} <= x.${lv("reorderPoint")} then 'low' else 'in_stock' end`;

  const levelId = `x.${lv("variant")}::text || ':' || x.${lv("location")}::text`;

  const levelIdKey = {
    expr: `(${levelId})`,
    dir: "asc",
    type: "text",
  } as const;

  const levelJson = `jsonb_build_object(
      'id', ${levelId},
      'variantId', x.${lv("variant")},
      'locationId', x.${lv("location")},
      'onHand', x.${lv("onHand")}::text,
      'allocated', x.${lv("reserved")}::text,
      'available', x.${lv("available")}::text,
      'incoming', x.${lv("incoming")}::text,
      'reorderPoint', x.${lv("reorderPoint")}::text,
      'status', ${levelStatus})`;

  const levelPage = {
    name: "page_inventory_levels",
    from: ctx.table("levels"),
    alias: "x",
    where: [
      `x.${lv("tenant")} = page_inventory_levels.tenant`,
      filterAny("status", levelStatus),
      filterAny("variantId", `x.${lv("variant")}`, "uuid"),
      filterAny("locationId", `x.${lv("location")}`, "uuid"),
      `(v_search is null or x.${lv("variant")}::text ilike v_search or x.${lv("location")}::text ilike v_search)`,
    ],
    keys: [
      { expr: `x.${lv("available")}`, dir: "asc", type: "numeric" },
      levelIdKey,
    ],
    sorts: {
      available: [
        { expr: `x.${lv("available")}`, dir: "asc", type: "numeric" },
        levelIdKey,
      ],
      onHand: [
        { expr: `x.${lv("onHand")}`, dir: "desc", type: "numeric" },
        levelIdKey,
      ],
      variantId: [
        { expr: `x.${lv("variant")}::text`, dir: "asc", type: "text" },
        levelIdKey,
      ],
    },
    facets: { status: levelStatus, locationId: `x.${lv("location")}::text` },
    rowJson: levelJson,
    defaultLimit: 50,
    maxLimit: 200,
    invalid: (message: string) => fail("INVENTORY_INVALID", message, "22023"),
  } as const;

  const metadata = (key: string): string => `x.${tx("metadata")} ->> '${key}'`;

  const movementIdKey = {
    expr: `x.${tx("id")}`,
    dir: "asc",
    type: "uuid",
  } as const;

  const newestKeys = [
    { expr: `x.${tx("effectiveAt")}`, dir: "desc", type: "timestamptz" },
    movementIdKey,
  ] as const;

  const movementJson = `jsonb_build_object(
      'id', x.${tx("id")},
      'kind', x.${tx("kind")},
      'variantId', ${metadata("variantId")},
      'locationId', ${metadata("locationId")},
      'binId', ${metadata("binId")},
      'lotId', ${metadata("lotId")},
      'quantity', ${metadata("quantity")},
      'documentType', x.${tx("referenceType")},
      'documentId', x.${tx("referenceId")},
      'effectiveAt', x.${tx("effectiveAt")})`;

  const movementPage = {
    name: "page_inventory_movements",
    from: transactions,
    alias: "x",
    where: [
      `x.${tx("tenant")} = page_inventory_movements.tenant`,
      `x.${tx("kind")} like 'stock.%'`,
      filterAny("kind", `x.${tx("kind")}`),
      filterAny("variantId", metadata("variantId")),
      filterAny("locationId", metadata("locationId")),
      filterAny("binId", metadata("binId")),
      filterAny("lotId", metadata("lotId")),
      filterAny("documentType", `x.${tx("referenceType")}`),
      filterAny("documentId", `x.${tx("referenceId")}`),
      `(v_search is null or x.${tx("kind")} ilike v_search or x.${tx("referenceId")} ilike v_search)`,
    ],
    keys: newestKeys,
    sorts: {
      effectiveAt: newestKeys,
      quantity: [
        {
          expr: `abs(coalesce((${metadata("quantity")})::numeric, 0))`,
          dir: "desc",
          type: "numeric",
        },
        movementIdKey,
      ],
    },
    facets: { kind: `x.${tx("kind")}`, locationId: metadata("locationId") },
    rowJson: movementJson,
    defaultLimit: 50,
    maxLimit: 200,
    invalid: (message: string) => fail("INVENTORY_INVALID", message, "22023"),
  } as const;

  const lots = ctx.hasTable("lots") && ctx.hasTable("buckets");

  const lt = columns(ctx, "lots");

  const k = columns(ctx, "buckets");

  // One row per lot, location and bin that holds stock, with the lot's own
  // columns named `lot_*` so they never collide with the bucket's.
  const lotsFrom = lots
    ? `(select y.*, lo.${lt("id")} as lot_pk, lo.${lt("code")} as lot_code, lo.${lt("variant")} as lot_variant, lo.${lt("expiresOn")} as lot_expires_on from ${ctx.table("buckets")} y join ${ctx.table("lots")} lo on lo.${lt("id")} = y.${k("lot")} where y.${k("onHand")} > 0)`
    : "";

  const lotId = `x.lot_pk::text || ':' || x.${k("location")}::text || ':' || coalesce(x.${k("bin")}::text, '')`;

  const lotExpiry = `case when x.lot_expires_on is null then 'none' when x.lot_expires_on < current_date then 'expired' when x.lot_expires_on <= current_date + ${String(EXPIRY_SOON_DAYS)} then 'soon' else 'later' end`;

  const lotIdKey = { expr: `(${lotId})`, dir: "asc", type: "text" } as const;

  const lotKeys = [
    {
      expr: `coalesce(x.lot_expires_on, date '9999-12-31')`,
      dir: "asc",
      type: "date",
    },
    lotIdKey,
  ] as const;

  const lotRow = `jsonb_build_object('id', ${lotId}, 'lotId', x.lot_pk, 'code', x.lot_code, 'variantId', x.lot_variant, 'locationId', x.${k("location")}, 'binId', x.${k("bin")}, 'expiresOn', x.lot_expires_on, 'onHand', x.${k("onHand")}::text, 'expiry', ${lotExpiry})`;

  const lotPage = {
    name: "page_inventory_lots",
    from: lotsFrom,
    alias: "x",
    where: [
      `x.${k("tenant")} = page_inventory_lots.tenant`,
      filterAny("expiry", lotExpiry),
      filterAny("variantId", "x.lot_variant", "uuid"),
      filterAny("locationId", `x.${k("location")}`, "uuid"),
      `(v_search is null or x.lot_code ilike v_search)`,
    ],
    keys: lotKeys,
    sorts: {
      expiresOn: lotKeys,
      onHand: [
        { expr: `x.${k("onHand")}`, dir: "desc", type: "numeric" },
        lotIdKey,
      ],
      code: [{ expr: `lower(x.lot_code)`, dir: "asc", type: "text" }, lotIdKey],
    },
    facets: { expiry: lotExpiry, locationId: `x.${k("location")}::text` },
    rowJson: lotRow,
    defaultLimit: 50,
    maxLimit: 200,
    invalid: (message: string) => fail("INVENTORY_INVALID", message, "22023"),
  } as const;

  return `${levelFunctions()}${movementFunctions()}${lots ? lotFunctions() : ""}`;

  function levelFunctions(): string {
    return `
-- A keyset page of the organization's stock levels, emptiest first (ADR 1077).
-- Row security decides what the caller sees. filters is { status (in_stock,
-- low, out), variantId, locationId (each a value or a list), search (a variant
-- or location id), sort (available, onHand, variantId), direction, facet,
-- count, limit, after, offset, paged, total, totalCap }.
create or replace function ${fn("page_inventory_levels")}(tenant ${ctx.idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_inventory_levels.filters, '{}'::jsonb);
  v_search text := ${searchPattern()};
  ${listDeclare(levelPage)}
begin
  ${listBody(levelPage)}
end;
$$;
${userGrant(`${fn("page_inventory_levels")}(${ctx.idType}, jsonb)`)}

-- One stock level by id, "variant:location", or INVENTORY_LEVEL_NOT_FOUND when
-- it does not exist or row security hides it.
create or replace function ${fn("get_inventory_level")}(level_id text)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_row jsonb;
begin
  select ${levelJson} into v_row
  from ${ctx.table("levels")} x
  where ${levelId} = get_inventory_level.level_id;
  if v_row is null then
    ${fail("INVENTORY_LEVEL_NOT_FOUND", "no such stock level", "P0002")}
  end if;
  return v_row;
end;
$$;
${userGrant(`${fn("get_inventory_level")}(text)`)}
`;
  }

  function movementFunctions(): string {
    return `
-- A keyset page of the ledger's stock movements, newest first (ADR 1077). Row
-- security decides what the caller sees. filters is { kind, variantId,
-- locationId, binId, lotId, documentType, documentId (each a value or a list),
-- search (the kind or the document id), sort (effectiveAt, quantity),
-- direction, facet, count, limit, after, offset, paged, total, totalCap }.
create or replace function ${fn("page_inventory_movements")}(tenant ${ctx.idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_inventory_movements.filters, '{}'::jsonb);
  v_search text := ${searchPattern()};
  ${listDeclare(movementPage)}
begin
  ${listBody(movementPage)}
end;
$$;
${userGrant(`${fn("page_inventory_movements")}(${ctx.idType}, jsonb)`)}

-- One stock movement by id, or INVENTORY_MOVEMENT_NOT_FOUND when it does not
-- exist or row security hides it.
create or replace function ${fn("get_inventory_movement")}(movement_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_row jsonb;
begin
  select ${movementJson} into v_row
  from ${transactions} x
  where x.${tx("id")} = get_inventory_movement.movement_id
    and x.${tx("kind")} like 'stock.%';
  if v_row is null then
    ${fail("INVENTORY_MOVEMENT_NOT_FOUND", "no such stock movement", "P0002")}
  end if;
  return v_row;
end;
$$;
${userGrant(`${fn("get_inventory_movement")}(uuid)`)}
`;
  }

  function lotFunctions(): string {
    return `
-- A keyset page of the lots that hold stock, one row per lot, location and
-- bin, soonest expiry first (ADR 1077). Needs inventory.read. filters is
-- { expiry (expired, soon, later, none), variantId, locationId (each a value
-- or a list), search (the lot code), sort (expiresOn, onHand, code),
-- direction, facet, count, limit, after, offset, paged, total, totalCap }.
create or replace function ${fn("page_inventory_lots")}(tenant ${ctx.idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_inventory_lots.filters, '{}'::jsonb);
  v_search text := ${searchPattern()};
  ${listDeclare(lotPage)}
begin
  if not (${SERVICE_CALLER} or ${ctx.scope.can("page_inventory_lots.tenant", read)}) then
    ${fail("INVENTORY_FORBIDDEN", "not allowed to read this inventory")}
  end if;
  ${listBody(lotPage)}
end;
$$;
${userGrant(`${fn("page_inventory_lots")}(${ctx.idType}, jsonb)`)}

-- One lot's stock by id, "lot:location:bin" (the bin may be empty), or
-- INVENTORY_LOT_NOT_FOUND when it does not exist or the caller cannot read it.
create or replace function ${fn("get_inventory_lot")}(lot_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row jsonb;
  v_tenant ${ctx.idType};
begin
  select x.${k("tenant")}, ${lotRow} into v_tenant, v_row
  from ${lotsFrom} x
  where ${lotId} = get_inventory_lot.lot_id;
  if v_row is null or not (${SERVICE_CALLER} or ${ctx.scope.can("v_tenant", read)}) then
    ${fail("INVENTORY_LOT_NOT_FOUND", "no such lot with stock", "P0002")}
  end if;
  return v_row;
end;
$$;
${userGrant(`${fn("get_inventory_lot")}(text)`)}
`;
  }
}
