import type { BlockSqlContext } from "../context.ts";
import type { InventoryNames } from "./inventory-stock.ts";

import { fail, userGrant } from "../shared.ts";
import {
  columns,
  guard,
  locationsOf,
  moveStock,
  stockHistory,
} from "./inventory-stock.ts";

/**
 * The quantity type of every stock column: up to six decimals, so a variant can
 * count in grams, millilitres or hundredths of a metre (ADR 0127).
 */
export const QUANTITY = "numeric(20, 6)";

/** How a variant's stock is tracked, per `stock_items.tracking`. */
const TRACKING_MODES = ["none", "lot", "serial"] as const;

/** How a variant's stock is valued, per `stock_items.costing`. */
const COSTING_METHODS = ["none", "average"] as const;

/** The states of one serial number. */
const SERIAL_STATUSES = ["in_stock", "out", "scrapped"] as const;

const list = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

/** Inventory's tracking tables, for the module's names. */
export const TRACKING_TABLES = {
  items: {
    name: "stock_items",
    app: {},
    lifecycle: { tenant: "tenant", export: true },
    columns: {
      variant: "variant_id",
      tenant: "tenant_id",
      unit: "unit",
      scale: "scale",
      tracking: "tracking",
      expiry: "tracks_expiry",
      costing: "costing",
      currency: "currency",
      averageCost: "average_cost",
      updatedAt: "updated_at",
    },
  },
  bins: {
    name: "stock_bins",
    app: {},
    lifecycle: { tenant: "tenant", export: true },
    columns: {
      id: "id",
      tenant: "tenant_id",
      location: "location_id",
      code: "code",
      name: "name",
      hold: "hold",
      active: "active",
      createdAt: "created_at",
    },
  },
  lots: {
    name: "stock_lots",
    app: {},
    lifecycle: { tenant: "tenant", export: true },
    columns: {
      id: "id",
      tenant: "tenant_id",
      variant: "variant_id",
      code: "code",
      expiresOn: "expires_on",
      createdAt: "created_at",
    },
  },
  serials: {
    name: "stock_serials",
    app: {},
    lifecycle: { tenant: "tenant", export: true },
    columns: {
      id: "id",
      tenant: "tenant_id",
      variant: "variant_id",
      serial: "serial",
      lot: "lot_id",
      location: "location_id",
      bin: "bin_id",
      status: "status",
      movement: "movement_id",
      updatedAt: "updated_at",
    },
  },
  buckets: {
    name: "stock_buckets",
    app: {},
    lifecycle: { tenant: "tenant", export: true },
    columns: {
      id: "id",
      tenant: "tenant_id",
      variant: "variant_id",
      location: "location_id",
      bin: "bin_id",
      lot: "lot_id",
      onHand: "on_hand",
      updatedAt: "updated_at",
    },
  },
} as const;

/**
 * The tables for units, lots, serials, bins and the stock per bin and lot. A
 * level's stock outside any bin or lot isn't a bucket row: it is on-hand minus
 * the level's buckets, so stock from before version 3 needs no backfill.
 */
