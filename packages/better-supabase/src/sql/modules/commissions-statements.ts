import type { CommissionSql } from "./commissions-sql.ts";

import { sqlString } from "../../core/template.ts";
import {
  filterAny,
  filterFlag,
  listBody,
  listDeclare,
} from "../list-template.ts";
import { fail, serviceGrant, userGrant } from "../shared.ts";
import { commissionAccount } from "./commissions-accrual.ts";
import { commissionJson } from "./commissions-tables.ts";

/** The `ctx.record` statement for a statement event over `v_statement`. */
function statementRecord(
  k: CommissionSql,
  type: "commission_statement.finalized" | "commission_statement.paid",
): string {
  const { ctx, s } = k;

  return ctx.record({
    type,
    payload: `jsonb_build_object('organizationId', v_statement.${s("tenant")}, 'id', v_statement.${s("id")}, 'sellerId', v_statement.${s("seller")}, 'currency', v_statement.${s("currency")}, 'startsOn', v_statement.${s("startsOn")}, 'endsOn', v_statement.${s("endsOn")}, 'total', v_statement.${s("total")}::text, 'status', v_statement.${s("status")})`,
    subject: `'commission-statements/' || v_statement.${s("id")}::text`,
    tenant: `v_statement.${s("tenant")}`,
    audit: {
      category: "billing",
      targetType: "commission_statement",
      recordId: `v_statement.${s("id")}::text`,
      summary: sqlString(
        type === "commission_statement.paid"
          ? "paid a commission statement"
          : "finalized a commission statement",
      ),
    },
  });
}

/**
 * Statements per seller and period, their payout on the ledger, the reads, the
 * payroll lines and the close steps the `periods` block calls.
 */
