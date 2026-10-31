import type { BlockSqlContext } from "../context.ts";

import { fail, pageSize, userGrant } from "../shared.ts";
import { warehouseSql } from "./warehouse-sql.ts";

/**
 * Without a plan, a count with more variance than this percent waits for a
 * review.
 */
export const DEFAULT_VARIANCE_LIMIT = 5;

export function warehouseCounting(ctx: BlockSqlContext): string {
  const q = warehouseSql(ctx);
  const { fn, n, plans, inventory, locations } = q;
  const idType = ctx.idType;

  if (!inventory.hasTable("counts") || !inventory.hasTable("countLines")) {
    throw new TypeError(
      "the warehouse block needs the inventory block's stock count tables",
    );
  }

  const counts = inventory.table("counts");
  const countLines = inventory.table("countLines");
  const c = (column: string): string => inventory.col("counts", column);
  const m = (column: string): string => inventory.col("countLines", column);
  const post = inventory.fn("post_stock_count");
  const open = inventory.fn("open_stock_count");

  const countMissing = fail(
    "WAREHOUSE_COUNT_NOT_FOUND",
    "no such stock count",
    "P0002",
  );

  return `
-- Creates a cycle count plan. input is { name, locationId, everyDays,
-- variantIds, varianceLimitPct, startsOn }. variantIds limits the count to
-- those variants; without it the whole location is counted. Needs
-- warehouse.manage.
create or replace function ${fn("create_count_plan")}(tenant ${idType}, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${plans};
  v_name text;
  v_location uuid;
  v_every integer;
  v_variants uuid[];
  v_limit numeric := ${String(DEFAULT_VARIANCE_LIMIT)};
  v_starts date;
begin
  if not ${q.allowed("create_count_plan.tenant", q.manage)} then
    ${q.forbidden("not allowed to manage count plans")}
  end if;
  if jsonb_typeof(create_count_plan.input) is distinct from 'object' then
    ${q.invalid("input must be an object")}
  end if;
  begin
    v_name := trim(create_count_plan.input ->> 'name');
    v_location := (create_count_plan.input ->> 'locationId')::uuid;
    v_every := (create_count_plan.input ->> 'everyDays')::integer;
    v_starts := coalesce((create_count_plan.input ->> 'startsOn')::date, current_date);
    if create_count_plan.input ? 'varianceLimitPct' then
      v_limit := (create_count_plan.input ->> 'varianceLimitPct')::numeric;
    end if;
    if jsonb_typeof(create_count_plan.input -> 'variantIds') = 'array' then
      v_variants := array(select jsonb_array_elements_text(create_count_plan.input -> 'variantIds'))::uuid[];
    end if;
  exception when invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range then
    ${q.invalid("locationId and variantIds are uuids, everyDays is a whole number, startsOn is a date and varianceLimitPct is a number")}
  end;
  if coalesce(length(v_name), 0) not between 1 and 200 then
    ${q.invalid("a plan needs a name of 1 to 200 characters")}
  end if;
  if v_every is null or v_every not between 1 and 3660 then
    ${q.invalid("everyDays is between 1 and 3660")}
  end if;
  if v_limit is null or v_limit < 0 or v_limit > 9999 then
    ${q.invalid("varianceLimitPct is between 0 and 9999")}
  end if;
  if not exists (select 1 from ${locations.table} x where x.${locations.col("id")} = v_location and x.${locations.col("tenant")} = create_count_plan.tenant) then
    ${q.invalid("no such location in this organization")}
  end if;
  insert into ${plans} (${n("tenant")}, ${n("name")}, ${n("location")}, ${n("everyDays")}, ${n("variants")}, ${n("varianceLimit")}, ${n("nextRunOn")})
  values (create_count_plan.tenant, v_name, v_location, v_every, v_variants, v_limit, v_starts)
  returning * into v_row;
  ${q.recordPlan("count_plan.created", "v_row", "count plan created")}
  return ${q.planJson("v_row")};
end;
$$;
${userGrant(`${fn("create_count_plan")}(${idType}, jsonb)`)}

-- The count plans of an organization by next run. Needs warehouse.read.
create or replace function ${fn("list_count_plans")}(tenant ${idType})
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not ${q.allowed("list_count_plans.tenant", q.read)} then
    ${q.forbidden("not allowed to read count plans")}
  end if;
  return coalesce((
    select jsonb_agg(${q.planJson("x")} order by x.${n("nextRunOn")}, x.${n("id")})
    from ${plans} x where x.${n("tenant")} = list_count_plans.tenant
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_count_plans")}(${idType})`)}

