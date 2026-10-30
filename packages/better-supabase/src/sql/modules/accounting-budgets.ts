import type { BlockSqlContext } from "../context.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { userGrant } from "../shared.ts";
import { accountingSql } from "./accounting-shared.ts";
import { appUniqueIndex, lockModuleTable } from "./over-app.ts";

/** Budgets per account and period, and the budget against the actuals. */
export function accountingBudgets(ctx: BlockSqlContext): string {
  const accounts = ctx.table("accounts");
  const periods = ctx.table("periods");
  const entries = ctx.table("entries");
  const lines = ctx.table("lines");
  const budgets = ctx.table("budgets");
  const budgetLines = ctx.table("budgetLines");
  const a = (column: string): string => ctx.col("accounts", column);
  const p = (column: string): string => ctx.col("periods", column);
  const e = (column: string): string => ctx.col("entries", column);
  const l = (column: string): string => ctx.col("lines", column);
  const b = (column: string): string => ctx.col("budgets", column);
  const bl = (column: string): string => ctx.col("budgetLines", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const sql = accountingSql(ctx);

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  const readPolicy = (logical: string, tenant: string): string =>
    `${lockModuleTable(ctx, logical, { read: true })}
${renderPolicy(
  makePolicy({
    table: ctx.table(logical),
    name: name(logical, "read"),
    command: "select",
    roles: ["authenticated"],
    using: ctx.scope.check(tenant, sql.read),
  }),
  { drop: true, target: ctx.table(logical) },
)}`;

  const invalid = (message: string): string =>
    sql.invalid("ACCOUNTING_BUDGET", message);

  const budgetJson = (row: string, withLines: boolean): string =>
    `jsonb_build_object('id', ${row}.${b("id")}, 'organizationId', ${row}.${b("tenant")}, 'name', ${row}.${b("name")}, 'fiscalYear', ${row}.${b("fiscalYear")}, 'status', ${row}.${b("status")}, 'total', coalesce((select sum(bt.${bl("amount")}) from ${budgetLines} bt where bt.${bl("budget")} = ${row}.${b("id")}), 0)::text, 'createdBy', ${row}.${b("createdBy")}, 'createdAt', ${row}.${b("createdAt")}, 'updatedAt', ${row}.${b("updatedAt")}${
      withLines
        ? `, 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', bx.${bl("id")}, 'accountId', bx.${bl("account")}, 'accountCode', ba.${a("code")}, 'periodNumber', bx.${bl("periodNumber")}, 'dimensions', bx.${bl("dimensions")}, 'amount', bx.${bl("amount")}::text) order by ba.${a("code")}, bx.${bl("periodNumber")}, bx.${bl("id")}) from ${budgetLines} bx join ${accounts} ba on ba.${a("id")} = bx.${bl("account")} where bx.${bl("budget")} = ${row}.${b("id")}), '[]'::jsonb)`
        : ""
    })`;

  const event = (type: "created" | "updated"): string =>
    ctx.record({
      type: `accounting_budget.${type}`,
      payload: `jsonb_build_object('organizationId', v_row.${b("tenant")}, 'id', v_row.${b("id")}, 'name', v_row.${b("name")}, 'fiscalYear', v_row.${b("fiscalYear")}, 'status', v_row.${b("status")})`,
      subject: `'accounting-budgets/' || v_row.${b("id")}::text`,
      tenant: `v_row.${b("tenant")}`,
      audit: {
        category: "data",
        targetType: "accounting_budget",
        recordId: `v_row.${b("id")}::text`,
        targetLabel: `v_row.${b("name")}`,
        summary: `'${type} budget ' || v_row.${b("name")}`,
      },
    });

  const saveTypes = `${idType}, text, integer, text, jsonb, uuid`;

  return `
create table if not exists ${budgets} (
  ${b("id")} uuid primary key default gen_random_uuid(),
  ${b("tenant")} ${idType} not null,
  ${b("name")} text not null check (length(${b("name")}) >= 1 and length(${b("name")}) <= 200),
  ${b("fiscalYear")} integer not null check (${b("fiscalYear")} >= 1900 and ${b("fiscalYear")} <= 9999),
  ${b("status")} text not null default 'draft' check (${b("status")} in ('draft', 'approved', 'archived')),
  ${b("createdBy")} uuid,
  ${b("createdAt")} timestamptz not null default now(),
  ${b("updatedAt")} timestamptz not null default now(),
  unique (${b("tenant")}, ${b("fiscalYear")}, ${b("name")})
);${appUniqueIndex(ctx, "budgets", ["tenant", "fiscalYear", "name"])}
${readPolicy("budgets", b("tenant"))}