export function trackingTables(
  ctx: BlockSqlContext,
  read: (table: string) => string,
  lock: (table: string) => string,
): string {
  const catalog = ctx.of("catalog");
  const variants = `${catalog.table("variants")} (${catalog.col("variants", "id")}) on delete cascade`;
  const loc = locationsOf(ctx);
  const location = `${loc.table} (${loc.col("id")}) on delete cascade`;
  const t = (name: string): string => ctx.table(name);
  const i = columns(ctx, "items");
  const b = columns(ctx, "bins");
  const lt = columns(ctx, "lots");
  const s = columns(ctx, "serials");
  const k = columns(ctx, "buckets");

  return `
create table if not exists ${t("items")} (
  ${i("variant")} uuid primary key references ${variants},
  ${i("tenant")} ${ctx.idType} not null,
  ${i("unit")} text not null default 'item' check (${i("unit")} ~ '^[a-z][a-z0-9_]{0,31}$'),
  ${i("scale")} smallint not null default 0 check (${i("scale")} between 0 and 6),
  ${i("tracking")} text not null default 'none' check (${i("tracking")} in (${list(TRACKING_MODES)})),
  ${i("expiry")} boolean not null default false,
  ${i("costing")} text not null default 'none' check (${i("costing")} in (${list(COSTING_METHODS)})),
  ${i("currency")} char(3) check (${i("currency")} ~ '^[A-Z]{3}$'),
  ${i("averageCost")} numeric(24, 6) check (${i("averageCost")} >= 0),
  ${i("updatedAt")} timestamptz not null default now(),
  check (${i("tracking")} <> 'serial' or ${i("scale")} = 0),
  check (${i("costing")} = 'none' or ${i("currency")} is not null)
);
create index if not exists stock_items_tenant_idx on ${t("items")} (${i("tenant")});
${lock("items")}
${read("items")}

create table if not exists ${t("bins")} (
  ${b("id")} uuid primary key default gen_random_uuid(),
  ${b("tenant")} ${ctx.idType} not null,
  ${b("location")} uuid not null references ${location},
  ${b("code")} text not null check (${b("code")} ~ '^[A-Za-z0-9][A-Za-z0-9_.-]{0,39}$'),
  ${b("name")} text check (length(${b("name")}) between 1 and 200),
  ${b("hold")} boolean not null default false,
  ${b("active")} boolean not null default true,
  ${b("createdAt")} timestamptz not null default now(),
  unique (${b("location")}, ${b("code")})
);
create index if not exists stock_bins_tenant_idx on ${t("bins")} (${b("tenant")});
${lock("bins")}
${read("bins")}

create table if not exists ${t("lots")} (
  ${lt("id")} uuid primary key default gen_random_uuid(),
  ${lt("tenant")} ${ctx.idType} not null,
  ${lt("variant")} uuid not null references ${variants},
  ${lt("code")} text not null check (length(${lt("code")}) between 1 and 100),
  ${lt("expiresOn")} date,
  ${lt("createdAt")} timestamptz not null default now(),
  unique (${lt("variant")}, ${lt("code")})
);
create index if not exists stock_lots_expiry_idx on ${t("lots")} (${lt("tenant")}, ${lt("expiresOn")}) where ${lt("expiresOn")} is not null;
${lock("lots")}
${read("lots")}

create table if not exists ${t("serials")} (
  ${s("id")} uuid primary key default gen_random_uuid(),
  ${s("tenant")} ${ctx.idType} not null,
  ${s("variant")} uuid not null references ${variants},
  ${s("serial")} text not null check (length(${s("serial")}) between 1 and 100),
  ${s("lot")} uuid references ${t("lots")} (${lt("id")}) on delete set null,
  ${s("location")} uuid references ${loc.table} (${loc.col("id")}) on delete set null,
  ${s("bin")} uuid references ${t("bins")} (${b("id")}) on delete set null,
  ${s("status")} text not null default 'in_stock' check (${s("status")} in (${list(SERIAL_STATUSES)})),
  ${s("movement")} uuid,
  ${s("updatedAt")} timestamptz not null default now(),
  unique (${s("variant")}, ${s("serial")})
);
create index if not exists stock_serials_location_id_idx on ${t("serials")} (${s("location")});
create index if not exists stock_serials_bin_idx on ${t("serials")} (${s("bin")});
create index if not exists stock_serials_lot_idx on ${t("serials")} (${s("lot")});
create index if not exists stock_serials_movement_idx on ${t("serials")} (${s("movement")});
create index if not exists stock_serials_tenant_idx on ${t("serials")} (${s("tenant")});
${lock("serials")}
${read("serials")}

create table if not exists ${t("buckets")} (
  ${k("id")} uuid primary key default gen_random_uuid(),
  ${k("tenant")} ${ctx.idType} not null,
  ${k("variant")} uuid not null references ${variants},
  ${k("location")} uuid not null references ${location},
  ${k("bin")} uuid references ${t("bins")} (${b("id")}) on delete restrict,
  ${k("lot")} uuid references ${t("lots")} (${lt("id")}) on delete restrict,
  ${k("onHand")} ${QUANTITY} not null default 0,
  ${k("updatedAt")} timestamptz not null default now(),
  check (${k("bin")} is not null or ${k("lot")} is not null),
  unique nulls not distinct (${k("variant")}, ${k("location")}, ${k("bin")}, ${k("lot")})
);
create index if not exists stock_buckets_location_idx on ${t("buckets")} (${k("location")});
create index if not exists stock_buckets_bin_idx on ${t("buckets")} (${k("bin")});
create index if not exists stock_buckets_lot_idx on ${t("buckets")} (${k("lot")});
create index if not exists stock_buckets_tenant_idx on ${t("buckets")} (${k("tenant")});
${lock("buckets")}
${read("buckets")}
`;
}

