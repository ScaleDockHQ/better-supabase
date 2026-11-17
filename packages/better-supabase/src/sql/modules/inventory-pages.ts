import type { BlockSqlContext } from "../context.ts";
import type { ListSortKey, ListTemplateOptions } from "../list-template.ts";

import {
  filterAny,
  listBody,
  listDeclare,
  searchPattern,
} from "../list-template.ts";
import { fail, SERVICE_CALLER, userGrant } from "../shared.ts";
import { columns, locationsOf } from "./inventory-stock.ts";
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

  const catalog = ctx.of("catalog");

  const vr = columns(catalog, "variants");

  const productOf = `(select v.${vr("product")} from ${catalog.table("variants")} v where v.${vr("id")}::text = ${metadata("variantId")})`;

  const movementJson = `jsonb_build_object(
      'id', x.${tx("id")},
      'kind', x.${tx("kind")},
      'variantId', ${metadata("variantId")},
      'productId', ${productOf},
      'locationId', ${metadata("locationId")},
      'binId', ${metadata("binId")},
      'lotId', ${metadata("lotId")},
      'quantity', ${metadata("quantity")},
      'unit', ${metadata("unit")},
      'reason', ${metadata("reason")},
      'note', ${ledger.has("transactions", "memo") ? `x.${tx("memo")}` : "null::text"},
      'actorId', x.${tx("actor")},
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
      filterAny("productId", productOf),
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

  // The lookup lists: the locations, the bins and the catalog variants a page
  // names or selects. Row security decides what the caller sees.
  const loc = locationsOf(ctx);

  const locationIdKey = {
    expr: `x.${loc.col("id")}`,
    dir: "asc",
    type: "uuid",
  } as const;

  const locationSort = (column: string): readonly ListSortKey[] => [
    { expr: `x.${loc.col(column)}`, dir: "asc", type: "text" },
    locationIdKey,
  ];

  const locationJson = `jsonb_build_object('id', x.${loc.col("id")}, 'code', x.${loc.col("code")}, 'name', x.${loc.col("name")}, 'kind', x.${loc.col("kind")}, 'active', ${loc.active("x")})`;

  const locationPage = {
    name: "page_stock_locations",
    from: loc.table,
    alias: "x",
    where: [
      `x.${loc.col("tenant")} = page_stock_locations.tenant`,
      filterAny("kind", `x.${loc.col("kind")}`),
      filterAny("active", `${loc.active("x")}::text`),
      `(v_search is null or x.${loc.col("code")} ilike v_search or x.${loc.col("name")} ilike v_search)`,
    ],
    keys: locationSort("code"),
    sorts: { code: locationSort("code"), name: locationSort("name") },
    facets: {
      kind: `x.${loc.col("kind")}`,
      active: `${loc.active("x")}::text`,
    },
    rowJson: locationJson,
    defaultLimit: 50,
    maxLimit: 200,
    invalid: (message: string) => fail("INVENTORY_INVALID", message, "22023"),
  } as const;

  const bins = ctx.hasTable("bins");

  const bn = columns(ctx, "bins");

  const binSort = (column: string): readonly ListSortKey[] => [
    { expr: `x.${bn(column)}`, dir: "asc", type: "text" },
    { expr: `x.${bn("id")}`, dir: "asc", type: "uuid" },
  ];

  const binJson = `jsonb_build_object('id', x.${bn("id")}, 'locationId', x.${bn("location")}, 'code', x.${bn("code")}, 'name', x.${bn("name")}, 'hold', x.${bn("hold")}, 'active', x.${bn("active")})`;

  const binPage = {
    name: "page_stock_bins",
    from: bins ? ctx.table("bins") : "",
    alias: "x",
    where: [
      `x.${bn("tenant")} = page_stock_bins.tenant`,
      filterAny("locationId", `x.${bn("location")}`, "uuid"),
      filterAny("active", `x.${bn("active")}::text`),
      filterAny("hold", `x.${bn("hold")}::text`),
      `(v_search is null or x.${bn("code")} ilike v_search or coalesce(x.${bn("name")}, '') ilike v_search)`,
    ],
    keys: binSort("code"),
    sorts: { code: binSort("code") },
    facets: {
      locationId: `x.${bn("location")}::text`,
      active: `x.${bn("active")}::text`,
    },
    rowJson: binJson,
    defaultLimit: 50,
    maxLimit: 200,
    invalid: (message: string) => fail("INVENTORY_INVALID", message, "22023"),
  } as const;

  const variantSort = (column: string): readonly ListSortKey[] => [
    { expr: `x.${vr(column)}`, dir: "asc", type: "text" },
    { expr: `x.${vr("id")}`, dir: "asc", type: "uuid" },
  ];

  const variantPage = {
    name: "page_stock_variants",
    from: catalog.table("variants"),
    alias: "x",
    where: [
      `x.${vr("tenant")} = page_stock_variants.tenant`,
      filterAny("productId", `x.${vr("product")}`, "uuid"),
      `(v_search is null or x.${vr("sku")} ilike v_search or coalesce(x.${vr("title")}, '') ilike v_search)`,
    ],
    keys: variantSort("sku"),
    sorts: { sku: variantSort("sku"), title: variantSort("title") },
    facets: {},
    rowJson: `jsonb_build_object('id', x.${vr("id")}, 'productId', x.${vr("product")}, 'sku', x.${vr("sku")}, 'title', x.${vr("title")})`,
    defaultLimit: 50,
    maxLimit: 200,
    invalid: (message: string) => fail("INVENTORY_INVALID", message, "22023"),
  } as const;

  return `${levelFunctions()}${movementFunctions()}${lots ? lotFunctions() : ""}${lookupFunctions()}`;

  function lookupFunctions(): string {
    const page = (
      name: string,
      what: string,
      filters: string,
      options: ListTemplateOptions,
    ): string => `
-- ${what} (ADR 1077). Row security decides what the caller sees. filters is
-- { ${filters}, search, sort, direction, facet, count, limit, after, offset,
-- paged, total, totalCap }.
create or replace function ${fn(name)}(tenant ${ctx.idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(${name}.filters, '{}'::jsonb);
  v_search text := ${searchPattern()};
  ${listDeclare(options)}
begin
  ${listBody(options)}
end;
$$;
${userGrant(`${fn(name)}(${ctx.idType}, jsonb)`)}
`;

    return `${page(
      "page_stock_locations",
      "A keyset page of the stock locations, by code",
      "kind (warehouse, store, virtual), active (true, false), each a value or a list; search (the code or name); sort (code, name)",
      locationPage,
    )}${
      bins
        ? page(
            "page_stock_bins",
            "A keyset page of the bins, by code",
            "locationId, active, hold, each a value or a list; search (the code or name); sort (code)",
            binPage,
          )
        : ""
    }${page(
      "page_stock_variants",
      "A keyset page of the catalog variants stock is kept for, by SKU",
      "productId (a value or a list); search (the SKU or title); sort (sku, title)",
      variantPage,
    )}`;
  }

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
-- productId, locationId, binId, lotId, documentType, documentId (each a value
-- or a list), search (the kind or the document id), sort (effectiveAt,
-- quantity), direction, facet, count, limit, after, offset, paged, total,
-- totalCap }.
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
