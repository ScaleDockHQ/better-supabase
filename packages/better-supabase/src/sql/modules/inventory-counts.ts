import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";
import type { ImportTargetContribution } from "../contributions.ts";
import type { InventoryNames } from "./inventory-stock.ts";

import { fail, serviceGrant, userGrant } from "../shared.ts";
import { columns, guard, locationsOf, moveStock } from "./inventory-stock.ts";
import { QUANTITY } from "./inventory-tracking.ts";

/** The states of a stock count document. */
const COUNT_STATUSES = ["open", "posted", "cancelled"] as const;

const NO_ID = "'00000000-0000-4000-8000-000000000000'::uuid";

/** The count tables, for the module's names. */
export const COUNT_TABLES = {
  counts: {
    name: "stock_counts",
    app: {},
    optionalTable: true,
    lifecycle: { tenant: "tenant", export: true },
    columns: {
      id: "id",
      tenant: "tenant_id",
      location: "location_id",
      status: "status",
      note: "note",
      openedBy: "opened_by",
      postedBy: "posted_by",
      openedAt: "opened_at",
      postedAt: "posted_at",
      updatedAt: "updated_at",
    },
    typed: ["status"],
  },
  countLines: {
    name: "stock_count_lines",
    app: {},
    optionalTable: true,
    lifecycle: { tenant: "tenant", export: true },
    columns: {
      id: "id",
      tenant: "tenant_id",
      count: "count_id",
      variant: "variant_id",
      bin: "bin_id",
      lot: "lot_id",
      serial: "serial",
      expected: "expected",
      counted: "counted",
      variance: "variance",
      movement: "movement_id",
      updatedAt: "updated_at",
    },
  },
} as const;

/** Whether the module has the count tables (managed, or mapped on adopted). */
function countsOn(ctx: BlockSqlContext): boolean {
  return (
    ctx.hasTable("counts") &&
    ctx.hasTable("countLines") &&
    (ctx.manages || !ctx.owns("counts"))
  );
}

/** The `stock_counts` and `stock_count_lines` tables (managed mode). */
export function countTables(
  ctx: BlockSqlContext,
  read: (table: string) => string,
  lock: (table: string) => string,
): string {
  if (!ctx.manages || !countsOn(ctx)) {
    return "";
  }

  const catalog = ctx.of("catalog");
  const loc = locationsOf(ctx);
  const c = columns(ctx, "counts");
  const n = columns(ctx, "countLines");
  const t = (name: string): string => ctx.table(name);

  return `
-- A stock count: the stock of one location, counted line by line. Posting it
-- writes each line's variance to the ledger as one 'count' movement.
create table if not exists ${t("counts")} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${ctx.idType} not null,
  ${c("location")} uuid not null references ${loc.table} (${loc.col("id")}) on delete cascade,
  ${c("status")} text not null default 'open' check (${c("status")} in (${COUNT_STATUSES.map((value) => `'${value}'`).join(", ")})),
  ${c("note")} text,
  ${c("openedBy")} uuid default auth.uid(),
  ${c("postedBy")} uuid,
  ${c("openedAt")} timestamptz not null default now(),
  ${c("postedAt")} timestamptz,
  ${c("updatedAt")} timestamptz not null default now()
);
create index if not exists ${ctx.naming.rename("stock_counts_location_idx")} on ${t("counts")} (${c("location")});
create index if not exists ${ctx.naming.rename("stock_counts_status_idx")} on ${t("counts")} (${c("tenant")}, ${c("status")});
${lock("counts")}
${read("counts")}

-- One counted position: a variant in a bin, a lot or neither, or one serial
-- number. expected is the stock when the line was opened; variance is
-- counted minus expected and stays null until the line is counted.
create table if not exists ${t("countLines")} (
  ${n("id")} uuid primary key default gen_random_uuid(),
  ${n("tenant")} ${ctx.idType} not null,
  ${n("count")} uuid not null references ${t("counts")} (${c("id")}) on delete cascade,
  ${n("variant")} uuid not null references ${catalog.table("variants")} (${catalog.col("variants", "id")}) on delete cascade,
  ${n("bin")} uuid references ${t("bins")} (${columns(ctx, "bins")("id")}) on delete restrict,
  ${n("lot")} uuid references ${t("lots")} (${columns(ctx, "lots")("id")}) on delete restrict,
  ${n("serial")} text check (length(${n("serial")}) between 1 and 100),
  ${n("expected")} ${QUANTITY} not null default 0 check (${n("expected")} >= 0),
  ${n("counted")} ${QUANTITY} check (${n("counted")} >= 0),
  ${n("variance")} ${QUANTITY} generated always as (${n("counted")} - ${n("expected")}) stored,
  ${n("movement")} uuid,
  ${n("updatedAt")} timestamptz not null default now()
);
create unique index if not exists ${ctx.naming.rename("stock_count_lines_key")} on ${t("countLines")} (${n("count")}, ${n("variant")}, coalesce(${n("bin")}, ${NO_ID}), coalesce(${n("lot")}, ${NO_ID}), coalesce(${n("serial")}, ''));
create index if not exists ${ctx.naming.rename("stock_count_lines_variant_idx")} on ${t("countLines")} (${n("variant")});
create index if not exists ${ctx.naming.rename("stock_count_lines_bin_idx")} on ${t("countLines")} (${n("bin")}) where ${n("bin")} is not null;
create index if not exists ${ctx.naming.rename("stock_count_lines_lot_idx")} on ${t("countLines")} (${n("lot")}) where ${n("lot")} is not null;
${lock("countLines")}
${read("countLines")}
`;
}

