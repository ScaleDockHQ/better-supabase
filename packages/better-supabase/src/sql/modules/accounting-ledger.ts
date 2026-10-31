import type { BlockSqlContext } from "../context.ts";
import type { ImportTargetContribution } from "../contributions.ts";

import { fail, serviceGrant, userGrant } from "../shared.ts";
import { entryJson } from "./accounting-entries.ts";
import { requireSettings } from "./accounting-setup.ts";
import { accountingSql } from "./accounting-shared.ts";

const plain = (qualified: string): string => qualified.replaceAll('"', "");

/**
 * Opening balances: rows per fiscal year, account and party, posted as one
 * opening entry. The carried rows `close_fiscal_year` writes live in the same
 * table.
 */
export function accountingOpeningFunctions(ctx: BlockSqlContext): string {
  const accounts = ctx.table("accounts");
  const journals = ctx.table("journals");
  const periods = ctx.table("periods");
  const entries = ctx.table("entries");
  const lines = ctx.table("lines");
  const openings = ctx.table("openingBalances");
  const settings = ctx.table("settings");
  const s = (column: string): string => ctx.col("settings", column);
  const a = (column: string): string => ctx.col("accounts", column);
  const j = (column: string): string => ctx.col("journals", column);
  const p = (column: string): string => ctx.col("periods", column);
  const e = (column: string): string => ctx.col("entries", column);
  const l = (column: string): string => ctx.col("lines", column);
  const o = (column: string): string => ctx.col("openingBalances", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const sql = accountingSql(ctx);
  const { allowed } = sql;

  const openingJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${o("id")}, 'organizationId', ${row}.${o("tenant")}, 'fiscalYear', ${row}.${o("fiscalYear")}, 'accountId', ${row}.${o("account")}, 'partyId', ${row}.${o("party")}, 'amount', ${row}.${o("amount")}::text, 'source', ${row}.${o("source")})`;

  return `
-- Whether the fiscal year's opening entry is posted: an unreversed entry with
-- the source opening_balance and the year as its id.
create or replace function ${fn("accounting_opening_posted")}(tenant ${idType}, fiscal_year integer)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from ${entries} y
    where y.${e("tenant")} = accounting_opening_posted.tenant and y.${e("sourceType")} = 'opening_balance'
      and y.${e("sourceId")} = accounting_opening_posted.fiscal_year::text and y.${e("status")} <> 'reversed'
  )
$$;

-- Writes one opening balance row (an upsert on the year, the account and the
-- party) and returns its id. A year whose opening entry is posted refuses it.
create or replace function ${fn("accounting_opening_write")}(tenant ${idType}, fiscal_year integer, account_id uuid, party_id uuid, amount bigint)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
begin
  if accounting_opening_write.fiscal_year is null or accounting_opening_write.fiscal_year < 1900 or accounting_opening_write.fiscal_year > 9999 then
    ${sql.invalid("ACCOUNTING_OPENING", "the fiscal year must be a year")}
  end if;
  if accounting_opening_write.amount is null or accounting_opening_write.amount = 0 then
    ${sql.invalid("ACCOUNTING_OPENING", "an opening balance needs a non-zero amount; a debit balance is positive")}
  end if;
  if not exists (
    select 1 from ${accounts} y where y.${a("id")} = accounting_opening_write.account_id and y.${a("tenant")} = accounting_opening_write.tenant
  ) then
    ${sql.notFound("ACCOUNTING_ACCOUNT", "an opening balance's account isn't an account of the organization")}
  end if;
  if ${fn("accounting_opening_posted")}(accounting_opening_write.tenant, accounting_opening_write.fiscal_year) then
    ${fail("ACCOUNTING_OPENING_POSTED", "the opening entry of the fiscal year is posted; reverse it first", "55000")}
  end if;
  insert into ${openings} (${o("tenant")}, ${o("fiscalYear")}, ${o("account")}, ${o("party")}, ${o("amount")}, ${o("source")})
  values (accounting_opening_write.tenant, accounting_opening_write.fiscal_year, accounting_opening_write.account_id, accounting_opening_write.party_id, accounting_opening_write.amount, 'imported')
  on conflict (${o("tenant")}, ${o("fiscalYear")}, ${o("account")}, coalesce(${o("party")}, '00000000-0000-0000-0000-000000000000'::uuid))
  do update set ${o("amount")} = excluded.${o("amount")}, ${o("source")} = 'imported', ${o("updatedAt")} = now()
  returning ${o("id")} into v_id;
  return v_id;