export function commissionStatements(k: CommissionSql): string {
  const { idType, fn, entries, statements, plans } = k;
  const { c, s, p, ledger } = k;
  const json = commissionJson(k);

  const forbidden = (message: string): string =>
    fail("COMMISSION_FORBIDDEN", message);

  const missing = fail(
    "COMMISSION_STATEMENT_NOT_FOUND",
    "no such commission statement",
    "P0002",
  );

  const total = (alias: string): string =>
    `coalesce((select sum(e.${c("amount")}) from ${entries} e where e.${c("statement")} = ${alias}.${s("id")} and e.${c("status")} = 'accrued'), 0)`;

  const idKey = (col: (name: string) => string) =>
    ({ expr: `x.${col("id")}`, dir: "asc", type: "uuid" }) as const;

  const statementKeys = (
    first: "createdAt" | "endsOn" | "total",
    dir: "asc" | "desc",
    type: string,
  ) =>
    [
      { expr: `x.${s(first)}`, dir, type },
      { expr: `x.${s("createdAt")}`, dir, type: "timestamptz" },
      idKey(s),
    ] as const;

  const statementList = {
    name: "list_commission_statements",
    from: statements,
    alias: "x",
    where: [
      `x.${s("tenant")} = list_commission_statements.tenant`,
      `(v_all or x.${s("seller")} = (select auth.uid()))`,
      filterAny("seller", `x.${s("seller")}`, "uuid"),
      filterAny("status", `x.${s("status")}`),
    ],
    keys: statementKeys("endsOn", "desc", "date"),
    sorts: {
      endsOn: statementKeys("endsOn", "desc", "date"),
      createdAt: statementKeys("createdAt", "desc", "timestamptz"),
      total: statementKeys("total", "desc", "numeric"),
    },
    facets: { status: `x.${s("status")}`, seller: `x.${s("seller")}` },
    rowJson: json.statement("x"),
    defaultLimit: 100,
    maxLimit: 500,
    invalid: (message: string) => fail("COMMISSION_INVALID", message, "22023"),
  } as const;

  const entryKeys = (
    first: "createdAt" | "occurredOn" | "amount",
    dir: "asc" | "desc",
    type: string,
  ) =>
    [
      { expr: `x.${c(first)}`, dir, type },
      { expr: `x.${c("createdAt")}`, dir, type: "timestamptz" },
      idKey(c),
    ] as const;

  const commissionList = {
    name: "list_commissions",
    from: entries,
    alias: "x",
    where: [
      `x.${c("tenant")} = list_commissions.tenant`,
      `(v_all or x.${c("seller")} = (select auth.uid()))`,
      filterAny("seller", `x.${c("seller")}`, "uuid"),
      filterAny("status", `x.${c("status")}`),
    ],
    keys: entryKeys("occurredOn", "desc", "date"),
    sorts: {
      occurredOn: entryKeys("occurredOn", "desc", "date"),
      createdAt: entryKeys("createdAt", "desc", "timestamptz"),
      amount: entryKeys("amount", "desc", "numeric"),
    },
    facets: { status: `x.${c("status")}`, seller: `x.${c("seller")}` },
    rowJson: json.entry("x"),
    defaultLimit: 100,
    maxLimit: 500,
    invalid: (message: string) => fail("COMMISSION_INVALID", message, "22023"),
  } as const;

  const planList = {
    name: "list_commission_plans",
    from: plans,
    alias: "x",
    where: [
      `x.${p("tenant")} = list_commission_plans.tenant`,
      `(${filterFlag("archived")} or x.${p("archivedAt")} is null)`,
    ],
    keys: [
      { expr: `x.${p("createdAt")}`, dir: "desc", type: "timestamptz" },
      { expr: `x.${p("id")}`, dir: "asc", type: "uuid" },
    ],
    sorts: {
      createdAt: [
        { expr: `x.${p("createdAt")}`, dir: "desc", type: "timestamptz" },
        { expr: `x.${p("id")}`, dir: "asc", type: "uuid" },
      ],
      name: [
        { expr: `x.${p("name")}`, dir: "asc", type: "text" },
        { expr: `x.${p("id")}`, dir: "asc", type: "uuid" },
      ],
    },
    facets: { kind: `x.${p("kind")}` },
    rowJson: `${json.plan("x")} || jsonb_build_object('assignments', coalesce((
        select jsonb_agg(${json.assignment("a")} order by a.${k.a("startsOn")} desc, a.${k.a("createdAt")} desc)
        from ${k.assignments} a where a.${k.a("plan")} = x.${p("id")}
      ), '[]'::jsonb))`,
    defaultLimit: 100,
    maxLimit: 500,
    invalid: (message: string) => fail("COMMISSION_INVALID", message, "22023"),
  } as const;

  return `
-- Collects a seller's accrued commissions dated from starts_on to ends_on
-- that are on no statement into the open statement of that range, and
-- updates its total. Without checking the caller: build_commission_statement
-- and the period close call it.
create or replace function ${fn("commission_statement_build")}(tenant ${idType}, seller_id uuid, currency text, starts_on date, ends_on date)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_statement ${statements};
begin
  select * into v_statement from ${statements} x
  where x.${s("tenant")} = commission_statement_build.tenant and x.${s("seller")} = commission_statement_build.seller_id
    and x.${s("currency")} = commission_statement_build.currency and x.${s("startsOn")} = commission_statement_build.starts_on
  for update;
  if found and v_statement.${s("status")} <> 'open' then
    ${fail("COMMISSION_STATEMENT_LOCKED", "the statement of this range is no longer open", "55000")}
  end if;
  if not found then
    insert into ${statements} (${s("tenant")}, ${s("seller")}, ${s("currency")}, ${s("startsOn")}, ${s("endsOn")})
    values (commission_statement_build.tenant, commission_statement_build.seller_id, commission_statement_build.currency,
      commission_statement_build.starts_on, commission_statement_build.ends_on)
    returning * into v_statement;
  end if;
  update ${entries} x set ${c("statement")} = v_statement.${s("id")}
  where x.${c("tenant")} = commission_statement_build.tenant and x.${c("seller")} = commission_statement_build.seller_id
    and x.${c("currency")} = commission_statement_build.currency and x.${c("status")} = 'accrued' and x.${c("statement")} is null
    and x.${c("occurredOn")} between commission_statement_build.starts_on and commission_statement_build.ends_on;
  update ${statements} x set ${s("endsOn")} = commission_statement_build.ends_on, ${s("total")} = ${total("x")}
  where x.${s("id")} = v_statement.${s("id")};
  return v_statement.${s("id")};
end;
$$;
${serviceGrant(`${fn("commission_statement_build")}(${idType}, uuid, text, date, date)`)}

-- Builds the statement of one seller and currency for a date range. Calling
-- it again adds commissions accrued since, until the statement is finalized.
-- Needs commissions.manage.
create or replace function ${fn("build_commission_statement")}(tenant ${idType}, seller_id uuid, currency text, starts_on date, ends_on date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_statement ${statements};
begin
  if not ${k.allowed("build_commission_statement.tenant", k.manage)} then
    ${forbidden("not allowed to build commission statements")}
  end if;
  if build_commission_statement.seller_id is null or upper(build_commission_statement.currency) !~ '^[A-Z]{3}$'
    or build_commission_statement.starts_on is null or build_commission_statement.ends_on is null
    or build_commission_statement.ends_on < build_commission_statement.starts_on then
    ${fail("COMMISSION_INVALID", "a statement needs a seller, a currency code and a range that ends on or after it starts", "22023")}
  end if;
  v_id := ${fn("commission_statement_build")}(build_commission_statement.tenant, build_commission_statement.seller_id,
    upper(build_commission_statement.currency), build_commission_statement.starts_on, build_commission_statement.ends_on);
  select * into v_statement from ${statements} x where x.${s("id")} = v_id;
  return ${json.statement("v_statement")};
end;
$$;
${userGrant(`${fn("build_commission_statement")}(${idType}, uuid, text, date, date)`)}

-- Locks a statement: its commissions can't be reversed afterwards. Without
-- checking the caller; finalize_commission_statement and the period close
-- call it.
create or replace function ${fn("commission_statement_finalize")}(statement_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_statement ${statements};
begin
  select * into v_statement from ${statements} x where x.${s("id")} = commission_statement_finalize.statement_id for update;
  if not found then
    ${missing}
  end if;
  if v_statement.${s("status")} <> 'open' then
    return ${json.statement("v_statement")};
  end if;
  update ${statements} x set ${s("status")} = 'finalized', ${s("finalizedAt")} = now(), ${s("total")} = ${total("x")}
  where x.${s("id")} = v_statement.${s("id")} returning * into v_statement;
  ${statementRecord(k, "commission_statement.finalized")}
  return ${json.statement("v_statement")};
end;
$$;
${serviceGrant(`${fn("commission_statement_finalize")}(uuid)`)}

-- Finalizes an open statement. Finalizing a finalized or paid statement
-- returns it unchanged. Needs commissions.manage.
create or replace function ${fn("finalize_commission_statement")}(statement_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant ${idType};
begin
  select x.${s("tenant")} into v_tenant from ${statements} x where x.${s("id")} = finalize_commission_statement.statement_id;
  if not found or not ${k.allowed("v_tenant", k.read)} then
    ${missing}
  end if;
  if not ${k.allowed("v_tenant", k.manage)} then
    ${forbidden("not allowed to finalize commission statements")}
  end if;
  return ${fn("commission_statement_finalize")}(finalize_commission_statement.statement_id);
end;
$$;
${userGrant(`${fn("finalize_commission_statement")}(uuid)`)}

-- Pays a finalized statement out: the ledger moves the total from the
-- seller's payable account to the commissions paid account. Paying a paid
-- statement returns it unchanged. Needs commissions.manage.
create or replace function ${fn("pay_commission_statement")}(statement_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_statement ${statements};
  v_tx uuid;
begin
  select * into v_statement from ${statements} x where x.${s("id")} = pay_commission_statement.statement_id for update;
  if not found or not ${k.allowed(`v_statement.${s("tenant")}`, k.read)} then
    ${missing}
  end if;
  if not ${k.allowed(`v_statement.${s("tenant")}`, k.manage)} then
    ${forbidden("not allowed to pay commission statements")}
  end if;
  if v_statement.${s("status")} = 'paid' then
    return ${json.statement("v_statement")};
  end if;
  if v_statement.${s("status")} <> 'finalized' then
    ${fail("COMMISSION_STATEMENT_OPEN", "finalize the statement before paying it", "55000")}
  end if;
  if v_statement.${s("total")} > 0 then
    v_tx := ${ledger.fn("ledger_post")}(v_statement.${s("tenant")}, 'commission.payout',
      jsonb_build_array(
        jsonb_build_object('account', ${commissionAccount(k, `v_statement.${s("tenant")}`, "payable", `v_statement.${s("currency")}`, `v_statement.${s("seller")}`)}, 'amount', (-v_statement.${s("total")})::text),
        jsonb_build_object('account', ${commissionAccount(k, `v_statement.${s("tenant")}`, "paid", `v_statement.${s("currency")}`)}, 'amount', v_statement.${s("total")}::text)),
      'commission-statements', v_statement.${s("id")}::text, null,
      'commission-statement:' || v_statement.${s("id")}::text, null,
      jsonb_build_object('sellerId', v_statement.${s("seller")}));
  end if;
  update ${statements} x set ${s("status")} = 'paid', ${s("paidAt")} = now(), ${s("paidBy")} = auth.uid(), ${s("ledgerTransaction")} = v_tx
  where x.${s("id")} = v_statement.${s("id")} returning * into v_statement;
  ${statementRecord(k, "commission_statement.paid")}
  return ${json.statement("v_statement")};
end;
$$;
${userGrant(`${fn("pay_commission_statement")}(uuid)`)}

-- A statement with its commissions. Needs commissions.read, or the seller's
-- own statement.
create or replace function ${fn("get_commission_statement")}(statement_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_statement ${statements};
begin
  select * into v_statement from ${statements} x where x.${s("id")} = get_commission_statement.statement_id;
  if not found or not (${k.allowed(`v_statement.${s("tenant")}`, k.read)} or v_statement.${s("seller")} = (select auth.uid())) then
    ${missing}
  end if;
  return ${json.statement("v_statement")} || jsonb_build_object('entries', coalesce((
    select jsonb_agg(${json.entry("y")} order by y.${c("occurredOn")}, y.${c("createdAt")})
    from ${entries} y where y.${c("statement")} = v_statement.${s("id")}
  ), '[]'::jsonb));
end;
$$;
${userGrant(`${fn("get_commission_statement")}(uuid)`)}

-- An organization's statements, newest first. filters is { seller (a value or a
-- list), status (a value or a list), sort, direction, facet, count, limit,
-- after, offset, paged, total, totalCap } (ADR 0749). Needs commissions.read;
-- without it a member sees their own.
create or replace function ${fn("list_commission_statements")}(tenant ${idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_commission_statements.filters, '{}'::jsonb);
  v_all boolean := ${k.allowed("list_commission_statements.tenant", k.read)};
  ${listDeclare(statementList)}
begin
  ${listBody(statementList)}
end;
$$;
${userGrant(`${fn("list_commission_statements")}(${idType}, jsonb)`)}

-- An organization's accrued commissions, newest first. filters is { seller (a
-- value or a list), status (a value or a list), sort, direction, facet, count,
-- limit, after, offset, paged, total, totalCap } (ADR 0749). Needs
-- commissions.read; without it a member sees their own.
create or replace function ${fn("list_commissions")}(tenant ${idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_commissions.filters, '{}'::jsonb);
  v_all boolean := ${k.allowed("list_commissions.tenant", k.read)};
  ${listDeclare(commissionList)}
begin
  ${listBody(commissionList)}
end;
$$;
${userGrant(`${fn("list_commissions")}(${idType}, jsonb)`)}

-- An organization's plans and the assignments of each, newest first. filters
-- is { archived, sort, direction, facet, count, limit, after, offset, paged,
-- total, totalCap } (ADR 0749). Needs commissions.read.
create or replace function ${fn("list_commission_plans")}(tenant ${idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_commission_plans.filters, '{}'::jsonb);
  ${listDeclare(planList)}
begin
  if not ${k.allowed("list_commission_plans.tenant", k.read)} then
    ${forbidden("not allowed to read commission plans")}
  end if;
  ${listBody(planList)}
end;
$$;
${userGrant(`${fn("list_commission_plans")}(${idType}, jsonb)`)}

-- What payroll adds for commissions: one line per seller and currency with
-- the total of the finalized and paid statements that end from from_date to
-- to_date. A payroll run reads it as the service role, or as a member with
-- commissions.read; payroll-export does not collect it by itself. amount is
-- in minor units, as text.
create or replace function ${fn("commission_payroll_lines")}(tenant ${idType}, from_date date, to_date date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not ${k.allowed("commission_payroll_lines.tenant", k.read)} then
    ${forbidden("not allowed to read commission statements")}
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('userId', y.seller, 'currency', y.currency, 'amount', y.amount::text, 'statementIds', y.ids) order by y.seller, y.currency)
    from (
      select x.${s("seller")} as seller, x.${s("currency")} as currency, sum(x.${s("total")}) as amount, jsonb_agg(x.${s("id")} order by x.${s("endsOn")}) as ids
      from ${statements} x
      where x.${s("tenant")} = commission_payroll_lines.tenant and x.${s("status")} in ('finalized', 'paid')
        and x.${s("endsOn")} between commission_payroll_lines.from_date and commission_payroll_lines.to_date and x.${s("total")} > 0
      group by x.${s("seller")}, x.${s("currency")}
    ) y
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("commission_payroll_lines")}(${idType}, date, date)`)}

