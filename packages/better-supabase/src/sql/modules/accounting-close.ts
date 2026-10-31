import type { BlockSqlContext } from "../context.ts";

import { fail, raise, userGrant } from "../shared.ts";
import { accountingJson, requireSettings } from "./accounting-setup.ts";
import { accountingSql } from "./accounting-shared.ts";

/**
 * `accounting_period_close_blockers(period_id)`: draft entries dated in the
 * period and, with the banking block, bank transactions booked in it that no
 * one has matched or ignored. The banking tables come after accounting's, so
 * that check is PL/pgSQL, which resolves them when it runs.
 */
function closeBlockers(ctx: BlockSqlContext): string {
  const p = (column: string): string => ctx.col("periods", column);
  const e = (column: string): string => ctx.col("entries", column);
  const fn = ctx.fn("accounting_period_close_blockers");
  const entries = ctx.table("entries");
  const periods = ctx.table("periods");

  const drafts = (period: string): string => `exists (
      select 1 from ${entries} y
      where y.${e("tenant")} = ${period}.${p("tenant")} and y.${e("status")} = 'draft'
        and y.${e("entryDate")} >= ${period}.${p("startsOn")} and y.${e("entryDate")} <= ${period}.${p("endsOn")}
    )`;

  const banking =
    ctx.installed("banking") && ctx.of("banking").mode !== "custom"
      ? ctx.of("banking")
      : undefined;

  if (banking === undefined) {
    return `-- What keeps a period from closing: draft entries dated in it.
create or replace function ${fn}(period_id uuid)
returns text[]
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(array_remove(array[
    case when ${drafts("x")} then 'draft_entries' end
  ], null), '{}'::text[])
  from ${periods} x where x.${p("id")} = accounting_period_close_blockers.period_id
$$;`;
  }

  const t = (column: string): string => banking.col("transactions", column);

  return `-- What keeps a period from closing: draft entries dated in it, and bank
-- transactions booked in it that are neither matched nor ignored.
create or replace function ${fn}(period_id uuid)
returns text[]
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_period ${periods}%rowtype;
  v_blockers text[] := '{}';
begin
  select * into v_period from ${periods} x where x.${p("id")} = accounting_period_close_blockers.period_id;
  if not found then
    return null;
  end if;
  if ${drafts("v_period")} then
    v_blockers := v_blockers || 'draft_entries'::text;
  end if;
  if exists (
    select 1 from ${banking.table("transactions")} y
    where y.${t("tenant")} = v_period.${p("tenant")} and y.${t("status")} = 'unmatched'
      and y.${t("bookedOn")} >= v_period.${p("startsOn")} and y.${t("bookedOn")} <= v_period.${p("endsOn")}
  ) then
    v_blockers := v_blockers || 'unreconciled_bank_transactions'::text;
  end if;
  return v_blockers;
end;
$$;`;
}

