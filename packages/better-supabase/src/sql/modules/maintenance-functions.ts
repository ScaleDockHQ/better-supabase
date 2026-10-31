import type { BlockSqlContext } from "../context.ts";
import type { MaintenanceSql } from "./maintenance-sql.ts";

import { pageSize, triggerGrant, userGrant } from "../shared.ts";
import { maintenanceSql } from "./maintenance-sql.ts";
import {
  MAINTENANCE_CALIBRATION_RESULTS,
  MAINTENANCE_PRIORITIES,
} from "./maintenance-values.ts";

const list = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

/** The plan json with its parts and whether it is due. */
function planView(q: MaintenanceSql, row: string): string {
  const { m, s, p, meters, parts } = q;

  return `${q.planJson(row)} || jsonb_build_object(
    'due', ${row}.${p("status")} = 'active' and ${row}.${p("workOrder")} is null and (
      (${row}.${p("kind")} = 'time' and ${row}.${p("nextDueAt")} <= now())
      or (${row}.${p("kind")} = 'meter' and exists (
        select 1 from ${meters} z
        where z.${m("id")} = ${row}.${p("meter")} and z.${m("reading")} >= coalesce(${row}.${p("lastDoneValue")}, 0) + ${row}.${p("everyValue")}
      ))
    ),
    'parts', coalesce((
      select jsonb_agg(jsonb_build_object('id', y.${s("id")}, 'name', y.${s("name")}, 'quantity', y.${s("quantity")}::text, 'variantId', y.${s("variant")}) order by y.${s("name")}, y.${s("id")})
      from ${parts} y where y.${s("plan")} = ${row}.${p("id")}
    ), '[]'::jsonb))`;
}

