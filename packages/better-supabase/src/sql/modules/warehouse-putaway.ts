import type { BlockSqlContext } from "../context.ts";

import { fail, userGrant } from "../shared.ts";
import { pickable } from "./warehouse-picking.ts";
import { warehouseSql } from "./warehouse-sql.ts";

/** The most bins or placements a read function returns. */
const LIST_LIMIT = 1000;

const DEFAULT_VELOCITY_DAYS = 30;
const DEFAULT_SLOTTING_LIMIT = 50;

/**
 * Putaway rules, bin slots and variant sizes; the suggestions made from them
 * for a receipt, a variant or a location's fastest movers; and the route of a
 * pick list.
 */
export function warehousePutaway(ctx: BlockSqlContext): string {
  const q = warehouseSql(ctx);
  const { fn, r, s, z, rules, slots, sizes, inventory, lists, lines, l, p } = q;
  const idType = ctx.idType;
  const bins = inventory.table("bins");
  const buckets = inventory.table("buckets");
  const b = (column: string): string => inventory.col("bins", column);
  const k = (column: string): string => inventory.col("buckets", column);
  const catalog = inventory.of("catalog");
  const variants = catalog.table("variants");
  const v = (column: string): string => catalog.col("variants", column);

  const readOrPick = (tenant: string): string =>
    `(${q.allowed(tenant, q.read)} or ${q.allowed(tenant, q.pick)})`;

  const ruleMissing = fail(
    "WAREHOUSE_RULE_NOT_FOUND",
    "no such putaway rule",
    "P0002",
  );

  const receipts = inventory.hasTable("receipts") ? receiptFunction(q) : "";

  return `
-- One rule as json.
create or replace function ${fn("putaway_rule_json")}(rule_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', x.${r("id")}, 'organizationId', x.${r("tenant")}, 'locationId', x.${r("location")},
    'binId', x.${r("bin")}, 'variantId', x.${r("variant")}, 'priority', x.${r("priority")},
    'maxQuantity', x.${r("maxQuantity")}::text, 'active', x.${r("active")}, 'createdAt', x.${r("createdAt")})
  from ${rules} x where x.${r("id")} = putaway_rule_json.rule_id
$$;
revoke execute on function ${fn("putaway_rule_json")}(uuid) from public, anon, authenticated;

-- Creates a putaway rule, or changes the one named by input.id. input is
-- { id, locationId, binId, variantId, priority, maxQuantity, active }: stock of
-- variantId (any variant when absent) goes to binId, lowest priority first,
-- until the bin holds maxQuantity of it. Needs warehouse.manage.
create or replace function ${fn("save_putaway_rule")}(tenant ${idType}, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${rules};
  v_id uuid;
  v_location uuid;
  v_bin uuid;
  v_variant uuid;
  v_priority integer;
  v_max numeric;
  v_active boolean;
begin
  if not ${q.allowed("save_putaway_rule.tenant", q.manage)} then
    ${q.forbidden("not allowed to manage putaway rules")}
  end if;
  if jsonb_typeof(save_putaway_rule.input) is distinct from 'object' then
    ${q.invalid("input must be an object")}
  end if;
  begin
    v_id := nullif(save_putaway_rule.input ->> 'id', '')::uuid;
    v_location := nullif(save_putaway_rule.input ->> 'locationId', '')::uuid;
    v_bin := nullif(save_putaway_rule.input ->> 'binId', '')::uuid;
    v_variant := nullif(save_putaway_rule.input ->> 'variantId', '')::uuid;
    v_priority := (save_putaway_rule.input ->> 'priority')::integer;
    v_max := (save_putaway_rule.input ->> 'maxQuantity')::numeric;
    v_active := (save_putaway_rule.input ->> 'active')::boolean;
  exception when invalid_text_representation or numeric_value_out_of_range then
    ${q.invalid("ids are uuids, priority is an integer, maxQuantity a number and active a boolean")}
  end;
  if v_id is not null then
    select * into v_row from ${rules} x
    where x.${r("id")} = v_id and x.${r("tenant")} = save_putaway_rule.tenant for update;
    if not found then
      ${ruleMissing}
    end if;
    v_location := coalesce(v_location, v_row.${r("location")});
    v_bin := coalesce(v_bin, v_row.${r("bin")});
    if not (save_putaway_rule.input ? 'variantId') then
      v_variant := v_row.${r("variant")};
    end if;
    if not (save_putaway_rule.input ? 'maxQuantity') then
      v_max := v_row.${r("maxQuantity")};
    end if;
    v_priority := coalesce(v_priority, v_row.${r("priority")});
    v_active := coalesce(v_active, v_row.${r("active")});
  end if;
  if v_location is null or v_bin is null then
    ${q.invalid("a rule needs a locationId and a binId")}
  end if;
  if not exists (
    select 1 from ${bins} x
    where x.${b("id")} = v_bin and x.${b("tenant")} = save_putaway_rule.tenant and x.${b("location")} = v_location
  ) then
    ${q.invalid("the bin has to be in the rule's location in this organization")}
  end if;
  if v_variant is not null and not exists (
    select 1 from ${variants} x where x.${v("id")} = v_variant and x.${v("tenant")} = save_putaway_rule.tenant
  ) then
    ${q.invalid("no such variant in this organization")}
  end if;
  if coalesce(v_priority, 100) not between 0 and 10000 or coalesce(v_max, 1) <= 0 then
    ${q.invalid("priority is between 0 and 10000 and maxQuantity is more than 0")}
  end if;
  if v_id is null then
    insert into ${rules} (${r("tenant")}, ${r("location")}, ${r("bin")}, ${r("variant")}, ${r("priority")}, ${r("maxQuantity")}, ${r("active")})
    values (save_putaway_rule.tenant, v_location, v_bin, v_variant, coalesce(v_priority, 100), v_max, coalesce(v_active, true))
    returning * into v_row;
  else
    update ${rules} x set ${r("location")} = v_location, ${r("bin")} = v_bin, ${r("variant")} = v_variant,
      ${r("priority")} = v_priority, ${r("maxQuantity")} = v_max, ${r("active")} = v_active
    where x.${r("id")} = v_row.${r("id")}
    returning * into v_row;
  end if;
  return ${fn("putaway_rule_json")}(v_row.${r("id")});
end;
$$;
${userGrant(`${fn("save_putaway_rule")}(${idType}, jsonb)`)}

-- Deletes a putaway rule. Returns false when it was already gone. Needs
-- warehouse.manage.
create or replace function ${fn("delete_putaway_rule")}(rule_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${rules};
begin
  select * into v_row from ${rules} x where x.${r("id")} = delete_putaway_rule.rule_id for update;
  if not found then
    return false;
  end if;
  if not ${q.allowed(`v_row.${r("tenant")}`, q.manage)} then
    ${q.forbidden("not allowed to manage putaway rules")}
  end if;
  delete from ${rules} x where x.${r("id")} = v_row.${r("id")};
  return true;
end;
$$;
${userGrant(`${fn("delete_putaway_rule")}(uuid)`)}

-- The putaway rules of a location, lowest priority first. filters is
-- { locationId, variantId }, both optional. Needs warehouse.read.
create or replace function ${fn("list_putaway_rules")}(tenant ${idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_location uuid;
  v_variant uuid;
begin
  if not ${q.allowed("list_putaway_rules.tenant", q.read)} then
    ${q.forbidden("not allowed to read putaway rules")}
  end if;
  begin
    v_location := nullif(list_putaway_rules.filters ->> 'locationId', '')::uuid;
    v_variant := nullif(list_putaway_rules.filters ->> 'variantId', '')::uuid;
  exception when invalid_text_representation then
    ${q.invalid("locationId and variantId are uuids")}
  end;
  return coalesce((
    select jsonb_agg(${fn("putaway_rule_json")}(y.id) order by y.priority, y.id)
    from (
      select x.${r("id")} as id, x.${r("priority")} as priority from ${rules} x
      where x.${r("tenant")} = list_putaway_rules.tenant
        and (v_location is null or x.${r("location")} = v_location)
        and (v_variant is null or x.${r("variant")} = v_variant)
      order by x.${r("priority")}, x.${r("id")}
      limit ${String(LIST_LIMIT)}
    ) y
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_putaway_rules")}(${idType}, jsonb)`)}

