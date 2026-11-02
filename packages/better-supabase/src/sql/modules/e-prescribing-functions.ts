import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { pageSize, userGrant } from "../shared.ts";
import { prescribingSql } from "./e-prescribing-sql.ts";
import { PRESCRIPTION_STATUSES } from "./e-prescribing-values.ts";
import { medicationTimeZone } from "./medications-shared.ts";

const list = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

/** The functions that move a prescription from draft to dispensed. */
export function prescribingFunctions(ctx: BlockSqlContext): string {
  const sql = prescribingSql(ctx);
  const { fn, p, prescriptions, medications } = sql;
  const idType = ctx.idType;
  const o = (column: string): string => medications.col("orders", column);
  const m = (column: string): string => medications.col("medications", column);
  const orders = medications.table("orders");
  const catalog = medications.table("medications");
  const today = `(now() at time zone ${sqlString(medicationTimeZone(medications))})::date`;

  return `
-- What a signed prescription freezes: the order's dose, schedule and bounds with
-- the medication's name and code, so later edits of the order do not change it.
create or replace function ${fn("prescription_order_snapshot")}(tenant ${idType}, order_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'orderId', x.${o("id")}, 'medicationId', x.${o("medication")}, 'medicationName', mx.${m("name")},
    'codeSystem', mx.${m("codeSystem")}, 'code', mx.${m("code")}, 'dose', x.${o("dose")}, 'doseUnit', x.${o("doseUnit")},
    'route', x.${o("route")}, 'schedule', x.${o("schedule")}, 'asNeeded', x.${o("asNeeded")},
    'asNeededReason', x.${o("asNeededReason")}, 'maxPerDay', x.${o("maxPerDay")},
    'startsOn', x.${o("startsOn")}, 'endsOn', x.${o("endsOn")})
  from ${orders} x join ${catalog} mx on mx.${m("tenant")} = x.${o("tenant")} and mx.${m("id")} = x.${o("medication")}
  where x.${o("tenant")} = prescription_order_snapshot.tenant and x.${o("id")} = prescription_order_snapshot.order_id;
$$;
revoke all on function ${fn("prescription_order_snapshot")}(${idType}, uuid) from public, anon, authenticated;

-- Drafts a prescription for an active medication order. The caller becomes the
-- prescriber; the service role names one in attrs.prescriberId. attrs is
-- { prescriberId, prescriberName }. Needs e_prescribing.write.
create or replace function ${fn("create_prescription")}(tenant ${idType}, order_id uuid, attrs jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_attrs jsonb := coalesce(create_prescription.attrs, '{}'::jsonb);
  v_order ${orders};
  v_row ${prescriptions};
  v_prescriber uuid := auth.uid();
  v_name text := nullif(trim(v_attrs ->> 'prescriberName'), '');
begin
  if not ${sql.allowed("create_prescription.tenant", sql.write)} then
    ${sql.forbidden("not allowed to draft prescriptions")}
  end if;
  begin
    v_prescriber := coalesce(v_prescriber, nullif(v_attrs ->> 'prescriberId', '')::uuid);
  exception when invalid_text_representation then
    ${sql.invalid("prescriberId is a uuid")}
  end;
  if v_prescriber is null then
    ${sql.invalid("a prescription needs a prescriber")}
  end if;
  if v_name is not null and length(v_name) > 300 then
    ${sql.invalid("a prescriber name is up to 300 characters")}
  end if;
  select * into v_order from ${orders} x where x.${o("tenant")} = create_prescription.tenant and x.${o("id")} = create_prescription.order_id;
  if not found then
    ${sql.invalid("the order is not one of the organization")}
  end if;
  if v_order.${o("status")} <> 'active' then
    ${sql.status("only an active medication order can be prescribed")}
  end if;
  begin
    insert into ${prescriptions} (${p("tenant")}, ${p("order")}, ${p("subjectType")}, ${p("subjectId")}, ${p("prescriber")}, ${p("prescriberName")})
    values (create_prescription.tenant, v_order.${o("id")}, v_order.${o("subjectType")}, v_order.${o("subjectId")}, v_prescriber, v_name)
    returning * into v_row;
  exception when unique_violation then
    ${sql.status("this order already has a prescription that is not cancelled")}
  end;
  ${sql.record("prescription.created", "v_row", "prescription drafted")}
  return ${sql.json("v_row")};
end;
$$;
${userGrant(`${fn("create_prescription")}(${idType}, uuid, jsonb)`)}

-- Signs a draft. Only the prescriber signs, as a signed-in user holding
-- e_prescribing.sign; the service role never does. The order must still be
-- active and not ended. The signature freezes the order into the prescription.
create or replace function ${fn("sign_prescription")}(prescription_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${prescriptions};
  v_order ${orders};
begin
  select * into v_row from ${prescriptions} x where x.${p("id")} = sign_prescription.prescription_id for update;
  if not found or not ${sql.allowed(`v_row.${p("tenant")}`, sql.read)} then
    ${sql.missing}
  end if;
  if not ${sql.allowed(`v_row.${p("tenant")}`, sql.sign)} then
    ${sql.forbidden("not allowed to sign prescriptions")}
  end if;
  if v_row.${p("prescriber")} is distinct from auth.uid() or auth.uid() is null then
    ${sql.forbidden("only the prescriber signs a prescription")}
  end if;
  if v_row.${p("status")} <> 'draft' then
    ${sql.status("only a draft can be signed")}
  end if;
  select * into v_order from ${orders} x where x.${o("tenant")} = v_row.${p("tenant")} and x.${o("id")} = v_row.${p("order")};
  if not found or v_order.${o("status")} <> 'active' or (v_order.${o("endsOn")} is not null and v_order.${o("endsOn")} < ${today}) then
    ${sql.status("the order is no longer active")}
  end if;
  ${ctx.hook("before_prescription_sign", [["uuid", `v_row.${p("id")}`]])}
  update ${prescriptions} x set ${p("status")} = 'signed', ${p("signedBy")} = auth.uid(), ${p("signedAt")} = now(),
    ${p("snapshot")} = ${fn("prescription_order_snapshot")}(v_row.${p("tenant")}, v_row.${p("order")}), ${p("updatedAt")} = now()
  where x.${p("id")} = v_row.${p("id")}
  returning * into v_row;
  ${sql.record("prescription.signed", "v_row", "prescription signed")}
  ${ctx.hook("after_prescription_sign", [["uuid", `v_row.${p("id")}`]])}
  return ${sql.json("v_row")};
end;
$$;
${userGrant(`${fn("sign_prescription")}(uuid)`)}

-- Records what the gateway answered for a signed prescription: with an error it
-- stays signed so it can be sent again, otherwise it is sent. gateway is the
-- port's key and reference the gateway's id for it. Needs e_prescribing.write.
create or replace function ${fn("record_prescription_delivery")}(prescription_id uuid, gateway text, reference text default null, error text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${prescriptions};
  v_gateway text := nullif(trim(record_prescription_delivery.gateway), '');
  v_reference text := nullif(trim(record_prescription_delivery.reference), '');
  v_error text := nullif(trim(record_prescription_delivery.error), '');
begin
  select * into v_row from ${prescriptions} x where x.${p("id")} = record_prescription_delivery.prescription_id for update;
  if not found or not ${sql.allowed(`v_row.${p("tenant")}`, sql.read)} then
    ${sql.missing}
  end if;
  if not ${sql.allowed(`v_row.${p("tenant")}`, sql.write)} then
    ${sql.forbidden("not allowed to send prescriptions")}
  end if;
  if v_gateway is null or length(v_gateway) > 100 then
    ${sql.invalid("gateway is 1 to 100 characters")}
  end if;
  if length(coalesce(v_reference, '')) > 200 or length(coalesce(v_error, '')) > 1000 then
    ${sql.invalid("a reference is up to 200 characters and an error up to 1000")}
  end if;
  if v_row.${p("status")} <> 'signed' then
    ${sql.status("only a signed prescription can be sent")}
  end if;
  if v_error is not null then
    update ${prescriptions} x set ${p("gateway")} = v_gateway, ${p("deliveryError")} = v_error, ${p("updatedAt")} = now()
    where x.${p("id")} = v_row.${p("id")}
    returning * into v_row;
    ${sql.record("prescription.delivery_failed", "v_row", "prescription delivery failed")}
  else
    update ${prescriptions} x set ${p("status")} = 'sent', ${p("gateway")} = v_gateway, ${p("gatewayReference")} = v_reference,
      ${p("sentAt")} = now(), ${p("deliveryError")} = null, ${p("updatedAt")} = now()
    where x.${p("id")} = v_row.${p("id")}
    returning * into v_row;
    ${sql.record("prescription.sent", "v_row", "prescription sent")}
  end if;
  return ${sql.json("v_row")};
end;
$$;
${userGrant(`${fn("record_prescription_delivery")}(uuid, text, text, text)`)}

-- Marks a sent prescription as dispensed, when the pharmacy reports it. Needs
-- e_prescribing.write.
create or replace function ${fn("record_prescription_dispense")}(prescription_id uuid, dispensed_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${prescriptions};
begin
  select * into v_row from ${prescriptions} x where x.${p("id")} = record_prescription_dispense.prescription_id for update;
  if not found or not ${sql.allowed(`v_row.${p("tenant")}`, sql.read)} then
    ${sql.missing}
  end if;
  if not ${sql.allowed(`v_row.${p("tenant")}`, sql.write)} then
    ${sql.forbidden("not allowed to record dispensing")}
  end if;
  if v_row.${p("status")} <> 'sent' then
    ${sql.status("only a sent prescription can be dispensed")}
  end if;
  update ${prescriptions} x set ${p("status")} = 'dispensed', ${p("dispensedAt")} = coalesce(record_prescription_dispense.dispensed_at, now()), ${p("updatedAt")} = now()
  where x.${p("id")} = v_row.${p("id")}
  returning * into v_row;
  ${sql.record("prescription.dispensed", "v_row", "prescription dispensed")}
  return ${sql.json("v_row")};
end;
$$;
${userGrant(`${fn("record_prescription_dispense")}(uuid, timestamptz)`)}

-- Cancels a prescription that is not dispensed. The prescriber, or a member with
-- e_prescribing.manage, cancels; a signed or sent one needs a reason.
create or replace function ${fn("cancel_prescription")}(prescription_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${prescriptions};
  v_reason text := nullif(trim(cancel_prescription.reason), '');
begin
  select * into v_row from ${prescriptions} x where x.${p("id")} = cancel_prescription.prescription_id for update;
  if not found or not ${sql.allowed(`v_row.${p("tenant")}`, sql.read)} then
    ${sql.missing}
  end if;
  if not ${sql.allowed(`v_row.${p("tenant")}`, sql.manage)} and not (${sql.allowed(`v_row.${p("tenant")}`, sql.write)} and v_row.${p("prescriber")} is not distinct from auth.uid()) then
    ${sql.forbidden("only the prescriber or a manager cancels a prescription")}
  end if;
  if v_row.${p("status")} in ('dispensed', 'cancelled') then
    ${sql.status("a dispensed or cancelled prescription cannot be cancelled")}
  end if;
  if v_reason is null and v_row.${p("status")} <> 'draft' then
    ${sql.invalid("cancelling a signed or sent prescription needs a reason")}
  end if;
  if length(coalesce(v_reason, '')) > 1000 then
    ${sql.invalid("a reason is up to 1000 characters")}
  end if;
  update ${prescriptions} x set ${p("status")} = 'cancelled', ${p("cancelledAt")} = now(), ${p("cancelReason")} = v_reason, ${p("updatedAt")} = now()
  where x.${p("id")} = v_row.${p("id")}
  returning * into v_row;
  ${sql.record("prescription.cancelled", "v_row", "prescription cancelled")}
  return ${sql.json("v_row")};
end;
$$;
${userGrant(`${fn("cancel_prescription")}(uuid, text)`)}

-- One prescription. Needs e_prescribing.read.
create or replace function ${fn("get_prescription")}(prescription_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${prescriptions};
begin
  select * into v_row from ${prescriptions} x where x.${p("id")} = get_prescription.prescription_id;
  if not found or not ${sql.allowed(`v_row.${p("tenant")}`, sql.read)} then
    ${sql.missing}
  end if;
  return ${sql.json("v_row")};
end;
$$;
${userGrant(`${fn("get_prescription")}(uuid)`)}

-- The organization's prescriptions, newest first. filters is { orderId,
-- subjectType, subjectId, status, prescriberId, limit, offset }. Needs
-- e_prescribing.read.
create or replace function ${fn("list_prescriptions")}(tenant ${idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_prescriptions.filters, '{}'::jsonb);
begin
  if not ${sql.allowed("list_prescriptions.tenant", sql.read)} then
    ${sql.forbidden("not allowed to read prescriptions")}
  end if;
  if v_filters ->> 'status' is not null and v_filters ->> 'status' not in (${list(PRESCRIPTION_STATUSES)}) then
    ${sql.invalid("status is draft, signed, sent, dispensed or cancelled")}
  end if;
  return coalesce((
    select jsonb_agg(${sql.json("q")} order by q.${p("createdAt")} desc, q.${p("id")})
    from (
      select y.* from ${prescriptions} y
      where y.${p("tenant")} = list_prescriptions.tenant
        and (v_filters ->> 'orderId' is null or y.${p("order")} = (v_filters ->> 'orderId')::uuid)
        and (v_filters ->> 'subjectType' is null or y.${p("subjectType")} = v_filters ->> 'subjectType')
        and (v_filters ->> 'subjectId' is null or y.${p("subjectId")} = v_filters ->> 'subjectId')
        and (v_filters ->> 'status' is null or y.${p("status")} = v_filters ->> 'status')
        and (v_filters ->> 'prescriberId' is null or y.${p("prescriber")} = (v_filters ->> 'prescriberId')::uuid)
      order by y.${p("createdAt")} desc, y.${p("id")}
      limit ${pageSize("(v_filters ->> 'limit')::int", 50, 200)} offset greatest(coalesce((v_filters ->> 'offset')::int, 0), 0)
    ) q
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_prescriptions")}(${idType}, jsonb)`)}
`;
}
