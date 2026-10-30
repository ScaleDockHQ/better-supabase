import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import {
  extraFieldsArg,
  fail,
  SERVICE_CALLER,
  serviceGrant,
  userGrant,
  writeExtraColumns,
} from "../shared.ts";
import {
  administrationJson,
  ADMINISTRATION_EXTRA,
  administrationRecord,
  doubleCheck,
  medicationJson,
  medicationKeys,
  medicationTimeZone,
  missedAfterMinutes,
  missedCaseKind,
  notifyMedication,
  orderJson,
  PLAN_DAYS,
  ROW_RESERVED,
  signatureCheck,
} from "./medications-shared.ts";

/**
 * Opens a case of `kind` for the missed dose in `v_row`, linked to the order's
 * record, seeding the organization's case kinds on first use.
 */
function missedCaseSql(ctx: BlockSqlContext, kind: string): string {
  const cases = ctx.of("cases");
  const k = (column: string): string => cases.col("kinds", column);
  const a = (column: string): string => ctx.col("administrations", column);
  const o = (column: string): string => ctx.col("orders", column);
  const m = (column: string): string => ctx.col("medications", column);
  const zone = sqlString(medicationTimeZone(ctx));

  const kindId = `select y.${k("id")} into v_case_kind from ${cases.table("kinds")} y
    where y.${k("tenant")}::text = v_row.${a("tenant")}::text and y.${k("key")} = ${sqlString(kind)} and y.${k("archivedAt")} is null;`;

  return `
    ${kindId}
    if v_case_kind is null then
      perform ${cases.fn("ensure_case_kinds")}(v_row.${a("tenant")});
      ${kindId}
    end if;
    if v_case_kind is not null then
      perform ${cases.fn("open_case_as")}(v_case_kind, jsonb_build_object(
        'title', left('Missed dose: ' || coalesce((select z.${m("name")} from ${ctx.table("medications")} z where z.${m("id")} = v_order.${o("medication")}), 'medication')
          || ' at ' || to_char(v_row.${a("scheduledAt")} at time zone ${zone}, 'YYYY-MM-DD HH24:MI'), 200),
        'source', 'internal',
        'occurredAt', v_row.${a("scheduledAt")},
        'originType', v_order.${o("subjectType")},
        'originId', v_order.${o("subjectId")}
      ), null);
    end if;`;
}