-- The period engine's close step for a commission period (ADR 0197): builds
-- and finalizes every seller's statement for the range, so a closed period
-- has no accrued commission outside a locked statement.
create or replace function ${fn("commission_close_range")}(tenant ${idType}, starts_on date, ends_on date)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row record;
  v_id uuid;
begin
  for v_row in
    select distinct x.${c("seller")} as seller, x.${c("currency")} as currency from ${entries} x
    where x.${c("tenant")} = commission_close_range.tenant and x.${c("status")} = 'accrued' and x.${c("statement")} is null
      and x.${c("occurredOn")} between commission_close_range.starts_on and commission_close_range.ends_on
  loop
    perform ${fn("commission_statement_build")}(commission_close_range.tenant, v_row.seller, v_row.currency, commission_close_range.starts_on, commission_close_range.ends_on);
  end loop;
  for v_id in
    select x.${s("id")} from ${statements} x
    where x.${s("tenant")} = commission_close_range.tenant and x.${s("status")} = 'open'
      and x.${s("startsOn")} >= commission_close_range.starts_on and x.${s("endsOn")} <= commission_close_range.ends_on
  loop
    perform ${fn("commission_statement_finalize")}(v_id);
  end loop;
end;
$$;
${serviceGrant(`${fn("commission_close_range")}(${idType}, date, date)`)}
`;
}