create table if not exists ${budgetLines} (
  ${bl("id")} uuid primary key default gen_random_uuid(),
  ${bl("tenant")} ${idType} not null,
  ${bl("budget")} uuid not null references ${budgets} (${b("id")}) on delete cascade,
  ${bl("account")} uuid not null references ${accounts} (${a("id")}) on delete restrict,
  -- The period of the budget's fiscal year, 1 to 12.
  ${bl("periodNumber")} smallint not null check (${bl("periodNumber")} >= 1 and ${bl("periodNumber")} <= 12),
  -- The dimension values the amount is for; actuals match lines that carry them.
  ${bl("dimensions")} jsonb not null default '{}'::jsonb check (jsonb_typeof(${bl("dimensions")}) = 'object'),
  -- Minor units of the functional currency, in the account's natural sign.
  ${bl("amount")} bigint not null,
  unique (${bl("budget")}, ${bl("account")}, ${bl("periodNumber")}, ${bl("dimensions")})
);${appUniqueIndex(ctx, "budgetLines", ["budget", "account", "periodNumber", "dimensions"])}
create index if not exists ${name("budgetLines", "account_idx")} on ${budgetLines} (${bl("account")});
${readPolicy("budgetLines", bl("tenant"))}

-- Creates a budget, or renames it, moves its status (draft, approved,
-- archived) and, when lines is given, replaces its lines. Each line names an
-- account (accountId or accountCode), a periodNumber, an amount and optional
-- dimensions.
create or replace function ${fn("save_accounting_budget")}(tenant ${idType}, name text, fiscal_year integer, status text default null, lines jsonb default null, budget_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${budgets}%rowtype;
  v_line record;
  v_account uuid;
  v_created boolean := save_accounting_budget.budget_id is null;
begin
  if not ${sql.allowed("save_accounting_budget.tenant", sql.write)} then
    ${sql.forbidden("ACCOUNTING_BUDGET", "not allowed to write budgets")}
  end if;
  if length(trim(coalesce(save_accounting_budget.name, ''))) not between 1 and 200
    or coalesce(save_accounting_budget.fiscal_year, 0) not between 1900 and 9999 then
    ${invalid("a budget needs a name of 1 to 200 characters and a fiscal year")}
  end if;
  if coalesce(save_accounting_budget.status, 'draft') not in ('draft', 'approved', 'archived') then
    ${invalid("status must be draft, approved or archived")}
  end if;
  if save_accounting_budget.lines is not null and jsonb_typeof(save_accounting_budget.lines) <> 'array' then
    ${invalid("lines is an array")}
  end if;
  if v_created then
    insert into ${budgets} (${b("tenant")}, ${b("name")}, ${b("fiscalYear")}, ${b("status")}, ${b("createdBy")})
    values (save_accounting_budget.tenant, trim(save_accounting_budget.name), save_accounting_budget.fiscal_year,
      coalesce(save_accounting_budget.status, 'draft'), auth.uid())
    returning * into v_row;
  else
    update ${budgets} y set ${b("name")} = trim(save_accounting_budget.name), ${b("fiscalYear")} = save_accounting_budget.fiscal_year,
      ${b("status")} = coalesce(save_accounting_budget.status, y.${b("status")}), ${b("updatedAt")} = now()
    where y.${b("id")} = save_accounting_budget.budget_id and y.${b("tenant")} = save_accounting_budget.tenant
    returning * into v_row;
    if not found then
      ${sql.notFound("ACCOUNTING_BUDGET", "budget not found")}
    end if;
  end if;
  if save_accounting_budget.lines is not null then
    delete from ${budgetLines} y where y.${bl("budget")} = v_row.${b("id")};
    for v_line in select q.value from jsonb_array_elements(save_accounting_budget.lines) q loop
      if jsonb_typeof(v_line.value) is distinct from 'object'
        or coalesce(v_line.value ->> 'amount', '') !~ '^-?[0-9]{1,18}$'
        or coalesce(v_line.value ->> 'periodNumber', '') !~ '^([1-9]|1[0-2])$'
        or (v_line.value ? 'dimensions' and jsonb_typeof(v_line.value -> 'dimensions') <> 'object') then
        ${invalid("every line has an account, a periodNumber from 1 to 12, an integer amount and dimensions as an object")}
      end if;
      select y.${a("id")} into v_account from ${accounts} y
      where y.${a("tenant")} = v_row.${b("tenant")}
        and (y.${a("id")}::text = v_line.value ->> 'accountId' or y.${a("code")} = v_line.value ->> 'accountCode');
      if v_account is null then
        ${sql.notFound("ACCOUNTING_ACCOUNT", "a budget line's account doesn't exist here")}
      end if;
      insert into ${budgetLines} (${bl("tenant")}, ${bl("budget")}, ${bl("account")}, ${bl("periodNumber")}, ${bl("dimensions")}, ${bl("amount")})
      values (v_row.${b("tenant")}, v_row.${b("id")}, v_account, (v_line.value ->> 'periodNumber')::smallint,
        coalesce(v_line.value -> 'dimensions', '{}'::jsonb), (v_line.value ->> 'amount')::bigint)
      on conflict (${bl("budget")}, ${bl("account")}, ${bl("periodNumber")}, ${bl("dimensions")})
      do update set ${bl("amount")} = ${budgetLines}.${bl("amount")} + excluded.${bl("amount")};
      v_account := null;
    end loop;
  end if;
  if v_created then
    ${event("created")}
  else
    ${event("updated")}
  end if;
  return ${budgetJson("v_row", true)};
end;
$$;
${userGrant(`${fn("save_accounting_budget")}(${saveTypes})`)}

create or replace function ${fn("get_accounting_budget")}(budget_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${budgetJson("x", true)} from ${budgets} x where x.${b("id")} = get_accounting_budget.budget_id
$$;
${userGrant(`${fn("get_accounting_budget")}(uuid)`)}

create or replace function ${fn("list_accounting_budgets")}(tenant ${idType}, fiscal_year integer default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${budgetJson("x", false)} order by x.${b("fiscalYear")} desc, x.${b("name")}), '[]'::jsonb)
  from ${budgets} x
  where x.${b("tenant")} = list_accounting_budgets.tenant
    and (list_accounting_budgets.fiscal_year is null or x.${b("fiscalYear")} = list_accounting_budgets.fiscal_year)
$$;
${userGrant(`${fn("list_accounting_budgets")}(${idType}, integer)`)}

-- The budget of each account and dimension set next to what posted entries
-- booked in the same periods of the fiscal year (one period, or all of them),
-- both in the account's natural sign, without year-end closing entries.
create or replace function ${fn("accounting_budget_vs_actual")}(budget_id uuid, period_number integer default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with budget as (
    select x.* from ${budgets} x where x.${b("id")} = accounting_budget_vs_actual.budget_id
  ),
  planned as (
    select y.${bl("account")} as account, y.${bl("dimensions")} as dimensions, sum(y.${bl("amount")}) as amount
    from ${budgetLines} y
    where y.${bl("budget")} = accounting_budget_vs_actual.budget_id
      and (accounting_budget_vs_actual.period_number is null or y.${bl("periodNumber")} = accounting_budget_vs_actual.period_number)
    group by y.${bl("account")}, y.${bl("dimensions")}
  ),
  compared as (
    select q.account, q.dimensions, q.amount as budget, ac.${a("code")} as code, ac.${a("name")} as name, ac.${a("type")} as type,
      coalesce((
        select sum(case when ac.${a("type")} in ('liability', 'equity', 'income') then z.${l("credit")} - z.${l("debit")} else z.${l("debit")} - z.${l("credit")} end)
        from ${lines} z
        join ${entries} w on w.${e("id")} = z.${l("entry")}
        join ${periods} v on v.${p("id")} = w.${e("period")}
        cross join budget g
        where z.${l("account")} = q.account and z.${l("dimensions")} @> q.dimensions
          and w.${e("status")} in ('posted', 'reversed') and w.${e("sourceType")} is distinct from 'fiscal_year'
          and v.${p("tenant")} = g.${b("tenant")} and v.${p("fiscalYear")} = g.${b("fiscalYear")}
          and (accounting_budget_vs_actual.period_number is null or v.${p("number")} = accounting_budget_vs_actual.period_number)
      ), 0) as actual
    from planned q join ${accounts} ac on ac.${a("id")} = q.account
  )
  select jsonb_build_object(
    'budgetId', g.${b("id")},
    'name', g.${b("name")},
    'fiscalYear', g.${b("fiscalYear")},
    'periodNumber', accounting_budget_vs_actual.period_number,
    'lines', coalesce((select jsonb_agg(jsonb_build_object('accountId', c.account, 'code', c.code, 'name', c.name, 'type', c.type,
      'dimensions', c.dimensions, 'budget', c.budget::text, 'actual', c.actual::text, 'variance', (c.actual - c.budget)::text)
      order by c.code, c.dimensions::text) from compared c), '[]'::jsonb),
    'budget', coalesce((select sum(c.budget) from compared c), 0)::text,
    'actual', coalesce((select sum(c.actual) from compared c), 0)::text
  )
  from budget g
$$;
${userGrant(`${fn("accounting_budget_vs_actual")}(uuid, integer)`)}
`;
}