/** The planning, recording, missed-dose and chart functions. */
export function medicationAdministrationFunctions(
  ctx: BlockSqlContext,
): string {
  const medications = ctx.table("medications");
  const orders = ctx.table("orders");
  const administrations = ctx.table("administrations");
  const m = (column: string): string => ctx.col("medications", column);
  const o = (column: string): string => ctx.col("orders", column);
  const a = (column: string): string => ctx.col("administrations", column);
  const fn = (name: string): string => ctx.fn(name);

  const extras = ctx.extraColumns(
    "administrations",
    ROW_RESERVED,
    ADMINISTRATION_EXTRA,
  );

  const fields = extraFieldsArg(extras);
  const hasSignature = ctx.has("administrations", "signature");

  /** The `signature_id` parameter of record_medication_administration. */
  const signed = hasSignature
    ? { param: ", signature_id uuid default null", type: ", uuid" }
    : { param: "", type: "" };

  const signatureSet = hasSignature
    ? `,\n    ${a("signature")} = record_medication_administration.signature_id`
    : "";

  /** Drops the signature this build left out so no stale overload stays. */
  const dropOld = (name: string, types: string): string =>
    hasSignature
      ? `drop function if exists ${fn(name)}(${types});\ndrop function if exists ${fn(name)}(${types}, jsonb);`
      : "";

  const idType = ctx.idType;
  const { administer, manage } = medicationKeys(ctx);
  const canSubject = ctx.of("subjects").fn("can_subject");
  const zone = sqlString(medicationTimeZone(ctx));
  const today = `(now() at time zone ${zone})::date`;
  const missedAfter = String(missedAfterMinutes(ctx));
  const claims = ctx.installed("notifications") ? "\n  v_claims text;" : "";
  const caseKind = missedCaseKind(ctx);
  const caseVars = caseKind === undefined ? "" : "\n  v_case_kind uuid;";
  const openCase = caseKind === undefined ? "" : missedCaseSql(ctx, caseKind);

  const hasNote = ctx.has("administrations", "note");

  const noteSet = hasNote
    ? `, ${a("note")} = nullif(trim(record_medication_administration.note), '')`
    : "";

  const forbidden = (message: string): string =>
    fail("MEDICATION_FORBIDDEN", message);

  const invalid = (message: string): string =>
    fail("MEDICATION_ADMINISTRATION_INVALID", message, "22023");

  const inactive = fail(
    "MEDICATION_ORDER_INACTIVE",
    "the medication order isn't active",
    "22023",
  );

  const mayAdminister = (order: string): string =>
    `(${SERVICE_CALLER} or (${ctx.can("tenant", `${order}.${o("tenant")}`, administer)} and coalesce(${canSubject}(${order}.${o("subjectType")}, ${order}.${o("subjectId")}, 'read'), false)))`;

  const highRisk = `coalesce((select y.${m("highRisk")} from ${medications} y where y.${m("tenant")} = v_order.${o("tenant")} and y.${m("id")} = v_order.${o("medication")}), false)`;

  const recorded = administrationRecord(
    ctx,
    "medication_administration.recorded",
    "v_row",
    "v_order",
    "Medication dose recorded",
  );

  const startMinute = `coalesce(split_part(v_order.${o("schedule")} ->> 'startTime', ':', 1)::integer * 60 + split_part(v_order.${o("schedule")} ->> 'startTime', ':', 2)::integer, 0)`;

  const everyMinutes = `(v_order.${o("schedule")} ->> 'everyHours')::integer * 60`;

  return `
-- Plans the doses of the organization's active scheduled orders from now
-- until \`until\` (at most ${String(PLAN_DAYS)} days ahead), in the block's time zone. A dose
-- already planned is kept, so the planner can run on a timer. Returns how many
-- doses it planned.
create or replace function ${fn("plan_medication_administrations")}(tenant ${idType}, until timestamptz)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_order ${orders}%rowtype;
  v_until timestamptz;
  v_today date := ${today};
  v_last date;
  v_count integer := 0;
  v_planned integer;
begin
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", "plan_medication_administrations.tenant", manage)}) then
    ${forbidden("not allowed to plan medication")}
  end if;
  if plan_medication_administrations.until is null then
    ${fail("MEDICATION_ORDER_INVALID", "planning needs an end time", "22023")}
  end if;
  v_until := least(plan_medication_administrations.until, now() + interval '${String(PLAN_DAYS)} days');
  v_last := (v_until at time zone ${zone})::date;
  for v_order in
    select * from ${orders} x
    where x.${o("tenant")} = plan_medication_administrations.tenant
      and x.${o("status")} = 'active'
      and x.${o("schedule")} is not null
      and x.${o("startsOn")} <= v_last
      and (x.${o("endsOn")} is null or x.${o("endsOn")} >= v_today)
  loop
    insert into ${administrations} (${a("tenant")}, ${a("order")}, ${a("scheduledAt")}, ${a("status")}, ${a("dose")})
    select v_order.${o("tenant")}, v_order.${o("id")}, s.at, 'planned', v_order.${o("dose")}
    from (
      select ((d.day + make_interval(mins => t.minute)) at time zone ${zone}) as at
      from generate_series(0, least(coalesce(v_order.${o("endsOn")}, v_last), v_last) - greatest(v_order.${o("startsOn")}, v_today)) as g(n)
      cross join lateral (select greatest(v_order.${o("startsOn")}, v_today) + g.n as day) d
      cross join lateral (
        select split_part(x #>> '{}', ':', 1)::integer * 60 + split_part(x #>> '{}', ':', 2)::integer as minute
        from jsonb_array_elements(coalesce(v_order.${o("schedule")} -> 'times', '[]'::jsonb)) x
        union
        select ${startMinute} + k * ${everyMinutes}
        from generate_series(0, 23) k
        where v_order.${o("schedule")} ? 'everyHours' and ${startMinute} + k * ${everyMinutes} < 1440
      ) t
      where not (v_order.${o("schedule")} ? 'weekdays')
        or extract(isodow from d.day)::integer in (select (w #>> '{}')::integer from jsonb_array_elements(v_order.${o("schedule")} -> 'weekdays') w)
    ) s
    where s.at > now() and s.at <= v_until
    on conflict (${a("order")}, ${a("scheduledAt")}) do nothing;
    get diagnostics v_planned = row_count;
    v_count := v_count + v_planned;
  end loop;
  return v_count;
end;
$$;
${userGrant(`${fn("plan_medication_administrations")}(${idType}, timestamptz)`)}

-- Records a planned or missed dose as given, refused or skipped. refused and
-- skipped need a reason. A dose of a high-risk medication, or of an order that
-- requires it, needs checked_by: another member who may administer.
${dropOld("record_medication_administration", "uuid, text, numeric, text, uuid, text")}
${fields.drop(fn("record_medication_administration"), `uuid, text, numeric, text, uuid, text${signed.type}`)}
create or replace function ${fn("record_medication_administration")}(administration_id uuid, status text, dose numeric default null, reason text default null, checked_by uuid default null, note text default null${signed.param}${fields.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${administrations}%rowtype;
  v_order ${orders}%rowtype;
  v_status text := lower(trim(record_medication_administration.status));
  v_reason text := nullif(trim(record_medication_administration.reason), '');
  v_dose numeric;
begin
  select * into v_row from ${administrations} x where x.${a("id")} = record_medication_administration.administration_id for update;
  if not found then
    ${fail("MEDICATION_ADMINISTRATION_NOT_FOUND", "medication dose not found", "P0002")}
  end if;
  select * into v_order from ${orders} x where x.${o("id")} = v_row.${a("order")};
  if not ${mayAdminister("v_order")} then
    ${forbidden("not allowed to administer medication")}
  end if;
  if v_status is null or v_status not in ('given', 'refused', 'skipped') then
    ${invalid("a dose is recorded as given, refused or skipped")}
  end if;
  if v_row.${a("status")} not in ('planned', 'missed') then
    ${invalid("the dose is already recorded")}
  end if;
  if v_order.${o("status")} <> 'active' then
    ${inactive}
  end if;
  if v_status in ('refused', 'skipped') and v_reason is null then
    ${fail("MEDICATION_REASON_REQUIRED", "a refused or skipped dose needs a reason", "22023")}
  end if;
  if length(v_reason) > 1000 then
    ${invalid("a reason is at most 1000 characters")}
  end if;
  if v_status = 'given' then
    v_dose := coalesce(record_medication_administration.dose, v_row.${a("dose")}, v_order.${o("dose")});
    if v_dose <= 0 then
      ${invalid("a dose is above zero")}
    end if;
    ${doubleCheck(ctx, {
      needed: `(${highRisk} or v_order.${o("requiresDoubleCheck")})`,
      checker: "record_medication_administration.checked_by",
      tenant: `v_order.${o("tenant")}`,
    })}
  end if;
  ${
    hasSignature
      ? signatureCheck(ctx, {
          signature: "record_medication_administration.signature_id",
          tenant: `v_order.${o("tenant")}`,
          type: "'medication_administration'",
          id: `v_row.${a("id")}::text`,
        })
      : ""
  }
  ${ctx.hook("before_medication_administration_record", [
    ["uuid", `v_order.${o("id")}`],
    ["text", "v_status"],
  ])}
  update ${administrations} x set
    ${a("status")} = v_status,
    ${a("administeredAt")} = now(),
    ${a("dose")} = case when v_status = 'given' then v_dose else x.${a("dose")} end,
    ${a("performer")} = (select auth.uid()),
    ${a("checkedBy")} = case when v_status = 'given' then record_medication_administration.checked_by end,
    ${a("reason")} = v_reason${noteSet}${signatureSet}
  where x.${a("id")} = v_row.${a("id")}
  returning x.* into v_row;${writeExtraColumns(administrations, extras, "record_medication_administration.fields", `x.${a("id")} = v_row.${a("id")}`, "v_row")}
  ${recorded}
  ${ctx.hook("after_medication_administration_record", [["uuid", `v_row.${a("id")}`]])}
  return ${administrationJson(ctx, "v_row")};
end;
$$;
${userGrant(`${fn("record_medication_administration")}(uuid, text, numeric, text, uuid, text${signed.type}${fields.type})`)}

-- Records a dose of an as-needed order, with the reason it was given. The
-- doses given in the last 24 hours plus this one stay within max_per_day.
${fields.drop(fn("record_as_needed_administration"), "uuid, numeric, text, uuid, text")}
create or replace function ${fn("record_as_needed_administration")}(order_id uuid, dose numeric default null, reason text default null, checked_by uuid default null, note text default null${fields.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${administrations}%rowtype;
  v_order ${orders}%rowtype;
  v_reason text := nullif(trim(record_as_needed_administration.reason), '');
  v_dose numeric;
  v_given numeric;
  v_today date := ${today};
begin
  select * into v_order from ${orders} x where x.${o("id")} = record_as_needed_administration.order_id for update;
  if not found then
    ${fail("MEDICATION_ORDER_NOT_FOUND", "medication order not found", "P0002")}
  end if;
  if not ${mayAdminister("v_order")} then
    ${forbidden("not allowed to administer medication")}
  end if;
  if not v_order.${o("asNeeded")} then
    ${fail("MEDICATION_ORDER_INVALID", "the order isn't given as needed", "22023")}
  end if;
  if v_order.${o("status")} <> 'active' or v_order.${o("startsOn")} > v_today or v_order.${o("endsOn")} < v_today then
    ${inactive}
  end if;
  if v_reason is null then
    ${fail("MEDICATION_REASON_REQUIRED", "an as-needed dose needs the reason it was given", "22023")}
  end if;
  if length(v_reason) > 1000 then
    ${invalid("a reason is at most 1000 characters")}
  end if;
  v_dose := coalesce(record_as_needed_administration.dose, v_order.${o("dose")});
  if v_dose <= 0 then
    ${invalid("a dose is above zero")}
  end if;
  if v_order.${o("maxPerDay")} is not null then
    select coalesce(sum(x.${a("dose")}), 0) into v_given from ${administrations} x
    where x.${a("order")} = v_order.${o("id")} and x.${a("status")} = 'given' and x.${a("administeredAt")} > now() - interval '24 hours';
    if v_given + v_dose > v_order.${o("maxPerDay")} then
      ${fail("MEDICATION_MAX_DOSE_EXCEEDED", "this dose goes over the most the order allows in 24 hours", "22023")}
    end if;
  end if;
  ${doubleCheck(ctx, {
    needed: `(${highRisk} or v_order.${o("requiresDoubleCheck")})`,
    checker: "record_as_needed_administration.checked_by",
    tenant: `v_order.${o("tenant")}`,
  })}
  ${ctx.hook("before_medication_administration_record", [
    ["uuid", `v_order.${o("id")}`],
    ["text", "'given'"],
  ])}
  insert into ${administrations} (${a("tenant")}, ${a("order")}, ${a("administeredAt")}, ${a("status")}, ${a("dose")}, ${a("performer")}, ${a("checkedBy")}, ${a("reason")}${hasNote ? `, ${a("note")}` : ""})
  values (v_order.${o("tenant")}, v_order.${o("id")}, now(), 'given', v_dose, (select auth.uid()), record_as_needed_administration.checked_by, v_reason${hasNote ? ", nullif(trim(record_as_needed_administration.note), '')" : ""})
  returning * into v_row;${writeExtraColumns(administrations, extras, "record_as_needed_administration.fields", `x.${a("id")} = v_row.${a("id")}`, "v_row")}
  ${recorded}
  ${ctx.hook("after_medication_administration_record", [["uuid", `v_row.${a("id")}`]])}
  return ${administrationJson(ctx, "v_row")};
end;
$$;
${userGrant(`${fn("record_as_needed_administration")}(uuid, numeric, text, uuid, text${fields.type})`)}

-- Marks the planned doses more than ${missedAfter} minutes past their time as missed,
-- and tells the members who manage medication. Run it on a timer.
create or replace function ${fn("mark_missed_medication_administrations")}()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${administrations}%rowtype;
  v_order ${orders}%rowtype;
  v_count integer := 0;${claims}${caseVars}
begin
  for v_row in
    update ${administrations} x set ${a("status")} = 'missed'
    where x.${a("status")} = 'planned' and x.${a("scheduledAt")} < now() - interval '${missedAfter} minutes'
    returning x.*
  loop
    select * into v_order from ${orders} x where x.${o("id")} = v_row.${a("order")};
    ${administrationRecord(ctx, "medication_administration.missed", "v_row", "v_order", "Medication dose missed")}
    ${notifyMedication(ctx, {
      type: "medication_administration.missed",
      tenant: `v_row.${a("tenant")}`,
      subjectType: `v_order.${o("subjectType")}`,
      subjectId: `v_order.${o("subjectId")}`,
      permission: manage,
      summary: "'A medication dose was missed'",
      key: `'medication_administration.missed:' || v_row.${a("id")}::text`,
      data: `jsonb_build_object('medicationOrderId', v_order.${o("id")}, 'scheduledAt', v_row.${a("scheduledAt")})`,
    })}${openCase}
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
${serviceGrant(`${fn("mark_missed_medication_administrations")}()`)}

-- The orders of a record that run between since and until (today in the
-- block's time zone by default), with their medication, and the doses
-- planned or recorded in that range.
create or replace function ${fn("medication_chart")}(subject_type text, subject_id text, since timestamptz default null, until timestamptz default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with bounds as (
    select
      coalesce(medication_chart.since, (date_trunc('day', now() at time zone ${zone}) at time zone ${zone})) as since,
      coalesce(medication_chart.until, ((date_trunc('day', now() at time zone ${zone}) + interval '1 day') at time zone ${zone})) as until
  )
  select jsonb_build_object(
    'since', b.since,
    'until', b.until,
    'orders', coalesce((
      select jsonb_agg(${orderJson(ctx, "x")} || jsonb_build_object('medication', ${medicationJson(ctx, "y")}) order by x.${o("startsOn")}, x.${o("id")})
      from ${orders} x
      join ${medications} y on y.${m("tenant")} = x.${o("tenant")} and y.${m("id")} = x.${o("medication")}
      where x.${o("subjectType")} = medication_chart.subject_type
        and x.${o("subjectId")} = medication_chart.subject_id
        and x.${o("startsOn")} <= (b.until at time zone ${zone})::date
        and (x.${o("endsOn")} is null or x.${o("endsOn")} >= (b.since at time zone ${zone})::date)
    ), '[]'::jsonb),
    'administrations', coalesce((
      select jsonb_agg(${administrationJson(ctx, "z")} order by coalesce(z.${a("scheduledAt")}, z.${a("administeredAt")}), z.${a("id")})
      from ${administrations} z
      join ${orders} x on x.${o("tenant")} = z.${a("tenant")} and x.${o("id")} = z.${a("order")}
      where x.${o("subjectType")} = medication_chart.subject_type
        and x.${o("subjectId")} = medication_chart.subject_id
        and coalesce(z.${a("scheduledAt")}, z.${a("administeredAt")}) >= b.since
        and coalesce(z.${a("scheduledAt")}, z.${a("administeredAt")}) < b.until
    ), '[]'::jsonb)
  )
  from bounds b
$$;
${userGrant(`${fn("medication_chart")}(text, text, timestamptz, timestamptz)`)}
`;
}
