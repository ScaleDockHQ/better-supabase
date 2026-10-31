import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { booksAccounting } from "../accounting-sources-sql.ts";
import { fail, SERVICE_CALLER, userGrant } from "../shared.ts";
import { subjectsOption } from "../subjects.ts";
import { moduleOperations } from "./permissions-model.ts";
import { projectType, taskType } from "./tasks.ts";
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
    ? ` or (${subject.type} = ${sqlString(taskType(tasks))} and ${subject.id} in (
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

  // Time billed on an invoice whose booked revenue already sits on this
  // project's dimension counts once, through the dimension's income.
  const booked =
    ledger === undefined
      ? ""
      : `
      and not exists (
        select 1 from ${ledger.table("entries")} n
        join ${ledger.table("lines")} l on l.${ledger.col("lines", "entry")} = n.${ledger.col("entries", "id")}
        join ${ledger.table("accounts")} a on a.${ledger.col("accounts", "id")} = l.${ledger.col("lines", "account")}
        where n.${ledger.col("entries", "tenant")} = v_project.${p("tenant")}
          and n.${ledger.col("entries", "sourceType")} = 'invoice' and n.${ledger.col("entries", "sourceId")} = d.${b("invoice")}::text
          and n.${ledger.col("entries", "status")} in ('posted', 'reversed')
          and a.${ledger.col("accounts", "type")} = 'income'
          and l.${ledger.col("lines", "dimensions")} ->> 'project' = v_project.${p("id")}::text
      )`;

  return `
-- What a project cost and earned, per currency: its time at the rate card's
-- cost (on the project and its work items), the time billed on invoices at
-- the billed rate (left out when the invoice's booked revenue is already on
-- the project dimension) and, with accounting, the posted expense and income
-- lines on its project dimension (expense claims and purchase bills). The margin is
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
    ${fail("TASK_PROJECT_NOT_FOUND", "project not found", "P0002")}
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
    left join ${ctx.table("billed")} d on d.${b("entry")} = x.${e("id")}${booked}
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

/**
 * `wip_valuation`: the finished, billable time no invoice has billed, valued at
 * the rate card's cost and at its billing rate, per currency.
 */
export function wipValuationSql(
  ctx: BlockSqlContext,
  timeZone: string,
): string {
  if (!ctx.manages) {
    return "";
  }

  const time = ctx.of("time-tracking");
  const entries = time.table("entries");
  const e = (column: string): string => time.col("entries", column);
  const r = (column: string): string => ctx.col("rates", column);
  const b = (column: string): string => ctx.col("billed", column);
  const fn = (name: string): string => ctx.fn(name);
  const read = ctx.permission("read", moduleOperations("billable-time").read);
  const { rowSubject } = entrySubjects(time, subjectsOption(time, ["column"]));
  const subject = rowSubject("x");
  const zone = sqlString(timeZone);
  const cost = ctx.has("rates", "cost") ? `c.${r("cost")}` : "null::bigint";
  const idType = ctx.idType;

  return `
-- The work in progress of unbilled time on as_of (today by default): the
-- finished, billable entries started on or before it that no invoice has
-- billed, per currency at the rate card's cost and at the billing rate (an
-- entry's own rate first). Entries without a cost or a rate are counted in
-- uncostedHours and unratedHours and left out of the amounts. Stock
-- consumed into production is not part of it (ADR 0144).
create or replace function ${fn("wip_valuation")}(tenant ${idType}, as_of date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_as_of date := coalesce(wip_valuation.as_of, current_date);
begin
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", "wip_valuation.tenant", read)}) then
    ${fail("BILLABLE_TIME_FORBIDDEN", "not allowed to read billable time")}
  end if;
  return (
    with open as (
      select extract(epoch from ${entryEnded(time, "x")} - x.${e("startedAt")}) as seconds,
        card.cost, card.currency as cost_currency,
        coalesce(x.${e("rate")}, card.rate) as rate, coalesce(x.${e("rateCurrency")}, card.currency) as rate_currency
      from ${entries} x
      left join lateral (
        select ${cost} as cost, c.${r("rate")} as rate, c.${r("currency")}::text as currency
        from ${ctx.table("rates")} c
        where c.${r("tenant")} = x.${e("tenant")}
          and (c.${r("user")} is null or c.${r("user")} = x.${e("user")})
          and (c.${r("subjectType")} is null or (c.${r("subjectType")} = ${subject.type} and c.${r("subjectId")} = ${subject.id}))
          and c.${r("effectiveFrom")} <= (x.${e("startedAt")} at time zone ${zone})::date
        order by (c.${r("subjectType")} is not null) desc, (c.${r("user")} is not null) desc, c.${r("effectiveFrom")} desc
        limit 1
      ) card on true
      where x.${e("tenant")} = wip_valuation.tenant
        and x.${e("billable")} and ${entryEnded(time, "x")} is not null
        and (x.${e("startedAt")} at time zone ${zone})::date <= v_as_of
        and not exists (select 1 from ${ctx.table("billed")} d where d.${b("entry")} = x.${e("id")})
    ),
    amounts as (
      select o.cost_currency as currency, round(o.seconds / 3600.0 * o.cost)::bigint as cost, 0::bigint as billable
      from open o where o.cost is not null
      union all
      select o.rate_currency, 0, round(o.seconds / 3600.0 * o.rate)::bigint
      from open o where o.rate is not null
    )
    select jsonb_build_object(
      'asOf', v_as_of,
      'hours', (select round(coalesce(sum(o.seconds), 0) / 3600.0, 2) from open o),
      'uncostedHours', (select round(coalesce(sum(o.seconds) filter (where o.cost is null), 0) / 3600.0, 2) from open o),
      'unratedHours', (select round(coalesce(sum(o.seconds) filter (where o.rate is null), 0) / 3600.0, 2) from open o),
      'totals', (select coalesce(jsonb_agg(jsonb_build_object('currency', t.currency, 'cost', t.cost::text, 'billable', t.billable::text) order by t.currency), '[]'::jsonb)
        from (select a.currency, sum(a.cost)::bigint as cost, sum(a.billable)::bigint as billable from amounts a group by a.currency) t)
    )
  );
end;
$$;
${userGrant(`${fn("wip_valuation")}(${idType}, date)`)}
`;
}
