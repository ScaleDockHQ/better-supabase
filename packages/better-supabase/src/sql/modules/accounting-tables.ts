import type { BlockSqlContext } from "../context.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { addExtraColumns, fail, SERVICE_CALLER } from "../shared.ts";
import {
  ACCOUNT_ROLES,
  ACCOUNT_TYPES,
  accountingSql,
  ENTRY_RESERVED,
  JOURNAL_TYPES,
  sqlList,
} from "./accounting-shared.ts";
import { appUniqueIndex, lockModuleTable } from "./over-app.ts";

/**
 * Lets the data-lifecycle purge of a tenant delete rows the immutability
 * triggers otherwise refuse.
 */
function purgeBypass(ctx: BlockSqlContext): string {
  if (!ctx.installed("data-lifecycle")) {
    return "";
  }

  const lifecycle = ctx.of("data-lifecycle");
  const d = (column: string): string => lifecycle.col("deletions", column);

  return `
  if tg_op = 'DELETE' and current_setting('better_supabase.purge_tenant', true) = to_jsonb(old) ->> tg_argv[0] then
    if ${SERVICE_CALLER} and exists (
      select 1 from ${lifecycle.table("deletions")} x
      where x.${d("tenant")}::text = to_jsonb(old) ->> tg_argv[0]
        and x.${d("cancelledAt")} is null and x.${d("purgedAt")} is null and x.${d("purgeAfter")} <= now()
    ) then
      return old;
    end if;
  end if;`;
}

/** The accounting tables, their indexes, policies and immutability triggers. */
export function accountingTables(ctx: BlockSqlContext): string {
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
  const openings = ctx.table("openingBalances");
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
  const o = (column: string): string => ctx.col("openingBalances", column);
  const t = (column: string): string => tax.col("codes", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const { read } = accountingSql(ctx);
  const extras = ctx.extraColumns("entries", ENTRY_RESERVED);

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
    using: ctx.scope.check(tenant, read),
  }),
  { drop: true, target: ctx.table(logical) },
)}`;

  const currency = (column: string): string =>
    `check (${column} ~ '^[A-Z]{3}$')`;

  return `
create table if not exists ${settings} (
  ${s("tenant")} ${idType} primary key,
  -- Every debit and credit is in minor units of this currency.
  ${s("functionalCurrency")} text not null ${currency(s("functionalCurrency"))},
  ${s("fiscalYearStartMonth")} smallint not null default 1 check (${s("fiscalYearStartMonth")} >= 1 and ${s("fiscalYearStartMonth")} <= 12),
  -- Nothing posts on or before this date, whatever the period's status.
  ${s("lockDate")} date,
  ${s("createdAt")} timestamptz not null default now(),
  ${s("updatedAt")} timestamptz not null default now()
);${appUniqueIndex(ctx, "settings", ["tenant"])}
${readPolicy("settings", s("tenant"))}

create table if not exists ${accounts} (
  ${a("id")} uuid primary key default gen_random_uuid(),
  ${a("tenant")} ${idType} not null,
  ${a("code")} text not null check (length(${a("code")}) >= 1 and length(${a("code")}) <= 50),
  ${a("name")} text not null check (length(${a("name")}) >= 1 and length(${a("name")}) <= 200),
  ${a("type")} text not null check (${a("type")} in (${sqlList(ACCOUNT_TYPES)})),
  ${a("subtype")} text,
  ${a("parent")} uuid references ${accounts} (${a("id")}) on delete restrict,
  -- Lines on the account must be in this currency; null takes any.
  ${a("currency")} text ${currency(a("currency"))},
  ${a("reconcilable")} boolean not null default false,
  -- The side a positive balance sits on; reports show it next to the amount.
  ${a("normalSide")} text not null default 'debit' check (${a("normalSide")} in ('debit', 'credit')),
  -- 1 for a top-level account, one more than the parent's for the rest.
  ${a("level")} smallint not null default 1 check (${a("level")} >= 1),
  -- The tax code a line on this account takes when it names none.
  ${a("defaultTaxCode")} uuid references ${taxes} (${t("id")}) on delete set null,
  -- An inactive account stays on the chart and in reports but takes no new lines.
  ${a("active")} boolean not null default true,
  ${a("archivedAt")} timestamptz,
  ${a("createdAt")} timestamptz not null default now(),
  ${a("updatedAt")} timestamptz not null default now(),
  unique (${a("tenant")}, ${a("code")})
);${appUniqueIndex(ctx, "accounts", ["tenant", "code"])}
create index if not exists ${name("accounts", "parent_idx")} on ${accounts} (${a("parent")}) where ${a("parent")} is not null;
create index if not exists ${name("accounts", "tax_idx")} on ${accounts} (${a("defaultTaxCode")}) where ${a("defaultTaxCode")} is not null;
${readPolicy("accounts", a("tenant"))}

