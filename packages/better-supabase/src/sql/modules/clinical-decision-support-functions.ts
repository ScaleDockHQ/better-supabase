import type { BlockSqlContext } from "../context.ts";

import { fail, userGrant } from "../shared.ts";
import { decisionSupportSql } from "./clinical-decision-support-sql.ts";
import {
  CARE_ALERT_DECISIONS,
  CARE_ALERT_SEVERITIES,
  CARE_RULE_KINDS,
} from "./clinical-decision-support-values.ts";

const list = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

/** The rule functions and the decision on an alert. */
export function decisionSupportFunctions(ctx: BlockSqlContext): string {
  const sql = decisionSupportSql(ctx);
  const { fn, r, a, rules, alerts, medications } = sql;
  const idType = ctx.idType;
  const m = (column: string): string => medications.col("medications", column);
  const catalog = medications.table("medications");

  return `
-- Saves a rule of the built-in set. attrs is { id, kind, medicationIds,
-- minDose, maxDose, maxPerDay, severity, message, active }: a dose_range rule
-- names one medication and at least one bound, an interaction rule names two,
-- and a duplicate_therapy rule names the medications of one therapy group.
-- Without an id it adds a rule. Needs clinical_decision_support.manage.
create or replace function ${fn("save_care_rule")}(tenant ${idType}, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_attrs jsonb := coalesce(save_care_rule.attrs, '{}'::jsonb);
  v_row ${rules};
  v_id uuid;
  v_kind text;
  v_ids uuid[];
  v_min numeric;
  v_max numeric;
  v_day numeric;
  v_severity text;
  v_message text;
  v_active boolean;
  v_created boolean := false;
begin
  if not ${sql.allowed("save_care_rule.tenant", sql.manage)} then
    ${sql.forbidden("not allowed to change care rules")}
  end if;
  begin
    v_id := nullif(v_attrs ->> 'id', '')::uuid;
    v_ids := coalesce((select array_agg(distinct e.value::uuid) from jsonb_array_elements_text(case when jsonb_typeof(v_attrs -> 'medicationIds') = 'array' then v_attrs -> 'medicationIds' else '[]'::jsonb end) e), '{}');
    v_min := nullif(v_attrs ->> 'minDose', '')::numeric;
    v_max := nullif(v_attrs ->> 'maxDose', '')::numeric;
    v_day := nullif(v_attrs ->> 'maxPerDay', '')::numeric;
    v_active := coalesce((v_attrs ->> 'active')::boolean, true);
  exception when invalid_text_representation or invalid_parameter_value then
    ${sql.invalid("ids are uuids, doses are numbers and active is true or false")}
  end;
  v_kind := v_attrs ->> 'kind';
  v_severity := coalesce(nullif(v_attrs ->> 'severity', ''), 'warning');
  v_message := nullif(trim(v_attrs ->> 'message'), '');
  if v_kind is null or v_kind not in (${list(CARE_RULE_KINDS)}) then
    ${sql.invalid("kind is dose_range, duplicate_therapy or interaction")}
  end if;
  if v_severity not in (${list(CARE_ALERT_SEVERITIES)}) then
    ${sql.invalid("severity is info, warning or critical")}
  end if;
  if v_message is not null and length(v_message) > 1000 then
    ${sql.invalid("a message is up to 1000 characters")}
  end if;
  if (select count(*) from ${catalog} mx where mx.${m("tenant")} = save_care_rule.tenant and mx.${m("id")} = any(v_ids)) <> cardinality(v_ids) then
    ${sql.invalid("medicationIds names medications that are not in the organization's catalog")}
  end if;
  if v_kind = 'dose_range' and (cardinality(v_ids) <> 1 or (v_min is null and v_max is null and v_day is null)) then
    ${sql.invalid("a dose range rule names one medication and at least one bound")}
  end if;
  if v_kind = 'dose_range' and v_min is not null and v_max is not null and v_min > v_max then
    ${sql.invalid("minDose is at most maxDose")}
  end if;
  if v_kind <> 'dose_range' and (v_min is not null or v_max is not null or v_day is not null) then
    ${sql.invalid("only a dose range rule has dose bounds")}
  end if;
  if v_kind = 'interaction' and cardinality(v_ids) <> 2 then
    ${sql.invalid("an interaction rule names two medications")}
  end if;
  if v_kind = 'duplicate_therapy' and cardinality(v_ids) < 2 then
    ${sql.invalid("a duplicate therapy rule names at least two medications")}
  end if;
  begin
    if v_id is null then
      insert into ${rules} (${r("tenant")}, ${r("kind")}, ${r("medicationIds")}, ${r("minDose")}, ${r("maxDose")}, ${r("maxPerDay")}, ${r("severity")}, ${r("message")}, ${r("active")})
      values (save_care_rule.tenant, v_kind, v_ids, v_min, v_max, v_day, v_severity, v_message, v_active)
      returning * into v_row;
      v_created := true;
    else
      update ${rules} x set ${r("kind")} = v_kind, ${r("medicationIds")} = v_ids, ${r("minDose")} = v_min, ${r("maxDose")} = v_max,
        ${r("maxPerDay")} = v_day, ${r("severity")} = v_severity, ${r("message")} = v_message, ${r("active")} = v_active, ${r("updatedAt")} = now()
      where x.${r("id")} = v_id and x.${r("tenant")} = save_care_rule.tenant
      returning * into v_row;
      if not found then
        ${sql.ruleMissing}
      end if;
    end if;
  exception when check_violation then
    ${sql.invalid("the rule's medications and bounds do not fit its kind")}
  end;
  if v_created then
    ${sql.recordRule("care_rule.created", "v_row", "care rule created")}
  else
    ${sql.recordRule("care_rule.updated", "v_row", "care rule changed")}
  end if;
  return ${sql.ruleJson("v_row")};
end;
$$;
${userGrant(`${fn("save_care_rule")}(${idType}, jsonb)`)}

-- Deletes a rule. Alerts it raised stay until the next evaluation resolves
-- them. Needs clinical_decision_support.manage.
create or replace function ${fn("delete_care_rule")}(rule_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${rules};
begin
  select * into v_row from ${rules} x where x.${r("id")} = delete_care_rule.rule_id for update;
  if not found or not ${sql.allowed(`v_row.${r("tenant")}`, sql.read)} then
    ${sql.ruleMissing}
  end if;
  if not ${sql.allowed(`v_row.${r("tenant")}`, sql.manage)} then
    ${sql.forbidden("not allowed to change care rules")}
  end if;
  delete from ${rules} x where x.${r("id")} = v_row.${r("id")};
  ${sql.recordRule("care_rule.deleted", "v_row", "care rule deleted")}
  return ${sql.ruleJson("v_row")};
end;
$$;
${userGrant(`${fn("delete_care_rule")}(uuid)`)}

-- The organization's rules, by kind. Needs clinical_decision_support.read.
create or replace function ${fn("list_care_rules")}(tenant ${idType})
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not ${sql.allowed("list_care_rules.tenant", sql.read)} then
    ${sql.forbidden("not allowed to read care rules")}
  end if;
  return coalesce((
    select jsonb_agg(${sql.ruleJson("y")} order by y.${r("kind")}, y.${r("createdAt")}, y.${r("id")})
    from ${rules} y
    where y.${r("tenant")} = list_care_rules.tenant
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_care_rules")}(${idType})`)}

