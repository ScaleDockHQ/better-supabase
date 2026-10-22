import type { ModuleContext } from "../context.ts";

import { NPS_MAX } from "../../core/contracts/form-definition.ts";
import { sqlString } from "../../core/template.ts";
import { fail, SERVICE_CALLER, userGrant } from "../shared.ts";
import { OPERATIONS } from "./access-model.ts";

/** The periods `form_nps` groups answers by, in UTC. */
const NPS_BUCKETS = ["day", "week", "month", "quarter", "year"] as const;

/**
 * The NPS counts of the `answer` column of `alias` as a jsonb object:
 * responses, the promoters (9 and 10), passives (7 and 8) and detractors (0 to
 * 6), and the score, the promoters' share minus the detractors', to one
 * decimal.
 */
const npsCounts = (alias: string): string => {
  const promoters = `count(*) filter (where ${alias}.answer >= 9)`;
  const detractors = `count(*) filter (where ${alias}.answer < 7)`;

  return `jsonb_build_object('responses', count(*), 'promoters', ${promoters}, 'passives', count(*) filter (where ${alias}.answer >= 7 and ${alias}.answer < 9), 'detractors', ${detractors}, 'score', case when count(*) = 0 then null else round((${promoters} - ${detractors}) * 100.0 / count(*), 1) end)`;
};

/**
 * `form_nps`: the Net Promoter Score of an nps field (the current version's
 * first one by default) over the submitted and accepted answers between since
 * and until, with a row per period when bucket is set. Needs `forms.review`.
 */
export function formNpsFunction(ctx: ModuleContext): string {
  const forms = ctx.table("forms");
  const versions = ctx.table("versions");
  const submissions = ctx.table("submissions");
  const f = (column: string): string => ctx.col("forms", column);
  const v = (column: string): string => ctx.col("versions", column);
  const s = (column: string): string => ctx.col("submissions", column);
  const fn = (name: string): string => ctx.fn(name);
  const review = ctx.permission("review", OPERATIONS["forms.review"]);

  return `
-- The Net Promoter Score of an nps field (the current version's first one by
-- default) over the submitted and accepted answers between since and until,
-- with a row per day, week, month, quarter or year (UTC) when bucket is set.
create or replace function ${fn("form_nps")}(form_id uuid, field text default null, since timestamptz default null, until timestamptz default null, bucket text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_form ${forms}%rowtype;
  v_field text := form_nps.field;
  v_total jsonb;
  v_periods jsonb;
begin
  select * into v_form from ${forms} x where x.${f("id")} = form_nps.form_id;
  if not found then
    ${fail("FORM_NOT_FOUND", "form not found", "P0002")}
  end if;
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", `v_form.${f("tenant")}`, review)}) then
    ${fail("FORM_FORBIDDEN", "not allowed to read this form's results")}
  end if;
  if form_nps.bucket is not null and form_nps.bucket not in (${NPS_BUCKETS.map(sqlString).join(", ")}) then
    ${fail("FORM_NPS_BUCKET_INVALID", `bucket is ${NPS_BUCKETS.join(", ")}`, "22023")}
  end if;
  if v_field is null then
    select q.field ->> 'key' into v_field
    from ${versions} x
    cross join lateral jsonb_array_elements(x.${v("definition")} -> 'steps') with ordinality as p(step, step_ord)
    cross join lateral jsonb_array_elements(p.step -> 'fields') with ordinality as q(field, field_ord)
    where x.${v("id")} = v_form.${f("currentVersion")} and q.field ->> 'type' = 'nps'
    order by p.step_ord, q.field_ord
    limit 1;
    if v_field is null then
      ${fail("FORM_NPS_FIELD_MISSING", "the form has no nps field", "22023")}
    end if;
  end if;
  with answered as (
    select r.answer, r.answered_at from (
      select case when jsonb_typeof(x.${s("answers")} -> v_field) = 'number' then (x.${s("answers")} ->> v_field)::numeric end as answer,
        x.${s("submittedAt")} as answered_at
      from ${submissions} x
      where x.${s("form")} = form_nps.form_id
        and x.${s("status")} in ('submitted', 'accepted')
        and (form_nps.since is null or x.${s("submittedAt")} >= form_nps.since)
        and (form_nps.until is null or x.${s("submittedAt")} < form_nps.until)
    ) r
    where r.answer between 0 and ${String(NPS_MAX)}
  )
  select ${npsCounts("a")},
    case when form_nps.bucket is null then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object('start', g.start) || g.counts order by g.start)
      from (
        select date_trunc(form_nps.bucket, b.answered_at, 'UTC') as start, ${npsCounts("b")} as counts
        from answered b
        group by 1
      ) g), '[]'::jsonb) end
  into v_total, v_periods
  from answered a;
  return jsonb_build_object('field', v_field) || v_total || jsonb_build_object('periods', v_periods);
end;
$$;
${userGrant(`${fn("form_nps")}(uuid, text, timestamptz, timestamptz, text)`)}
`;
}