create table if not exists ${roles} (
  ${r("tenant")} ${idType} not null,
  ${r("role")} text not null check (${r("role")} in (${sqlList(ACCOUNT_ROLES)})),
  ${r("account")} uuid not null references ${accounts} (${a("id")}) on delete restrict,
  ${r("updatedAt")} timestamptz not null default now(),
  primary key (${r("tenant")}, ${r("role")})
);${appUniqueIndex(ctx, "roles", ["tenant", "role"])}
create index if not exists ${name("roles", "account_idx")} on ${roles} (${r("account")});
${readPolicy("roles", r("tenant"))}

create table if not exists ${journals} (
  ${j("id")} uuid primary key default gen_random_uuid(),
  ${j("tenant")} ${idType} not null,
  ${j("code")} text not null check (${j("code")} ~ '^[A-Z0-9][A-Z0-9_-]{0,15}$'),
  ${j("name")} text not null check (length(${j("name")}) >= 1 and length(${j("name")}) <= 200),
  ${j("type")} text not null check (${j("type")} in (${sqlList(JOURNAL_TYPES)})),
  -- The bank or cash account a bank or cash journal posts against.
  ${j("defaultAccount")} uuid references ${accounts} (${a("id")}) on delete restrict,
  ${j("currency")} text ${currency(j("currency"))},
  -- The counter account a bank or cash journal's lines offset by default.
  ${j("contraAccount")} uuid references ${accounts} (${a("id")}) on delete restrict,
  -- The bank account (banking block) the journal books; its statements post here.
  ${j("bankAccount")} uuid,
  ${j("createdAt")} timestamptz not null default now(),
  ${j("updatedAt")} timestamptz not null default now(),
  unique (${j("tenant")}, ${j("code")})
);${appUniqueIndex(ctx, "journals", ["tenant", "code"])}
create index if not exists ${name("journals", "account_idx")} on ${journals} (${j("defaultAccount")}) where ${j("defaultAccount")} is not null;
create index if not exists ${name("journals", "contra_idx")} on ${journals} (${j("contraAccount")}) where ${j("contraAccount")} is not null;
${readPolicy("journals", j("tenant"))}

create table if not exists ${periods} (
  ${p("id")} uuid primary key default gen_random_uuid(),
  ${p("tenant")} ${idType} not null,
  -- The calendar year the fiscal year starts in.
  ${p("fiscalYear")} integer not null check (${p("fiscalYear")} >= 1900 and ${p("fiscalYear")} <= 9999),
  ${p("number")} smallint not null check (${p("number")} >= 1 and ${p("number")} <= 12),
  ${p("startsOn")} date not null,
  ${p("endsOn")} date not null,
  ${p("status")} text not null default 'open' check (${p("status")} in ('open', 'closed', 'locked')),
  ${p("closedAt")} timestamptz,
  ${p("closedBy")} uuid,
  -- A locked period takes no posting at all, not even an import.
  ${p("lockedAt")} timestamptz,
  ${p("lockedBy")} uuid,
  ${p("createdAt")} timestamptz not null default now(),
  check (${p("endsOn")} >= ${p("startsOn")}),
  unique (${p("tenant")}, ${p("fiscalYear")}, ${p("number")})
);${appUniqueIndex(ctx, "periods", ["tenant", "fiscalYear", "number"])}
create index if not exists ${name("periods", "dates_idx")} on ${periods} (${p("tenant")}, ${p("startsOn")}, ${p("endsOn")});
${readPolicy("periods", p("tenant"))}

