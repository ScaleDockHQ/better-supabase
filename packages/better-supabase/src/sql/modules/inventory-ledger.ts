import type { BlockSqlContext } from "../context.ts";
import type { InventoryNames } from "./inventory-stock.ts";

import { fail } from "../shared.ts";
import { columns, strict, threshold } from "./inventory-stock.ts";

/** The stock movement reasons and the counter account each posts against. */
const STOCK_COUNTERS: Readonly<Record<string, readonly [string, string]>> = {
  adjustment: ["stock:adjustments", "Adjustments"],
  damage: ["stock:adjustments", "Adjustments"],
  loss: ["stock:adjustments", "Adjustments"],
  count: ["stock:adjustments", "Adjustments"],
  expired: ["stock:adjustments", "Adjustments"],
  scrap: ["stock:adjustments", "Adjustments"],
  receipt: ["stock:suppliers", "Suppliers"],
  sale: ["stock:customers", "Customers"],
  return: ["stock:customers", "Customers"],
  transfer_out: ["stock:transit", "In transit"],
  transfer_in: ["stock:transit", "In transit"],
};

/**
 * The counter account each reason posts a weighted average cost against, in the
 * cost currency. Transfers keep the value: it is per variant, not per
 * location.
 */
const VALUE_COUNTERS: Readonly<Record<string, readonly [string, string]>> = {
  receipt: ["stock_value:suppliers", "Stock purchases"],
  sale: ["stock_value:cogs", "Cost of goods sold"],
  return: ["stock_value:cogs", "Cost of goods sold"],
};

export const counterCase = (reason: string, index: 0 | 1): string =>
  `case ${reason} ${Object.entries(STOCK_COUNTERS)
    .map(([key, value]) => `when '${key}' then '${value[index]}'`)
    .join(" ")} end`;

/**
 * A `jsonb` array of `{ lotId, quantity }`: the stock movement `movement` took
 * out, by lot, so a cancel or a transfer puts the same lots back.
 */
export function movementLots(
  inventory: BlockSqlContext,
  movement: string,
): string {
  const ledger = inventory.of("ledger");
  const la = columns(ledger, "accounts");
  const le = columns(ledger, "entries");

  return `(select jsonb_agg(jsonb_build_object('lotId', g.lot, 'quantity', g.quantity::text))
    from (select a.${la("metadata")} ->> 'lotId' as lot, (sum(-e.${le("amount")} / power(10::numeric, a.${la("scale")})))::numeric(20, 6) as quantity
      from ${ledger.table("entries")} e join ${ledger.table("accounts")} a on a.${la("id")} = e.${le("account")}
      where e.${le("transaction")} = ${movement} and a.${la("kind")} = 'stock'
      group by a.${la("metadata")} ->> 'lotId') g)`;
}

const valueCase = (reason: string, index: 0 | 1): string =>
  `case ${reason} ${Object.entries(VALUE_COUNTERS)
    .map(([key, value]) => `when '${key}' then '${value[index]}'`)
    .join(
      " ",
    )} else '${index === 0 ? "stock_value:adjustments" : "Stock adjustments"}' end`;

/** Reasons that sell or ship stock: they skip hold bins and expired lots. */
const OUTBOUND = "('sale', 'transfer_out')";

/**
 * The stock ledger lives in the ledger block: a movement is a transaction
 * between the variant's stock accounts at the location (one per bin and lot it
 * touches) and a counter account for its reason. Amounts are base units: the
 * quantity times ten to the variant's scale, so a 1.250 kg movement at scale 3
 * posts 1250 (ADR 0127). Levels and buckets stay projections the movement
 * updates in the same transaction. With average costing the same transaction
 * moves the stock's value between the variant's value account and a value
 * counter.
 */