-- Sets how far a bin is from the dispatch area and how much it holds. input is
-- { binId, walkRank, capacity }: the lowest walkRank is the closest, and
-- capacity is in the unit of variant sizes (no limit when absent). Needs
-- warehouse.manage.
create or replace function ${fn("save_bin_slot")}(tenant ${idType}, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_bin uuid;
  v_rank integer;
  v_capacity numeric;
  v_row ${slots};
begin
  if not ${q.allowed("save_bin_slot.tenant", q.manage)} then
    ${q.forbidden("not allowed to manage bin slots")}
  end if;
  if jsonb_typeof(save_bin_slot.input) is distinct from 'object' then
    ${q.invalid("input must be an object")}
  end if;
  begin
    v_bin := (save_bin_slot.input ->> 'binId')::uuid;
    v_rank := coalesce((save_bin_slot.input ->> 'walkRank')::integer, 0);
    v_capacity := (save_bin_slot.input ->> 'capacity')::numeric;
  exception when invalid_text_representation or numeric_value_out_of_range then
    ${q.invalid("binId is a uuid, walkRank an integer and capacity a number")}
  end;
  if v_rank not between 0 and 100000 or coalesce(v_capacity, 1) <= 0 then
    ${q.invalid("walkRank is between 0 and 100000 and capacity is more than 0")}
  end if;
  if not exists (select 1 from ${bins} x where x.${b("id")} = v_bin and x.${b("tenant")} = save_bin_slot.tenant) then
    ${q.invalid("no such bin in this organization")}
  end if;
  insert into ${slots} (${s("tenant")}, ${s("bin")}, ${s("walkRank")}, ${s("capacity")})
  values (save_bin_slot.tenant, v_bin, v_rank, v_capacity)
  on conflict (${s("bin")}) do update set ${s("walkRank")} = excluded.${s("walkRank")},
    ${s("capacity")} = excluded.${s("capacity")}, ${s("updatedAt")} = now()
  returning * into v_row;
  return jsonb_build_object('binId', v_row.${s("bin")}, 'walkRank', v_row.${s("walkRank")},
    'capacity', v_row.${s("capacity")}::text);
end;
$$;
${userGrant(`${fn("save_bin_slot")}(${idType}, jsonb)`)}

-- Sets the space one unit of a variant takes in a bin. input is
-- { variantId, size }. Needs warehouse.manage.
create or replace function ${fn("save_variant_size")}(tenant ${idType}, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_variant uuid;
  v_size numeric;
  v_row ${sizes};
begin
  if not ${q.allowed("save_variant_size.tenant", q.manage)} then
    ${q.forbidden("not allowed to manage variant sizes")}
  end if;
  if jsonb_typeof(save_variant_size.input) is distinct from 'object' then
    ${q.invalid("input must be an object")}
  end if;
  begin
    v_variant := (save_variant_size.input ->> 'variantId')::uuid;
    v_size := (save_variant_size.input ->> 'size')::numeric;
  exception when invalid_text_representation or numeric_value_out_of_range then
    ${q.invalid("variantId is a uuid and size a number")}
  end;
  if v_size is null or v_size <= 0 then
    ${q.invalid("size is more than 0")}
  end if;
  if not exists (select 1 from ${variants} x where x.${v("id")} = v_variant and x.${v("tenant")} = save_variant_size.tenant) then
    ${q.invalid("no such variant in this organization")}
  end if;
  insert into ${sizes} (${z("tenant")}, ${z("variant")}, ${z("size")})
  values (save_variant_size.tenant, v_variant, v_size)
  on conflict (${z("variant")}) do update set ${z("size")} = excluded.${z("size")}, ${z("updatedAt")} = now()
  returning * into v_row;
  return jsonb_build_object('variantId', v_row.${z("variant")}, 'size', v_row.${z("size")}::text);
end;
$$;
${userGrant(`${fn("save_variant_size")}(${idType}, jsonb)`)}

-- The bins of a location with their slot and how full they are. filters is
-- { locationId }. used is the stock in the bin times the variant sizes.
-- Needs warehouse.read.
create or replace function ${fn("list_bin_slots")}(tenant ${idType}, filters jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_location uuid;
begin
  if not ${q.allowed("list_bin_slots.tenant", q.read)} then
    ${q.forbidden("not allowed to read bin slots")}
  end if;
  begin
    v_location := (list_bin_slots.filters ->> 'locationId')::uuid;
  exception when invalid_text_representation then
    ${q.invalid("locationId is a uuid")}
  end;
  if v_location is null then
    ${q.invalid("filters needs a locationId")}
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('binId', y.bin, 'code', y.code, 'locationId', v_location, 'hold', y.hold,
      'active', y.active, 'walkRank', y.walk_rank, 'capacity', y.capacity::text, 'used', y.used::text)
      order by y.walk_rank nulls last, y.code)
    from (
      select x.${b("id")} as bin, x.${b("code")} as code, x.${b("hold")} as hold, x.${b("active")} as active,
        sl.${s("walkRank")} as walk_rank, sl.${s("capacity")} as capacity,
        coalesce((
          select sum(c.${k("onHand")} * coalesce(sz.${z("size")}, 1))
          from ${buckets} c left join ${sizes} sz on sz.${z("variant")} = c.${k("variant")}
          where c.${k("bin")} = x.${b("id")}
        ), 0) as used
      from ${bins} x left join ${slots} sl on sl.${s("bin")} = x.${b("id")}
      where x.${b("tenant")} = list_bin_slots.tenant and x.${b("location")} = v_location
      order by sl.${s("walkRank")} nulls last, x.${b("code")}
      limit ${String(LIST_LIMIT)}
    ) y
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_bin_slots")}(${idType}, jsonb)`)}

-- Where stock of a variant goes in a location. Rule bins come first (a rule for
-- the variant before one for any variant, then by priority), then bins that
-- already hold it, then the other active bins by walk rank and how empty they
-- are. Bins on hold or inactive are skipped; a bin takes no more than its
-- rule's maxQuantity of the variant or its slot capacity. Not granted to
-- anyone.
create or replace function ${fn("putaway_plan")}(plan_tenant ${idType}, plan_location uuid, plan_variant uuid, plan_quantity numeric)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_left numeric := plan_quantity;
  v_size numeric;
  v_room numeric;
  v_take numeric;
  v_placements jsonb := '[]'::jsonb;
  rec record;
begin
  select coalesce((select x.${z("size")} from ${sizes} x where x.${z("variant")} = plan_variant), 1) into v_size;
  for rec in
    with held as (
      select c.${k("bin")} as bin,
        coalesce(sum(c.${k("onHand")}) filter (where c.${k("variant")} = plan_variant), 0) as of_variant,
        sum(c.${k("onHand")} * coalesce(sz.${z("size")}, 1)) as used
      from ${buckets} c left join ${sizes} sz on sz.${z("variant")} = c.${k("variant")}
      where c.${k("tenant")} = plan_tenant and c.${k("location")} = plan_location and c.${k("bin")} is not null
      group by c.${k("bin")}
    ),
    cand as (
      select distinct on (y.bin) y.bin, y.tier, y.rank, y.rule_id, y.max_quantity
      from (
        select x.${r("bin")} as bin, case when x.${r("variant")} is null then 1 else 0 end as tier,
          x.${r("priority")} as rank, x.${r("id")} as rule_id, x.${r("maxQuantity")} as max_quantity
        from ${rules} x
        where x.${r("tenant")} = plan_tenant and x.${r("location")} = plan_location and x.${r("active")}
          and (x.${r("variant")} is null or x.${r("variant")} = plan_variant)
        union all
        select h.bin, 2, 0, null::uuid, null::numeric from held h where h.of_variant > 0
        union all
        select x.${b("id")}, 3, coalesce(sl.${s("walkRank")}, 100001), null::uuid, null::numeric
        from ${bins} x left join ${slots} sl on sl.${s("bin")} = x.${b("id")}
        where x.${b("tenant")} = plan_tenant and x.${b("location")} = plan_location
      ) y
      order by y.bin, y.tier, y.rank
    )
    select c.bin, bn.${b("code")} as code, c.tier, c.rank, c.rule_id, c.max_quantity,
      coalesce(h.of_variant, 0) as of_variant, coalesce(h.used, 0) as used, sl.${s("capacity")} as capacity
    from cand c
    join ${bins} bn on bn.${b("id")} = c.bin
    left join held h on h.bin = c.bin
    left join ${slots} sl on sl.${s("bin")} = c.bin
    where bn.${b("active")} and not bn.${b("hold")} and bn.${b("location")} = plan_location and bn.${b("tenant")} = plan_tenant
    order by c.tier, c.rank, case when c.tier = 2 then -coalesce(h.of_variant, 0) else coalesce(h.used, 0) end, bn.${b("code")}
  loop
    exit when v_left <= 0;
    v_room := least(
      case when rec.max_quantity is null then 'Infinity'::numeric else rec.max_quantity - rec.of_variant end,
      case when rec.capacity is null then 'Infinity'::numeric else (rec.capacity - rec.used) / v_size end
    );
    continue when v_room <= 0;
    v_take := least(v_left, trunc(v_room, 6));
    continue when v_take <= 0;
    v_placements := v_placements || jsonb_build_object('binId', rec.bin, 'binCode', rec.code,
      'quantity', v_take::text, 'source', case when rec.tier < 2 then 'rule' when rec.tier = 2 then 'stock' else 'free' end,
      'ruleId', rec.rule_id);
    v_left := v_left - v_take;
  end loop;
  return jsonb_build_object('locationId', plan_location, 'variantId', plan_variant, 'quantity', plan_quantity::text,
    'placements', v_placements, 'unassigned', v_left::text);
end;
$$;
revoke execute on function ${fn("putaway_plan")}(${idType}, uuid, uuid, numeric) from public, anon, authenticated;

-- Suggests bins for stock about to be put away. input is { locationId,
-- variantId, quantity }. Nothing moves: the suggestion lists each bin with the
-- quantity it takes, why (rule, stock or free), and what is left over when no
-- bin has room. Needs warehouse.read or warehouse.pick.
create or replace function ${fn("suggest_putaway")}(tenant ${idType}, input jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_location uuid;
  v_variant uuid;
  v_quantity numeric;
begin
  if not ${readOrPick("suggest_putaway.tenant")} then
    ${q.forbidden("not allowed to read putaway suggestions")}
  end if;
  if jsonb_typeof(suggest_putaway.input) is distinct from 'object' then
    ${q.invalid("input must be an object")}
  end if;
  begin
    v_location := (suggest_putaway.input ->> 'locationId')::uuid;
    v_variant := (suggest_putaway.input ->> 'variantId')::uuid;
    v_quantity := (suggest_putaway.input ->> 'quantity')::numeric;
  exception when invalid_text_representation or numeric_value_out_of_range then
    ${q.invalid("locationId and variantId are uuids and quantity is a number")}
  end;
  if v_quantity is null or v_quantity <= 0 then
    ${q.invalid("quantity is more than 0")}
  end if;
  if not exists (select 1 from ${q.locations.table} x where x.${q.locations.col("id")} = v_location and x.${q.locations.col("tenant")} = suggest_putaway.tenant) then
    ${q.invalid("no such location in this organization")}
  end if;
  if not exists (select 1 from ${variants} x where x.${v("id")} = v_variant and x.${v("tenant")} = suggest_putaway.tenant) then
    ${q.invalid("no such variant in this organization")}
  end if;
  return ${fn("putaway_plan")}(suggest_putaway.tenant, v_location, v_variant, v_quantity);
end;
$$;
${userGrant(`${fn("suggest_putaway")}(${idType}, jsonb)`)}
${receipts}
-- Suggests where the fastest movers of a location should live. input is
-- { locationId, days, limit }: the variants most picked in the last days
-- (default ${String(DEFAULT_VELOCITY_DAYS)}), at most limit of them (default ${String(DEFAULT_SLOTTING_LIMIT)}), each get the closest bin
-- with a slot that holds their stock, fastest first. A variant already in a bin
-- as close or closer stays (action keep). Nothing moves. Needs warehouse.read.
create or replace function ${fn("suggest_slotting")}(tenant ${idType}, input jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_location uuid;
  v_days integer;
  v_limit integer;
  v_taken uuid[] := '{}';
  v_bin uuid;
  v_rank integer;
  v_current_rank integer;
  v_action text;
  v_suggested uuid;
  v_out jsonb := '[]'::jsonb;
  rec record;
begin
  if not ${q.allowed("suggest_slotting.tenant", q.read)} then
    ${q.forbidden("not allowed to read slotting suggestions")}
  end if;
  if jsonb_typeof(suggest_slotting.input) is distinct from 'object' then
    ${q.invalid("input must be an object")}
  end if;
  begin
    v_location := (suggest_slotting.input ->> 'locationId')::uuid;
    v_days := coalesce((suggest_slotting.input ->> 'days')::integer, ${String(DEFAULT_VELOCITY_DAYS)});
    v_limit := coalesce((suggest_slotting.input ->> 'limit')::integer, ${String(DEFAULT_SLOTTING_LIMIT)});
  exception when invalid_text_representation or numeric_value_out_of_range then
    ${q.invalid("locationId is a uuid, days and limit are integers")}
  end;
  if v_days not between 1 and 365 or v_limit not between 1 and 500 then
    ${q.invalid("days is between 1 and 365 and limit between 1 and 500")}
  end if;
  if not exists (select 1 from ${q.locations.table} x where x.${q.locations.col("id")} = v_location and x.${q.locations.col("tenant")} = suggest_slotting.tenant) then
    ${q.invalid("no such location in this organization")}
  end if;
  for rec in
    with moves as (
      select y.${l("variant")} as variant, sum(y.${l("picked")}) as velocity, count(*) as picks
      from ${lines} y join ${lists} x on x.${p("id")} = y.${l("list")}
      where x.${p("tenant")} = suggest_slotting.tenant and x.${p("location")} = v_location
        and y.${l("picked")} > 0 and y.${l("pickedAt")} >= now() - make_interval(days => v_days)
      group by y.${l("variant")}
      order by sum(y.${l("picked")}) desc, y.${l("variant")}
      limit v_limit
    )
    select m.variant, m.velocity, m.picks,
      coalesce((select sum(c.${k("onHand")}) from ${buckets} c
        where c.${k("tenant")} = suggest_slotting.tenant and c.${k("location")} = v_location
          and c.${k("variant")} = m.variant and c.${k("bin")} is not null), 0) as on_hand,
      (select c.${k("bin")} from ${buckets} c
        where c.${k("tenant")} = suggest_slotting.tenant and c.${k("location")} = v_location
          and c.${k("variant")} = m.variant and c.${k("bin")} is not null
        order by c.${k("onHand")} desc, c.${k("bin")} limit 1) as current_bin,
      coalesce((select sz.${z("size")} from ${sizes} sz where sz.${z("variant")} = m.variant), 1) as size
    from moves m
    order by m.velocity desc, m.variant
  loop
    v_current_rank := (select sl.${s("walkRank")} from ${slots} sl where sl.${s("bin")} = rec.current_bin);
    v_bin := null;
    v_rank := null;
    select x.${b("id")}, sl.${s("walkRank")} into v_bin, v_rank
    from ${bins} x join ${slots} sl on sl.${s("bin")} = x.${b("id")}
    where x.${b("tenant")} = suggest_slotting.tenant and x.${b("location")} = v_location
      and x.${b("active")} and not x.${b("hold")} and not (x.${b("id")} = any(v_taken))
      and (sl.${s("capacity")} is null or sl.${s("capacity")} >= rec.on_hand * rec.size)
    order by sl.${s("walkRank")}, x.${b("code")}
    limit 1;
    if v_bin is null or (v_current_rank is not null and v_current_rank <= v_rank) or v_bin = rec.current_bin then
      v_action := 'keep';
      v_suggested := rec.current_bin;
    else
      v_action := 'move';
      v_suggested := v_bin;
    end if;
    if v_suggested is not null then
      v_taken := v_taken || v_suggested;
    end if;
    v_out := v_out || jsonb_build_object('variantId', rec.variant, 'velocity', rec.velocity::text, 'picks', rec.picks,
      'onHand', rec.on_hand::text, 'currentBinId', rec.current_bin, 'suggestedBinId', v_suggested, 'action', v_action);
  end loop;
  return v_out;
end;
$$;
${userGrant(`${fn("suggest_slotting")}(${idType}, jsonb)`)}

-- Sets the order a picker walks an open pick list. line_ids lists open lines of
-- the list in walking order; open lines left out follow in variant order.
-- Picked lines keep no position. Needs the same permission as record_pick.
create or replace function ${fn("set_pick_route")}(pick_list_id uuid, line_ids uuid[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_list ${lists};
  v_count integer;
begin
  select * into v_list from ${lists} x where x.${p("id")} = set_pick_route.pick_list_id for update;
  if not found then
    ${q.listMissing}
  end if;
  if not coalesce(${pickable(q, "v_list")}, false) then
    ${q.forbidden("not allowed to pick from this list")}
  end if;
  if v_list.${p("status")} <> 'open' then
    ${q.state("only an open pick list has a route")}
  end if;
  if (select count(distinct t) from unnest(set_pick_route.line_ids) t) <> coalesce(cardinality(set_pick_route.line_ids), 0) then
    ${q.invalid("a line is on the route once")}
  end if;
  select count(*) into v_count from ${lines} y
  where y.${l("list")} = v_list.${p("id")} and y.${l("status")} = 'open' and y.${l("id")} = any(coalesce(set_pick_route.line_ids, '{}'));
  if v_count <> coalesce(cardinality(set_pick_route.line_ids), 0) then
    ${q.invalid("the route lists open lines of this pick list")}
  end if;
  update ${lines} y set ${l("route")} = o.position
  from (
    select y2.${l("id")} as id, row_number() over (
      order by coalesce(array_position(coalesce(set_pick_route.line_ids, '{}'), y2.${l("id")}), 1000000), y2.${l("variant")}, y2.${l("id")}
    ) as position
    from ${lines} y2 where y2.${l("list")} = v_list.${p("id")} and y2.${l("status")} = 'open'
  ) o
  where y.${l("id")} = o.id;
  return ${fn("pick_list_json")}(v_list.${p("id")});
end;
$$;
${userGrant(`${fn("set_pick_route")}(uuid, uuid[])`)}
`;
}

function receiptFunction(q: ReturnType<typeof warehouseSql>): string {
  const { fn, inventory } = q;
  const receipts = inventory.table("receipts");
  const receiptLines = inventory.table("receiptLines");
  const a = (column: string): string => inventory.col("receipts", column);
  const m = (column: string): string => inventory.col("receiptLines", column);

  return `
-- Suggests bins for every variant of a goods receipt, at the receipt's
-- location. Lines of one variant are planned together. Variants are planned
-- one by one, so two variants can be suggested the same bin when it has room
-- for each but not both. Needs warehouse.read or warehouse.pick.
create or replace function ${fn("suggest_receipt_putaway")}(receipt_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_receipt ${receipts};
  v_out jsonb := '[]'::jsonb;
  rec record;
begin
  select * into v_receipt from ${receipts} x where x.${a("id")} = suggest_receipt_putaway.receipt_id;
  if not found then
    ${fail("WAREHOUSE_RECEIPT_NOT_FOUND", "no such goods receipt", "P0002")}
  end if;
  if not (${q.allowed(`v_receipt.${a("tenant")}`, q.read)} or ${q.allowed(`v_receipt.${a("tenant")}`, q.pick)}) then
    ${q.forbidden("not allowed to read putaway suggestions")}
  end if;
  if v_receipt.${a("location")} is null then
    ${q.state("the receipt has no location")}
  end if;
  for rec in
    select x.${m("variant")} as variant, sum(x.${m("quantity")}) as quantity
    from ${receiptLines} x
    where x.${m("receipt")} = v_receipt.${a("id")} and x.${m("quantity")} > 0
    group by x.${m("variant")}
    order by x.${m("variant")}
  loop
    v_out := v_out || ${fn("putaway_plan")}(v_receipt.${a("tenant")}, v_receipt.${a("location")}, rec.variant, rec.quantity);
  end loop;
  return v_out;
end;
$$;
${userGrant(`${fn("suggest_receipt_putaway")}(uuid)`)}
`;
}