create table if not exists ${entries} (
  ${e("id")} uuid primary key default gen_random_uuid(),
  ${e("tenant")} ${idType} not null,
  ${e("journal")} uuid not null references ${journals} (${j("id")}) on delete restrict,
  ${e("fiscalYear")} integer,
  -- The entry's place in its journal and fiscal year, set when it posts.
  ${e("sequence")} integer,
  ${e("number")} text,
  ${e("entryDate")} date not null,
  ${e("period")} uuid references ${periods} (${p("id")}) on delete restrict,
  ${e("status")} text not null default 'draft' check (${e("status")} in ('draft', 'posted', 'reversed')),
  ${e("reference")} text check (${e("reference")} is null or length(${e("reference")}) <= 200),
  -- The document the entry books, such as invoice and its id.
  ${e("sourceType")} text check (${e("sourceType")} is null or ${e("sourceType")} ~ '^[a-z][a-z0-9_]{0,62}$'),
  ${e("sourceId")} text,
  ${e("reverses")} uuid references ${entries} (${e("id")}) on delete restrict,
  ${e("memo")} text check (${e("memo")} is null or length(${e("memo")}) <= 2000),
  ${e("postedAt")} timestamptz,
  ${e("postedBy")} uuid,
  ${e("createdBy")} uuid,
  ${e("createdAt")} timestamptz not null default now(),
  ${e("updatedAt")} timestamptz not null default now(),
  check ((${e("sourceType")} is null) = (${e("sourceId")} is null)),
  check (${e("status")} = 'draft' or (${e("number")} is not null and ${e("period")} is not null and ${e("postedAt")} is not null))
);${addExtraColumns(entries, extras)}
create unique index if not exists ${name("entries", "number_idx")} on ${entries} (${e("journal")}, ${e("fiscalYear")}, ${e("sequence")}) where ${e("sequence")} is not null;
-- A document books once: a second entry for it waits until the first is reversed.
create unique index if not exists ${name("entries", "source_idx")} on ${entries} (${e("tenant")}, ${e("sourceType")}, ${e("sourceId")}) where ${e("sourceType")} is not null and ${e("status")} <> 'reversed';
create unique index if not exists ${name("entries", "reverses_idx")} on ${entries} (${e("reverses")}) where ${e("reverses")} is not null;
create index if not exists ${name("entries", "date_idx")} on ${entries} (${e("tenant")}, ${e("entryDate")} desc);
create index if not exists ${name("entries", "period_idx")} on ${entries} (${e("period")}, ${e("status")});
${readPolicy("entries", e("tenant"))}

create table if not exists ${dimensions} (
  ${d("id")} uuid primary key default gen_random_uuid(),
  ${d("tenant")} ${idType} not null,
  -- The key lines use in their dimensions object, such as project or department.
  ${d("key")} text not null check (${d("key")} ~ '^[a-z][a-z0-9_]{0,62}$'),
  ${d("name")} text not null check (length(${d("name")}) >= 1 and length(${d("name")}) <= 200),
  ${d("createdAt")} timestamptz not null default now(),
  unique (${d("tenant")}, ${d("key")})
);${appUniqueIndex(ctx, "dimensions", ["tenant", "key"])}
${readPolicy("dimensions", d("tenant"))}

create table if not exists ${values} (
  ${v("id")} uuid primary key default gen_random_uuid(),
  ${v("tenant")} ${idType} not null,
  ${v("dimension")} uuid not null references ${dimensions} (${d("id")}) on delete cascade,
  ${v("code")} text not null check (length(${v("code")}) >= 1 and length(${v("code")}) <= 100),
  ${v("name")} text not null check (length(${v("name")}) >= 1 and length(${v("name")}) <= 200),
  ${v("archivedAt")} timestamptz,
  unique (${v("dimension")}, ${v("code")})
);${appUniqueIndex(ctx, "dimensionValues", ["dimension", "code"])}
${readPolicy("dimensionValues", v("tenant"))}