export function stockLedger(
  ctx: BlockSqlContext,
  names: InventoryNames,
): string {
  const { fn } = names;
  const ledger = ctx.of("ledger");
  const levels = ctx.table("levels");
  const items = ctx.table("items");
  const bins = ctx.table("bins");
  const lots = ctx.table("lots");
  const serials = ctx.table("serials");
  const buckets = ctx.table("buckets");
  const lv = columns(ctx, "levels");
  const i = columns(ctx, "items");
  const b = columns(ctx, "bins");
  const lt = columns(ctx, "lots");
  const s = columns(ctx, "serials");
  const k = columns(ctx, "buckets");
  const lb = columns(ledger, "balances");
  const account = ledger.fn("ledger_account_for");

  const reasons = Object.keys(STOCK_COUNTERS)
    .map((reason) => `'${reason}'`)
    .join(", ");

  const signature = `${ctx.idType}, uuid, uuid, numeric, text, text, text, text, jsonb`;

  return `
drop function if exists ${fn("move_stock")}(${ctx.idType}, uuid, uuid, integer, text, text, text, text);

-- Posts a stock movement to the ledger and applies it to its level and
-- buckets. detail is null or an object with binId, lotId or lot ({ code,
-- expiresOn }), serials (an array, one per unit of a serial-tracked
-- variant), and unitCost and currency for a receipt under average costing.
-- Without a bin or lot, stock leaves first-expiry-first-out: the lot that
-- expires first, then the stock outside any lot; a sale or a transfer out
-- skips hold bins and expired lots. A tracked variant without backorders
-- can't go below zero on hand in any bucket, and a sale or a transfer out
-- can't take available below zero. Returns the ledger transaction, the
-- movement's id.
create or replace function ${fn("move_stock")}(tenant ${ctx.idType}, variant uuid, location uuid, quantity numeric, reason text, reference_type text default null, reference_id text default null, note text default null, detail jsonb default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_unit text;
  v_scale smallint;
  v_tracking text;
  v_expiry boolean;
  v_costing text;
  v_currency text;
  v_average numeric;
  v_factor numeric;
  v_bin uuid;
  v_lot uuid;
  v_serials text[];
  v_parts jsonb := '[]'::jsonb;
  v_part record;
  v_rest numeric;
  v_take numeric;
  v_lines jsonb := '[]'::jsonb;
  v_held numeric := 0;
  v_bucket numeric;
  v_strict boolean;
  v_id uuid;
  v_on_hand numeric;
  v_after numeric;
  v_point numeric;
  v_unbinned numeric;
  v_total numeric;
  v_value bigint := 0;
  v_balance bigint;
  v_value_account uuid;
  v_suffix text;
begin
  if move_stock.quantity is null or move_stock.quantity = 0 then
    ${fail("INVENTORY_QUANTITY_INVALID", "the quantity must not be zero", "22023")}
  end if;
  if move_stock.reason is null or move_stock.reason not in (${reasons}) then
    ${fail("INVENTORY_REASON_INVALID", "unknown stock movement reason", "22023")}
  end if;
  if move_stock.detail is not null and jsonb_typeof(move_stock.detail) <> 'object' then
    ${fail("INVENTORY_DETAIL_INVALID", "detail must be an object", "22023")}
  end if;
  select x.${i("unit")}, x.${i("scale")}, x.${i("tracking")}, x.${i("expiry")}, x.${i("costing")}, x.${i("currency")}, x.${i("averageCost")}
  into v_unit, v_scale, v_tracking, v_expiry, v_costing, v_currency, v_average
  from ${items} x where x.${i("variant")} = move_stock.variant for update;
  v_unit := coalesce(v_unit, 'item');
  v_scale := coalesce(v_scale, 0);
  v_tracking := coalesce(v_tracking, 'none');
  v_costing := coalesce(v_costing, 'none');
  v_factor := power(10::numeric, v_scale);
  if move_stock.quantity * v_factor <> trunc(move_stock.quantity * v_factor) then
    ${fail("INVENTORY_QUANTITY_PRECISION", "the quantity has more decimals than the variant's scale", "22023")}
  end if;
  v_strict := ${strict(ctx, "move_stock.variant")};
  v_bin := nullif(move_stock.detail ->> 'binId', '')::uuid;
  v_lot := nullif(move_stock.detail ->> 'lotId', '')::uuid;
  if v_lot is null and jsonb_typeof(move_stock.detail -> 'lot') = 'object' then
    v_lot := ${fn("stock_lot_for")}(move_stock.tenant, move_stock.variant, move_stock.detail -> 'lot' ->> 'code',
      nullif(move_stock.detail -> 'lot' ->> 'expiresOn', '')::date);
  end if;
  if v_lot is not null and not exists (select 1 from ${lots} x where x.${lt("id")} = v_lot and x.${lt("variant")} = move_stock.variant) then
    ${fail("INVENTORY_LOT_NOT_FOUND", "the lot isn't a lot of this variant", "P0002")}
  end if;
  if v_bin is not null and not exists (select 1 from ${bins} x where x.${b("id")} = v_bin and x.${b("location")} = move_stock.location) then
    ${fail("INVENTORY_BIN_NOT_FOUND", "the bin isn't at this location", "P0002")}
  end if;
  if jsonb_typeof(move_stock.detail -> 'serials') = 'array' then
    v_serials := array(select jsonb_array_elements_text(move_stock.detail -> 'serials'));
  end if;
  if v_tracking = 'serial' then
    if v_serials is null or cardinality(v_serials) <> abs(move_stock.quantity)
      or (select count(distinct e) from unnest(v_serials) e where length(e) between 1 and 100) <> cardinality(v_serials) then
      ${fail("INVENTORY_SERIALS_REQUIRED", "a serial-tracked variant needs one distinct serial number per unit", "22023")}
    end if;
  elsif coalesce(cardinality(v_serials), 0) > 0 then
    ${fail("INVENTORY_SERIALS_UNTRACKED", "the variant doesn't track serial numbers", "22023")}
  end if;

  if move_stock.quantity > 0 then
    if v_tracking = 'lot' and v_lot is null and move_stock.reason = 'receipt' then
      ${fail("INVENTORY_LOT_REQUIRED", "a lot-tracked variant receives stock into a lot", "22023")}
    end if;
    if v_expiry and v_lot is not null and move_stock.reason = 'receipt'
      and (select x.${lt("expiresOn")} from ${lots} x where x.${lt("id")} = v_lot) is null then
      ${fail("INVENTORY_EXPIRY_REQUIRED", "the variant tracks expiry, so its lots need an expiry date", "22023")}
    end if;
    if v_tracking = 'serial' then
      if exists (select 1 from ${serials} x where x.${s("variant")} = move_stock.variant and x.${s("serial")} = any (v_serials) and x.${s("status")} = 'in_stock') then
        ${fail("INVENTORY_SERIAL_IN_STOCK", "a serial number is already in stock", "23505")}
      end if;
      insert into ${serials} as x (${s("tenant")}, ${s("variant")}, ${s("serial")}, ${s("lot")}, ${s("location")}, ${s("bin")}, ${s("status")})
      select move_stock.tenant, move_stock.variant, e, v_lot, move_stock.location, v_bin, 'in_stock' from unnest(v_serials) e
      on conflict (${s("variant")}, ${s("serial")}) do update
        set ${s("lot")} = coalesce(excluded.${s("lot")}, x.${s("lot")}), ${s("location")} = excluded.${s("location")},
          ${s("bin")} = excluded.${s("bin")}, ${s("status")} = 'in_stock', ${s("updatedAt")} = now();
      select jsonb_agg(jsonb_build_object('bin', v_bin, 'lot', g.lot, 'quantity', g.n)) into v_parts
      from (select x.${s("lot")} as lot, count(*) as n from ${serials} x
        where x.${s("variant")} = move_stock.variant and x.${s("serial")} = any (v_serials) group by x.${s("lot")}) g;
    else
      v_parts := jsonb_build_array(jsonb_build_object('bin', v_bin, 'lot', v_lot, 'quantity', move_stock.quantity));
    end if;
  elsif v_tracking = 'serial' then
    if (select count(*) from ${serials} x where x.${s("variant")} = move_stock.variant and x.${s("serial")} = any (v_serials)
        and x.${s("status")} = 'in_stock' and x.${s("location")} = move_stock.location and (v_bin is null or x.${s("bin")} = v_bin)) <> cardinality(v_serials) then
      ${fail("INVENTORY_SERIAL_NOT_IN_STOCK", "a serial number isn't in stock at this location", "P0002")}
    end if;
    select jsonb_agg(jsonb_build_object('bin', g.bin, 'lot', g.lot, 'quantity', -g.n)) into v_parts
    from (select x.${s("bin")} as bin, x.${s("lot")} as lot, count(*) as n from ${serials} x
      where x.${s("variant")} = move_stock.variant and x.${s("serial")} = any (v_serials) group by x.${s("bin")}, x.${s("lot")}) g;
    update ${serials} x set ${s("status")} = case when move_stock.reason = 'scrap' then 'scrapped' else 'out' end,
      ${s("location")} = null, ${s("bin")} = null, ${s("updatedAt")} = now()
    where x.${s("variant")} = move_stock.variant and x.${s("serial")} = any (v_serials);
  elsif v_bin is not null or v_lot is not null then
    if v_lot is not null and move_stock.reason in ${OUTBOUND}
      and (select x.${lt("expiresOn")} from ${lots} x where x.${lt("id")} = v_lot) < current_date then
      ${fail("INVENTORY_LOT_EXPIRED", "the lot has expired", "55000")}
    end if;
    v_parts := jsonb_build_array(jsonb_build_object('bin', v_bin, 'lot', v_lot, 'quantity', move_stock.quantity));
  else
    v_rest := -move_stock.quantity;
    for v_part in
      select y.${k("bin")} as bin, y.${k("lot")} as lot, y.${k("onHand")} as on_hand
      from ${buckets} y
      left join ${bins} bn on bn.${b("id")} = y.${k("bin")}
      left join ${lots} lo on lo.${lt("id")} = y.${k("lot")}
      where y.${k("variant")} = move_stock.variant and y.${k("location")} = move_stock.location and y.${k("onHand")} > 0
        and (move_stock.reason not in ${OUTBOUND}
          or (not coalesce(bn.${b("hold")}, false) and (lo.${lt("expiresOn")} is null or lo.${lt("expiresOn")} >= current_date)))
      order by coalesce(bn.${b("hold")}, false), lo.${lt("expiresOn")} nulls last, lo.${lt("code")} nulls last, bn.${b("code")}
      for update of y
    loop
      exit when v_rest <= 0;
      v_take := least(v_rest, v_part.on_hand);
      v_parts := v_parts || jsonb_build_array(jsonb_build_object('bin', v_part.bin, 'lot', v_part.lot, 'quantity', -v_take));
      v_rest := v_rest - v_take;
    end loop;
    if v_rest > 0 then
      v_parts := v_parts || jsonb_build_array(jsonb_build_object('bin', null, 'lot', null, 'quantity', -v_rest));
    end if;
  end if;

  for v_part in
    select nullif(p ->> 'bin', '')::uuid as bin, nullif(p ->> 'lot', '')::uuid as lot, (p ->> 'quantity')::numeric as quantity
    from jsonb_array_elements(v_parts) p
  loop
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('account', ${account}(move_stock.tenant, 'stock',
      'stock:' || move_stock.variant::text || ':' || move_stock.location::text
        || case when v_part.bin is null and v_part.lot is null then '' else ':' || coalesce(v_part.bin::text, '-') || ':' || coalesce(v_part.lot::text, '-') end,
      'Stock', v_unit, v_scale, 'product-variants', move_stock.variant::text, null, true, ${names.read}, 'inventory',
      jsonb_strip_nulls(jsonb_build_object('variantId', move_stock.variant, 'locationId', move_stock.location, 'binId', v_part.bin, 'lotId', v_part.lot))),
      'amount', (v_part.quantity * v_factor)::bigint));
    if v_part.bin is not null or v_part.lot is not null then
      insert into ${buckets} as x (${k("tenant")}, ${k("variant")}, ${k("location")}, ${k("bin")}, ${k("lot")}, ${k("onHand")})
      values (move_stock.tenant, move_stock.variant, move_stock.location, v_part.bin, v_part.lot, v_part.quantity)
      on conflict (${k("variant")}, ${k("location")}, ${k("bin")}, ${k("lot")}) do update
        set ${k("onHand")} = x.${k("onHand")} + excluded.${k("onHand")}, ${k("updatedAt")} = now()
      returning x.${k("onHand")} into v_bucket;
      if v_bucket < 0 and v_strict then
        ${fail("INVENTORY_INSUFFICIENT", "not enough stock in this bin or lot", "23514")}
      end if;
      if v_part.bin is not null and (select x.${b("hold")} from ${bins} x where x.${b("id")} = v_part.bin) then
        v_held := v_held + v_part.quantity;
      end if;
    end if;
  end loop;

  v_suffix := case when v_unit = 'item' and v_scale = 0 then '' else ':' || v_unit || ':' || v_scale::text end;
  v_lines := v_lines || jsonb_build_array(jsonb_build_object('account', ${account}(move_stock.tenant, 'stock_counter',
    ${counterCase("move_stock.reason", 0)} || v_suffix, ${counterCase("move_stock.reason", 1)}, v_unit, v_scale,
    null, null, null, true, ${names.read}, 'inventory', null), 'amount', -(move_stock.quantity * v_factor)::bigint));

  if v_costing = 'average' and move_stock.reason not in ('transfer_in', 'transfer_out') then
    if move_stock.detail ? 'currency' and upper(move_stock.detail ->> 'currency') is distinct from v_currency then
      ${fail("INVENTORY_COST_CURRENCY_MISMATCH", "the unit cost is in another currency than the variant's costing", "22023")}
    end if;
    select coalesce(sum(x.${lv("onHand")}), 0) into v_total from ${levels} x where x.${lv("variant")} = move_stock.variant;
    v_value_account := ${account}(move_stock.tenant, 'stock_value', 'stock_value:' || move_stock.variant::text, 'Stock value',
      v_currency, 0::smallint, 'product-variants', move_stock.variant::text, null, true, ${names.read}, 'inventory',
      jsonb_build_object('variantId', move_stock.variant));
    v_balance := coalesce((select y.${lb("balance")} from ${ledger.table("balances")} y where y.${lb("account")} = v_value_account), 0);
    if move_stock.quantity > 0 then
      v_value := round(move_stock.quantity * coalesce(nullif(move_stock.detail ->> 'unitCost', '')::numeric, v_average, 0));
    elsif v_total + move_stock.quantity <= 0 then
      v_value := -v_balance;
    else
      v_value := -round(-move_stock.quantity * coalesce(v_average, 0));
    end if;
    if v_value <> 0 then
      v_lines := v_lines || jsonb_build_array(
        jsonb_build_object('account', v_value_account, 'amount', v_value),
        jsonb_build_object('account', ${account}(move_stock.tenant, 'stock_value_counter', ${valueCase("move_stock.reason", 0)} || ':' || v_currency,
          ${valueCase("move_stock.reason", 1)} || ' ' || v_currency, v_currency, 0::smallint, null, null, null, true, ${names.read}, 'inventory', null),
          'amount', -v_value));
    end if;
    update ${items} x set ${i("averageCost")} = case when v_total + move_stock.quantity > 0
        then round((v_balance + v_value)::numeric / (v_total + move_stock.quantity), 6) else x.${i("averageCost")} end,
      ${i("updatedAt")} = now()
    where x.${i("variant")} = move_stock.variant;
  end if;

  v_id := ${ledger.fn("ledger_post")}(move_stock.tenant, 'stock.' || move_stock.reason, v_lines,
    move_stock.reference_type, move_stock.reference_id, move_stock.note, null, null,
    jsonb_strip_nulls(jsonb_build_object('variantId', move_stock.variant, 'locationId', move_stock.location, 'reason', move_stock.reason,
      'quantity', move_stock.quantity::text, 'unit', nullif(v_unit, 'item'))));
  if v_serials is not null then
    update ${serials} x set ${s("movement")} = v_id
    where x.${s("variant")} = move_stock.variant and x.${s("serial")} = any (v_serials);
  end if;
  insert into ${levels} as x (${lv("tenant")}, ${lv("variant")}, ${lv("location")}, ${lv("onHand")}, ${lv("held")})
  values (move_stock.tenant, move_stock.variant, move_stock.location, move_stock.quantity, greatest(v_held, 0))
  on conflict (${lv("variant")}, ${lv("location")}) do update
    set ${lv("onHand")} = x.${lv("onHand")} + excluded.${lv("onHand")}, ${lv("held")} = greatest(x.${lv("held")} + v_held, 0), ${lv("updatedAt")} = now()
  returning x.${lv("onHand")}, x.${lv("available")}, x.${lv("reorderPoint")} into v_on_hand, v_after, v_point;
  if move_stock.quantity < 0 and v_strict then
    select v_on_hand - coalesce(sum(y.${k("onHand")}), 0) into v_unbinned from ${buckets} y
    where y.${k("variant")} = move_stock.variant and y.${k("location")} = move_stock.location;
    if v_on_hand < 0 or v_unbinned < 0 or (v_after < 0 and move_stock.reason in ${OUTBOUND}) then
      ${fail("INVENTORY_INSUFFICIENT", "not enough stock at this location", "23514")}
    end if;
  end if;
  ${threshold(ctx, {
    tenant: "move_stock.tenant",
    variant: "move_stock.variant",
    location: "move_stock.location",
    before: "(v_after - move_stock.quantity + v_held)",
    after: "v_after",
    point: "v_point",
  })}
  if move_stock.quantity > 0 then
    perform ${fn("fill_backorders")}(move_stock.tenant, move_stock.variant, move_stock.location);
  end if;
  return v_id;
end;
$$;
revoke execute on function ${fn("move_stock")}(${signature}) from public, anon, authenticated;
`;
}