function planFunctions(ctx: BlockSqlContext, q: MaintenanceSql): string {
  const { fn, p, s, m, plans, parts, meters } = q;
  const idType = ctx.idType;

  const parse = (src: string): string => `begin
    v_title := trim(${src} ->> 'title');
    v_kind := ${src} ->> 'kind';
    v_days := (${src} ->> 'everyDays')::integer;
    v_value := (${src} ->> 'everyValue')::numeric;
    v_meter := nullif(${src} ->> 'meterId', '')::uuid;
    v_asset := nullif(${src} ->> 'assetId', '')::uuid;
    v_priority := coalesce(nullif(${src} ->> 'priority', ''), 'normal');
  exception when invalid_text_representation or numeric_value_out_of_range then
    ${q.invalid("everyDays and everyValue are numbers, meterId and assetId are ids")}
  end;`;

  const checks = `if coalesce(length(v_title), 0) not between 1 and 200 then
    ${q.invalid("a plan needs a title of 1 to 200 characters")}
  end if;
  if v_kind = 'time' and (v_days is null or v_days < 1 or v_meter is not null or v_value is not null) then
    ${q.invalid("a time plan needs everyDays of at least 1 and no meter")}
  end if;
  if v_kind = 'meter' and (v_meter is null or v_value is null or v_value <= 0 or v_days is not null) then
    ${q.invalid("a meter plan needs a meterId and an everyValue above 0")}
  end if;
  if v_kind is null or v_kind not in ('time', 'meter') then
    ${q.invalid("the kind is time or meter")}
  end if;
  if v_priority not in (${list(MAINTENANCE_PRIORITIES)}) then
    ${q.invalid("the priority is low, normal, high or urgent")}
  end if;`;

  const partsInsert = (plan: string, tenant: string, src: string): string => `
  if ${src} ? 'parts' then
    if jsonb_typeof(${src} -> 'parts') is distinct from 'array' then
      ${q.invalid("parts must be a list")}
    end if;
    delete from ${parts} y where y.${s("plan")} = ${plan};
    insert into ${parts} (${s("tenant")}, ${s("plan")}, ${s("name")}, ${s("quantity")}, ${s("variant")})
    select ${tenant}, ${plan}, trim(e ->> 'name'), coalesce((e ->> 'quantity')::numeric, 1), nullif(e ->> 'variantId', '')::uuid
    from jsonb_array_elements(${src} -> 'parts') e;
  end if;`;

  return `
-- Creates a plan. input is { title, kind: 'time' | 'meter', everyDays,
-- meterId, everyValue, assetId, priority, parts: [{ name, quantity,
-- variantId }] }. A time plan falls due everyDays from now; a meter plan
-- everyValue units above the meter's reading. Needs maintenance.manage.
create or replace function ${fn("create_maintenance_plan")}(tenant ${idType}, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${plans};
  v_title text;
  v_kind text;
  v_days integer;
  v_value numeric;
  v_meter uuid;
  v_asset uuid;
  v_priority text;
  v_reading numeric;
begin
  if not ${q.allowed("create_maintenance_plan.tenant", q.manage)} then
    ${q.forbidden("not allowed to manage maintenance plans")}
  end if;
  if jsonb_typeof(create_maintenance_plan.input) is distinct from 'object' then
    ${q.invalid("input must be an object")}
  end if;
  ${parse("create_maintenance_plan.input")}
  ${checks}
  if v_meter is not null then
    select z.${m("reading")} into v_reading from ${meters} z
    where z.${m("id")} = v_meter and z.${m("tenant")} = create_maintenance_plan.tenant;
    if not found then
      ${q.meterMissing}
    end if;
  end if;
  ${ctx.hook("before_maintenance_plan_create", [
    [idType, "create_maintenance_plan.tenant"],
    ["jsonb", "create_maintenance_plan.input"],
  ])}
  begin
    insert into ${plans} (${p("tenant")}, ${p("title")}, ${p("asset")}, ${p("kind")}, ${p("everyDays")}, ${p("meter")}, ${p("everyValue")}, ${p("priority")}, ${p("lastDoneValue")}, ${p("nextDueAt")}, ${p("createdBy")})
    values (create_maintenance_plan.tenant, v_title, v_asset, v_kind, v_days, v_meter, v_value, v_priority, v_reading,
      case when v_kind = 'time' then now() + v_days * interval '1 day' end, auth.uid())
    returning * into v_row;${partsInsert(`v_row.${p("id")}`, `v_row.${p("tenant")}`, "create_maintenance_plan.input")}
  exception when check_violation or not_null_violation or invalid_text_representation then
    ${q.invalid("a part needs a name of 1 to 200 characters and a quantity above 0")}
  end;
  ${q.recordPlan("maintenance_plan.created", "v_row", "maintenance plan created")}
  ${ctx.hook("after_maintenance_plan_create", [["uuid", `v_row.${p("id")}`]])}
  return ${planView(q, "v_row")};
end;
$$;
${userGrant(`${fn("create_maintenance_plan")}(${idType}, jsonb)`)}

-- Changes a plan: title, priority, assetId, everyDays, everyValue, status
-- ('active' or 'paused') and parts. The kind and the meter stay. Needs
-- maintenance.manage.
create or replace function ${fn("update_maintenance_plan")}(plan_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${plans};
  v_title text;
  v_kind text;
  v_days integer;
  v_value numeric;
  v_meter uuid;
  v_asset uuid;
  v_priority text;
  v_status text;
begin
  select * into v_row from ${plans} x where x.${p("id")} = update_maintenance_plan.plan_id for update;
  if not found or not ${q.allowed(`v_row.${p("tenant")}`, q.read)} then
    ${q.planMissing}
  end if;
  if not ${q.allowed(`v_row.${p("tenant")}`, q.manage)} then
    ${q.forbidden("not allowed to manage maintenance plans")}
  end if;
  if jsonb_typeof(update_maintenance_plan.changes) is distinct from 'object' then
    ${q.invalid("changes must be an object")}
  end if;
  if update_maintenance_plan.changes ? 'kind' or update_maintenance_plan.changes ? 'meterId' then
    ${q.invalid("a plan keeps its kind and meter")}
  end if;
  ${parse("update_maintenance_plan.changes")}
  v_kind := v_row.${p("kind")};
  v_meter := v_row.${p("meter")};
  v_title := case when update_maintenance_plan.changes ? 'title' then v_title else v_row.${p("title")} end;
  v_days := case when update_maintenance_plan.changes ? 'everyDays' then v_days else v_row.${p("everyDays")} end;
  v_value := case when update_maintenance_plan.changes ? 'everyValue' then v_value else v_row.${p("everyValue")} end;
  v_asset := case when update_maintenance_plan.changes ? 'assetId' then v_asset else v_row.${p("asset")} end;
  v_priority := case when update_maintenance_plan.changes ? 'priority' then v_priority else v_row.${p("priority")} end;
  v_status := coalesce(update_maintenance_plan.changes ->> 'status', v_row.${p("status")});
  if v_status not in ('active', 'paused') then
    ${q.invalid("the status is active or paused")}
  end if;
  ${checks}
  begin
    update ${plans} x set
      ${p("title")} = v_title, ${p("asset")} = v_asset, ${p("everyDays")} = v_days, ${p("everyValue")} = v_value,
      ${p("priority")} = v_priority, ${p("status")} = v_status,
      ${p("nextDueAt")} = case when v_kind = 'time' then coalesce(x.${p("lastDoneAt")}, x.${p("createdAt")}) + v_days * interval '1 day' end,
      ${p("updatedAt")} = now()
    where x.${p("id")} = v_row.${p("id")}
    returning * into v_row;${partsInsert(`v_row.${p("id")}`, `v_row.${p("tenant")}`, "update_maintenance_plan.changes")}
  exception when check_violation or not_null_violation or invalid_text_representation then
    ${q.invalid("a part needs a name of 1 to 200 characters and a quantity above 0")}
  end;
  ${q.recordPlan("maintenance_plan.updated", "v_row", "maintenance plan updated")}
  return ${planView(q, "v_row")};
end;
$$;
${userGrant(`${fn("update_maintenance_plan")}(uuid, jsonb)`)}

-- Deletes a plan with its parts. Its open work order stays. Needs
-- maintenance.manage.
create or replace function ${fn("delete_maintenance_plan")}(plan_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${plans};
begin
  select * into v_row from ${plans} x where x.${p("id")} = delete_maintenance_plan.plan_id for update;
  if not found or not ${q.allowed(`v_row.${p("tenant")}`, q.read)} then
    ${q.planMissing}
  end if;
  if not ${q.allowed(`v_row.${p("tenant")}`, q.manage)} then
    ${q.forbidden("not allowed to manage maintenance plans")}
  end if;
  delete from ${plans} x where x.${p("id")} = v_row.${p("id")};
  ${q.recordPlan("maintenance_plan.deleted", "v_row", "maintenance plan deleted")}
  return ${q.planJson("v_row")};
end;
$$;
${userGrant(`${fn("delete_maintenance_plan")}(uuid)`)}
`;
}