create table if not exists ${rates} (
  ${x("tenant")} ${idType} not null,
  ${x("base")} text not null ${currency(x("base"))},
  ${x("quote")} text not null ${currency(x("quote"))},
  ${x("onDate")} date not null,
  -- One unit of base costs rate units of quote.
  ${x("rate")} numeric not null check (${x("rate")} > 0),
  ${x("createdAt")} timestamptz not null default now(),
  primary key (${x("tenant")}, ${x("base")}, ${x("quote")}, ${x("onDate")}),
  check (${x("base")} <> ${x("quote")})
);${appUniqueIndex(ctx, "fxRates", ["tenant", "base", "quote", "onDate"])}
${readPolicy("fxRates", x("tenant"))}

create table if not exists ${lines} (
  ${l("id")} uuid primary key default gen_random_uuid(),
  ${l("tenant")} ${idType} not null,
  ${l("entry")} uuid not null references ${entries} (${e("id")}) on delete cascade,
  ${l("position")} smallint not null default 0,
  ${l("account")} uuid not null references ${accounts} (${a("id")}) on delete restrict,
  -- Minor units of the functional currency; a line has one side.
  ${l("debit")} bigint not null default 0 check (${l("debit")} >= 0),
  ${l("credit")} bigint not null default 0 check (${l("credit")} >= 0),
  -- The transaction currency and its signed amount (positive is a debit).
  ${l("currency")} text not null ${currency(l("currency"))},
  ${l("amountCurrency")} bigint not null,
  ${l("fxRate")} numeric check (${l("fxRate")} is null or ${l("fxRate")} > 0),
  ${l("taxCode")} uuid references ${taxes} (${t("id")}) on delete restrict,
  -- The part of the line that is tax, in minor units of the functional currency.
  ${l("taxAmount")} bigint not null default 0 check (${l("taxAmount")} >= 0),
  -- The customer, supplier or employee the line concerns.
  ${l("party")} uuid,
  ${l("dimensions")} jsonb not null default '{}'::jsonb check (jsonb_typeof(${l("dimensions")}) = 'object'),
  ${l("description")} text check (${l("description")} is null or length(${l("description")}) <= 500),
  check ((${l("debit")} = 0) <> (${l("credit")} = 0)),
  check (${l("taxAmount")} <= ${l("debit")} + ${l("credit")})
);
create index if not exists ${name("lines", "entry_idx")} on ${lines} (${l("entry")}, ${l("position")});
create index if not exists ${name("lines", "account_idx")} on ${lines} (${l("account")});
create index if not exists ${name("lines", "party_idx")} on ${lines} (${l("tenant")}, ${l("party")}) where ${l("party")} is not null;
create index if not exists ${name("lines", "tax_idx")} on ${lines} (${l("taxCode")}) where ${l("taxCode")} is not null;
${readPolicy("lines", l("tenant"))}

create table if not exists ${openings} (
  ${o("id")} uuid primary key default gen_random_uuid(),
  ${o("tenant")} ${idType} not null,
  ${o("fiscalYear")} integer not null check (${o("fiscalYear")} >= 1900 and ${o("fiscalYear")} <= 9999),
  ${o("account")} uuid not null references ${accounts} (${a("id")}) on delete restrict,
  ${o("party")} uuid,
  -- Signed minor units of the functional currency; a debit balance is positive.
  ${o("amount")} bigint not null check (${o("amount")} <> 0),
  -- imported rows come from the old books, carried rows from close_fiscal_year.
  ${o("source")} text not null default 'imported' check (${o("source")} in ('imported', 'carried')),
  ${o("createdAt")} timestamptz not null default now(),
  ${o("updatedAt")} timestamptz not null default now()
);
create unique index if not exists ${name("openingBalances", "key_idx")} on ${openings} (${o("tenant")}, ${o("fiscalYear")}, ${o("account")}, coalesce(${o("party")}, '00000000-0000-0000-0000-000000000000'::uuid));
create index if not exists ${name("openingBalances", "account_idx")} on ${openings} (${o("account")});
${readPolicy("openingBalances", o("tenant"))}

