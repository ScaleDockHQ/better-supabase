import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { fail, userGrant } from "../shared.ts";
import {
  ACCOUNT_ROLES,
  ACCOUNT_TYPES,
  accountingConfig,
  accountingSql,
  DEFAULT_JOURNALS,
  GENERIC_CHART,
  JOURNAL_TYPES,
  sqlList,
} from "./accounting-shared.ts";

/** The JSON shapes the accounting functions return, as SQL over a row alias. */
export interface AccountingJson {
  settings(row: string): string;
  account(row: string): string;
  journal(row: string): string;
  period(row: string): string;
  dimension(row: string): string;
}

export function accountingJson(ctx: BlockSqlContext): AccountingJson {
  const s = (column: string): string => ctx.col("settings", column);
  const a = (column: string): string => ctx.col("accounts", column);
  const r = (column: string): string => ctx.col("roles", column);
  const j = (column: string): string => ctx.col("journals", column);
  const p = (column: string): string => ctx.col("periods", column);
  const d = (column: string): string => ctx.col("dimensions", column);
  const v = (column: string): string => ctx.col("dimensionValues", column);

  return {
    settings: (row) =>
      `jsonb_build_object('organizationId', ${row}.${s("tenant")}, 'functionalCurrency', ${row}.${s("functionalCurrency")}, 'fiscalYearStartMonth', ${row}.${s("fiscalYearStartMonth")}, 'lockDate', ${row}.${s("lockDate")}, 'createdAt', ${row}.${s("createdAt")}, 'updatedAt', ${row}.${s("updatedAt")})`,
    account: (row) =>
      `jsonb_build_object('id', ${row}.${a("id")}, 'organizationId', ${row}.${a("tenant")}, 'code', ${row}.${a("code")}, 'name', ${row}.${a("name")}, 'type', ${row}.${a("type")}, 'subtype', ${row}.${a("subtype")}, 'parentId', ${row}.${a("parent")}, 'currency', ${row}.${a("currency")}, 'reconcilable', ${row}.${a("reconcilable")}, 'normalSide', ${row}.${a("normalSide")}, 'level', ${row}.${a("level")}, 'defaultTaxCodeId', ${row}.${a("defaultTaxCode")}, 'active', ${row}.${a("active")}, 'roles', coalesce((select jsonb_agg(ar.${r("role")} order by ar.${r("role")}) from ${ctx.table("roles")} ar where ar.${r("account")} = ${row}.${a("id")}), '[]'::jsonb), 'archivedAt', ${row}.${a("archivedAt")}, 'createdAt', ${row}.${a("createdAt")}, 'updatedAt', ${row}.${a("updatedAt")})`,
    journal: (row) =>
      `jsonb_build_object('id', ${row}.${j("id")}, 'organizationId', ${row}.${j("tenant")}, 'code', ${row}.${j("code")}, 'name', ${row}.${j("name")}, 'type', ${row}.${j("type")}, 'defaultAccountId', ${row}.${j("defaultAccount")}, 'currency', ${row}.${j("currency")}, 'contraAccountId', ${row}.${j("contraAccount")}, 'bankAccountId', ${row}.${j("bankAccount")}, 'createdAt', ${row}.${j("createdAt")}, 'updatedAt', ${row}.${j("updatedAt")})`,
    period: (row) =>
      `jsonb_build_object('id', ${row}.${p("id")}, 'organizationId', ${row}.${p("tenant")}, 'fiscalYear', ${row}.${p("fiscalYear")}, 'number', ${row}.${p("number")}, 'startsOn', ${row}.${p("startsOn")}, 'endsOn', ${row}.${p("endsOn")}, 'status', ${row}.${p("status")}, 'closedAt', ${row}.${p("closedAt")}, 'closedBy', ${row}.${p("closedBy")}, 'lockedAt', ${row}.${p("lockedAt")}, 'lockedBy', ${row}.${p("lockedBy")})`,
    dimension: (row) =>
      `jsonb_build_object('id', ${row}.${d("id")}, 'organizationId', ${row}.${d("tenant")}, 'key', ${row}.${d("key")}, 'name', ${row}.${d("name")}, 'values', coalesce((select jsonb_agg(jsonb_build_object('id', dv.${v("id")}, 'code', dv.${v("code")}, 'name', dv.${v("name")}, 'archivedAt', dv.${v("archivedAt")}) order by dv.${v("code")}) from ${ctx.table("dimensionValues")} dv where dv.${v("dimension")} = ${row}.${d("id")}), '[]'::jsonb), 'createdAt', ${row}.${d("createdAt")})`,
  };
}