/** Loads a variant's tenant into `v_tenant`, raising when it doesn't exist. */
function loadVariant(ctx: BlockSqlContext, variant: string): string {
  const catalog = ctx.of("catalog");
  const v = columns(catalog, "variants");

  return `select cv.${v("tenant")} into v_tenant from ${catalog.table("variants")} cv where cv.${v("id")} = ${variant};
  if v_tenant is null then
    ${fail("INVENTORY_VARIANT_NOT_FOUND", "variant not found", "P0002")}
  end if;`;
}

/** The JSON of stock item row `alias`, or the defaults for `variant`. */
function itemJson(ctx: BlockSqlContext, alias: string): string {
  const i = columns(ctx, "items");

  return `jsonb_build_object('variantId', ${alias}.${i("variant")}, 'unit', ${alias}.${i("unit")}, 'scale', ${alias}.${i("scale")},
    'tracking', ${alias}.${i("tracking")}, 'tracksExpiry', ${alias}.${i("expiry")}, 'costing', ${alias}.${i("costing")},
    'currency', ${alias}.${i("currency")}, 'averageCost', ${alias}.${i("averageCost")}::text)`;
}

export function trackingFunctions(
  ctx: BlockSqlContext,
  names: InventoryNames,
): string {
  const { fn } = names;
  const items = ctx.table("items");
  const bins = ctx.table("bins");
  const lots = ctx.table("lots");
  const buckets = ctx.table("buckets");
  const serials = ctx.table("serials");
  const levels = ctx.table("levels");
  const loc = locationsOf(ctx);
  const l = loc.col;
  const i = columns(ctx, "items");
  const b = columns(ctx, "bins");
  const lt = columns(ctx, "lots");
  const k = columns(ctx, "buckets");
  const s = columns(ctx, "serials");
  const lv = columns(ctx, "levels");
  const currencyUnits = ctx.of("catalog").fn("currency_minor_units");
  const ledger = ctx.of("ledger");
  const la = columns(ledger, "accounts");
  const lb = columns(ledger, "balances");

  return `
-- Sets how a variant's stock is counted: its unit and decimal scale, lot or
-- serial tracking, expiry dates and weighted average costing. Null keeps a
-- setting. The unit, scale, tracking and costing are fixed once the variant
-- has stock history. Returns the item.
create or replace function ${fn("set_stock_item")}(variant uuid, unit text, scale smallint, tracking text, tracks_expiry boolean, costing text, currency text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${ctx.idType};
  v_row ${items}%rowtype;
  v_old ${items}%rowtype;
begin
  ${loadVariant(ctx, "set_stock_item.variant")}
  ${guard(names.scope, names.manage, "v_tenant")}
  select * into v_old from ${items} x where x.${i("variant")} = set_stock_item.variant for update;
  v_row.${i("variant")} := set_stock_item.variant;
  v_row.${i("tenant")} := v_tenant;
  v_row.${i("unit")} := coalesce(set_stock_item.unit, v_old.${i("unit")}, 'item');
  v_row.${i("scale")} := coalesce(set_stock_item.scale, v_old.${i("scale")}, 0);
  v_row.${i("tracking")} := coalesce(set_stock_item.tracking, v_old.${i("tracking")}, 'none');
  v_row.${i("expiry")} := coalesce(set_stock_item.tracks_expiry, v_old.${i("expiry")}, false);
  v_row.${i("costing")} := coalesce(set_stock_item.costing, v_old.${i("costing")}, 'none');
  v_row.${i("currency")} := coalesce(upper(set_stock_item.currency), v_old.${i("currency")});
  v_row.${i("averageCost")} := v_old.${i("averageCost")};
  if v_row.${i("unit")} !~ '^[a-z][a-z0-9_]{0,31}$' then
    ${fail("INVENTORY_UNIT_INVALID", "the unit must be 1 to 32 lowercase letters, digits or underscores", "22023")}
  end if;
  if v_row.${i("scale")} not between 0 and 6 then
    ${fail("INVENTORY_SCALE_INVALID", "the scale must be 0 to 6 decimals", "22023")}
  end if;
  if v_row.${i("tracking")} not in (${list(TRACKING_MODES)}) then
    ${fail("INVENTORY_TRACKING_INVALID", `tracking must be one of ${TRACKING_MODES.join(", ")}`, "22023")}
  end if;
  if v_row.${i("tracking")} = 'serial' and v_row.${i("scale")} <> 0 then
    ${fail("INVENTORY_SCALE_INVALID", "serial tracking counts whole units, so the scale must be 0", "22023")}
  end if;
  if v_row.${i("costing")} not in (${list(COSTING_METHODS)}) then
    ${fail("INVENTORY_COSTING_INVALID", `costing must be one of ${COSTING_METHODS.join(", ")}`, "22023")}
  end if;
  if v_row.${i("costing")} <> 'none' and (v_row.${i("currency")} is null or ${currencyUnits}(v_row.${i("currency")}) is null) then
    ${fail("INVENTORY_CURRENCY_INVALID", "average costing needs an ISO 4217 currency", "22023")}
  end if;
  if (v_row.${i("unit")}, v_row.${i("scale")}, v_row.${i("tracking")}, v_row.${i("costing")}, v_row.${i("currency")})
      is distinct from (coalesce(v_old.${i("unit")}, 'item'), coalesce(v_old.${i("scale")}, 0), coalesce(v_old.${i("tracking")}, 'none'),
        coalesce(v_old.${i("costing")}, 'none'), v_old.${i("currency")})
    and ${stockHistory(ctx, (each) => `${each} = set_stock_item.variant`)} then
    ${fail("INVENTORY_ITEM_LOCKED", "the variant has stock history; its unit, scale, tracking and costing are fixed", "55000")}
  end if;
  v_row.${i("updatedAt")} := now();
  insert into ${items} as x select v_row.*
  on conflict (${i("variant")}) do update set ${i("unit")} = excluded.${i("unit")}, ${i("scale")} = excluded.${i("scale")},
    ${i("tracking")} = excluded.${i("tracking")}, ${i("expiry")} = excluded.${i("expiry")}, ${i("costing")} = excluded.${i("costing")},
    ${i("currency")} = excluded.${i("currency")}, ${i("updatedAt")} = now();
  return ${itemJson(ctx, "v_row")};
end;
$$;
${userGrant(`${fn("set_stock_item")}(uuid, text, smallint, text, boolean, text, text)`)}

-- Creates a bin at a location (bin null) or updates one. Stock in a hold bin
-- counts as held: on hand, but not available to sell.
create or replace function ${fn("save_bin")}(location uuid, bin uuid, code text, name text, hold boolean, active boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${ctx.idType};
  v_id uuid := save_bin.bin;
  v_hold boolean;
  v_was boolean;
begin
  select x.${l("tenant")} into v_tenant from ${loc.table} x where x.${l("id")} = save_bin.location;
  if v_tenant is null then
    ${fail("INVENTORY_LOCATION_NOT_FOUND", "location not found", "P0002")}
  end if;
  ${guard(names.scope, names.manage, "v_tenant")}
  if save_bin.code is null or save_bin.code !~ '^[A-Za-z0-9][A-Za-z0-9_.-]{0,39}$' then
    ${fail("INVENTORY_BIN_CODE_INVALID", "the code must be 1 to 40 letters, digits, dots, dashes or underscores", "22023")}
  end if;
  begin
    if v_id is null then
      insert into ${bins} (${b("tenant")}, ${b("location")}, ${b("code")}, ${b("name")}, ${b("hold")}, ${b("active")})
      values (v_tenant, save_bin.location, save_bin.code, save_bin.name, coalesce(save_bin.hold, false), coalesce(save_bin.active, true))
      returning ${b("id")}, ${b("hold")} into v_id, v_hold;
      v_was := v_hold;
    else
      select x.${b("hold")} into v_was from ${bins} x where x.${b("id")} = v_id and x.${b("location")} = save_bin.location for update;
      if not found then
        ${fail("INVENTORY_BIN_NOT_FOUND", "bin not found at this location", "P0002")}
      end if;
      update ${bins} x set ${b("code")} = save_bin.code, ${b("name")} = save_bin.name,
        ${b("hold")} = coalesce(save_bin.hold, x.${b("hold")}), ${b("active")} = coalesce(save_bin.active, x.${b("active")})
      where x.${b("id")} = v_id
      returning x.${b("hold")} into v_hold;
    end if;
  exception when unique_violation then
    ${fail("INVENTORY_BIN_CODE_TAKEN", "another bin at this location has this code", "23505")}
  end;
  if v_hold <> v_was then
    update ${levels} x set ${lv("held")} = greatest(x.${lv("held")} + case when v_hold then y.on_hand else -y.on_hand end, 0), ${lv("updatedAt")} = now()
    from (select z.${k("variant")} as variant, sum(z.${k("onHand")}) as on_hand from ${buckets} z
      where z.${k("bin")} = v_id and z.${k("onHand")} > 0 group by z.${k("variant")}) y
    where x.${lv("variant")} = y.variant and x.${lv("location")} = save_bin.location;
  end if;
  return jsonb_build_object('id', v_id, 'code', save_bin.code, 'hold', v_hold, 'active', coalesce(save_bin.active, true));
end;
$$;
${userGrant(`${fn("save_bin")}(uuid, uuid, text, text, boolean, boolean)`)}

-- The lot of a variant with this code, created when missing. A given
-- expires_on replaces the stored one.
create or replace function ${fn("stock_lot_for")}(tenant ${ctx.idType}, variant uuid, code text, expires_on date)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
begin
  if stock_lot_for.code is null or length(stock_lot_for.code) not between 1 and 100 then
    ${fail("INVENTORY_LOT_INVALID", "a lot code is 1 to 100 characters", "22023")}
  end if;
  insert into ${lots} as x (${lt("tenant")}, ${lt("variant")}, ${lt("code")}, ${lt("expiresOn")})
  values (stock_lot_for.tenant, stock_lot_for.variant, stock_lot_for.code, stock_lot_for.expires_on)
  on conflict (${lt("variant")}, ${lt("code")}) do update
    set ${lt("expiresOn")} = coalesce(excluded.${lt("expiresOn")}, x.${lt("expiresOn")})
  returning x.${lt("id")} into v_id;
  return v_id;
end;
$$;
revoke execute on function ${fn("stock_lot_for")}(${ctx.idType}, uuid, text, date) from public, anon, authenticated;

-- Creates a lot of a variant or updates its expiry date. Returns the lot.
create or replace function ${fn("save_lot")}(variant uuid, code text, expires_on date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_id uuid;
begin
  ${loadVariant(ctx, "save_lot.variant")}
  ${guard(names.scope, names.manage, "v_tenant")}
  v_id := ${fn("stock_lot_for")}(v_tenant, save_lot.variant, save_lot.code, save_lot.expires_on);
  return (select jsonb_build_object('id', x.${lt("id")}, 'code', x.${lt("code")}, 'expiresOn', x.${lt("expiresOn")})
    from ${lots} x where x.${lt("id")} = v_id);
end;
$$;
${userGrant(`${fn("save_lot")}(uuid, text, date)`)}

-- A variant's stock at a location: the level, each bin and lot bucket, the
-- stock outside any bin or lot, and the serial numbers in stock there.
create or replace function ${fn("stock_detail")}(variant uuid, location uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_level record;
  v_buckets jsonb;
  v_bucketed numeric;
begin
  select x.${l("tenant")} into v_tenant from ${loc.table} x where x.${l("id")} = stock_detail.location;
  if v_tenant is null or not (auth.role() = 'service_role' or ${names.scope.can("v_tenant", names.read)}) then
    ${fail("INVENTORY_LOCATION_NOT_FOUND", "location not found", "P0002")}
  end if;
  select x.${lv("onHand")} as on_hand, x.${lv("reserved")} as reserved, x.${lv("held")} as held, x.${lv("available")} as available
  into v_level from ${levels} x where x.${lv("variant")} = stock_detail.variant and x.${lv("location")} = stock_detail.location;
  select coalesce(jsonb_agg(jsonb_build_object('binId', y.${k("bin")}, 'binCode', bn.${b("code")}, 'hold', coalesce(bn.${b("hold")}, false),
      'lotId', y.${k("lot")}, 'lotCode', lo.${lt("code")}, 'expiresOn', lo.${lt("expiresOn")}, 'onHand', y.${k("onHand")}::text)
      order by lo.${lt("expiresOn")} nulls last, bn.${b("code")} nulls first, lo.${lt("code")}), '[]'::jsonb),
    coalesce(sum(y.${k("onHand")}), 0)
  into v_buckets, v_bucketed
  from ${buckets} y
  left join ${bins} bn on bn.${b("id")} = y.${k("bin")}
  left join ${lots} lo on lo.${lt("id")} = y.${k("lot")}
  where y.${k("variant")} = stock_detail.variant and y.${k("location")} = stock_detail.location and y.${k("onHand")} <> 0;
  return jsonb_build_object('variantId', stock_detail.variant, 'locationId', stock_detail.location,
    'onHand', coalesce(v_level.on_hand, 0)::text, 'reserved', coalesce(v_level.reserved, 0)::text,
    'held', coalesce(v_level.held, 0)::text, 'available', coalesce(v_level.available, 0)::text,
    'unbinned', (coalesce(v_level.on_hand, 0) - v_bucketed)::text, 'buckets', v_buckets,
    'serials', coalesce((select jsonb_agg(z.${s("serial")} order by z.${s("serial")}) from ${serials} z
      where z.${s("variant")} = stock_detail.variant and z.${s("location")} = stock_detail.location and z.${s("status")} = 'in_stock'), '[]'::jsonb));
end;
$$;
${userGrant(`${fn("stock_detail")}(uuid, uuid)`)}

-- The lots with stock that expire on or before a date, soonest first.
create or replace function ${fn("expiring_lots")}(tenant ${ctx.idType}, before date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (auth.role() = 'service_role' or ${names.scope.can("expiring_lots.tenant", names.read)}) then
    ${fail("INVENTORY_FORBIDDEN", "not allowed to read this inventory")}
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('lotId', lo.${lt("id")}, 'code', lo.${lt("code")}, 'variantId', lo.${lt("variant")},
      'locationId', y.${k("location")}, 'binId', y.${k("bin")}, 'expiresOn', lo.${lt("expiresOn")}, 'onHand', y.${k("onHand")}::text)
      order by lo.${lt("expiresOn")}, lo.${lt("code")}, y.${k("location")})
    from ${buckets} y join ${lots} lo on lo.${lt("id")} = y.${k("lot")}
    where y.${k("tenant")} = expiring_lots.tenant and y.${k("onHand")} > 0
      and lo.${lt("expiresOn")} <= coalesce(expiring_lots.before, current_date)), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("expiring_lots")}(${ctx.idType}, date)`)}