function meterFunctions(ctx: BlockSqlContext, q: MaintenanceSql): string {
  const { fn, m, r, meters, readings } = q;
  const idType = ctx.idType;

  return `
-- Adds a meter, for example hours run or kilometres, optionally on an asset.
-- Needs maintenance.manage.
create or replace function ${fn("create_maintenance_meter")}(tenant ${idType}, name text, unit text, asset_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${meters};
begin
  if not ${q.allowed("create_maintenance_meter.tenant", q.manage)} then
    ${q.forbidden("not allowed to manage maintenance plans")}
  end if;
  begin
    insert into ${meters} (${m("tenant")}, ${m("name")}, ${m("unit")}, ${m("asset")})
    values (create_maintenance_meter.tenant, trim(create_maintenance_meter.name), trim(create_maintenance_meter.unit), create_maintenance_meter.asset_id)
    returning * into v_row;
  exception when check_violation or not_null_violation then
    ${q.invalid("a meter needs a name of 1 to 200 characters and a unit of 1 to 30")}
  end;
  return ${q.meterJson("v_row")};
end;
$$;
${userGrant(`${fn("create_maintenance_meter")}(${idType}, text, text, uuid)`)}

-- Records a reading. A reading never goes below the meter's latest one, and
-- one taken earlier than the latest is kept in the history only. Needs
-- maintenance.record.
create or replace function ${fn("record_meter_reading")}(meter_id uuid, value numeric, read_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${meters};
  v_at timestamptz := coalesce(record_meter_reading.read_at, now());
begin
  select * into v_row from ${meters} x where x.${m("id")} = record_meter_reading.meter_id for update;
  if not found or not ${q.allowed(`v_row.${m("tenant")}`, q.read)} then
    ${q.meterMissing}
  end if;
  if not ${q.allowed(`v_row.${m("tenant")}`, q.record)} then
    ${q.forbidden("not allowed to record meter readings")}
  end if;
  if record_meter_reading.value is null or record_meter_reading.value < 0 then
    ${q.invalid("a reading is a number of 0 or more")}
  end if;
  if (v_row.${m("readAt")} is null or v_at >= v_row.${m("readAt")}) and record_meter_reading.value < v_row.${m("reading")} then
    ${q.invalid("a reading is not below the previous one")}
  end if;
  insert into ${readings} (${r("tenant")}, ${r("meter")}, ${r("value")}, ${r("readAt")}, ${r("readBy")})
  values (v_row.${m("tenant")}, v_row.${m("id")}, record_meter_reading.value, v_at, auth.uid());
  if v_row.${m("readAt")} is null or v_at >= v_row.${m("readAt")} then
    update ${meters} x set ${m("reading")} = record_meter_reading.value, ${m("readAt")} = v_at
    where x.${m("id")} = v_row.${m("id")}
    returning * into v_row;
  end if;
  ${ctx.record({
    type: "maintenance_meter_reading.recorded",
    payload: `jsonb_build_object('organizationId', v_row.${m("tenant")}, 'meterId', v_row.${m("id")}, 'value', record_meter_reading.value::text, 'readAt', v_at)`,
    subject: `'maintenance-meters/' || v_row.${m("id")}::text`,
    tenant: `v_row.${m("tenant")}`,
    audit: false,
  })}
  return ${q.meterJson("v_row")};
end;
$$;
${userGrant(`${fn("record_meter_reading")}(uuid, numeric, timestamptz)`)}

-- The meters of an organization with their latest reading.
create or replace function ${fn("list_maintenance_meters")}(tenant ${idType})
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not ${q.allowed("list_maintenance_meters.tenant", q.read)} then
    ${q.forbidden("not allowed to read maintenance")}
  end if;
  return coalesce((
    select jsonb_agg(${q.meterJson("x")} order by x.${m("name")}, x.${m("id")})
    from ${meters} x where x.${m("tenant")} = list_maintenance_meters.tenant
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_maintenance_meters")}(${idType})`)}
`;
}

function calibrationFunctions(ctx: BlockSqlContext, q: MaintenanceSql): string {
  const { fn, c, calibrations } = q;
  const idType = ctx.idType;

  return `