-- An account's level follows its parent's; moving an account moves its children.
create or replace function ${fn("accounting_account_level")}()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' or new.${a("parent")} is distinct from old.${a("parent")} then
    new.${a("level")} := coalesce((select y.${a("level")} from ${accounts} y where y.${a("id")} = new.${a("parent")}), 0) + 1;
  end if;
  return new;
end;
$$;
revoke execute on function ${fn("accounting_account_level")}() from public, anon, authenticated;
drop trigger if exists ${ctx.trigger("accounting_accounts_level")} on ${accounts};
create trigger ${ctx.trigger("accounting_accounts_level")} before insert or update of ${a("parent")} on ${accounts}
  for each row execute function ${fn("accounting_account_level")}();

create or replace function ${fn("accounting_account_level_children")}()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  with recursive down (id, level) as (
    select y.${a("id")}, new.${a("level")} + 1 from ${accounts} y where y.${a("parent")} = new.${a("id")}
    union all
    select y.${a("id")}, down.level + 1 from ${accounts} y join down on y.${a("parent")} = down.id
  )
  update ${accounts} y set ${a("level")} = down.level from down where y.${a("id")} = down.id and y.${a("level")} <> down.level;
  return null;
end;
$$;
revoke execute on function ${fn("accounting_account_level_children")}() from public, anon, authenticated;
drop trigger if exists ${ctx.trigger("accounting_accounts_level_children")} on ${accounts};
create trigger ${ctx.trigger("accounting_accounts_level_children")} after update of ${a("parent")} on ${accounts}
  for each row when (old.${a("parent")} is distinct from new.${a("parent")}) execute function ${fn("accounting_account_level_children")}();

-- A posted entry changes only from posted to reversed; its lines never change.
create or replace function ${fn("accounting_entry_guard")}()
returns trigger
language plpgsql
set search_path = ''
as $$
begin${purgeBypass(ctx)}
  if tg_op = 'UPDATE' and old.${e("status")} = 'draft' then
    return new;
  end if;
  if tg_op = 'DELETE' and old.${e("status")} = 'draft' then
    return old;
  end if;
  if tg_op = 'UPDATE' and old.${e("status")} = 'posted' and new.${e("status")} = 'reversed'
    and (to_jsonb(new) - ${sqlString(ctx.colName("entries", "status"))} - ${sqlString(ctx.colName("entries", "updatedAt"))})
      = (to_jsonb(old) - ${sqlString(ctx.colName("entries", "status"))} - ${sqlString(ctx.colName("entries", "updatedAt"))}) then
    return new;
  end if;
  ${fail("ACCOUNTING_ENTRY_POSTED", "a posted entry can't be changed or deleted; reverse it", "55000")}
end;
$$;
revoke execute on function ${fn("accounting_entry_guard")}() from public, anon, authenticated;
drop trigger if exists ${ctx.trigger("accounting_entries_guard")} on ${entries};
create trigger ${ctx.trigger("accounting_entries_guard")} before update or delete on ${entries}
  for each row execute function ${fn("accounting_entry_guard")}(${sqlString(ctx.colName("entries", "tenant"))});

create or replace function ${fn("accounting_entry_line_guard")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_entry uuid := case when tg_op = 'DELETE' then old.${l("entry")} else new.${l("entry")} end;
begin${purgeBypass(ctx)}
  if exists (select 1 from ${entries} y where y.${e("id")} = v_entry and y.${e("status")} <> 'draft')
    or (tg_op = 'UPDATE' and exists (select 1 from ${entries} y where y.${e("id")} = old.${l("entry")} and y.${e("status")} <> 'draft')) then
    ${fail("ACCOUNTING_ENTRY_POSTED", "the lines of a posted entry can't change; reverse it", "55000")}
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;
revoke execute on function ${fn("accounting_entry_line_guard")}() from public, anon, authenticated;
drop trigger if exists ${ctx.trigger("accounting_entry_lines_guard")} on ${lines};
create trigger ${ctx.trigger("accounting_entry_lines_guard")} before insert or update or delete on ${lines}
  for each row execute function ${fn("accounting_entry_line_guard")}(${sqlString(ctx.colName("lines", "tenant"))});
`;
}