end;
$$;

-- Saves a fiscal year's opening balances: balances is an array of
-- { accountId | accountCode, partyId?, amount } with amount as signed minor
-- units of the functional currency (a debit balance is positive). Each row
-- replaces the row of its account and party, carried rows included.
create or replace function ${fn("save_accounting_opening_balances")}(tenant ${idType}, fiscal_year integer, balances jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row record;
  v_account uuid;
  v_ids uuid[] := '{}';
begin
  if not ${allowed("save_accounting_opening_balances.tenant", sql.manage)} then
    ${sql.forbidden("ACCOUNTING_OPENING", "not allowed to manage the chart of accounts")}
  end if;
  if jsonb_typeof(save_accounting_opening_balances.balances) is distinct from 'array' then
    ${sql.invalid("ACCOUNTING_OPENING", "balances is an array")}
  end if;
  for v_row in select e.value from jsonb_array_elements(save_accounting_opening_balances.balances) e loop
    if jsonb_typeof(v_row.value) is distinct from 'object' or coalesce(v_row.value ->> 'amount', '') !~ '^-?[0-9]{1,18}$' then
      ${sql.invalid("ACCOUNTING_OPENING", "every balance is an object with an integer amount")}
    end if;
    begin
      v_account := coalesce(
        nullif(v_row.value ->> 'accountId', '')::uuid,
        (select y.${a("id")} from ${accounts} y where y.${a("tenant")} = save_accounting_opening_balances.tenant and y.${a("code")} = v_row.value ->> 'accountCode')
      );
      v_ids := v_ids || ${fn("accounting_opening_write")}(save_accounting_opening_balances.tenant, save_accounting_opening_balances.fiscal_year,
        v_account, nullif(v_row.value ->> 'partyId', '')::uuid, (v_row.value ->> 'amount')::bigint);
    exception
      when invalid_text_representation then
        ${sql.invalid("ACCOUNTING_OPENING", "accountId and partyId are uuids")}
    end;
  end loop;
  return jsonb_build_object('organizationId', save_accounting_opening_balances.tenant, 'fiscalYear', save_accounting_opening_balances.fiscal_year,
    'balances', (select coalesce(jsonb_agg(${openingJson("y")} order by y.${o("account")}, y.${o("party")}), '[]'::jsonb)
      from ${openings} y where y.${o("id")} = any (v_ids)));
end;
$$;
${userGrant(`${fn("save_accounting_opening_balances")}(${idType}, integer, jsonb)`)}

-- A fiscal year's opening balances, imported and carried, with their total
-- (zero when the books balance).
create or replace function ${fn("list_accounting_opening_balances")}(tenant ${idType}, fiscal_year integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'organizationId', list_accounting_opening_balances.tenant,
    'fiscalYear', list_accounting_opening_balances.fiscal_year,
    'posted', ${fn("accounting_opening_posted")}(list_accounting_opening_balances.tenant, list_accounting_opening_balances.fiscal_year),
    'balances', coalesce(jsonb_agg(${openingJson("y")} order by y.${o("account")}, y.${o("party")}), '[]'::jsonb),
    'total', coalesce(sum(y.${o("amount")}), 0)::text)
  from ${openings} y
  where y.${o("tenant")} = list_accounting_opening_balances.tenant and y.${o("fiscalYear")} = list_accounting_opening_balances.fiscal_year
$$;
${userGrant(`${fn("list_accounting_opening_balances")}(${idType}, integer)`)}

-- Posts the imported opening balances of a fiscal year as one entry dated on
-- the year's first day, in journal_id or the first general journal. The
-- balances must add up to zero. Posting twice returns the same entry. Carried
-- balances aren't posted: the entries of the closed year already hold them.
create or replace function ${fn("post_accounting_opening_balances")}(tenant ${idType}, fiscal_year integer, journal_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_settings ${settings}%rowtype;
  v_row ${entries}%rowtype;
  v_journal uuid := post_accounting_opening_balances.journal_id;
  v_starts date;
  v_net numeric;
  v_count integer;
begin
  if not ${allowed("post_accounting_opening_balances.tenant", sql.post)} then
    ${sql.forbidden("ACCOUNTING_OPENING", "not allowed to post accounting entries")}
  end if;
  ${requireSettings(ctx, "post_accounting_opening_balances.tenant")}
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(post_accounting_opening_balances.tenant::text || ':opening:' || post_accounting_opening_balances.fiscal_year::text, 0));
  select * into v_row from ${entries} y
  where y.${e("tenant")} = post_accounting_opening_balances.tenant and y.${e("sourceType")} = 'opening_balance'
    and y.${e("sourceId")} = post_accounting_opening_balances.fiscal_year::text and y.${e("status")} <> 'reversed';
  if found then
    return ${entryJson(ctx, "v_row", true)};
  end if;
  select count(*), coalesce(sum(y.${o("amount")}), 0) into v_count, v_net from ${openings} y
  where y.${o("tenant")} = post_accounting_opening_balances.tenant and y.${o("fiscalYear")} = post_accounting_opening_balances.fiscal_year and y.${o("source")} = 'imported';
  if v_count = 0 then
    ${sql.notFound("ACCOUNTING_OPENING", "the fiscal year has no imported opening balances")}
  end if;
  if v_net <> 0 then
    ${fail("ACCOUNTING_ENTRY_UNBALANCED", "the opening balances don't add up to zero", "23514")}
  end if;
  select min(y.${p("startsOn")}) into v_starts from ${periods} y
  where y.${p("tenant")} = post_accounting_opening_balances.tenant and y.${p("fiscalYear")} = post_accounting_opening_balances.fiscal_year;
  if v_starts is null then
    ${fail("ACCOUNTING_PERIOD_NOT_FOUND", "the fiscal year has no periods; open it first", "P0002")}
  end if;
  if v_journal is null then
    select y.${j("id")} into v_journal from ${journals} y
    where y.${j("tenant")} = post_accounting_opening_balances.tenant and y.${j("type")} = 'general'
    order by y.${j("code")} limit 1;
  elsif not exists (select 1 from ${journals} y where y.${j("id")} = v_journal and y.${j("tenant")} = post_accounting_opening_balances.tenant) then
    ${sql.notFound("ACCOUNTING_JOURNAL", "journal not found")}
  end if;
  if v_journal is null then
    ${fail("ACCOUNTING_JOURNAL_NOT_FOUND", "the opening entry needs a general journal", "P0002")}
  end if;
  insert into ${entries} (${e("tenant")}, ${e("journal")}, ${e("entryDate")}, ${e("sourceType")}, ${e("sourceId")}, ${e("memo")}, ${e("createdBy")})
  values (post_accounting_opening_balances.tenant, v_journal, v_starts, 'opening_balance', post_accounting_opening_balances.fiscal_year::text,
    'Opening balances of fiscal year ' || post_accounting_opening_balances.fiscal_year::text, auth.uid())
  returning * into v_row;
  insert into ${lines} (${l("tenant")}, ${l("entry")}, ${l("position")}, ${l("account")}, ${l("debit")}, ${l("credit")}, ${l("currency")}, ${l("amountCurrency")}, ${l("party")})
  select post_accounting_opening_balances.tenant, v_row.${e("id")}, (row_number() over (order by w.${a("code")}, y.${o("party")}))::smallint, y.${o("account")},
    greatest(y.${o("amount")}, 0)::bigint, greatest(-y.${o("amount")}, 0)::bigint, v_settings.${s("functionalCurrency")}, y.${o("amount")}, y.${o("party")}
  from ${openings} y join ${accounts} w on w.${a("id")} = y.${o("account")}
  where y.${o("tenant")} = post_accounting_opening_balances.tenant and y.${o("fiscalYear")} = post_accounting_opening_balances.fiscal_year and y.${o("source")} = 'imported';
  v_row := ${fn("accounting_post")}(v_row.${e("id")}, true);
  return ${entryJson(ctx, "v_row", true)};
end;
$$;
${userGrant(`${fn("post_accounting_opening_balances")}(${idType}, integer, uuid)`)}
`;
}

/** The column balance, the journal listing and the per-period trial balance. */
export function accountingLedgerReports(ctx: BlockSqlContext): string {
  const accounts = ctx.table("accounts");
  const journals = ctx.table("journals");
  const periods = ctx.table("periods");
  const entries = ctx.table("entries");
  const lines = ctx.table("lines");
  const a = (column: string): string => ctx.col("accounts", column);
  const j = (column: string): string => ctx.col("journals", column);
  const p = (column: string): string => ctx.col("periods", column);
  const e = (column: string): string => ctx.col("entries", column);
  const l = (column: string): string => ctx.col("lines", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;

  return `
-- The trial balance of one period: the balance before it and its debits and
-- credits, through its last day.
create or replace function ${fn("accounting_period_trial_balance")}(period_id uuid, dimensions jsonb default '{}'::jsonb)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${fn("accounting_trial_balance")}(y.${p("tenant")}, y.${p("startsOn")}, y.${p("endsOn")}, accounting_period_trial_balance.dimensions)
  from ${periods} y where y.${p("id")} = accounting_period_trial_balance.period_id
$$;
${userGrant(`${fn("accounting_period_trial_balance")}(uuid, jsonb)`)}

-- The trial balance in columns: per account the opening, period and closing
-- balance, each as a debit and a credit column. With rollup, a parent account
-- also adds up the accounts below it (the totals count each line once).
create or replace function ${fn("accounting_column_balance")}(tenant ${idType}, since date default null, until date default null, dimensions jsonb default '{}'::jsonb, rollup boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with recursive sums as (
    select y.${l("account")} as account,
      sum(case when z.${e("entryDate")} < accounting_column_balance.since then y.${l("debit")} - y.${l("credit")} else 0 end) as opening,
      sum(case when accounting_column_balance.since is null or z.${e("entryDate")} >= accounting_column_balance.since then y.${l("debit")} else 0 end) as debit,
      sum(case when accounting_column_balance.since is null or z.${e("entryDate")} >= accounting_column_balance.since then y.${l("credit")} else 0 end) as credit
    from ${lines} y join ${entries} z on z.${e("id")} = y.${l("entry")}
    where z.${e("tenant")} = accounting_column_balance.tenant and z.${e("status")} in ('posted', 'reversed')
      and y.${l("dimensions")} @> coalesce(accounting_column_balance.dimensions, '{}'::jsonb)
      and (accounting_column_balance.until is null or z.${e("entryDate")} <= accounting_column_balance.until)
    group by y.${l("account")}
  ),
  tree (leaf, node) as (
    select w.${a("id")}, w.${a("id")} from ${accounts} w where w.${a("tenant")} = accounting_column_balance.tenant
    union all
    select t.leaf, w.${a("parent")} from tree t join ${accounts} w on w.${a("id")} = t.node
    where w.${a("parent")} is not null and coalesce(accounting_column_balance.rollup, false)
  ),
  rolled as (
    select t.node as account, sum(c.opening) as opening, sum(c.debit) as debit, sum(c.credit) as credit
    from tree t join sums c on c.account = t.leaf group by t.node
  )
  select jsonb_build_object(
    'accounts', coalesce((
      select jsonb_agg(jsonb_build_object('accountId', w.${a("id")}, 'code', w.${a("code")}, 'name', w.${a("name")}, 'type', w.${a("type")},
        'parentId', w.${a("parent")}, 'level', w.${a("level")},
        'openingDebit', greatest(r.opening, 0)::text, 'openingCredit', greatest(-r.opening, 0)::text,
        'debit', r.debit::text, 'credit', r.credit::text,
        'closingDebit', greatest(r.opening + r.debit - r.credit, 0)::text, 'closingCredit', greatest(r.credit - r.debit - r.opening, 0)::text) order by w.${a("code")})
      from rolled r join ${accounts} w on w.${a("id")} = r.account), '[]'::jsonb),
    'totals', (select jsonb_build_object(
        'openingDebit', coalesce(sum(greatest(c.opening, 0)), 0)::text, 'openingCredit', coalesce(sum(greatest(-c.opening, 0)), 0)::text,
        'debit', coalesce(sum(c.debit), 0)::text, 'credit', coalesce(sum(c.credit), 0)::text,
        'closingDebit', coalesce(sum(greatest(c.opening + c.debit - c.credit, 0)), 0)::text,
        'closingCredit', coalesce(sum(greatest(c.credit - c.debit - c.opening, 0)), 0)::text)
      from sums c)
  )
$$;
${userGrant(`${fn("accounting_column_balance")}(${idType}, date, date, jsonb, boolean)`)}

-- The posted entries from since through until, per journal, each with its
-- lines in position order. journal_id narrows it to one journal.
create or replace function ${fn("accounting_journal_listing")}(tenant ${idType}, since date default null, until date default null, journal_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('journals', coalesce(jsonb_agg(jsonb_build_object(
      'journalId', g.${j("id")}, 'code', g.${j("code")}, 'name', g.${j("name")}, 'type', g.${j("type")},
      'entries', g.entries, 'totalDebit', g.total_debit::text, 'totalCredit', g.total_credit::text) order by g.${j("code")}), '[]'::jsonb))
  from (
    select w.*,
      (select jsonb_agg(jsonb_build_object('id', z.${e("id")}, 'number', z.${e("number")}, 'entryDate', z.${e("entryDate")}, 'status', z.${e("status")},
          'reference', z.${e("reference")}, 'memo', z.${e("memo")},
          'lines', (select jsonb_agg(jsonb_build_object('accountId', y.${l("account")}, 'accountCode', x.${a("code")}, 'accountName', x.${a("name")},
              'debit', y.${l("debit")}::text, 'credit', y.${l("credit")}::text, 'taxAmount', y.${l("taxAmount")}::text, 'partyId', y.${l("party")},
              'description', y.${l("description")}) order by y.${l("position")}, y.${l("id")})
            from ${lines} y join ${accounts} x on x.${a("id")} = y.${l("account")} where y.${l("entry")} = z.${e("id")}))
        order by z.${e("entryDate")}, z.${e("number")}, z.${e("id")})
        from ${entries} z
        where z.${e("journal")} = w.${j("id")} and z.${e("status")} in ('posted', 'reversed')
          and (accounting_journal_listing.since is null or z.${e("entryDate")} >= accounting_journal_listing.since)
          and (accounting_journal_listing.until is null or z.${e("entryDate")} <= accounting_journal_listing.until)) as entries,
      (select coalesce(sum(y.${l("debit")}), 0) from ${lines} y join ${entries} z on z.${e("id")} = y.${l("entry")}
        where z.${e("journal")} = w.${j("id")} and z.${e("status")} in ('posted', 'reversed')
          and (accounting_journal_listing.since is null or z.${e("entryDate")} >= accounting_journal_listing.since)
          and (accounting_journal_listing.until is null or z.${e("entryDate")} <= accounting_journal_listing.until)) as total_debit,
      (select coalesce(sum(y.${l("credit")}), 0) from ${lines} y join ${entries} z on z.${e("id")} = y.${l("entry")}
        where z.${e("journal")} = w.${j("id")} and z.${e("status")} in ('posted', 'reversed')
          and (accounting_journal_listing.since is null or z.${e("entryDate")} >= accounting_journal_listing.since)
          and (accounting_journal_listing.until is null or z.${e("entryDate")} <= accounting_journal_listing.until)) as total_credit
    from ${journals} w
    where w.${j("tenant")} = accounting_journal_listing.tenant
      and (accounting_journal_listing.journal_id is null or w.${j("id")} = accounting_journal_listing.journal_id)
  ) g
  where g.entries is not null
$$;
${userGrant(`${fn("accounting_journal_listing")}(${idType}, date, date, uuid)`)}
`;
}

/**
 * The import targets of a ledger (ADR 0141, ADR 0144): accounts, journals,
 * journal entries and opening balances. Every function resolves accounts and
 * journals by code, so a file from another system maps onto it as is.
 */
export function accountingImportFunctions(ctx: BlockSqlContext): string {
  const accounts = ctx.table("accounts");
  const journals = ctx.table("journals");
  const a = (column: string): string => ctx.col("accounts", column);
  const j = (column: string): string => ctx.col("journals", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;

  const accountByCode = (tenant: string, code: string): string =>
    `(select y.${a("id")} from ${accounts} y where y.${a("tenant")} = ${tenant} and y.${a("code")} = ${code})`;

  const invalid = (message: string): string =>
    fail("IMPORT_ITEM_INVALID", message, "22023");

  const dataCheck = (name: string, what: string): string => `
  if jsonb_typeof(${name}.item -> 'data') is distinct from 'object' then
    ${invalid(`${what} item needs data`)}
  end if;`;

  return `
-- The import target of the accounting_account entity: item.data is the input
-- of save_accounting_account, with parentCode for the parent by code.
create or replace function ${fn("import_accounting_account")}(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${idType} := (import_accounting_account.item ->> 'tenant')::${idType};
  v_data jsonb := import_accounting_account.item -> 'data';
  v_parent uuid;
  v_row jsonb;
begin${dataCheck("import_accounting_account", "an account")}
  begin
    v_parent := coalesce(nullif(v_data ->> 'parentId', '')::uuid, ${accountByCode("v_tenant", "v_data ->> 'parentCode'")});
    if nullif(v_data ->> 'parentCode', '') is not null and v_parent is null then
      ${invalid("the parent account code isn't an account of the organization; import parents first")}
    end if;
    v_row := ${fn("save_accounting_account")}(v_tenant, v_data ->> 'code', v_data ->> 'name', v_data ->> 'type', nullif(v_data ->> 'subtype', ''),
      v_parent, nullif(v_data ->> 'currency', ''), coalesce((v_data ->> 'reconcilable')::boolean, false),
      import_accounting_account.subject_id::uuid, nullif(v_data ->> 'normalSide', ''), nullif(v_data ->> 'defaultTaxCodeId', '')::uuid,
      coalesce((v_data ->> 'active')::boolean, true));
  exception
    when invalid_text_representation then
      ${invalid("an account's ids are uuids and its flags booleans")}
  end;
  return jsonb_build_object('subjectId', v_row ->> 'id', 'updatedAt', v_row ->> 'updatedAt');
end;
$$;
${serviceGrant(`${fn("import_accounting_account")}(uuid, jsonb, text)`)}

-- The import target of the accounting_journal entity: item.data is the input
-- of save_accounting_journal, with defaultAccountCode, contraAccountCode and
-- bankAccountCode for accounts by code.
create or replace function ${fn("import_accounting_journal")}(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${idType} := (import_accounting_journal.item ->> 'tenant')::${idType};
  v_data jsonb := import_accounting_journal.item -> 'data';
  v_default uuid;
  v_contra uuid;
  v_bank uuid;
  v_row jsonb;
begin${dataCheck("import_accounting_journal", "a journal")}
  begin
    v_default := coalesce(nullif(v_data ->> 'defaultAccountId', '')::uuid, ${accountByCode("v_tenant", "v_data ->> 'defaultAccountCode'")});
    v_contra := coalesce(nullif(v_data ->> 'contraAccountId', '')::uuid, ${accountByCode("v_tenant", "v_data ->> 'contraAccountCode'")});
    v_bank := coalesce(nullif(v_data ->> 'bankAccountId', '')::uuid, ${accountByCode("v_tenant", "v_data ->> 'bankAccountCode'")});
  exception
    when invalid_text_representation then
      ${invalid("a journal's account ids are uuids")}
  end;
  if (nullif(v_data ->> 'defaultAccountCode', '') is not null and v_default is null)
    or (nullif(v_data ->> 'contraAccountCode', '') is not null and v_contra is null)
    or (nullif(v_data ->> 'bankAccountCode', '') is not null and v_bank is null) then
    ${invalid("an account code of the journal isn't an account of the organization; import accounts first")}
  end if;
  v_row := ${fn("save_accounting_journal")}(v_tenant, v_data ->> 'code', v_data ->> 'name', v_data ->> 'type', v_default,
    nullif(v_data ->> 'currency', ''), import_accounting_journal.subject_id::uuid, v_contra, v_bank);
  return jsonb_build_object('subjectId', v_row ->> 'id', 'updatedAt', v_row ->> 'updatedAt');
end;
$$;
${serviceGrant(`${fn("import_accounting_journal")}(uuid, jsonb, text)`)}

-- The import target of the accounting_entry entity: item.data is { journalCode
-- | journalId, entryDate, memo?, reference?, post?, lines: [{ accountCode |
-- accountId, debit, credit, ... }] } with the amounts of save_accounting_entry.
-- The lines must balance, or the item is reported as an error and nothing is
-- written. The entry posts unless post is false; in import mode it may land in
-- a closed period, never in a locked one.
create or replace function ${fn("import_accounting_entry")}(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${idType} := (import_accounting_entry.item ->> 'tenant')::${idType};
  v_data jsonb := import_accounting_entry.item -> 'data';
  v_journal uuid;
  v_lines jsonb;
  v_debit numeric;
  v_credit numeric;
  v_row jsonb;
begin${dataCheck("import_accounting_entry", "an entry")}
  if jsonb_typeof(v_data -> 'lines') is distinct from 'array' or jsonb_array_length(v_data -> 'lines') < 2 then
    ${invalid("an entry needs at least two lines")}
  end if;
  begin
    v_journal := coalesce(nullif(v_data ->> 'journalId', '')::uuid,
      (select y.${j("id")} from ${journals} y where y.${j("tenant")} = v_tenant and y.${j("code")} = v_data ->> 'journalCode'));
    select jsonb_agg((e.value - 'accountCode') || jsonb_build_object('accountId', coalesce(nullif(e.value ->> 'accountId', '')::uuid, ${accountByCode("v_tenant", "e.value ->> 'accountCode'")})) order by e.ordinality),
      coalesce(sum((coalesce(nullif(e.value ->> 'debit', ''), '0'))::numeric), 0),
      coalesce(sum((coalesce(nullif(e.value ->> 'credit', ''), '0'))::numeric), 0)
    into v_lines, v_debit, v_credit
    from jsonb_array_elements(v_data -> 'lines') with ordinality e;
  exception
    when invalid_text_representation then
      ${invalid("an entry's ids are uuids and its amounts integers")}
  end;
  if v_journal is null then
    ${invalid("the journal isn't a journal of the organization; import journals first")}
  end if;
  if exists (select 1 from jsonb_array_elements(v_lines) e where e.value ->> 'accountId' is null) then
    ${invalid("a line's account isn't an account of the organization; import accounts first")}
  end if;
  if v_debit <> v_credit then
    ${fail("IMPORT_ITEM_INVALID", "the lines don't balance: debits and credits differ", "22023")}
  end if;
  v_row := ${fn("save_accounting_entry")}(v_journal, (v_data ->> 'entryDate')::date, v_lines, nullif(v_data ->> 'memo', ''), nullif(v_data ->> 'reference', ''),
    null, null, import_accounting_entry.subject_id::uuid);
  if coalesce((v_data ->> 'post')::boolean, true) then
    v_row := ${fn("post_accounting_entry")}((v_row ->> 'id')::uuid);
  end if;
  return jsonb_build_object('subjectId', v_row ->> 'id');
end;
$$;
${serviceGrant(`${fn("import_accounting_entry")}(uuid, jsonb, text)`)}

-- The import target of the accounting_opening_balance entity: item.data is
-- { fiscalYear, accountCode | accountId, partyId?, amount }. Post the year's
-- rows with post_accounting_opening_balances once they are all in.
create or replace function ${fn("import_accounting_opening_balance")}(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${idType} := (import_accounting_opening_balance.item ->> 'tenant')::${idType};
  v_data jsonb := import_accounting_opening_balance.item -> 'data';
  v_account uuid;
begin${dataCheck("import_accounting_opening_balance", "an opening balance")}
  if coalesce(v_data ->> 'fiscalYear', '') !~ '^[0-9]{4}$' or coalesce(v_data ->> 'amount', '') !~ '^-?[0-9]{1,18}$' then
    ${invalid("an opening balance needs a fiscalYear and an integer amount")}
  end if;
  begin
    v_account := coalesce(nullif(v_data ->> 'accountId', '')::uuid, ${accountByCode("v_tenant", "v_data ->> 'accountCode'")});
    return jsonb_build_object('subjectId', ${fn("accounting_opening_write")}(v_tenant, (v_data ->> 'fiscalYear')::integer, v_account,
      nullif(v_data ->> 'partyId', '')::uuid, (v_data ->> 'amount')::bigint));
  exception
    when invalid_text_representation then
      ${invalid("an opening balance's ids are uuids")}
  end;
end;
$$;
${serviceGrant(`${fn("import_accounting_opening_balance")}(uuid, jsonb, text)`)}
`;
}

/** What `contributes.imports` returns for the accounting block. */
export function accountingImportTargets(
  own: BlockSqlContext,
): readonly ImportTargetContribution[] {
  return own.mode === "custom"
    ? []
    : [
        {
          entity: "accounting_account",
          subjectType: "accounting_account",
          write: plain(own.fn("import_accounting_account")),
        },
        {
          entity: "accounting_journal",
          subjectType: "accounting_journal",
          write: plain(own.fn("import_accounting_journal")),
        },
        {
          entity: "accounting_entry",
          subjectType: "accounting_entry",
          write: plain(own.fn("import_accounting_entry")),
        },
        {
          entity: "accounting_opening_balance",
          subjectType: "accounting_opening_balance",
          write: plain(own.fn("import_accounting_opening_balance")),
        },
      ];
}