-- Writes off the stock of every lot that expired before as_of (today by
-- default) with an expired movement. Returns how many buckets it emptied.
create or replace function ${fn("expire_lots")}(tenant ${ctx.idType}, as_of date)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
begin
  ${guard(names.scope, names.manage, "expire_lots.tenant")}
  for v_row in
    select y.${k("variant")} as variant, y.${k("location")} as location, y.${k("bin")} as bin, y.${k("lot")} as lot, y.${k("onHand")} as on_hand,
      (select array_agg(z.${s("serial")}) from ${serials} z where z.${s("variant")} = y.${k("variant")} and z.${s("lot")} = y.${k("lot")}
        and z.${s("location")} = y.${k("location")} and z.${s("bin")} is not distinct from y.${k("bin")} and z.${s("status")} = 'in_stock') as serials
    from ${buckets} y join ${lots} lo on lo.${lt("id")} = y.${k("lot")}
    where y.${k("tenant")} = expire_lots.tenant and y.${k("onHand")} > 0 and lo.${lt("expiresOn")} < coalesce(expire_lots.as_of, current_date)
    order by lo.${lt("expiresOn")}
    for update of y
  loop
    perform ${moveStock(ctx, {
      tenant: "expire_lots.tenant",
      variant: "v_row.variant",
      location: "v_row.location",
      quantity: "-v_row.on_hand",
      reason: "'expired'",
      referenceType: "'stock_lot'",
      referenceId: "v_row.lot::text",
      detail:
        "jsonb_strip_nulls(jsonb_build_object('binId', v_row.bin, 'lotId', v_row.lot, 'serials', to_jsonb(v_row.serials)))",
    })};
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
${userGrant(`${fn("expire_lots")}(${ctx.idType}, date)`)}

