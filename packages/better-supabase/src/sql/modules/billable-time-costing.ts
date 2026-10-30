import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { booksAccounting } from "../accounting-sources-sql.ts";
import { fail, SERVICE_CALLER, userGrant } from "../shared.ts";
import { subjectsOption } from "../subjects.ts";
import { moduleOperations } from "./permissions-model.ts";
import { projectType, workItemType } from "./tasks.ts";
import { entryEnded, entrySubjects } from "./time-tracking-owner.ts";

/** Whether billable time renders `project_costs`: tasks has projects. */
export const costsProjects = (ctx: BlockSqlContext): boolean =>
  ctx.manages &&
  ctx.has("rates", "cost") &&
  ctx.installed("tasks") &&
  ctx.of("tasks").hasTable("projects");

/**
 * `project_costs`: a project's time at cost, the time billed on invoices, the
 * accounting lines on its `project` dimension, the margin and the budget used.
 */
export function projectCostsSql(
  ctx: BlockSqlContext,
  timeZone: string,
): string {
  if (!costsProjects(ctx)) {
    return "";
  }

  const time = ctx.of("time-tracking");
  const tasks = ctx.of("tasks");
  const entries = time.table("entries");
  const e = (column: string): string => time.col("entries", column);
  const r = (column: string): string => ctx.col("rates", column);
  const b = (column: string): string => ctx.col("billed", column);
  const p = (column: string): string => tasks.col("projects", column);
  const w = (column: string): string => tasks.col("items", column);
  const fn = (name: string): string => ctx.fn(name);
  const read = ctx.permission("read", moduleOperations("billable-time").read);
  const { rowSubject } = entrySubjects(time, subjectsOption(time, ["column"]));
  const subject = rowSubject("x");
  const zone = sqlString(timeZone);

  const budget = (logical: string): string =>
    tasks.has("projects", logical) ? `v_project.${p(logical)}` : "null";

  const items = tasks.has("items", "project")
    ? ` or (${subject.type} = ${sqlString(workItemType(tasks))} and ${subject.id} in (
        select y.${w("id")}::text from ${tasks.table("items")} y where y.${w("project")} = v_project.${p("id")}
      ))`
    : "";

  const ledger = booksAccounting(ctx) ? ctx.of("accounting") : undefined;

  const accounting =
    ledger === undefined
      ? "select null::text as currency, 0::bigint as expenses, 0::bigint as income where false"
      : `select l.${ledger.col("lines", "currency")}::text as currency,
        coalesce(sum(l.${ledger.col("lines", "debit")} - l.${ledger.col("lines", "credit")}) filter (where a.${ledger.col("accounts", "type")} = 'expense'), 0)::bigint as expenses,
        coalesce(sum(l.${ledger.col("lines", "credit")} - l.${ledger.col("lines", "debit")}) filter (where a.${ledger.col("accounts", "type")} = 'income'), 0)::bigint as income
      from ${ledger.table("lines")} l
      join ${ledger.table("entries")} n on n.${ledger.col("entries", "id")} = l.${ledger.col("lines", "entry")}
      join ${ledger.table("accounts")} a on a.${ledger.col("accounts", "id")} = l.${ledger.col("lines", "account")}
      where l.${ledger.col("lines", "tenant")} = v_project.${p("tenant")}
        and n.${ledger.col("entries", "status")} in ('posted', 'reversed')
        and l.${ledger.col("lines", "dimensions")} ->> 'project' = v_project.${p("id")}::text
      group by l.${ledger.col("lines", "currency")}`;

  return `
-- What a project cost and earned, per currency: its time at the rate card's
-- cost (on the project and its work items), the time billed on invoices at
-- the billed rate and, with accounting, the posted expense and income lines
-- on its project dimension (expense claims and purchase bills). The margin is
-- the billed time and income less the time cost and expenses; budget use
-- compares the hours and, in the budget's currency, the cost to the budget.
create or replace function ${fn("project_costs")}(project_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_project ${tasks.table("projects")}%rowtype;
  v_result jsonb;
begin
  select * into v_project from ${tasks.table("projects")} x where x.${p("id")} = project_costs.project_id;
  if not found or not (${SERVICE_CALLER} or ${ctx.can("tenant", `v_project.${p("tenant")}`, read)}) then
    ${fail("WORK_ITEM_PROJECT_NOT_FOUND", "project not found", "P0002")}
  end if;
  with spent as (
    select extract(epoch from ${entryEnded(time, "x")} - x.${e("startedAt")}) as seconds, card.cost, card.currency,
      d.${b("rate")} as billed_rate, d.${b("currency")}::text as billed_currency, d.${b("seconds")} as billed_seconds
    from ${entries} x
    left join lateral (
      select c.${r("cost")} as cost, c.${r("currency")}::text as currency
      from ${ctx.table("rates")} c
      where c.${r("tenant")} = x.${e("tenant")}
        and (c.${r("user")} is null or c.${r("user")} = x.${e("user")})
        and (c.${r("subjectType")} is null or (c.${r("subjectType")} = ${subject.type} and c.${r("subjectId")} = ${subject.id}))
        and c.${r("effectiveFrom")} <= (x.${e("startedAt")} at time zone ${zone})::date
      order by (c.${r("subjectType")} is not null) desc, (c.${r("user")} is not null) desc, c.${r("effectiveFrom")} desc
      limit 1
    ) card on true
    left join ${ctx.table("billed")} d on d.${b("entry")} = x.${e("id")}
    where x.${e("tenant")} = v_project.${p("tenant")}
      and ${entryEnded(time, "x")} is not null
      and ((${subject.type} = ${sqlString(projectType(tasks))} and ${subject.id} = v_project.${p("id")}::text)${items})
  ),
  totals as (
    select u.currency, sum(u.time_cost)::bigint as time_cost, sum(u.billed)::bigint as billed,
      sum(u.expenses)::bigint as expenses, sum(u.income)::bigint as income
    from (
      select s.currency, round(s.seconds / 3600.0 * s.cost)::bigint as time_cost, 0::bigint as billed, 0::bigint as expenses, 0::bigint as income
      from spent s where s.cost is not null
      union all
      select s.billed_currency, 0, round(s.billed_seconds / 3600.0 * s.billed_rate)::bigint, 0, 0
      from spent s where s.billed_rate is not null
      union all
      select q.currency, 0, 0, q.expenses, q.income from (${accounting}) q
    ) u
    group by u.currency
  )
  select jsonb_build_object(
    'projectId', v_project.${p("id")},
    'organizationId', v_project.${p("tenant")},
    'hours', (select round(coalesce(sum(s.seconds), 0) / 3600.0, 2) from spent s),
    'uncostedHours', (select round(coalesce(sum(s.seconds) filter (where s.cost is null), 0) / 3600.0, 2) from spent s),
    'budgetAmount', ${budget("budgetAmount")}::text,
    'budgetCurrency', ${budget("budgetCurrency")},
    'budgetHours', ${budget("budgetHours")},
    'totals', (
      select coalesce(jsonb_agg(jsonb_build_object(
          'currency', t.currency,
          'timeCost', t.time_cost::text,
          'billed', t.billed::text,
          'expenses', t.expenses::text,
          'income', t.income::text,
          'margin', (t.billed + t.income - t.time_cost - t.expenses)::text
        ) order by t.currency), '[]'::jsonb)
      from totals t))
  into v_result;
  return v_result;
end;
$$;
${userGrant(`${fn("project_costs")}(uuid)`)}
`;
}