-- Acknowledges or overrides an open alert. Overriding, and any decision on a
-- critical alert, needs a reason. The decision is audited and stays on the
-- alert while the engine keeps raising it. Needs clinical_decision_support.write.
create or replace function ${fn("decide_care_alert")}(alert_id uuid, decision text, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${alerts};
  v_reason text := nullif(trim(decide_care_alert.reason), '');
begin
  select * into v_row from ${alerts} x where x.${a("id")} = decide_care_alert.alert_id for update;
  if not found or not ${sql.allowed(`v_row.${a("tenant")}`, sql.read)} then
    ${sql.alertMissing}
  end if;
  if not ${sql.allowed(`v_row.${a("tenant")}`, sql.write)} then
    ${sql.forbidden("not allowed to decide on care alerts")}
  end if;
  if decide_care_alert.decision is null or decide_care_alert.decision not in (${list(CARE_ALERT_DECISIONS)}) then
    ${sql.invalid("decision is acknowledged or overridden")}
  end if;
  if v_row.${a("status")} = 'resolved' or (v_row.${a("status")} = 'overridden') or (v_row.${a("status")} = 'acknowledged' and decide_care_alert.decision = 'acknowledged') then
    ${fail("CARE_ALERT_STATUS", "this alert has already been decided or resolved", "55000")}
  end if;
  if v_reason is null and (decide_care_alert.decision = 'overridden' or v_row.${a("severity")} = 'critical') then
    ${sql.invalid("overriding an alert, or deciding on a critical one, needs a reason")}
  end if;
  if v_reason is not null and length(v_reason) > 1000 then
    ${sql.invalid("a reason is up to 1000 characters")}
  end if;
  ${ctx.hook("before_care_alert_decide", [
    ["uuid", `v_row.${a("id")}`],
    ["text", "decide_care_alert.decision"],
  ])}
  update ${alerts} x set ${a("status")} = decide_care_alert.decision, ${a("decidedBy")} = auth.uid(), ${a("decidedAt")} = now(),
    ${a("decisionReason")} = v_reason, ${a("updatedAt")} = now()
  where x.${a("id")} = v_row.${a("id")}
  returning * into v_row;
  ${sql.recordAlert("care_alert.decided", "v_row", "care alert decided")}
  ${ctx.hook("after_care_alert_decide", [["uuid", `v_row.${a("id")}`]])}
  return ${sql.alertJson("v_row")};
end;
$$;
${userGrant(`${fn("decide_care_alert")}(uuid, text, text)`)}
`;
}