/** Period close and reopen, the lock date's companion, and the year-end close. */
export function accountingCloseFunctions(ctx: BlockSqlContext): string {
  const accounts = ctx.table("accounts");
  const roles = ctx.table("roles");
  const journals = ctx.table("journals");
  const periods = ctx.table("periods");
  const entries = ctx.table("entries");
  const lines = ctx.table("lines");
  const settings = ctx.table("settings");
  const s = (column: string): string => ctx.col("settings", column);
  const a = (column: string): string => ctx.col("accounts", column);
  const r = (column: string): string => ctx.col("roles", column);
  const j = (column: string): string => ctx.col("journals", column);
  const p = (column: string): string => ctx.col("periods", column);
  const e = (column: string): string => ctx.col("entries", column);
  const l = (column: string): string => ctx.col("lines", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const sql = accountingSql(ctx);
  const json = accountingJson(ctx);
  const { allowed } = sql;

  const periodNotFound = sql.notFound("ACCOUNTING_PERIOD", "period not found");

  const periodPayload = (row: string, extra = ""): string =>
    `jsonb_build_object('organizationId', ${row}.${p("tenant")}, 'id', ${row}.${p("id")}, 'fiscalYear', ${row}.${p("fiscalYear")}, 'number', ${row}.${p("number")}, 'startsOn', ${row}.${p("startsOn")}, 'endsOn', ${row}.${p("endsOn")}${extra})`;

  const recordPeriod = (
    type: "accounting_period.closed" | "accounting_period.reopened",
    row: string,
    extra = "",
  ): string =>
    ctx.record({
      type,
      payload: periodPayload(row, extra),
      subject: `'accounting-periods/' || ${row}.${p("id")}::text`,
      tenant: `${row}.${p("tenant")}`,
      audit: {
        category: "data",
        targetType: "accounting_period",
        recordId: `${row}.${p("id")}::text`,
        targetLabel: `${row}.${p("fiscalYear")}::text || '-' || lpad(${row}.${p("number")}::text, 2, '0')`,
        summary: `'${type === "accounting_period.closed" ? "closed" : "reopened"} period ' || ${row}.${p("fiscalYear")}::text || '-' || lpad(${row}.${p("number")}::text, 2, '0')`,
      },
    });

  const balances = `select y.${l("account")} as account, sum(y.${l("debit")}) - sum(y.${l("credit")}) as net
    from ${lines} y
    join ${entries} z on z.${e("id")} = y.${l("entry")}
    join ${accounts} w on w.${a("id")} = y.${l("account")}
    where z.${e("tenant")} = close_fiscal_year.tenant and z.${e("fiscalYear")} = close_fiscal_year.fiscal_year
      and z.${e("status")} in ('posted', 'reversed') and w.${a("type")} in ('income', 'expense')
    group by y.${l("account")}
    having sum(y.${l("debit")}) <> sum(y.${l("credit")})`;

  const closePeriod = `update ${periods} y set ${p("status")} = 'closed', ${p("closedAt")} = now(), ${p("closedBy")} = auth.uid()
    where y.${p("id")} = v_period.${p("id")}
    returning * into v_period;
    ${recordPeriod("accounting_period.closed", "v_period")}`;

  return `
${closeBlockers(ctx)}
${userGrant(`${fn("accounting_period_close_blockers")}(uuid)`)}

-- Closes a period: nothing posts into it until it reopens. Closing a closed
-- period returns it unchanged.
create or replace function ${fn("close_accounting_period")}(period_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_period ${periods}%rowtype;
  v_blockers text[];
begin
  select * into v_period from ${periods} y where y.${p("id")} = close_accounting_period.period_id for update;
  if not found then
    ${periodNotFound}
  end if;
  if not ${allowed(`v_period.${p("tenant")}`, sql.close)} then
    ${sql.forbidden("ACCOUNTING_PERIOD", "not allowed to close accounting periods")}
  end if;
  if v_period.${p("status")} = 'closed' then
    return ${json.period("v_period")};
  end if;
  v_blockers := ${fn("accounting_period_close_blockers")}(v_period.${p("id")});
  if cardinality(v_blockers) > 0 then
    ${raise("the period can't close yet: %", "55000", "ACCOUNTING_PERIOD_CLOSE_BLOCKED", "array_to_string(v_blockers, ', ')")}
  end if;
  ${closePeriod}
  return ${json.period("v_period")};
end;
$$;
${userGrant(`${fn("close_accounting_period")}(uuid)`)}

-- Reopens a closed period with a reason. A period on or before the lock date
-- stays closed; move the lock date first.
create or replace function ${fn("reopen_accounting_period")}(period_id uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_period ${periods}%rowtype;
  v_settings ${settings}%rowtype;
begin
  select * into v_period from ${periods} y where y.${p("id")} = reopen_accounting_period.period_id for update;
  if not found then
    ${periodNotFound}
  end if;
  if not ${allowed(`v_period.${p("tenant")}`, sql.close)} then
    ${sql.forbidden("ACCOUNTING_PERIOD", "not allowed to reopen accounting periods")}
  end if;
  if nullif(trim(reopen_accounting_period.reason), '') is null then
    ${sql.invalid("ACCOUNTING_PERIOD", "reopening a period needs a reason")}
  end if;
  if v_period.${p("status")} = 'open' then
    return ${json.period("v_period")};
  end if;
  ${requireSettings(ctx, `v_period.${p("tenant")}`)}
  if v_settings.${s("lockDate")} is not null and v_period.${p("startsOn")} <= v_settings.${s("lockDate")} then
    ${fail("ACCOUNTING_PERIOD_CLOSED", "the period is on or before the lock date", "55000")}
  end if;
  update ${periods} y set ${p("status")} = 'open', ${p("closedAt")} = null, ${p("closedBy")} = null
  where y.${p("id")} = v_period.${p("id")}
  returning * into v_period;
  ${recordPeriod("accounting_period.reopened", "v_period", `, 'reason', trim(reopen_accounting_period.reason)`)}
  return ${json.period("v_period")};
end;
$$;
${userGrant(`${fn("reopen_accounting_period")}(uuid, text)`)}

-- Closes a fiscal year: one closing entry in the first general journal moves
-- every income and expense balance to the retained earnings account, then
-- every period of the year closes. Reverse the closing entry to redo it.
create or replace function ${fn("close_fiscal_year")}(tenant ${idType}, fiscal_year integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_settings ${settings}%rowtype;
  v_period ${periods}%rowtype;
  v_starts date;
  v_ends date;
  v_open integer;
  v_retained uuid;
  v_journal uuid;
  v_entry ${entries}%rowtype;
  v_net numeric;
  v_count integer;
  v_closing uuid;
begin
  if not ${allowed("close_fiscal_year.tenant", sql.close)} then
    ${sql.forbidden("ACCOUNTING_PERIOD", "not allowed to close fiscal years")}
  end if;
  ${requireSettings(ctx, "close_fiscal_year.tenant")}
  select min(y.${p("startsOn")}), max(y.${p("endsOn")}), count(*) filter (where y.${p("status")} = 'open')
  into v_starts, v_ends, v_open
  from ${periods} y where y.${p("tenant")} = close_fiscal_year.tenant and y.${p("fiscalYear")} = close_fiscal_year.fiscal_year;
  if v_starts is null then
    ${fail("ACCOUNTING_PERIOD_NOT_FOUND", "the fiscal year has no periods; open it first", "P0002")}
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(close_fiscal_year.tenant::text || ':fiscal_year:' || close_fiscal_year.fiscal_year::text, 0));
  if exists (
    select 1 from ${entries} y
    where y.${e("tenant")} = close_fiscal_year.tenant and y.${e("sourceType")} = 'fiscal_year'
      and y.${e("sourceId")} = close_fiscal_year.fiscal_year::text and y.${e("status")} <> 'reversed'
  ) then
    ${fail("FISCAL_YEAR_CLOSED", "the fiscal year is already closed; reverse its closing entry to close it again", "55000")}
  end if;
  if exists (
    select 1 from ${entries} y
    where y.${e("tenant")} = close_fiscal_year.tenant and y.${e("status")} = 'draft'
      and y.${e("entryDate")} >= v_starts and y.${e("entryDate")} <= v_ends
  ) then
    ${fail("ACCOUNTING_PERIOD_CLOSE_BLOCKED", "the fiscal year can't close yet: draft_entries", "55000")}
  end if;
  select y.${r("account")} into v_retained from ${roles} y
  where y.${r("tenant")} = close_fiscal_year.tenant and y.${r("role")} = 'retained_earnings';
  if v_retained is null then
    ${fail("ACCOUNTING_ACCOUNT_ROLE_MISSING", "no account has the retained_earnings role", "P0002")}
  end if;
  select y.${j("id")} into v_journal from ${journals} y
  where y.${j("tenant")} = close_fiscal_year.tenant and y.${j("type")} = 'general'
  order by y.${j("code")} limit 1;
  if v_journal is null then
    ${fail("ACCOUNTING_JOURNAL_NOT_FOUND", "the year-end close needs a general journal", "P0002")}
  end if;
  select count(*), coalesce(sum(c.net), 0) into v_count, v_net from (${balances}) c;
  if v_count > 0 then
    insert into ${entries} (${e("tenant")}, ${e("journal")}, ${e("entryDate")}, ${e("sourceType")}, ${e("sourceId")}, ${e("memo")}, ${e("createdBy")})
    values (close_fiscal_year.tenant, v_journal, v_ends, 'fiscal_year', close_fiscal_year.fiscal_year::text,
      'Closing of fiscal year ' || close_fiscal_year.fiscal_year::text, auth.uid())
    returning * into v_entry;
    insert into ${lines} (${l("tenant")}, ${l("entry")}, ${l("position")}, ${l("account")}, ${l("debit")}, ${l("credit")}, ${l("currency")}, ${l("amountCurrency")})
    select close_fiscal_year.tenant, v_entry.${e("id")}, (row_number() over (order by w.${a("code")}))::smallint, c.account,
      greatest(-c.net, 0)::bigint, greatest(c.net, 0)::bigint, v_settings.${s("functionalCurrency")}, (-c.net)::bigint
    from (${balances}) c join ${accounts} w on w.${a("id")} = c.account;
    if v_net <> 0 then
      insert into ${lines} (${l("tenant")}, ${l("entry")}, ${l("position")}, ${l("account")}, ${l("debit")}, ${l("credit")}, ${l("currency")}, ${l("amountCurrency")})
      values (close_fiscal_year.tenant, v_entry.${e("id")}, 32767, v_retained,
        greatest(v_net, 0)::bigint, greatest(-v_net, 0)::bigint, v_settings.${s("functionalCurrency")}, v_net::bigint);
    end if;
    v_entry := ${fn("accounting_post")}(v_entry.${e("id")}, true);
    v_closing := v_entry.${e("id")};
  elsif v_open = 0 then
    ${fail("FISCAL_YEAR_CLOSED", "the fiscal year is already closed", "55000")}
  end if;
  for v_period in
    select * from ${periods} y
    where y.${p("tenant")} = close_fiscal_year.tenant and y.${p("fiscalYear")} = close_fiscal_year.fiscal_year and y.${p("status")} = 'open'
    order by y.${p("number")}
    for update
  loop
    ${closePeriod}
  end loop;
  ${ctx.record({
    type: "fiscal_year.closed",
    payload: `jsonb_build_object('organizationId', close_fiscal_year.tenant, 'fiscalYear', close_fiscal_year.fiscal_year, 'closingEntryId', v_closing)`,
    subject: `'fiscal-years/' || close_fiscal_year.tenant::text || '/' || close_fiscal_year.fiscal_year::text`,
    tenant: "close_fiscal_year.tenant",
    audit: {
      category: "data",
      targetType: "fiscal_year",
      recordId: "close_fiscal_year.fiscal_year::text",
      targetLabel: "close_fiscal_year.fiscal_year::text",
      summary: `'closed fiscal year ' || close_fiscal_year.fiscal_year::text`,
    },
  })}
  return jsonb_build_object('organizationId', close_fiscal_year.tenant, 'fiscalYear', close_fiscal_year.fiscal_year, 'closingEntryId', v_closing);
end;
$$;
${userGrant(`${fn("close_fiscal_year")}(${idType}, integer)`)}
`;
}

/** The trial balance, profit and loss, balance sheet and general ledger. */
export function accountingReportFunctions(ctx: BlockSqlContext): string {
  const accounts = ctx.table("accounts");
  const entries = ctx.table("entries");
  const lines = ctx.table("lines");
  const a = (column: string): string => ctx.col("accounts", column);
  const e = (column: string): string => ctx.col("entries", column);
  const l = (column: string): string => ctx.col("lines", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;

  const booked = (fnName: string): string =>
    `from ${lines} y join ${entries} z on z.${e("id")} = y.${l("entry")}
    where z.${e("tenant")} = ${fnName}.tenant and z.${e("status")} in ('posted', 'reversed')
      and y.${l("dimensions")} @> coalesce(${fnName}.dimensions, '{}'::jsonb)`;

  const accountLine = (amount: string): string =>
    `jsonb_build_object('accountId', w.${a("id")}, 'code', w.${a("code")}, 'name', w.${a("name")}, 'type', w.${a("type")}, 'subtype', w.${a("subtype")}, 'amount', (${amount})::text)`;

  return `
-- Per account: the balance before since, the debits and credits from since
-- through until, and the closing balance; debit balances are positive. Lines
-- match when their dimensions contain the dimensions filter.
create or replace function ${fn("accounting_trial_balance")}(tenant ${idType}, since date default null, until date default null, dimensions jsonb default '{}'::jsonb)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with sums as (
    select y.${l("account")} as account,
      sum(case when z.${e("entryDate")} < accounting_trial_balance.since then y.${l("debit")} - y.${l("credit")} else 0 end) as opening,
      sum(case when accounting_trial_balance.since is null or z.${e("entryDate")} >= accounting_trial_balance.since then y.${l("debit")} else 0 end) as debit,
      sum(case when accounting_trial_balance.since is null or z.${e("entryDate")} >= accounting_trial_balance.since then y.${l("credit")} else 0 end) as credit
    ${booked("accounting_trial_balance")}
      and (accounting_trial_balance.until is null or z.${e("entryDate")} <= accounting_trial_balance.until)
    group by y.${l("account")}
  )
  select jsonb_build_object(
    'accounts', coalesce(jsonb_agg(jsonb_build_object('accountId', w.${a("id")}, 'code', w.${a("code")}, 'name', w.${a("name")}, 'type', w.${a("type")},
      'opening', c.opening::text, 'debit', c.debit::text, 'credit', c.credit::text, 'closing', (c.opening + c.debit - c.credit)::text) order by w.${a("code")}), '[]'::jsonb),
    'totals', jsonb_build_object('opening', coalesce(sum(c.opening), 0)::text, 'debit', coalesce(sum(c.debit), 0)::text, 'credit', coalesce(sum(c.credit), 0)::text,
      'closing', coalesce(sum(c.opening + c.debit - c.credit), 0)::text)
  )
  from sums c join ${accounts} w on w.${a("id")} = c.account
$$;
${userGrant(`${fn("accounting_trial_balance")}(${idType}, date, date, jsonb)`)}

-- Income and expenses from since through until, without year-end closing
-- entries. Income counts credits, expenses debits.
create or replace function ${fn("accounting_profit_and_loss")}(tenant ${idType}, since date default null, until date default null, dimensions jsonb default '{}'::jsonb)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with sums as (
    select y.${l("account")} as account, sum(y.${l("credit")}) - sum(y.${l("debit")}) as credit_balance
    ${booked("accounting_profit_and_loss")}
      and z.${e("sourceType")} is distinct from 'fiscal_year'
      and (accounting_profit_and_loss.since is null or z.${e("entryDate")} >= accounting_profit_and_loss.since)
      and (accounting_profit_and_loss.until is null or z.${e("entryDate")} <= accounting_profit_and_loss.until)
    group by y.${l("account")}
  ),
  kept as (
    select w.*, c.credit_balance from sums c join ${accounts} w on w.${a("id")} = c.account
    where w.${a("type")} in ('income', 'expense') and c.credit_balance <> 0
  )
  select jsonb_build_object(
    'income', coalesce((select jsonb_agg(${accountLine("w.credit_balance")} order by w.${a("code")}) from kept w where w.${a("type")} = 'income'), '[]'::jsonb),
    'expenses', coalesce((select jsonb_agg(${accountLine("-w.credit_balance")} order by w.${a("code")}) from kept w where w.${a("type")} = 'expense'), '[]'::jsonb),
    'totalIncome', coalesce((select sum(w.credit_balance) from kept w where w.${a("type")} = 'income'), 0)::text,
    'totalExpenses', coalesce((select -sum(w.credit_balance) from kept w where w.${a("type")} = 'expense'), 0)::text,
    'netIncome', coalesce((select sum(w.credit_balance) from kept w), 0)::text
  )
$$;
${userGrant(`${fn("accounting_profit_and_loss")}(${idType}, date, date, jsonb)`)}

-- Assets, liabilities and equity on as_of. Income and expenses not yet
-- closed into retained earnings count as current earnings under equity.
create or replace function ${fn("accounting_balance_sheet")}(tenant ${idType}, as_of date default null, dimensions jsonb default '{}'::jsonb)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with sums as (
    select y.${l("account")} as account, sum(y.${l("debit")}) - sum(y.${l("credit")}) as debit_balance
    ${booked("accounting_balance_sheet")}
      and z.${e("entryDate")} <= coalesce(accounting_balance_sheet.as_of, current_date)
    group by y.${l("account")}
  ),
  kept as (
    select w.*, c.debit_balance from sums c join ${accounts} w on w.${a("id")} = c.account
    where c.debit_balance <> 0
  ),
  totals as (
    select
      coalesce(sum(w.debit_balance) filter (where w.${a("type")} = 'asset'), 0) as assets,
      coalesce(-sum(w.debit_balance) filter (where w.${a("type")} = 'liability'), 0) as liabilities,
      coalesce(-sum(w.debit_balance) filter (where w.${a("type")} = 'equity'), 0) as equity,
      coalesce(-sum(w.debit_balance) filter (where w.${a("type")} in ('income', 'expense')), 0) as earnings
    from kept w
  )
  select jsonb_build_object(
    'asOf', coalesce(accounting_balance_sheet.as_of, current_date),
    'assets', coalesce((select jsonb_agg(${accountLine("w.debit_balance")} order by w.${a("code")}) from kept w where w.${a("type")} = 'asset'), '[]'::jsonb),
    'liabilities', coalesce((select jsonb_agg(${accountLine("-w.debit_balance")} order by w.${a("code")}) from kept w where w.${a("type")} = 'liability'), '[]'::jsonb),
    'equity', coalesce((select jsonb_agg(${accountLine("-w.debit_balance")} order by w.${a("code")}) from kept w where w.${a("type")} = 'equity'), '[]'::jsonb),
    'currentEarnings', t.earnings::text,
    'totalAssets', t.assets::text,
    'totalLiabilities', t.liabilities::text,
    'totalEquity', (t.equity + t.earnings)::text,
    'balanced', t.assets = t.liabilities + t.equity + t.earnings
  )
  from totals t
$$;
${userGrant(`${fn("accounting_balance_sheet")}(${idType}, date, jsonb)`)}

-- One account's posted lines from since through until with a running
-- balance; debit balances are positive.
create or replace function ${fn("accounting_general_ledger")}(account_id uuid, since date default null, until date default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with account as (
    select w.* from ${accounts} w where w.${a("id")} = accounting_general_ledger.account_id
  ),
  booked as (
    select y.*, z.${e("entryDate")} as entry_date, z.${e("number")} as entry_number, z.${e("journal")} as journal_id, z.${e("memo")} as memo
    from ${lines} y join ${entries} z on z.${e("id")} = y.${l("entry")}
    where y.${l("account")} = accounting_general_ledger.account_id and z.${e("status")} in ('posted', 'reversed')
      and (accounting_general_ledger.until is null or z.${e("entryDate")} <= accounting_general_ledger.until)
  ),
  opening as (
    select coalesce(sum(b.${l("debit")} - b.${l("credit")}), 0) as amount from booked b
    where b.entry_date < accounting_general_ledger.since
  ),
  period as (
    select b.*, (select o.amount from opening o) + sum(b.${l("debit")} - b.${l("credit")}) over (order by b.entry_date, b.entry_number, b.${l("position")}, b.${l("id")}) as balance
    from booked b
    where accounting_general_ledger.since is null or b.entry_date >= accounting_general_ledger.since
  )
  select jsonb_build_object(
    'account', jsonb_build_object('id', w.${a("id")}, 'code', w.${a("code")}, 'name', w.${a("name")}, 'type', w.${a("type")}),
    'opening', (select o.amount from opening o)::text,
    'lines', coalesce((select jsonb_agg(jsonb_build_object('entryId', b.${l("entry")}, 'number', b.entry_number, 'entryDate', b.entry_date, 'journalId', b.journal_id,
      'description', coalesce(b.${l("description")}, b.memo), 'partyId', b.${l("party")}, 'debit', b.${l("debit")}::text, 'credit', b.${l("credit")}::text, 'balance', b.balance::text)
      order by b.entry_date, b.entry_number, b.${l("position")}, b.${l("id")}) from period b), '[]'::jsonb),
    'closing', ((select o.amount from opening o) + coalesce((select sum(b.${l("debit")} - b.${l("credit")}) from period b), 0))::text
  )
  from account w
$$;
${userGrant(`${fn("accounting_general_ledger")}(uuid, date, date)`)}
`;
}