-- Opens the plan's stock count and moves its next run on. A plan whose last
-- count is still open doesn't open another. Not granted to anyone.
create or replace function ${fn("count_plan_run")}(plan_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${plans};
  v_count uuid;
begin
  select * into v_row from ${plans} x where x.${n("id")} = count_plan_run.plan_id for update;
  if not found then
    ${q.planMissing}
  end if;
  if not v_row.${n("active")} then
    ${q.state("the plan is switched off")}
  end if;
  if v_row.${n("lastCount")} is not null and exists (
    select 1 from ${counts} x where x.${c("id")} = v_row.${n("lastCount")} and x.${c("status")} = 'open'
  ) then
    ${q.state("the last count of this plan is still open")}
  end if;
  v_count := (${open}(v_row.${n("tenant")}, v_row.${n("location")},
    jsonb_strip_nulls(jsonb_build_object('note', 'Cycle count: ' || v_row.${n("name")}, 'variantIds', to_jsonb(v_row.${n("variants")})))
  ) ->> 'id')::uuid;
  update ${plans} x set
    ${n("lastRunAt")} = now(),
    ${n("lastCount")} = v_count,
    ${n("nextRunOn")} = greatest(x.${n("nextRunOn")}, current_date) + x.${n("everyDays")}
  where x.${n("id")} = v_row.${n("id")}
  returning * into v_row;
  ${q.recordPlan("count_plan.executed", "v_row", "count plan executed", ", 'countId', v_count")}
  return ${q.planJson("v_row")} || jsonb_build_object('countId', v_count);
end;
$$;
revoke execute on function ${fn("count_plan_run")}(uuid) from public, anon, authenticated;

-- Opens a plan's count now, ahead of its schedule. Opening the count needs
-- inventory.manage as well as warehouse.manage.
create or replace function ${fn("run_count_plan")}(plan_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant ${idType};
begin
  select x.${n("tenant")} into v_tenant from ${plans} x where x.${n("id")} = run_count_plan.plan_id;
  if not found then
    ${q.planMissing}
  end if;
  if not ${q.allowed("v_tenant", q.manage)} then
    ${q.forbidden("not allowed to manage count plans")}
  end if;
  return ${fn("count_plan_run")}(run_count_plan.plan_id);
end;
$$;
${userGrant(`${fn("run_count_plan")}(uuid)`)}

-- Opens the count of every active plan that is due, for a job that runs daily.
-- A plan whose last count is still open waits. Returns the plans and the counts
-- that were opened. Needs warehouse.manage.
create or replace function ${fn("run_due_count_plans")}(tenant ${idType})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_plan uuid;
  v_result jsonb;
  v_out jsonb := '[]'::jsonb;
begin
  if not ${q.allowed("run_due_count_plans.tenant", q.manage)} then
    ${q.forbidden("not allowed to manage count plans")}
  end if;
  for v_plan in
    select x.${n("id")} from ${plans} x
    where x.${n("tenant")} = run_due_count_plans.tenant and x.${n("active")} and x.${n("nextRunOn")} <= current_date
      and not exists (select 1 from ${counts} z where z.${c("id")} = x.${n("lastCount")} and z.${c("status")} = 'open')
    order by x.${n("nextRunOn")}, x.${n("id")}
    limit ${pageSize("null", 50, 50)}
  loop
    v_result := ${fn("count_plan_run")}(v_plan);
    v_out := v_out || jsonb_build_array(jsonb_build_object('planId', v_plan, 'countId', v_result -> 'countId'));
  end loop;
  return v_out;
end;
$$;
${userGrant(`${fn("run_due_count_plans")}(${idType})`)}

-- The variance of a count as a percent of what the books held, per counted
-- line, against the limit of the plan that opened it (${String(DEFAULT_VARIANCE_LIMIT)} percent
-- without one). Needs warehouse.read.
create or replace function ${fn("get_cycle_count_variance")}(count_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant ${idType};
  v_plan uuid;
  v_limit numeric := ${String(DEFAULT_VARIANCE_LIMIT)};
  v_lines jsonb;
  v_max numeric;
begin
  select x.${c("tenant")} into v_tenant from ${counts} x where x.${c("id")} = get_cycle_count_variance.count_id;
  if not found then
    ${countMissing}
  end if;
  if not ${q.allowed("v_tenant", q.read)} then
    ${q.forbidden("not allowed to read counts")}
  end if;
  select p.${n("id")}, p.${n("varianceLimit")} into v_plan, v_limit
  from ${plans} p where p.${n("lastCount")} = get_cycle_count_variance.count_id;
  v_limit := coalesce(v_limit, ${String(DEFAULT_VARIANCE_LIMIT)});
  select coalesce(jsonb_agg(jsonb_build_object('lineId', y.id, 'variantId', y.variant, 'expected', y.expected::text, 'counted', y.counted::text,
      'variance', (y.counted - y.expected)::text, 'variancePct', round(y.pct, 2)::text) order by y.pct desc, y.id), '[]'::jsonb),
    max(y.pct)
  into v_lines, v_max
  from (
    select z.${m("id")} as id, z.${m("variant")} as variant, z.${m("expected")} as expected, z.${m("counted")} as counted,
      abs(z.${m("counted")} - z.${m("expected")}) / greatest(z.${m("expected")}, 1) * 100 as pct
    from ${countLines} z
    where z.${m("count")} = get_cycle_count_variance.count_id and z.${m("counted")} is not null
  ) y;
  return jsonb_build_object('countId', get_cycle_count_variance.count_id, 'planId', v_plan, 'limitPct', v_limit::text,
    'maxVariancePct', round(coalesce(v_max, 0), 2)::text, 'overLimit', coalesce(v_max, 0) > v_limit, 'lines', v_lines);
end;
$$;
${userGrant(`${fn("get_cycle_count_variance")}(uuid)`)}

-- Posts a stock count through the inventory block. A count with a line over the
-- plan's variance limit posts only when approve is true, so a person has seen
-- the numbers first. Needs warehouse.manage, and inventory.manage to post.
create or replace function ${fn("post_cycle_count")}(count_id uuid, approve boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant ${idType};
  v_variance jsonb;
  v_over boolean;
begin
  select x.${c("tenant")} into v_tenant from ${counts} x where x.${c("id")} = post_cycle_count.count_id;
  if not found then
    ${countMissing}
  end if;
  if not ${q.allowed("v_tenant", q.manage)} then
    ${q.forbidden("not allowed to post counts")}
  end if;
  v_variance := ${fn("get_cycle_count_variance")}(post_cycle_count.count_id);
  v_over := (v_variance ->> 'overLimit')::boolean;
  if v_over and not coalesce(post_cycle_count.approve, false) then
    ${fail("WAREHOUSE_VARIANCE_OVER_LIMIT", "a line is off by more than the plan allows, review the count and post it with approve", "55000")}
  end if;
  return ${post}(post_cycle_count.count_id) || jsonb_build_object('approved', v_over, 'maxVariancePct', v_variance -> 'maxVariancePct');
end;
$$;
${userGrant(`${fn("post_cycle_count")}(uuid, boolean)`)}
`;
}