/** `select * into v_settings ...`, failing when the organization isn't set up. */
export function requireSettings(
  ctx: BlockSqlContext,
  tenant: string,
  into = "v_settings",
): string {
  return `select * into ${into} from ${ctx.table("settings")} st where st.${ctx.col("settings", "tenant")} = ${tenant};
  if not found then
    ${fail("ACCOUNTING_SETTING_NOT_FOUND", "accounting isn't set up for this organization; call setup_accounting first", "P0002")}
  end if;`;
}

/**
 * Settings, the chart of accounts, account roles, journals, fiscal periods,
 * dimensions, tax codes and exchange rates.
 */
export function accountingSetupFunctions(ctx: BlockSqlContext): string {
  const settings = ctx.table("settings");
  const accounts = ctx.table("accounts");
  const roles = ctx.table("roles");
  const journals = ctx.table("journals");
  const periods = ctx.table("periods");
  const entries = ctx.table("entries");
  const lines = ctx.table("lines");
  const dimensions = ctx.table("dimensions");
  const values = ctx.table("dimensionValues");
  const rates = ctx.table("fxRates");
  const tax = ctx.of("tax");
  const taxes = tax.table("codes");
  const s = (column: string): string => ctx.col("settings", column);
  const a = (column: string): string => ctx.col("accounts", column);
  const r = (column: string): string => ctx.col("roles", column);
  const j = (column: string): string => ctx.col("journals", column);
  const p = (column: string): string => ctx.col("periods", column);
  const e = (column: string): string => ctx.col("entries", column);
  const l = (column: string): string => ctx.col("lines", column);
  const d = (column: string): string => ctx.col("dimensions", column);
  const v = (column: string): string => ctx.col("dimensionValues", column);
  const x = (column: string): string => ctx.col("fxRates", column);
  const t = (column: string): string => tax.col("codes", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const config = accountingConfig(ctx);
  const sql = accountingSql(ctx);
  const json = accountingJson(ctx);
  const { allowed } = sql;

  const chart =
    config.chart === "generic"
      ? `
  if not exists (select 1 from ${accounts} y where y.${a("tenant")} = setup_accounting.tenant) then
    insert into ${accounts} (${a("tenant")}, ${a("code")}, ${a("name")}, ${a("type")}, ${a("subtype")}, ${a("reconcilable")}, ${a("normalSide")})
    values
      ${GENERIC_CHART.map(
        (account) =>
          `(setup_accounting.tenant, ${sqlString(account.code)}, ${sqlString(account.name)}, ${sqlString(account.type)}, ${sqlString(account.subtype)}, ${String(account.reconcilable ?? false)}, ${sqlString(account.type === "asset" || account.type === "expense" ? "debit" : "credit")})`,
      ).join(",\n      ")};
    insert into ${roles} (${r("tenant")}, ${r("role")}, ${r("account")})
    select setup_accounting.tenant, c.role, y.${a("id")}
    from (values ${GENERIC_CHART.flatMap((account) =>
      account.role === undefined
        ? []
        : [`(${sqlString(account.role)}, ${sqlString(account.code)})`],
    ).join(", ")}) c (role, code)
    join ${accounts} y on y.${a("tenant")} = setup_accounting.tenant and y.${a("code")} = c.code
    on conflict (${r("tenant")}, ${r("role")}) do nothing;
  end if;
  if not exists (select 1 from ${journals} y where y.${j("tenant")} = setup_accounting.tenant) then
    insert into ${journals} (${j("tenant")}, ${j("code")}, ${j("name")}, ${j("type")}, ${j("defaultAccount")})
    select setup_accounting.tenant, c.code, c.name, c.type,
      (select y.${a("id")} from ${accounts} y where y.${a("tenant")} = setup_accounting.tenant and y.${a("code")} = c.account)
    from (values ${DEFAULT_JOURNALS.map(
      (journal) =>
        `(${sqlString(journal.code)}, ${sqlString(journal.name)}, ${sqlString(journal.type)}, ${journal.account === undefined ? "null::text" : sqlString(journal.account)})`,
    ).join(", ")}) c (code, name, type, account);
  end if;`
      : "";

  const notFound = (entity: string, what: string): string =>
    sql.notFound(entity, `${what} not found`);

  return `
-- Sets up accounting for an organization: its functional currency and the
-- month its fiscal year starts${config.chart === "generic" ? ", then the generic chart, its account roles and the default journals when it has none" : ""}.
-- Neither setting changes once entries post or periods exist.
create or replace function ${fn("setup_accounting")}(tenant ${idType}, functional_currency text default null, fiscal_year_start_month integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${settings}%rowtype;
  v_currency text := upper(coalesce(nullif(trim(setup_accounting.functional_currency), ''), ${sqlString(config.functionalCurrency)}));
  v_month integer := coalesce(setup_accounting.fiscal_year_start_month, ${String(config.fiscalYearStartMonth)});
begin
  if not ${allowed("setup_accounting.tenant", sql.manage)} then
    ${sql.forbidden("ACCOUNTING_SETTING", "not allowed to manage accounting")}
  end if;
  if v_currency !~ '^[A-Z]{3}$' then
    ${sql.invalid("ACCOUNTING_SETTING", "the functional currency must be an ISO 4217 code such as EUR")}
  end if;
  if v_month < 1 or v_month > 12 then
    ${sql.invalid("ACCOUNTING_SETTING", "the fiscal year starts in a month from 1 to 12")}
  end if;
  select * into v_row from ${settings} y where y.${s("tenant")} = setup_accounting.tenant for update;
  if found then
    if setup_accounting.functional_currency is not null and v_row.${s("functionalCurrency")} <> v_currency
      and exists (select 1 from ${entries} y where y.${e("tenant")} = setup_accounting.tenant and y.${e("status")} <> 'draft') then
      ${sql.invalid("ACCOUNTING_SETTING", "the functional currency can't change once entries are posted")}
    end if;
    if setup_accounting.fiscal_year_start_month is not null and v_row.${s("fiscalYearStartMonth")} <> v_month
      and exists (select 1 from ${periods} y where y.${p("tenant")} = setup_accounting.tenant) then
      ${sql.invalid("ACCOUNTING_SETTING", "the fiscal year start can't change once periods exist")}
    end if;
    update ${settings} y set
      ${s("functionalCurrency")} = case when setup_accounting.functional_currency is null then y.${s("functionalCurrency")} else v_currency end,
      ${s("fiscalYearStartMonth")} = case when setup_accounting.fiscal_year_start_month is null then y.${s("fiscalYearStartMonth")} else v_month end,
      ${s("updatedAt")} = now()
    where y.${s("tenant")} = setup_accounting.tenant
    returning * into v_row;
  else
    insert into ${settings} (${s("tenant")}, ${s("functionalCurrency")}, ${s("fiscalYearStartMonth")})
    values (setup_accounting.tenant, v_currency, v_month)
    returning * into v_row;
  end if;
  -- Cost center and cost object are built in: every organization has both.
  insert into ${dimensions} (${d("tenant")}, ${d("key")}, ${d("name")})
  values (setup_accounting.tenant, 'cost_center', 'Cost center'), (setup_accounting.tenant, 'cost_object', 'Cost object')
  on conflict (${d("tenant")}, ${d("key")}) do nothing;${chart}
  return ${json.settings("v_row")};
end;
$$;
${userGrant(`${fn("setup_accounting")}(${idType}, text, integer)`)}

create or replace function ${fn("get_accounting_settings")}(tenant ${idType})
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${json.settings("x")} from ${settings} x where x.${s("tenant")} = get_accounting_settings.tenant
$$;
${userGrant(`${fn("get_accounting_settings")}(${idType})`)}

-- Nothing posts on or before the lock date; null unlocks.
create or replace function ${fn("set_accounting_lock_date")}(tenant ${idType}, lock_date date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_settings ${settings}%rowtype;
begin
  if not ${allowed("set_accounting_lock_date.tenant", sql.close)} then
    ${sql.forbidden("ACCOUNTING_SETTING", "not allowed to close accounting periods")}
  end if;
  ${requireSettings(ctx, "set_accounting_lock_date.tenant")}
  update ${settings} y set ${s("lockDate")} = set_accounting_lock_date.lock_date, ${s("updatedAt")} = now()
  where y.${s("tenant")} = set_accounting_lock_date.tenant
  returning * into v_settings;
  return ${json.settings("v_settings")};
end;
$$;
${userGrant(`${fn("set_accounting_lock_date")}(${idType}, date)`)}

-- Creates an account, or changes one (account_id, or the account with the code).
-- An account with posted lines keeps its type. The normal side defaults to
-- debit for assets and expenses and credit for the rest; the level follows
-- the parent; the default tax code is the code a line on the account takes
-- when it names none.
drop function if exists ${fn("save_accounting_account")}(${idType}, text, text, text, text, uuid, text, boolean, uuid);
create or replace function ${fn("save_accounting_account")}(tenant ${idType}, code text, name text, type text, subtype text default null, parent_id uuid default null, currency text default null, reconcilable boolean default false, account_id uuid default null, normal_side text default null, default_tax_code_id uuid default null, active boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${accounts}%rowtype;
  v_id uuid := save_accounting_account.account_id;
  v_currency text := upper(nullif(trim(save_accounting_account.currency), ''));
  v_side text;
begin
  if not ${allowed("save_accounting_account.tenant", sql.manage)} then
    ${sql.forbidden("ACCOUNTING_ACCOUNT", "not allowed to manage the chart of accounts")}
  end if;
  if nullif(trim(save_accounting_account.code), '') is null or nullif(trim(save_accounting_account.name), '') is null then
    ${sql.invalid("ACCOUNTING_ACCOUNT", "an account needs a code and a name")}
  end if;
  if save_accounting_account.type is null or save_accounting_account.type not in (${sqlList(ACCOUNT_TYPES)}) then
    ${sql.invalid("ACCOUNTING_ACCOUNT", "the account type is asset, liability, equity, income or expense")}
  end if;
  if save_accounting_account.subtype is not null and save_accounting_account.subtype not in (${sqlList(config.subtypes)}) then
    ${sql.invalid("ACCOUNTING_ACCOUNT", "the subtype isn't one of blocks.accounting.options.subtypes")}
  end if;
  if v_currency is not null and v_currency !~ '^[A-Z]{3}$' then
    ${sql.invalid("ACCOUNTING_ACCOUNT", "the currency must be an ISO 4217 code such as EUR")}
  end if;
  v_side := coalesce(save_accounting_account.normal_side, case when save_accounting_account.type in ('asset', 'expense') then 'debit' else 'credit' end);
  if v_side not in ('debit', 'credit') then
    ${sql.invalid("ACCOUNTING_ACCOUNT", "the normal side is debit or credit")}
  end if;
  if save_accounting_account.default_tax_code_id is not null and not exists (
    select 1 from ${taxes} y where y.${t("id")} = save_accounting_account.default_tax_code_id and y.${t("tenant")} = save_accounting_account.tenant
  ) then
    ${sql.notFound("ACCOUNTING_TAX_CODE", "tax code not found")}
  end if;
  if v_id is null then
    select y.${a("id")} into v_id from ${accounts} y
    where y.${a("tenant")} = save_accounting_account.tenant and y.${a("code")} = trim(save_accounting_account.code);
  end if;
  if save_accounting_account.parent_id is not null then
    if not exists (select 1 from ${accounts} y where y.${a("id")} = save_accounting_account.parent_id and y.${a("tenant")} = save_accounting_account.tenant) then
      ${notFound("ACCOUNTING_ACCOUNT", "parent account")}
    end if;
    if v_id is not null and exists (
      with recursive up (id) as (
        select save_accounting_account.parent_id
        union
        select y.${a("parent")} from ${accounts} y join up on y.${a("id")} = up.id where y.${a("parent")} is not null
      )
      select 1 from up where up.id = v_id
    ) then
      ${sql.invalid("ACCOUNTING_ACCOUNT", "an account can't be its own parent")}
    end if;
  end if;
  if v_id is null then
    insert into ${accounts} (${a("tenant")}, ${a("code")}, ${a("name")}, ${a("type")}, ${a("subtype")}, ${a("parent")}, ${a("currency")}, ${a("reconcilable")},
      ${a("normalSide")}, ${a("defaultTaxCode")}, ${a("active")})
    values (save_accounting_account.tenant, trim(save_accounting_account.code), trim(save_accounting_account.name), save_accounting_account.type,
      save_accounting_account.subtype, save_accounting_account.parent_id, v_currency, coalesce(save_accounting_account.reconcilable, false),
      v_side, save_accounting_account.default_tax_code_id, coalesce(save_accounting_account.active, true))
    returning * into v_row;
  else
    select * into v_row from ${accounts} y where y.${a("id")} = v_id and y.${a("tenant")} = save_accounting_account.tenant for update;
    if not found then
      ${notFound("ACCOUNTING_ACCOUNT", "account")}
    end if;
    if exists (
      select 1 from ${lines} y join ${entries} z on z.${e("id")} = y.${l("entry")}
      where y.${l("account")} = v_id and z.${e("status")} <> 'draft'
        and (v_row.${a("type")} <> save_accounting_account.type or (v_currency is not null and y.${l("currency")} <> v_currency))
    ) then
      ${fail("ACCOUNTING_ACCOUNT_IN_USE", "the account has posted lines, so its type and currency stay", "55000")}
    end if;
    update ${accounts} y set ${a("code")} = trim(save_accounting_account.code), ${a("name")} = trim(save_accounting_account.name),
      ${a("type")} = save_accounting_account.type, ${a("subtype")} = save_accounting_account.subtype, ${a("parent")} = save_accounting_account.parent_id,
      ${a("currency")} = v_currency, ${a("reconcilable")} = coalesce(save_accounting_account.reconcilable, false),
      ${a("normalSide")} = v_side, ${a("defaultTaxCode")} = save_accounting_account.default_tax_code_id,
      ${a("active")} = coalesce(save_accounting_account.active, true), ${a("updatedAt")} = now()
    where y.${a("id")} = v_id
    returning * into v_row;
  end if;
  return ${json.account("v_row")};
end;
$$;
${userGrant(`${fn("save_accounting_account")}(${idType}, text, text, text, text, uuid, text, boolean, uuid, text, uuid, boolean)`)}

-- Archives an account (nothing posts to it), or restores it. An account
-- mapped to a role, a journal or a tax code stays.
create or replace function ${fn("archive_accounting_account")}(account_id uuid, archived boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${accounts}%rowtype;
begin
  select * into v_row from ${accounts} y where y.${a("id")} = archive_accounting_account.account_id for update;
  if not found then
    ${notFound("ACCOUNTING_ACCOUNT", "account")}
  end if;
  if not ${allowed(`v_row.${a("tenant")}`, sql.manage)} then
    ${sql.forbidden("ACCOUNTING_ACCOUNT", "not allowed to manage the chart of accounts")}
  end if;
  if coalesce(archive_accounting_account.archived, true) and (
    exists (select 1 from ${roles} y where y.${r("account")} = v_row.${a("id")})
    or exists (select 1 from ${journals} y where y.${j("defaultAccount")} = v_row.${a("id")})
    or exists (select 1 from ${taxes} y where (y.${t("salesAccount")} = v_row.${a("id")} or y.${t("purchaseAccount")} = v_row.${a("id")}) and y.${t("archivedAt")} is null)
  ) then
    ${fail("ACCOUNTING_ACCOUNT_IN_USE", "the account is mapped to a role, a journal or a tax code", "55000")}
  end if;
  update ${accounts} y set ${a("archivedAt")} = case when coalesce(archive_accounting_account.archived, true) then coalesce(y.${a("archivedAt")}, now()) end,
    ${a("updatedAt")} = now()
  where y.${a("id")} = v_row.${a("id")}
  returning * into v_row;
  return ${json.account("v_row")};
end;
$$;
${userGrant(`${fn("archive_accounting_account")}(uuid, boolean)`)}

-- Maps a role (receivable, bank, retained_earnings) to an account; null unmaps it.
create or replace function ${fn("set_accounting_account_role")}(tenant ${idType}, role text, account_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not ${allowed("set_accounting_account_role.tenant", sql.manage)} then
    ${sql.forbidden("ACCOUNTING_ACCOUNT", "not allowed to manage the chart of accounts")}
  end if;
  if set_accounting_account_role.role is null or set_accounting_account_role.role not in (${sqlList(ACCOUNT_ROLES)}) then
    ${fail("ACCOUNTING_ACCOUNT_ROLE_INVALID", "unknown account role", "22023")}
  end if;
  if set_accounting_account_role.account_id is null then
    delete from ${roles} y where y.${r("tenant")} = set_accounting_account_role.tenant and y.${r("role")} = set_accounting_account_role.role;
  else
    if not exists (
      select 1 from ${accounts} y where y.${a("id")} = set_accounting_account_role.account_id
        and y.${a("tenant")} = set_accounting_account_role.tenant and y.${a("archivedAt")} is null
    ) then
      ${notFound("ACCOUNTING_ACCOUNT", "account")}
    end if;
    insert into ${roles} (${r("tenant")}, ${r("role")}, ${r("account")})
    values (set_accounting_account_role.tenant, set_accounting_account_role.role, set_accounting_account_role.account_id)
    on conflict (${r("tenant")}, ${r("role")}) do update set ${r("account")} = excluded.${r("account")}, ${r("updatedAt")} = now();
  end if;
  return coalesce((
    select jsonb_object_agg(y.${r("role")}, y.${r("account")}) from ${roles} y where y.${r("tenant")} = set_accounting_account_role.tenant
  ), '{}'::jsonb);
end;
$$;
${userGrant(`${fn("set_accounting_account_role")}(${idType}, text, uuid)`)}

create or replace function ${fn("list_accounting_accounts")}(tenant ${idType}, include_archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${json.account("x")} order by x.${a("code")}), '[]'::jsonb)
  from ${accounts} x
  where x.${a("tenant")} = list_accounting_accounts.tenant
    and (coalesce(list_accounting_accounts.include_archived, false) or x.${a("archivedAt")} is null)
$$;
${userGrant(`${fn("list_accounting_accounts")}(${idType}, boolean)`)}

-- Creates a journal, or changes one (journal_id, or the journal with the code).
drop function if exists ${fn("save_accounting_journal")}(${idType}, text, text, text, uuid, text, uuid);
create or replace function ${fn("save_accounting_journal")}(tenant ${idType}, code text, name text, type text, default_account_id uuid default null, currency text default null, journal_id uuid default null, contra_account_id uuid default null, bank_account_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${journals}%rowtype;
  v_id uuid := save_accounting_journal.journal_id;
  v_code text := upper(trim(save_accounting_journal.code));
  v_currency text := upper(nullif(trim(save_accounting_journal.currency), ''));
begin
  if not ${allowed("save_accounting_journal.tenant", sql.manage)} then
    ${sql.forbidden("ACCOUNTING_JOURNAL", "not allowed to manage journals")}
  end if;
  if v_code is null or v_code !~ '^[A-Z0-9][A-Z0-9_-]{0,15}$' or nullif(trim(save_accounting_journal.name), '') is null then
    ${sql.invalid("ACCOUNTING_JOURNAL", "a journal needs a short code (letters, digits, - and _) and a name")}
  end if;
  if save_accounting_journal.type is null or save_accounting_journal.type not in (${sqlList(JOURNAL_TYPES)}) then
    ${sql.invalid("ACCOUNTING_JOURNAL", "the journal type is sales, purchase, bank, cash or general")}
  end if;
  if v_currency is not null and v_currency !~ '^[A-Z]{3}$' then
    ${sql.invalid("ACCOUNTING_JOURNAL", "the currency must be an ISO 4217 code such as EUR")}
  end if;
  if save_accounting_journal.default_account_id is not null and not exists (
    select 1 from ${accounts} y where y.${a("id")} = save_accounting_journal.default_account_id
      and y.${a("tenant")} = save_accounting_journal.tenant and y.${a("archivedAt")} is null
  ) then
    ${notFound("ACCOUNTING_ACCOUNT", "account")}
  end if;
  if save_accounting_journal.contra_account_id is not null and not exists (
    select 1 from ${accounts} y where y.${a("id")} = save_accounting_journal.contra_account_id
      and y.${a("tenant")} = save_accounting_journal.tenant and y.${a("archivedAt")} is null
  ) then
    ${sql.notFound("ACCOUNTING_ACCOUNT", "contra account not found")}
  end if;
  if v_id is null then
    select y.${j("id")} into v_id from ${journals} y where y.${j("tenant")} = save_accounting_journal.tenant and y.${j("code")} = v_code;
  end if;
  if v_id is null then
    insert into ${journals} (${j("tenant")}, ${j("code")}, ${j("name")}, ${j("type")}, ${j("defaultAccount")}, ${j("currency")}, ${j("contraAccount")}, ${j("bankAccount")})
    values (save_accounting_journal.tenant, v_code, trim(save_accounting_journal.name), save_accounting_journal.type, save_accounting_journal.default_account_id, v_currency,
      save_accounting_journal.contra_account_id, save_accounting_journal.bank_account_id)
    returning * into v_row;
  else
    update ${journals} y set ${j("code")} = v_code, ${j("name")} = trim(save_accounting_journal.name), ${j("type")} = save_accounting_journal.type,
      ${j("defaultAccount")} = save_accounting_journal.default_account_id, ${j("currency")} = v_currency,
      ${j("contraAccount")} = save_accounting_journal.contra_account_id, ${j("bankAccount")} = save_accounting_journal.bank_account_id, ${j("updatedAt")} = now()
    where y.${j("id")} = v_id and y.${j("tenant")} = save_accounting_journal.tenant
    returning * into v_row;
    if not found then
      ${notFound("ACCOUNTING_JOURNAL", "journal")}
    end if;
  end if;
  return ${json.journal("v_row")};
end;
$$;
${userGrant(`${fn("save_accounting_journal")}(${idType}, text, text, text, uuid, text, uuid, uuid, uuid)`)}

create or replace function ${fn("list_accounting_journals")}(tenant ${idType})
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${json.journal("x")} order by x.${j("code")}), '[]'::jsonb)
  from ${journals} x
  where x.${j("tenant")} = list_accounting_journals.tenant
$$;
${userGrant(`${fn("list_accounting_journals")}(${idType})`)}

-- Creates the twelve monthly periods of a fiscal year, from the start month of
-- the calendar year fiscal_year. Periods that exist stay as they are.
create or replace function ${fn("open_fiscal_year")}(tenant ${idType}, fiscal_year integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_settings ${settings}%rowtype;
  v_start date;
begin
  if not ${allowed("open_fiscal_year.tenant", sql.manage)} then
    ${sql.forbidden("ACCOUNTING_PERIOD", "not allowed to manage accounting periods")}
  end if;
  if open_fiscal_year.fiscal_year is null or open_fiscal_year.fiscal_year < 1900 or open_fiscal_year.fiscal_year > 9998 then
    ${sql.invalid("ACCOUNTING_PERIOD", "the fiscal year is a calendar year such as 2026")}
  end if;
  ${requireSettings(ctx, "open_fiscal_year.tenant")}
  v_start := make_date(open_fiscal_year.fiscal_year, v_settings.${s("fiscalYearStartMonth")}, 1);
  insert into ${periods} (${p("tenant")}, ${p("fiscalYear")}, ${p("number")}, ${p("startsOn")}, ${p("endsOn")})
  select open_fiscal_year.tenant, open_fiscal_year.fiscal_year, n,
    (v_start + make_interval(months => n - 1))::date,
    (v_start + make_interval(months => n) - interval '1 day')::date
  from generate_series(1, 12) n
  on conflict (${p("tenant")}, ${p("fiscalYear")}, ${p("number")}) do nothing;
  return coalesce((
    select jsonb_agg(${json.period("y")} order by y.${p("number")}) from ${periods} y
    where y.${p("tenant")} = open_fiscal_year.tenant and y.${p("fiscalYear")} = open_fiscal_year.fiscal_year
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("open_fiscal_year")}(${idType}, integer)`)}

