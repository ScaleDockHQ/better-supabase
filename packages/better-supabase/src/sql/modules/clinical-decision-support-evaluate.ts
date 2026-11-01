import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { pageSize, userGrant } from "../shared.ts";
import { decisionSupportSql } from "./clinical-decision-support-sql.ts";
import { CARE_BUILT_IN_SOURCE } from "./clinical-decision-support-values.ts";
import { medicationTimeZone } from "./medications-shared.ts";

/**
 * Evaluation, the context for external engines and the alert store: the
 * built-in dose range, duplicate therapy and interaction rules run here, and
 * every engine's alerts go through `sync_care_alerts`.
 */
export function decisionSupportEvaluation(ctx: BlockSqlContext): string {
  const sql = decisionSupportSql(ctx);
  const { fn, r, a, rules, alerts, medications } = sql;
  const idType = ctx.idType;
  const o = (column: string): string => medications.col("orders", column);
  const m = (column: string): string => medications.col("medications", column);
  const orders = medications.table("orders");
  const catalog = medications.table("medications");
  const today = `(now() at time zone ${sqlString(medicationTimeZone(medications))})::date`;
  const source = sqlString(CARE_BUILT_IN_SOURCE);

  const rank = (row: string): string =>
    `case ${row}.${a("severity")} when 'critical' then 0 when 'warning' then 1 else 2 end`;

  const rule = (kind: string): string =>
    `r.${r("tenant")} = evaluate_care_rules.tenant and r.${r("active")} and r.${r("kind")} = '${kind}'`;

  const doseAlert = (
    limit: "min" | "max" | "day",
    column: string,
    value: string,
    sentence: string,
    compare: string,
  ): string => `
      select jsonb_build_object(
        'kind', 'dose_range', 'severity', r.${r("severity")}, 'ruleId', r.${r("id")},
        'orderIds', jsonb_build_array(d.order_id),
        'fingerprint', 'dose_range:' || r.${r("id")}::text || ':' || d.order_id::text || ':${limit}',
        'message', coalesce(r.${r("message")}, format('%s: ${sentence}', d.name, ${value}, d.unit, r.${r(column)})),
        'details', jsonb_build_object('medicationId', d.medication_id, 'limit', '${limit}', 'value', ${value}, 'unit', d.unit, 'bound', r.${r(column)}))
      from active d join ${rules} r on r.${r("medicationIds")}[1] = d.medication_id
      where ${rule("dose_range")} and r.${r(column)} is not null and ${compare}`;

  const context = (name: string, build: string): string =>
    `'${name}', ${build}`;

  const observationContext =
    sql.observations === undefined
      ? "'[]'::jsonb"
      : (() => {
          const ob = sql.observations;
          const x = (column: string): string => ob.col("observations", column);
          const d = (column: string): string => ob.col("definitions", column);

          return `coalesce((select jsonb_agg(jsonb_build_object('key', q.${d("key")}, 'code', q.${d("code")}, 'codeSystem', q.${d("codeSystem")}, 'unit', q.${d("unit")}, 'valueNumber', q.${x("valueNumber")}, 'valueText', q.${x("valueText")}, 'valueCode', q.${x("valueCode")}, 'flag', q.${x("flag")}, 'observedAt', q.${x("observedAt")}) order by q.${d("key")})
      from (select distinct on (od.${d("id")}) od.${d("key")}, od.${d("code")}, od.${d("codeSystem")}, od.${d("unit")}, ox.${x("valueNumber")}, ox.${x("valueText")}, ox.${x("valueCode")}, ox.${x("flag")}, ox.${x("observedAt")}
        from ${ob.table("observations")} ox join ${ob.table("definitions")} od on od.${d("id")} = ox.${x("definition")}
        where ox.${x("tenant")} = care_decision_context.tenant and ox.${x("subjectType")} = care_decision_context.subject_type and ox.${x("subjectId")} = care_decision_context.subject_id and ox.${x("status")} <> 'entered_in_error'
        order by od.${d("id")}, ox.${x("observedAt")} desc) q), '[]'::jsonb)`;
        })();

  const consentContext =
    sql.consents === undefined
      ? "'[]'::jsonb"
      : (() => {
          const co = sql.consents;
          const c = (column: string): string => co.col("consents", column);
          const p = (column: string): string => co.col("purposes", column);

          return `coalesce((select jsonb_agg(jsonb_build_object('purpose', pu.${p("key")}, 'status', cx.${c("status")}, 'scope', cx.${c("scope")}, 'grantedAt', cx.${c("grantedAt")}, 'validUntil', cx.${c("validUntil")}) order by pu.${p("key")})
      from ${co.table("consents")} cx join ${co.table("purposes")} pu on pu.${p("id")} = cx.${c("purpose")}
      where cx.${c("tenant")} = care_decision_context.tenant and cx.${c("subjectType")} = care_decision_context.subject_type and cx.${c("subjectId")} = care_decision_context.subject_id and cx.${c("status")} = 'granted'), '[]'::jsonb)`;
        })();

  const planContext =
    sql.carePlans === undefined
      ? "null"
      : (() => {
          const cp = sql.carePlans;
          const p = (column: string): string => cp.col("plans", column);

          return `(select jsonb_build_object('id', px.${p("id")}, 'title', px.${p("title")}, 'version', px.${p("version")}, 'reviewOn', px.${p("reviewOn")})
      from ${cp.table("plans")} px
      where px.${p("tenant")} = care_decision_context.tenant and px.${p("subjectType")} = care_decision_context.subject_type and px.${p("subjectId")} = care_decision_context.subject_id and px.${p("status")} = 'active'
      order by px.${p("version")} desc limit 1)`;
        })();

  const activeOrders = (tenant: string, type: string, id: string): string =>
    `from ${orders} o join ${catalog} mx on mx.${m("id")} = o.${o("medication")} and mx.${m("tenant")} = o.${o("tenant")}
    where o.${o("tenant")} = ${tenant} and o.${o("subjectType")} = ${type} and o.${o("subjectId")} = ${id}
      and o.${o("status")} = 'active' and o.${o("startsOn")} <= ${today} and (o.${o("endsOn")} is null or o.${o("endsOn")} >= ${today})`;

  return `
-- The alerts an engine raised for a record, stored and diffed by fingerprint:
-- a new fingerprint raises an alert, a known one updates it and keeps the
-- decision, and an open or decided alert of this source that the engine no
-- longer returns is resolved. Not callable through the API.
create or replace function ${fn("sync_care_alerts")}(tenant ${idType}, subject_type text, subject_id text, source text, alerts jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_item jsonb;
  v_row ${alerts};
  v_seen text[] := '{}';
  v_kind text;
  v_severity text;
  v_message text;
  v_fingerprint text;
  v_rule uuid;
  v_orders uuid[];
  v_details jsonb;
begin
  if jsonb_typeof(sync_care_alerts.alerts) is distinct from 'array' then
    ${sql.invalid("alerts is an array")}
  end if;
  for v_item in select e.value from jsonb_array_elements(sync_care_alerts.alerts) e loop
    v_kind := coalesce(nullif(v_item ->> 'kind', ''), 'other');
    v_severity := coalesce(nullif(v_item ->> 'severity', ''), 'warning');
    v_message := nullif(trim(v_item ->> 'message'), '');
    if v_kind not in ('dose_range', 'duplicate_therapy', 'interaction', 'allergy', 'other') then
      ${sql.invalid("kind is dose_range, duplicate_therapy, interaction, allergy or other")}
    end if;
    if v_severity not in ('info', 'warning', 'critical') then
      ${sql.invalid("severity is info, warning or critical")}
    end if;
    if v_message is null or length(v_message) > 1000 then
      ${sql.invalid("an alert needs a message of up to 1000 characters")}
    end if;
    v_fingerprint := coalesce(nullif(trim(v_item ->> 'fingerprint'), ''), md5(v_kind || '|' || v_message));
    if length(v_fingerprint) > 200 then
      ${sql.invalid("a fingerprint is up to 200 characters")}
    end if;
    v_details := case when jsonb_typeof(v_item -> 'details') = 'object' then v_item -> 'details' else null end;
    begin
      v_rule := nullif(v_item ->> 'ruleId', '')::uuid;
      v_orders := coalesce((select array_agg(e.value::uuid) from jsonb_array_elements_text(case when jsonb_typeof(v_item -> 'orderIds') = 'array' then v_item -> 'orderIds' else '[]'::jsonb end) e), '{}');
    exception when invalid_text_representation then
      ${sql.invalid("ruleId and orderIds are uuids")}
    end;
    select * into v_row from ${alerts} x
    where x.${a("tenant")} = sync_care_alerts.tenant and x.${a("subjectType")} = sync_care_alerts.subject_type and x.${a("subjectId")} = sync_care_alerts.subject_id
      and x.${a("fingerprint")} = v_fingerprint and x.${a("status")} <> 'resolved'
    for update;
    if found then
      update ${alerts} x set ${a("kind")} = v_kind, ${a("severity")} = v_severity, ${a("message")} = v_message, ${a("rule")} = v_rule,
        ${a("orderIds")} = v_orders, ${a("details")} = v_details, ${a("updatedAt")} = now()
      where x.${a("id")} = v_row.${a("id")};
    else
      insert into ${alerts} (${a("tenant")}, ${a("subjectType")}, ${a("subjectId")}, ${a("kind")}, ${a("severity")}, ${a("source")}, ${a("rule")}, ${a("orderIds")}, ${a("message")}, ${a("details")}, ${a("fingerprint")})
      values (sync_care_alerts.tenant, sync_care_alerts.subject_type, sync_care_alerts.subject_id, v_kind, v_severity, sync_care_alerts.source, v_rule, v_orders, v_message, v_details, v_fingerprint)
      returning * into v_row;
      ${sql.recordAlert("care_alert.raised", "v_row", "care alert raised")}
    end if;
    v_seen := array_append(v_seen, v_fingerprint);
  end loop;
  for v_row in
    update ${alerts} x set ${a("status")} = 'resolved', ${a("updatedAt")} = now()
    where x.${a("tenant")} = sync_care_alerts.tenant and x.${a("subjectType")} = sync_care_alerts.subject_type and x.${a("subjectId")} = sync_care_alerts.subject_id
      and x.${a("source")} = sync_care_alerts.source and x.${a("status")} <> 'resolved' and not (x.${a("fingerprint")} = any(v_seen))
    returning x.*
  loop
    ${sql.recordAlert("care_alert.resolved", "v_row", "care alert resolved")}
  end loop;
  return coalesce((
    select jsonb_agg(${sql.alertJson("y")} order by ${rank("y")}, y.${a("createdAt")}, y.${a("id")})
    from ${alerts} y
    where y.${a("tenant")} = sync_care_alerts.tenant and y.${a("subjectType")} = sync_care_alerts.subject_type and y.${a("subjectId")} = sync_care_alerts.subject_id and y.${a("status")} <> 'resolved'
  ), '[]'::jsonb);
end;
$$;
revoke execute on function ${fn("sync_care_alerts")}(${idType}, text, text, text, jsonb) from public, anon, authenticated, service_role;

-- Runs the built-in rule set over a record's active medication orders: dose
-- range (a dose or a daily total outside a rule's bounds), duplicate therapy
-- (one medication ordered twice, or two medications of a therapy group) and
-- interaction (both medications of a pair are active). Returns the record's
-- open alerts. Needs clinical_decision_support.write.
create or replace function ${fn("evaluate_care_rules")}(tenant ${idType}, subject_type text, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_alerts jsonb;
begin
  if not ${sql.allowed("evaluate_care_rules.tenant", sql.write)} then
    ${sql.forbidden("not allowed to evaluate care rules")}
  end if;
  ${sql.subjectCheck("evaluate_care_rules.subject_type", "evaluate_care_rules.subject_id", "evaluate_care_rules.tenant", "evaluating")}
  with active as (
    select o.${o("id")} as order_id, o.${o("medication")} as medication_id, o.${o("dose")} as dose, o.${o("doseUnit")} as unit, mx.${m("name")} as name,
      coalesce(
        case when o.${o("schedule")} ? 'times' then jsonb_array_length(o.${o("schedule")} -> 'times') * o.${o("dose")}
          when o.${o("schedule")} ? 'everyHours' then 24 / nullif((o.${o("schedule")} ->> 'everyHours')::numeric, 0) * o.${o("dose")} end,
        case when o.${o("asNeeded")} then o.${o("maxPerDay")} end) as per_day
    ${activeOrders("evaluate_care_rules.tenant", "evaluate_care_rules.subject_type", "evaluate_care_rules.subject_id")}
  ), raised(alert) as (${doseAlert("min", "minDose", "d.dose", "a dose of %s %s is below the minimum of %s", `d.dose < r.${r("minDose")}`)}
    union all ${doseAlert("max", "maxDose", "d.dose", "a dose of %s %s is above the maximum of %s", `d.dose > r.${r("maxDose")}`)}
    union all ${doseAlert("day", "maxPerDay", "d.per_day", "%s %s a day is above the maximum of %s", `d.per_day > r.${r("maxPerDay")}`)}
    union all
      select jsonb_build_object(
        'kind', 'duplicate_therapy', 'severity', 'warning',
        'orderIds', to_jsonb(array_agg(d.order_id order by d.order_id)),
        'fingerprint', 'duplicate:' || d.medication_id::text,
        'message', format('%s is ordered more than once', min(d.name)),
        'details', jsonb_build_object('medicationId', d.medication_id))
      from active d group by d.medication_id having count(*) > 1
    union all
      select jsonb_build_object(
        'kind', 'duplicate_therapy', 'severity', r.${r("severity")}, 'ruleId', r.${r("id")},
        'orderIds', to_jsonb(array_agg(d.order_id order by d.order_id)),
        'fingerprint', 'therapy_group:' || r.${r("id")}::text,
        'message', coalesce(r.${r("message")}, format('%s are in the same therapy group', string_agg(distinct d.name, ', '))),
        'details', jsonb_build_object('medicationIds', to_jsonb(array_agg(distinct d.medication_id))))
      from ${rules} r join active d on d.medication_id = any(r.${r("medicationIds")})
      where ${rule("duplicate_therapy")}
      group by r.${r("id")} having count(distinct d.medication_id) > 1
    union all
      select jsonb_build_object(
        'kind', 'interaction', 'severity', r.${r("severity")}, 'ruleId', r.${r("id")},
        'orderIds', (select to_jsonb(array_agg(d.order_id order by d.order_id)) from active d where d.medication_id = any(r.${r("medicationIds")})),
        'fingerprint', 'interaction:' || r.${r("id")}::text,
        'message', coalesce(r.${r("message")}, format('%s interact', (select string_agg(distinct d.name, ' and ') from active d where d.medication_id = any(r.${r("medicationIds")})))),
        'details', jsonb_build_object('medicationIds', to_jsonb(r.${r("medicationIds")})))
      from ${rules} r
      where ${rule("interaction")}
        and (select count(distinct d.medication_id) from active d where d.medication_id = any(r.${r("medicationIds")})) = 2
  )
  select coalesce(jsonb_agg(raised.alert), '[]'::jsonb) into v_alerts from raised;
  return ${fn("sync_care_alerts")}(evaluate_care_rules.tenant, evaluate_care_rules.subject_type, evaluate_care_rules.subject_id, ${source}, v_alerts);
end;
$$;
${userGrant(`${fn("evaluate_care_rules")}(${idType}, text, text)`)}

-- Stores the alerts an external engine returned for a record, keyed by its
-- source name. Alerts of that source the engine no longer returns are resolved.
-- The built-in source name is reserved. Needs clinical_decision_support.write.
create or replace function ${fn("record_care_alerts")}(tenant ${idType}, subject_type text, subject_id text, source text, alerts jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not ${sql.allowed("record_care_alerts.tenant", sql.write)} then
    ${sql.forbidden("not allowed to record care alerts")}
  end if;
  if coalesce(trim(record_care_alerts.source), '') = '' or length(record_care_alerts.source) > 100 or record_care_alerts.source = ${source} then
    ${sql.invalid("source names the engine, up to 100 characters, and is not the built-in source")}
  end if;
  ${sql.subjectCheck("record_care_alerts.subject_type", "record_care_alerts.subject_id", "record_care_alerts.tenant", "recording")}
  return ${fn("sync_care_alerts")}(record_care_alerts.tenant, record_care_alerts.subject_type, record_care_alerts.subject_id, trim(record_care_alerts.source), record_care_alerts.alerts);
end;
$$;
${userGrant(`${fn("record_care_alerts")}(${idType}, text, text, text, jsonb)`)}

-- What an external engine needs to decide: the record's active medication
-- orders, the latest observation of each kind, granted consents and the
-- active care plan. Blocks that aren't installed contribute nothing. Needs
-- clinical_decision_support.read.
create or replace function ${fn("care_decision_context")}(tenant ${idType}, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not ${sql.allowed("care_decision_context.tenant", sql.read)} then
    ${sql.forbidden("not allowed to read the decision context")}
  end if;
  ${sql.subjectCheck("care_decision_context.subject_type", "care_decision_context.subject_id", "care_decision_context.tenant", "the context")}
  return jsonb_build_object(
    'organizationId', care_decision_context.tenant,
    'subjectType', care_decision_context.subject_type,
    'subjectId', care_decision_context.subject_id,
    ${context(
      "medications",
      `coalesce((select jsonb_agg(jsonb_build_object('orderId', o.${o("id")}, 'medicationId', o.${o("medication")}, 'name', mx.${m("name")}, 'codeSystem', mx.${m("codeSystem")}, 'code', mx.${m("code")}, 'dose', o.${o("dose")}, 'doseUnit', o.${o("doseUnit")}, 'asNeeded', o.${o("asNeeded")}, 'maxPerDay', o.${o("maxPerDay")}, 'schedule', o.${o("schedule")}, 'startsOn', o.${o("startsOn")}, 'endsOn', o.${o("endsOn")}) order by mx.${m("name")}, o.${o("id")})
      ${activeOrders("care_decision_context.tenant", "care_decision_context.subject_type", "care_decision_context.subject_id")}), '[]'::jsonb)`,
    )},
    ${context("observations", observationContext)},
    ${context("consents", consentContext)},
    ${context("carePlan", planContext)});
end;
$$;
${userGrant(`${fn("care_decision_context")}(${idType}, text, text)`)}

-- A record's alerts, serious ones first. filters is { subjectType, subjectId,
-- status, kind, limit, offset }; without a status the resolved ones are left out.
create or replace function ${fn("list_care_alerts")}(tenant ${idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_care_alerts.filters, '{}'::jsonb);
begin
  if not ${sql.allowed("list_care_alerts.tenant", sql.read)} then
    ${sql.forbidden("not allowed to read care alerts")}
  end if;
  return coalesce((
    select jsonb_agg(${sql.alertJson("q")} order by ${rank("q")}, q.${a("createdAt")} desc, q.${a("id")})
    from (
      select y.* from ${alerts} y
      where y.${a("tenant")} = list_care_alerts.tenant
        and (v_filters ->> 'subjectType' is null or y.${a("subjectType")} = v_filters ->> 'subjectType')
        and (v_filters ->> 'subjectId' is null or y.${a("subjectId")} = v_filters ->> 'subjectId')
        and (v_filters ->> 'kind' is null or y.${a("kind")} = v_filters ->> 'kind')
        and ((v_filters ->> 'status' is null and y.${a("status")} <> 'resolved') or y.${a("status")} = v_filters ->> 'status')
      order by y.${a("createdAt")} desc, y.${a("id")}
      limit ${pageSize("(v_filters ->> 'limit')::int", 50, 200)} offset greatest(coalesce((v_filters ->> 'offset')::int, 0), 0)
    ) q
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_care_alerts")}(${idType}, jsonb)`)}
`;
}