-- A variant's weighted average cost, its stock across locations and the value
-- of that stock in minor units of the cost currency.
create or replace function ${fn("stock_valuation")}(variant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_item record;
begin
  ${loadVariant(ctx, "stock_valuation.variant")}
  if not (auth.role() = 'service_role' or ${names.scope.can("v_tenant", names.read)}) then
    ${fail("INVENTORY_FORBIDDEN", "not allowed to read this inventory")}
  end if;
  select x.${i("costing")} as costing, x.${i("currency")} as currency, x.${i("averageCost")} as average_cost
  into v_item from ${items} x where x.${i("variant")} = stock_valuation.variant;
  return jsonb_build_object('variantId', stock_valuation.variant, 'costing', coalesce(v_item.costing, 'none'),
    'currency', v_item.currency, 'averageCost', v_item.average_cost::text,
    'onHand', (select coalesce(sum(x.${lv("onHand")}), 0) from ${levels} x where x.${lv("variant")} = stock_valuation.variant)::text,
    'value', coalesce((select y.${lb("balance")} from ${ledger.table("accounts")} a join ${ledger.table("balances")} y on y.${lb("account")} = a.${la("id")}
      where a.${la("tenant")} = v_tenant and a.${la("code")} = 'stock_value:' || stock_valuation.variant::text), 0)::text);
end;
$$;
${userGrant(`${fn("stock_valuation")}(uuid)`)}
`;
}