create or replace function ${fn("list_accounting_periods")}(tenant ${idType}, fiscal_year integer default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${json.period("x")} order by x.${p("startsOn")}), '[]'::jsonb)
  from ${periods} x
  where x.${p("tenant")} = list_accounting_periods.tenant
    and (list_accounting_periods.fiscal_year is null or x.${p("fiscalYear")} = list_accounting_periods.fiscal_year)
$$;
${userGrant(`${fn("list_accounting_periods")}(${idType}, integer)`)}

-- Creates or renames a dimension (project, department, cost center) by key.
create or replace function ${fn("save_accounting_dimension")}(tenant ${idType}, key text, name text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${dimensions}%rowtype;
begin
  if not ${allowed("save_accounting_dimension.tenant", sql.manage)} then
    ${sql.forbidden("ACCOUNTING_DIMENSION", "not allowed to manage dimensions")}
  end if;
  if coalesce(save_accounting_dimension.key, '') !~ '^[a-z][a-z0-9_]{0,62}$' or nullif(trim(save_accounting_dimension.name), '') is null then
    ${sql.invalid("ACCOUNTING_DIMENSION", "a dimension needs a lower-case key and a name")}
  end if;
  insert into ${dimensions} (${d("tenant")}, ${d("key")}, ${d("name")})
  values (save_accounting_dimension.tenant, save_accounting_dimension.key, trim(save_accounting_dimension.name))
  on conflict (${d("tenant")}, ${d("key")}) do update set ${d("name")} = excluded.${d("name")}
  returning * into v_row;
  return ${json.dimension("v_row")};
end;
$$;
${userGrant(`${fn("save_accounting_dimension")}(${idType}, text, text)`)}

-- Adds or renames a value of a dimension by code; archived values take no new lines.
create or replace function ${fn("save_accounting_dimension_value")}(dimension_id uuid, code text, name text, archived boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_dimension ${dimensions}%rowtype;
begin
  select * into v_dimension from ${dimensions} y where y.${d("id")} = save_accounting_dimension_value.dimension_id;
  if not found then
    ${notFound("ACCOUNTING_DIMENSION", "dimension")}
  end if;
  if not ${allowed(`v_dimension.${d("tenant")}`, sql.manage)} then
    ${sql.forbidden("ACCOUNTING_DIMENSION", "not allowed to manage dimensions")}
  end if;
  if nullif(trim(save_accounting_dimension_value.code), '') is null or nullif(trim(save_accounting_dimension_value.name), '') is null then
    ${sql.invalid("ACCOUNTING_DIMENSION", "a dimension value needs a code and a name")}
  end if;
  insert into ${values} as y (${v("tenant")}, ${v("dimension")}, ${v("code")}, ${v("name")}, ${v("archivedAt")})
  values (v_dimension.${d("tenant")}, v_dimension.${d("id")}, trim(save_accounting_dimension_value.code), trim(save_accounting_dimension_value.name),
    case when coalesce(save_accounting_dimension_value.archived, false) then now() end)
  on conflict (${v("dimension")}, ${v("code")}) do update
    set ${v("name")} = excluded.${v("name")}, ${v("archivedAt")} = case when excluded.${v("archivedAt")} is null then null else coalesce(y.${v("archivedAt")}, excluded.${v("archivedAt")}) end;
  return ${json.dimension("v_dimension")};
end;
$$;
${userGrant(`${fn("save_accounting_dimension_value")}(uuid, text, text, boolean)`)}

create or replace function ${fn("list_accounting_dimensions")}(tenant ${idType})
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${json.dimension("x")} order by x.${d("key")}), '[]'::jsonb)
  from ${dimensions} x
  where x.${d("tenant")} = list_accounting_dimensions.tenant