-- Records a calibration. input is { assetId, instrument, performedAt, dueAt,
-- result: 'pass' | 'fail' | 'adjusted', reference }. Needs maintenance.record.
create or replace function ${fn("record_calibration")}(tenant ${idType}, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${calibrations};
begin
  if not ${q.allowed("record_calibration.tenant", q.record)} then
    ${q.forbidden("not allowed to record calibrations")}
  end if;
  if jsonb_typeof(record_calibration.input) is distinct from 'object' then
    ${q.invalid("input must be an object")}
  end if;
  begin
    insert into ${calibrations} (${c("tenant")}, ${c("asset")}, ${c("instrument")}, ${c("performedAt")}, ${c("dueAt")}, ${c("result")}, ${c("reference")}, ${c("performedBy")})
    values (record_calibration.tenant, nullif(record_calibration.input ->> 'assetId', '')::uuid, trim(record_calibration.input ->> 'instrument'),
      (record_calibration.input ->> 'performedAt')::timestamptz, (record_calibration.input ->> 'dueAt')::timestamptz,
      record_calibration.input ->> 'result', nullif(trim(record_calibration.input ->> 'reference'), ''), auth.uid())
    returning * into v_row;
  exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    ${q.invalid(`a calibration needs an instrument, a performedAt, a dueAt on or after it, and a result of ${MAINTENANCE_CALIBRATION_RESULTS.join(", ")}`)}
  end;
  ${ctx.record({
    type: "maintenance_calibration.recorded",
    payload: `jsonb_build_object('organizationId', v_row.${c("tenant")}, 'id', v_row.${c("id")}, 'assetId', v_row.${c("asset")}, 'instrument', v_row.${c("instrument")}, 'result', v_row.${c("result")})`,
    subject: `'maintenance-calibrations/' || v_row.${c("id")}::text`,
    tenant: `v_row.${c("tenant")}`,
    audit: false,
  })}
  return ${q.calibrationJson("v_row")};
end;
$$;
${userGrant(`${fn("record_calibration")}(${idType}, jsonb)`)}

-- Calibrations, newest first. filters is { assetId, dueBefore, limit, offset }.
create or replace function ${fn("list_calibrations")}(tenant ${idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_calibrations.filters, '{}'::jsonb);
  v_limit integer := ${pageSize("(v_filters ->> 'limit')::integer", 50, 200)};
begin
  if not ${q.allowed("list_calibrations.tenant", q.read)} then
    ${q.forbidden("not allowed to read maintenance")}
  end if;
  return coalesce((
    select jsonb_agg(${q.calibrationJson("y")} order by y.${c("performedAt")} desc, y.${c("id")})
    from (
      select * from ${calibrations} x
      where x.${c("tenant")} = list_calibrations.tenant
        and (not v_filters ? 'assetId' or x.${c("asset")} = (v_filters ->> 'assetId')::uuid)
        and (not v_filters ? 'dueBefore' or x.${c("dueAt")} <= (v_filters ->> 'dueBefore')::timestamptz)
      order by x.${c("performedAt")} desc, x.${c("id")}
      limit v_limit offset coalesce((v_filters ->> 'offset')::integer, 0)
    ) y
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_calibrations")}(${idType}, jsonb)`)}
`;
}

function dispatchFunctions(ctx: BlockSqlContext, q: MaintenanceSql): string {
  const { fn, p, s, plans, parts } = q;
  const idType = ctx.idType;
  const dispatch = ctx.of("dispatch");
  const w = (column: string): string => dispatch.col("workOrders", column);
  const orders = dispatch.table("workOrders");
  const trigger = ctx.naming.rename("bsb_maintenance_work_order");

  return `
-- Plans of an organization, soonest due first. filters is { status, kind,
-- assetId, due: true, limit, offset }. Each plan carries its parts and whether
-- it is due now.
create or replace function ${fn("list_maintenance_plans")}(tenant ${idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_maintenance_plans.filters, '{}'::jsonb);
  v_limit integer := ${pageSize("(v_filters ->> 'limit')::integer", 50, 200)};
begin
  if not ${q.allowed("list_maintenance_plans.tenant", q.read)} then
    ${q.forbidden("not allowed to read maintenance")}
  end if;
  return coalesce((
    select jsonb_agg(y.view order by y.due_first, y.id)
    from (
      select ${planView(q, "x")} as view, x.${p("id")} as id, x.${p("nextDueAt")} as due_first
      from ${plans} x
      where x.${p("tenant")} = list_maintenance_plans.tenant
        and (not v_filters ? 'status' or x.${p("status")} = v_filters ->> 'status')
        and (not v_filters ? 'kind' or x.${p("kind")} = v_filters ->> 'kind')
        and (not v_filters ? 'assetId' or x.${p("asset")} = (v_filters ->> 'assetId')::uuid)
      order by x.${p("nextDueAt")} nulls last, x.${p("id")}
      limit v_limit offset coalesce((v_filters ->> 'offset')::integer, 0)
    ) y
    where (v_filters ->> 'due') is distinct from 'true' or (y.view ->> 'due')::boolean
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_maintenance_plans")}(${idType}, jsonb)`)}

-- Opens a dispatch work order for every active plan that is due and has none
-- open, with the plan's spare parts on it. It returns [{ planId, workOrderId }].
-- The caller needs maintenance.manage and the dispatch permission to create
-- work orders. Run it on a schedule with the service role.
create or replace function ${fn("generate_maintenance_work_orders")}(tenant ${idType})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_plan ${plans};
  v_view jsonb;
  v_order jsonb;
  v_part record;
  v_made jsonb := '[]'::jsonb;
begin
  if not ${q.allowed("generate_maintenance_work_orders.tenant", q.manage)} then
    ${q.forbidden("not allowed to manage maintenance plans")}
  end if;
  for v_plan in
    select * from ${plans} x
    where x.${p("tenant")} = generate_maintenance_work_orders.tenant and x.${p("status")} = 'active' and x.${p("workOrder")} is null
    order by x.${p("nextDueAt")} nulls last, x.${p("id")}
    for update
  loop
    v_view := ${planView(q, "v_plan")};
    continue when not (v_view ->> 'due')::boolean;
    v_order := ${dispatch.fn("create_work_order")}(
      tenant => v_plan.${p("tenant")},
      title => v_plan.${p("title")},
      priority => v_plan.${p("priority")},
      asset_id => v_plan.${p("asset")});
    for v_part in
      select y.${s("name")} as name, y.${s("quantity")} as quantity, y.${s("variant")} as variant
      from ${parts} y where y.${s("plan")} = v_plan.${p("id")} order by y.${s("name")}, y.${s("id")}
    loop
      perform ${dispatch.fn("record_work_order_part")}(
        work_order_id => (v_order ->> 'id')::uuid,
        name => v_part.name,
        quantity => v_part.quantity,
        asset_id => v_plan.${p("asset")},
        variant_id => v_part.variant);
    end loop;
    update ${plans} x set ${p("workOrder")} = (v_order ->> 'id')::uuid, ${p("updatedAt")} = now()
    where x.${p("id")} = v_plan.${p("id")}
    returning * into v_plan;
    ${q.recordPlan("maintenance_plan.triggered", "v_plan", "maintenance work order opened", `, 'workOrderId', v_plan.${p("workOrder")}`)}
    v_made := v_made || jsonb_build_array(jsonb_build_object('planId', v_plan.${p("id")}, 'workOrderId', v_plan.${p("workOrder")}));
  end loop;
  return v_made;
end;
$$;
${userGrant(`${fn("generate_maintenance_work_orders")}(${idType})`)}

-- A plan's next due date moves when its work order is done, and a cancelled
-- work order frees the plan to open another one.
create or replace function ${fn("maintenance_work_order_closed")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_plan ${plans};
  v_done timestamptz;
  v_reading numeric;
begin
  select * into v_plan from ${plans} x where x.${p("workOrder")} = new.${w("id")} for update;
  if not found then
    return new;
  end if;
  if new.${w("status")}::text = 'cancelled' then
    update ${plans} x set ${p("workOrder")} = null, ${p("updatedAt")} = now() where x.${p("id")} = v_plan.${p("id")};
    return new;
  end if;
  v_done := coalesce(new.${w("completedAt")}, now());
  select z.${q.m("reading")} into v_reading from ${q.meters} z where z.${q.m("id")} = v_plan.${p("meter")};
  update ${plans} x set
    ${p("workOrder")} = null,
    ${p("lastDoneAt")} = v_done,
    ${p("lastDoneValue")} = v_reading,
    ${p("nextDueAt")} = case when x.${p("kind")} = 'time' then v_done + x.${p("everyDays")} * interval '1 day' end,
    ${p("updatedAt")} = now()
  where x.${p("id")} = v_plan.${p("id")}
  returning * into v_plan;
  ${q.recordPlan("maintenance_plan.completed", "v_plan", "maintenance work order done", `, 'workOrderId', new.${w("id")}`)}
  return new;
end;
$$;
${triggerGrant(`${fn("maintenance_work_order_closed")}()`)}
drop trigger if exists ${trigger} on ${orders};
create trigger ${trigger} after update of ${w("status")} on ${orders}
  for each row when (new.${w("status")}::text in ('done', 'cancelled') and old.${w("status")}::text is distinct from new.${w("status")}::text)
  execute function ${fn("maintenance_work_order_closed")}();
`;
}

export function maintenanceFunctions(ctx: BlockSqlContext): string {
  const q = maintenanceSql(ctx);

  return `${planFunctions(ctx, q)}${meterFunctions(ctx, q)}${calibrationFunctions(ctx, q)}${dispatchFunctions(ctx, q)}`;
}