function helperFunctions(ctx: BlockSqlContext, names: InventoryNames): string {
  const { fn } = names;
  const levels = ctx.table("levels");
  const buckets = ctx.table("buckets");
  const serials = ctx.table("serials");
  const lv = columns(ctx, "levels");
  const k = columns(ctx, "buckets");
  const s = columns(ctx, "serials");

  return `
-- What the books say is at a position now: a serial number counts 1 when it is
-- in stock at the location; a bin or lot is that bucket; neither is the level's
-- stock outside any bin or lot.
create or replace function ${fn("count_expected")}(variant uuid, location uuid, bin uuid, lot uuid, serial text)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when $5 is not null then
      (select count(*) from ${serials} y where y.${s("variant")} = $1 and y.${s("serial")} = $5 and y.${s("location")} = $2 and y.${s("status")} = 'in_stock')::numeric
    when $3 is null and $4 is null then
      coalesce((select x.${lv("onHand")} from ${levels} x where x.${lv("variant")} = $1 and x.${lv("location")} = $2), 0)
        - coalesce((select sum(y.${k("onHand")}) from ${buckets} y where y.${k("variant")} = $1 and y.${k("location")} = $2), 0)
    else
      coalesce((select y.${k("onHand")} from ${buckets} y where y.${k("variant")} = $1 and y.${k("location")} = $2
        and y.${k("bin")} is not distinct from $3 and y.${k("lot")} is not distinct from $4), 0)
  end
$$;
revoke execute on function ${fn("count_expected")}(uuid, uuid, uuid, uuid, text) from public, anon, authenticated;
`;
}