$$;
${userGrant(`${fn("list_accounting_dimensions")}(${idType})`)}

-- Records what one unit of base costs in quote on a date.
create or replace function ${fn("set_accounting_fx_rate")}(tenant ${idType}, base text, quote text, on_date date, rate numeric)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_base text := upper(trim(set_accounting_fx_rate.base));
  v_quote text := upper(trim(set_accounting_fx_rate.quote));
begin
  if not ${allowed("set_accounting_fx_rate.tenant", sql.manage)} then
    ${sql.forbidden("ACCOUNTING_FX_RATE", "not allowed to manage exchange rates")}
  end if;
  if coalesce(v_base, '') !~ '^[A-Z]{3}$' or coalesce(v_quote, '') !~ '^[A-Z]{3}$' or v_base = v_quote
    or set_accounting_fx_rate.on_date is null or coalesce(set_accounting_fx_rate.rate, 0) <= 0 then
    ${sql.invalid("ACCOUNTING_FX_RATE", "a rate needs two different ISO 4217 codes, a date and a positive rate")}
  end if;
  insert into ${rates} (${x("tenant")}, ${x("base")}, ${x("quote")}, ${x("onDate")}, ${x("rate")})
  values (set_accounting_fx_rate.tenant, v_base, v_quote, set_accounting_fx_rate.on_date, set_accounting_fx_rate.rate)
  on conflict (${x("tenant")}, ${x("base")}, ${x("quote")}, ${x("onDate")}) do update set ${x("rate")} = excluded.${x("rate")};
  return jsonb_build_object('organizationId', set_accounting_fx_rate.tenant, 'base', v_base, 'quote', v_quote,
    'onDate', set_accounting_fx_rate.on_date, 'rate', set_accounting_fx_rate.rate::text);
