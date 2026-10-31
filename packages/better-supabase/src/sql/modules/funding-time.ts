import type { BlockSqlContext } from "../context.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { fail, serviceGrant } from "../shared.ts";
import { subjectsOption } from "../subjects.ts";
import { fromTime, timeCategory } from "./funding-shared.ts";
import {
  byEmployee,
  entryEnded,
  entrySubjects,
} from "./time-tracking-owner.ts";
import { userTimeZoneOf } from "./time-tracking-status.ts";

/**
 * `register_funding_deliveries_from_time`, when time-tracking is installed:
 * registers the approved time entries of a range as deliveries.
 */
export function fundingTimeFunctions(ctx: BlockSqlContext): string {
  if (!fromTime(ctx)) {
    return "";
  }

  const time = ctx.of("time-tracking");
  const entries = time.table("entries");
  const timesheets = time.table("timesheets");
  const e = (column: string): string => time.col("entries", column);
  const t = (column: string): string => time.col("timesheets", column);
  const awards = ctx.table("awards");
  const products = ctx.table("products");
  const deliveries = ctx.table("deliveries");
  const w = (column: string): string => ctx.col("awards", column);
  const p = (column: string): string => ctx.col("products", column);
  const d = (column: string): string => ctx.col("deliveries", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const category = timeCategory(ctx);

  const rawZone = time.option("timeZone");

  const zone = sqlString(
    typeof rawZone === "string" && rawZone.length > 0 ? rawZone : "UTC",
  );

  const employee = byEmployee(time);
  const eOwner = employee ? e("employee") : e("user");
  const tOwner = employee ? t("employee") : t("user");

  const week = (at: string, owner: string): string =>
    userTimeZoneOf(time) === undefined
      ? `${time.fn("time_week")}(${at})`
      : `${time.fn("time_week")}(${at}, ${owner})`;

  const approved = `s.${t("approvedAt")} is not null`;

  const { rowSubject } = entrySubjects(time, subjectsOption(time, ["column"]));
  const subject = rowSubject("x");
  const ended = entryEnded(time, "x");
  const performer = time.has("entries", "user") ? `x.${e("user")}` : "null";

  const categoryOf =
    category === undefined ? "null::text" : `x.${sqlIdent(category)}::text`;

  const codeMatch =
    category === undefined
      ? ""
      : `\n        and y.${p("code")} = v_entry.category`;

  return `
-- Registers the approved time entries that started from since to until (days
-- in the time-tracking zone) as deliveries. An entry delivers on the active
-- award of its record${category === undefined ? "" : ` whose product code is its ${category}`}; an
-- entry with no award, or with several, is returned as unmatched. Minutes and
-- hours count the entry's duration; other units count one per entry. An entry
-- registered before is skipped, so the import can run again.
create or replace function ${fn("register_funding_deliveries_from_time")}(tenant ${idType}, since date, until date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_entry record;
  v_awards uuid[];
  v_units numeric;
  v_award uuid;
  v_unit text;
  v_delivery jsonb;
  v_registered jsonb := '[]'::jsonb;
  v_unmatched jsonb := '[]'::jsonb;
begin
  if register_funding_deliveries_from_time.since is null or register_funding_deliveries_from_time.until is null
    or register_funding_deliveries_from_time.until < register_funding_deliveries_from_time.since then
    ${fail("FUNDING_INVALID", "since and until are days, until on or after since", "22023")}
  end if;
  for v_entry in
    select x.${e("id")}::text as id, ${subject.type} as subject_type, ${subject.id}::text as subject_id,
      (x.${e("startedAt")} at time zone ${zone})::date as day,
      extract(epoch from ${ended} - x.${e("startedAt")}) as seconds,
      ${performer} as performer, ${categoryOf} as category
    from ${entries} x
    where x.${e("tenant")} = register_funding_deliveries_from_time.tenant
      and ${ended} is not null
      and ${subject.type} is not null
      and x.${e("startedAt")} >= (register_funding_deliveries_from_time.since::timestamp at time zone ${zone})
      and x.${e("startedAt")} < ((register_funding_deliveries_from_time.until + 1)::timestamp at time zone ${zone})
      and exists (
        select 1 from ${timesheets} s
        where s.${t("tenant")} = x.${e("tenant")} and s.${tOwner} = x.${eOwner}
          and s.${t("week")} = ${week(`x.${e("startedAt")}`, `x.${eOwner}`)} and ${approved}
      )
      and not exists (
        select 1 from ${deliveries} z
        where z.${d("tenant")} = x.${e("tenant")} and z.${d("sourceType")} = 'time_entry' and z.${d("sourceId")} = x.${e("id")}::text
      )
    order by x.${e("startedAt")}, x.${e("id")}
  loop
    select array_agg(a.${w("id")} order by a.${w("id")}), min(y.${p("unit")}) into v_awards, v_unit
    from ${awards} a
    join ${products} y on y.${p("tenant")} = a.${w("tenant")} and y.${p("id")} = a.${w("product")}
    where a.${w("tenant")} = register_funding_deliveries_from_time.tenant
      and a.${w("subjectType")} = v_entry.subject_type and a.${w("subjectId")} = v_entry.subject_id
      and a.${w("status")} = 'active'
      and v_entry.day >= a.${w("startsOn")} and v_entry.day <= coalesce(a.${w("endsOn")}, v_entry.day)
      and (y.${p("validFrom")} is null or v_entry.day >= y.${p("validFrom")})
      and (y.${p("validUntil")} is null or v_entry.day <= y.${p("validUntil")})${codeMatch};
    if coalesce(cardinality(v_awards), 0) <> 1 then
      v_unmatched := v_unmatched || jsonb_build_array(jsonb_build_object(
        'entryId', v_entry.id,
        'subjectType', v_entry.subject_type,
        'subjectId', v_entry.subject_id,
        'deliveredOn', v_entry.day,
        'reason', case when coalesce(cardinality(v_awards), 0) = 0 then 'no_award' else 'several_awards' end
      ));
      continue;
    end if;
    v_award := v_awards[1];
    v_units := case v_unit
      when 'minute' then round(v_entry.seconds / 60, 2)
      when 'hour' then round(v_entry.seconds / 3600, 4)
      else 1
    end;
    if v_units <= 0 then
      v_unmatched := v_unmatched || jsonb_build_array(jsonb_build_object(
        'entryId', v_entry.id,
        'subjectType', v_entry.subject_type,
        'subjectId', v_entry.subject_id,
        'deliveredOn', v_entry.day,
        'reason', 'no_duration'
      ));
      continue;
    end if;
    v_delivery := ${fn("register_funding_delivery")}(v_award, v_entry.day, v_units, 'time_entry', v_entry.id, v_entry.performer, null);
    v_registered := v_registered || jsonb_build_array(v_delivery);
  end loop;
  return jsonb_build_object('registered', v_registered, 'unmatched', v_unmatched);
end;
$$;
${serviceGrant(`${fn("register_funding_deliveries_from_time")}(${idType}, date, date)`)}
`;
}