/** The count, line and posting functions. */
export function countFunctions(
  ctx: BlockSqlContext,
  names: InventoryNames,
): string {
  if (!countsOn(ctx)) {
    return "";
  }

  const { fn } = names;
  const loc = locationsOf(ctx);
  const counts = ctx.table("counts");
  const lines = ctx.table("countLines");
  const levels = ctx.table("levels");
  const buckets = ctx.table("buckets");
  const serials = ctx.table("serials");
  const items = ctx.table("items");
  const l = loc.col;
  const c = columns(ctx, "counts");
  const n = columns(ctx, "countLines");
  const lv = columns(ctx, "levels");
  const k = columns(ctx, "buckets");
  const s = columns(ctx, "serials");
  const i = columns(ctx, "items");
  const catalog = ctx.of("catalog");
  const v = columns(catalog, "variants");

  const serialTracked = (variant: string): string =>
    `exists (select 1 from ${items} q where q.${i("variant")} = ${variant} and q.${i("tracking")} = 'serial')`;

  return `${helperFunctions(ctx, names)}
-- Opens a count of a location and snapshots its stock into lines: each bin and
-- lot bucket, the stock outside any bin or lot, and each serial number in stock.
-- attrs: { note?, variantIds? } counts only those variants. A line starts with
-- no counted quantity. Returns the count's id and its number of lines.
create or replace function ${fn("open_stock_count")}(tenant ${ctx.idType}, location uuid, attrs jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_attrs jsonb := coalesce(open_stock_count.attrs, '{}'::jsonb);
  v_variants uuid[];
  v_id uuid;
  v_lines integer;
begin
  ${guard(names.scope, names.manage, "open_stock_count.tenant")}
  if not exists (select 1 from ${loc.table} x where x.${l("id")} = open_stock_count.location and x.${l("tenant")} = open_stock_count.tenant) then
    ${fail("INVENTORY_LOCATION_NOT_FOUND", "location not found", "P0002")}
  end if;
  begin
    if jsonb_typeof(v_attrs -> 'variantIds') = 'array' then
      v_variants := array(select jsonb_array_elements_text(v_attrs -> 'variantIds'))::uuid[];
    end if;
  exception when invalid_text_representation then
    ${fail("INVENTORY_COUNT_INVALID", "variantIds is a list of uuids", "22023")}
  end;
  insert into ${counts} as x (${c("tenant")}, ${c("location")}, ${c("note")})
  values (open_stock_count.tenant, open_stock_count.location, nullif(btrim(v_attrs ->> 'note'), ''))
  returning x.${c("id")} into v_id;
  insert into ${lines} (${n("tenant")}, ${n("count")}, ${n("variant")}, ${n("bin")}, ${n("lot")}, ${n("serial")}, ${n("expected")})
  select open_stock_count.tenant, v_id, p.variant, p.bin, p.lot, p.serial, p.expected
  from (
    select y.${k("variant")} as variant, y.${k("bin")} as bin, y.${k("lot")} as lot, null::text as serial, y.${k("onHand")} as expected
    from ${buckets} y
    where y.${k("location")} = open_stock_count.location and y.${k("tenant")} = open_stock_count.tenant and y.${k("onHand")} > 0
      and not ${serialTracked(`y.${k("variant")}`)}
    union all
    select x.${lv("variant")}, null, null, null,
      x.${lv("onHand")} - coalesce((select sum(y.${k("onHand")}) from ${buckets} y where y.${k("variant")} = x.${lv("variant")} and y.${k("location")} = x.${lv("location")}), 0)
    from ${levels} x
    where x.${lv("location")} = open_stock_count.location and x.${lv("tenant")} = open_stock_count.tenant
      and not ${serialTracked(`x.${lv("variant")}`)}
    union all
    select z.${s("variant")}, z.${s("bin")}, z.${s("lot")}, z.${s("serial")}, 1
    from ${serials} z
    where z.${s("location")} = open_stock_count.location and z.${s("tenant")} = open_stock_count.tenant and z.${s("status")} = 'in_stock'
  ) p
  where (v_variants is null or p.variant = any (v_variants)) and p.expected > 0
  on conflict do nothing;
  get diagnostics v_lines = row_count;
  return jsonb_build_object('id', v_id, 'lines', v_lines);
end;
$$;
${userGrant(`${fn("open_stock_count")}(${ctx.idType}, uuid, jsonb)`)}

-- Records what was counted at a position of an open count. attrs: { variantId,
-- binId?, lotId?, serial?, counted }. A position that isn't a line yet (stock
-- the books don't know of) becomes one, with expected taken from the stock now.
-- A serial number is counted 0 or 1. Returns the line's id, expected, counted
-- and variance.
create or replace function ${fn("record_count_line")}(count uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_attrs jsonb := coalesce(record_count_line.attrs, '{}'::jsonb);
  v_count record;
  v_variant uuid;
  v_bin uuid;
  v_lot uuid;
  v_serial text := nullif(btrim(v_attrs ->> 'serial'), '');
  v_counted numeric;
  v_row record;
begin
  select x.${c("tenant")} as tenant, x.${c("location")} as location, x.${c("status")} as status into v_count
  from ${counts} x where x.${c("id")} = record_count_line.count for update;
  if not found then
    ${fail("INVENTORY_COUNT_NOT_FOUND", "stock count not found", "P0002")}
  end if;
  ${guard(names.scope, names.manage, "v_count.tenant")}
  if v_count.status <> 'open' then
    ${fail("INVENTORY_COUNT_CLOSED", "a posted or cancelled count takes no more lines", "22023")}
  end if;
  begin
    v_variant := (v_attrs ->> 'variantId')::uuid;
    v_bin := nullif(v_attrs ->> 'binId', '')::uuid;
    v_lot := nullif(v_attrs ->> 'lotId', '')::uuid;
    v_counted := (v_attrs ->> 'counted')::numeric;
  exception when invalid_text_representation or numeric_value_out_of_range then
    ${fail("INVENTORY_COUNT_INVALID", "variantId, binId and lotId are uuids and counted is a number", "22023")}
  end;
  if v_variant is null or v_counted is null or v_counted < 0 then
    ${fail("INVENTORY_COUNT_INVALID", "a line needs a variantId and a counted quantity of zero or more", "22023")}
  end if;
  if not exists (select 1 from ${catalog.table("variants")} cv where cv.${v("id")} = v_variant and cv.${v("tenant")} = v_count.tenant) then
    ${fail("INVENTORY_VARIANT_NOT_FOUND", "variant not found in this organization", "P0002")}
  end if;
  if ${serialTracked("v_variant")} and (v_serial is null or v_counted not in (0, 1)) then
    ${fail("INVENTORY_COUNT_INVALID", "a serial-tracked variant is counted per serial number, 0 or 1", "22023")}
  end if;
  if v_serial is not null and (v_counted not in (0, 1) or v_bin is not null or v_lot is not null) then
    ${fail("INVENTORY_COUNT_INVALID", "a serial number is counted 0 or 1, without a bin or lot", "22023")}
  end if;
  if v_bin is not null and not exists (select 1 from ${ctx.table("bins")} b where b.${columns(ctx, "bins")("id")} = v_bin and b.${columns(ctx, "bins")("location")} = v_count.location) then
    ${fail("INVENTORY_BIN_NOT_FOUND", "the bin isn't at this location", "P0002")}
  end if;
  if v_lot is not null and not exists (select 1 from ${ctx.table("lots")} b where b.${columns(ctx, "lots")("id")} = v_lot and b.${columns(ctx, "lots")("variant")} = v_variant) then
    ${fail("INVENTORY_LOT_NOT_FOUND", "the lot isn't a lot of this variant", "P0002")}
  end if;
  insert into ${lines} as x (${n("tenant")}, ${n("count")}, ${n("variant")}, ${n("bin")}, ${n("lot")}, ${n("serial")}, ${n("expected")}, ${n("counted")})
  values (v_count.tenant, record_count_line.count, v_variant, v_bin, v_lot, v_serial,
    ${fn("count_expected")}(v_variant, v_count.location, v_bin, v_lot, v_serial), v_counted)
  on conflict (${n("count")}, ${n("variant")}, coalesce(${n("bin")}, ${NO_ID}), coalesce(${n("lot")}, ${NO_ID}), coalesce(${n("serial")}, '')) do update
    set ${n("counted")} = excluded.${n("counted")}, ${n("updatedAt")} = now()
  returning x.${n("id")}, x.${n("expected")}, x.${n("counted")}, x.${n("variance")} into v_row;
  update ${counts} x set ${c("updatedAt")} = now() where x.${c("id")} = record_count_line.count;
  return jsonb_build_object('id', v_row.${n("id")}, 'expected', v_row.${n("expected")}::text, 'counted', v_row.${n("counted")}::text, 'variance', v_row.${n("variance")}::text);
end;
$$;
${userGrant(`${fn("record_count_line")}(uuid, jsonb)`)}

-- Posts an open count: each counted line with a variance becomes one 'count'
-- movement of that variance (counted minus the snapshot, so stock that moved
-- since the snapshot stays), referenced to the count. Lines not counted post
-- nothing. A second call changes nothing and returns posted: false. Returns the
-- number of movements and the sum of the absolute variances.
create or replace function ${fn("post_stock_count")}(count uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count record;
  v_line record;
  v_movement uuid;
  v_moves integer := 0;
  v_total numeric := 0;
begin
  select x.${c("tenant")} as tenant, x.${c("location")} as location, x.${c("status")} as status, x.${c("note")} as note into v_count
  from ${counts} x where x.${c("id")} = post_stock_count.count for update;
  if not found then
    ${fail("INVENTORY_COUNT_NOT_FOUND", "stock count not found", "P0002")}
  end if;
  ${guard(names.scope, names.manage, "v_count.tenant")}
  if v_count.status = 'posted' then
    return jsonb_build_object('posted', false, 'movements', (select count(*) from ${lines} y where y.${n("count")} = post_stock_count.count and y.${n("movement")} is not null), 'variance', null);
  end if;
  if v_count.status <> 'open' then
    ${fail("INVENTORY_COUNT_CLOSED", "a cancelled count can't be posted", "22023")}
  end if;
  for v_line in
    select y.${n("id")} as id, y.${n("variant")} as variant, y.${n("bin")} as bin, y.${n("lot")} as lot, y.${n("serial")} as serial, y.${n("variance")} as variance
    from ${lines} y
    where y.${n("count")} = post_stock_count.count and y.${n("variance")} is not null and y.${n("variance")} <> 0 and y.${n("movement")} is null
    order by y.${n("variant")}, y.${n("id")}
  loop
    insert into ${levels} (${lv("tenant")}, ${lv("variant")}, ${lv("location")})
    values (v_count.tenant, v_line.variant, v_count.location)
    on conflict (${lv("variant")}, ${lv("location")}) do nothing;
    v_movement := ${moveStock(ctx, {
      tenant: "v_count.tenant",
      variant: "v_line.variant",
      location: "v_count.location",
      quantity: "v_line.variance",
      reason: "'count'",
      referenceType: "'stock_count'",
      referenceId: "post_stock_count.count::text",
      note: "coalesce(v_count.note, 'Stock count')",
      detail:
        "jsonb_strip_nulls(jsonb_build_object('binId', v_line.bin, 'lotId', v_line.lot, 'serials', case when v_line.serial is not null then jsonb_build_array(v_line.serial) end))",
    })};
    update ${lines} y set ${n("movement")} = v_movement, ${n("updatedAt")} = now() where y.${n("id")} = v_line.id;
    v_moves := v_moves + 1;
    v_total := v_total + abs(v_line.variance);
  end loop;
  update ${counts} x set ${c("status")} = 'posted', ${c("postedAt")} = now(), ${c("postedBy")} = auth.uid(), ${c("updatedAt")} = now() where x.${c("id")} = post_stock_count.count;
  return jsonb_build_object('posted', true, 'movements', v_moves, 'variance', v_total::text);
end;
$$;
${userGrant(`${fn("post_stock_count")}(uuid)`)}

-- Cancels an open count; its lines stay for the record and nothing is posted.
create or replace function ${fn("cancel_stock_count")}(count uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_status text;
begin
  select x.${c("tenant")}, x.${c("status")} into v_tenant, v_status from ${counts} x where x.${c("id")} = cancel_stock_count.count for update;
  if v_tenant is null then
    ${fail("INVENTORY_COUNT_NOT_FOUND", "stock count not found", "P0002")}
  end if;
  ${guard(names.scope, names.manage, "v_tenant")}
  if v_status = 'cancelled' then
    return false;
  end if;
  if v_status <> 'open' then
    ${fail("INVENTORY_COUNT_CLOSED", "a posted count can't be cancelled", "22023")}
  end if;
  update ${counts} x set ${c("status")} = 'cancelled', ${c("updatedAt")} = now() where x.${c("id")} = cancel_stock_count.count;
  return true;
end;
$$;
${userGrant(`${fn("cancel_stock_count")}(uuid)`)}
${importFunctions(ctx, names)}`;
}