end;
$$;
${userGrant(`${fn("set_accounting_fx_rate")}(${idType}, text, text, date, numeric)`)}

-- The rate on the date or the latest before it, or the inverse of the
-- opposite pair's; ACCOUNTING_FX_RATE_MISSING when neither has one.
create or replace function ${fn("accounting_fx_rate")}(tenant ${idType}, base text, quote text, on_date date)
returns numeric
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_base text := upper(trim(accounting_fx_rate.base));
  v_quote text := upper(trim(accounting_fx_rate.quote));
  v_rate numeric;
begin
  if not ${allowed("accounting_fx_rate.tenant", sql.read)} then
    ${sql.forbidden("ACCOUNTING_FX_RATE", "not allowed to read accounting")}
  end if;
  if v_base = v_quote then
    return 1;
  end if;
  select y.${x("rate")} into v_rate from ${rates} y
  where y.${x("tenant")} = accounting_fx_rate.tenant and y.${x("base")} = v_base and y.${x("quote")} = v_quote and y.${x("onDate")} <= accounting_fx_rate.on_date
  order by y.${x("onDate")} desc limit 1;
  if v_rate is null then
    select 1 / y.${x("rate")} into v_rate from ${rates} y
    where y.${x("tenant")} = accounting_fx_rate.tenant and y.${x("base")} = v_quote and y.${x("quote")} = v_base and y.${x("onDate")} <= accounting_fx_rate.on_date
    order by y.${x("onDate")} desc limit 1;
  end if;
  if v_rate is null then
    ${fail("ACCOUNTING_FX_RATE_MISSING", "no exchange rate for the currency pair on or before the date", "P0002")}
  end if;
  return v_rate;
end;
$$;
${userGrant(`${fn("accounting_fx_rate")}(${idType}, text, text, date)`)}
`;
}