function importFunctions(ctx: BlockSqlContext, names: InventoryNames): string {
  const { fn } = names;
  const loc = locationsOf(ctx);
  const counts = ctx.table("counts");
  const lines = ctx.table("countLines");
  const l = loc.col;
  const c = columns(ctx, "counts");
  const n = columns(ctx, "countLines");
  const catalog = ctx.of("catalog");
  const v = columns(catalog, "variants");
  const bins = ctx.table("bins");
  const lots = ctx.table("lots");
  const b = columns(ctx, "bins");
  const lt = columns(ctx, "lots");

  return `
-- The import target of the stock_count entity: item.data is { locationId or
-- location (a code), note?, lines: [{ variantId or sku, binId or bin (a code)?,
-- lotId or lot (a code)?, serial?, counted, expected? }] }. A line without
-- expected takes the stock now. An imported count stays open; post it with
-- post_stock_count, which posts once. Importing the same key again replaces the
-- lines of an open count and refuses a posted one.
create or replace function ${fn("import_stock_count")}(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType} := (import_stock_count.item ->> 'tenant')::${ctx.idType};
  v_data jsonb := import_stock_count.item -> 'data';
  v_location uuid;
  v_id uuid;
  v_status text;
  v_updated timestamptz;
  v_entry jsonb;
  v_variant uuid;
  v_bin uuid;
  v_lot uuid;
  v_serial text;
  v_counted numeric;
  v_expected numeric;
begin
  if jsonb_typeof(v_data -> 'lines') is distinct from 'array' then
    ${fail("IMPORT_ITEM_INVALID", "a stock count needs a list of lines", "22023")}
  end if;
  begin
    v_location := nullif(v_data ->> 'locationId', '')::uuid;
  exception when invalid_text_representation then
    ${fail("IMPORT_ITEM_INVALID", "locationId is a uuid", "22023")}
  end;
  if v_location is null then
    select x.${l("id")} into v_location from ${loc.table} x where x.${l("tenant")} = v_tenant and x.${l("code")} = v_data ->> 'location';
  elsif not exists (select 1 from ${loc.table} x where x.${l("id")} = v_location and x.${l("tenant")} = v_tenant) then
    v_location := null;
  end if;
  if v_location is null then
    ${fail("IMPORT_ITEM_INVALID", "the count's location isn't in this organization", "22023")}
  end if;
  if import_stock_count.subject_id is null then
    insert into ${counts} as x (${c("tenant")}, ${c("location")}, ${c("note")})
    values (v_tenant, v_location, nullif(btrim(v_data ->> 'note'), ''))
    returning x.${c("id")}, x.${c("updatedAt")} into v_id, v_updated;
  else
    select x.${c("id")}, x.${c("status")} into v_id, v_status from ${counts} x
    where x.${c("id")} = import_stock_count.subject_id::uuid and x.${c("tenant")} = v_tenant for update;
    if v_id is null then
      ${fail("IMPORT_ITEM_INVALID", "the stock count no longer exists", "22023")}
    end if;
    if v_status <> 'open' then
      ${fail("IMPORT_ITEM_INVALID", "a posted or cancelled count can't be imported again", "22023")}
    end if;
    update ${counts} x set ${c("location")} = v_location, ${c("note")} = nullif(btrim(v_data ->> 'note'), ''), ${c("updatedAt")} = now()
    where x.${c("id")} = v_id returning x.${c("updatedAt")} into v_updated;
    delete from ${lines} y where y.${n("count")} = v_id and y.${n("movement")} is null;
  end if;
  for v_entry in select e from jsonb_array_elements(v_data -> 'lines') e loop
    begin
      v_variant := nullif(v_entry ->> 'variantId', '')::uuid;
      v_bin := nullif(v_entry ->> 'binId', '')::uuid;
      v_lot := nullif(v_entry ->> 'lotId', '')::uuid;
      v_counted := (v_entry ->> 'counted')::numeric;
      v_expected := (v_entry ->> 'expected')::numeric;
    exception when invalid_text_representation or numeric_value_out_of_range then
      ${fail("IMPORT_ITEM_INVALID", "ids are uuids and counted and expected are numbers", "22023")}
    end;
    if v_variant is null then
      select y.${v("id")} into v_variant from ${catalog.table("variants")} y where y.${v("tenant")} = v_tenant and y.${v("sku")} = v_entry ->> 'sku';
    end if;
    if v_variant is null or not exists (select 1 from ${catalog.table("variants")} y where y.${v("id")} = v_variant and y.${v("tenant")} = v_tenant) then
      ${fail("IMPORT_ITEM_INVALID", "a line's variant isn't in this organization", "22023")}
    end if;
    if v_bin is null and nullif(v_entry ->> 'bin', '') is not null then
      select y.${b("id")} into v_bin from ${bins} y where y.${b("tenant")} = v_tenant and y.${b("location")} = v_location and y.${b("code")} = v_entry ->> 'bin';
      if v_bin is null then
        ${fail("IMPORT_ITEM_INVALID", "a line's bin isn't at the location", "22023")}
      end if;
    end if;
    if v_lot is null and nullif(v_entry ->> 'lot', '') is not null then
      select y.${lt("id")} into v_lot from ${lots} y where y.${lt("tenant")} = v_tenant and y.${lt("variant")} = v_variant and y.${lt("code")} = v_entry ->> 'lot';
      if v_lot is null then
        ${fail("IMPORT_ITEM_INVALID", "a line's lot isn't a lot of its variant", "22023")}
      end if;
    end if;
    v_serial := nullif(btrim(v_entry ->> 'serial'), '');
    if v_counted is null or v_counted < 0 or (v_serial is not null and (v_counted not in (0, 1) or v_bin is not null or v_lot is not null)) then
      ${fail("IMPORT_ITEM_INVALID", "a line needs a counted quantity of zero or more, and a serial is counted 0 or 1", "22023")}
    end if;
    insert into ${lines} as x (${n("tenant")}, ${n("count")}, ${n("variant")}, ${n("bin")}, ${n("lot")}, ${n("serial")}, ${n("expected")}, ${n("counted")})
    values (v_tenant, v_id, v_variant, v_bin, v_lot, v_serial,
      coalesce(v_expected, ${fn("count_expected")}(v_variant, v_location, v_bin, v_lot, v_serial)), v_counted)
    on conflict (${n("count")}, ${n("variant")}, coalesce(${n("bin")}, ${NO_ID}), coalesce(${n("lot")}, ${NO_ID}), coalesce(${n("serial")}, '')) do update
      set ${n("counted")} = excluded.${n("counted")}, ${n("expected")} = excluded.${n("expected")}, ${n("updatedAt")} = now();
  end loop;
  return jsonb_build_object('subjectId', v_id::text, 'updatedAt', v_updated);
end;
$$;
${serviceGrant(`${fn("import_stock_count")}(uuid, jsonb, text)`)}

create or replace function ${fn("stock_count_updated_at")}(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select x.${c("updatedAt")} from ${counts} x where x.${c("id")} = $1::uuid
$$;
${serviceGrant(`${fn("stock_count_updated_at")}(text)`)}
`;
}

export function countContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  if (!countsOn(ctx)) {
    return [];
  }

  return [
    {
      name: "open_stock_count",
      args: ["{id}", "uuid", "jsonb"],
      returns: "jsonb",
    },
    { name: "record_count_line", args: ["uuid", "jsonb"], returns: "jsonb" },
    { name: "post_stock_count", args: ["uuid"], returns: "jsonb" },
    { name: "cancel_stock_count", args: ["uuid"], returns: "boolean" },
  ];
}

/** An import target names its functions as `schema.function`, without quotes. */
const plain = (qualified: string): string => qualified.replaceAll('"', "");

/** What `contributes.imports` adds for stock counts. */
export function countImportTargets(
  own: BlockSqlContext,
): readonly ImportTargetContribution[] {
  if (!countsOn(own)) {
    return [];
  }

  return [
    {
      entity: "stock_count",
      subjectType: "stock_count",
      write: plain(own.fn("import_stock_count")),
      updatedAt: plain(own.fn("stock_count_updated_at")),
    },
  ];
}
