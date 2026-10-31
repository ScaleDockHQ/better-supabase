import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { uniqueContributions } from "../contributions.ts";
import { fail, userGrant } from "../shared.ts";
import { entryJson } from "./accounting-entries.ts";
import { accountingSql } from "./accounting-shared.ts";

/**
 * Whether `autoPost` posts the entries blocks book, or leaves them as drafts
 * for an accountant to post.
 */
function autoPost(ctx: BlockSqlContext): boolean {
  return ctx.option("autoPost") !== false;
}

/**
 * Books the documents of other blocks: `accounting_post_source` turns what a
 * block's lines function returns into an entry, once per document, and
 * `accounting_reverse_source` undoes it.
 */
export function accountingPostingFunctions(ctx: BlockSqlContext): string {
  const settings = ctx.table("settings");
  const accounts = ctx.table("accounts");
  const roles = ctx.table("roles");
  const journals = ctx.table("journals");
  const periods = ctx.table("periods");
  const entries = ctx.table("entries");
  const lines = ctx.table("lines");
  const tx = ctx.of("tax");
  const taxes = tx.table("codes");
  const dimensions = ctx.table("dimensions");
  const values = ctx.table("dimensionValues");
  const s = (column: string): string => ctx.col("settings", column);
  const d = (column: string): string => ctx.col("dimensions", column);
  const v = (column: string): string => ctx.col("dimensionValues", column);
  const a = (column: string): string => ctx.col("accounts", column);
  const r = (column: string): string => ctx.col("roles", column);
  const j = (column: string): string => ctx.col("journals", column);
  const p = (column: string): string => ctx.col("periods", column);
  const e = (column: string): string => ctx.col("entries", column);
  const l = (column: string): string => ctx.col("lines", column);
  const t = (column: string): string => tx.col("codes", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const sql = accountingSql(ctx);

  const sources = uniqueContributions(
    "accounting",
    ctx.contributions("accounting"),
    (source) => source.source,
  );

  const known = sources.map((source) => sqlString(source.source)).join(", ");

  const dispatch =
    sources.length === 0
      ? ""
      : `v_doc := case accounting_post_source.source_type
${sources.map((source) => `    when ${sqlString(source.source)} then ${source.lines}(accounting_post_source.source_id)`).join("\n")}
  end;
  v_kind := case accounting_post_source.source_type
${sources.map((source) => `    when ${sqlString(source.source)} then ${sqlString(source.journal)}`).join("\n")}
  end;`;

  const unknown = fail(
    "ACCOUNTING_SOURCE_INVALID",
    "no installed block books this source type",
    "22023",
  );

  const account = (where: string): string =>
    `select y.${a("id")} into v_account from ${accounts} y where ${where} and y.${a("tenant")} = v_tenant and y.${a("archivedAt")} is null`;

  const role = (expression: string): string =>
    `select y.${a("id")} into v_account from ${roles} z join ${accounts} y on y.${a("id")} = z.${r("account")}
      where z.${r("tenant")} = v_tenant and z.${r("role")} = ${expression} and y.${a("archivedAt")} is null`;

  return `
-- Books a block's document once: the block's lines function describes the
-- entry in the document's currency with account roles, and this resolves the
-- roles, tax codes and exchange rates, then saves the entry in the source's
-- journal type and posts it (autoPost) when its date falls in an open period
-- after the lock date. A document books once until its entry is reversed, so
-- calling it again returns the same entry. Returns null when the organization
-- hasn't set up accounting or the document has nothing to book.
create or replace function ${fn("accounting_post_source")}(source_type text, source_id text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_doc jsonb;
  v_kind text;
  v_tenant ${idType};
  v_settings ${settings}%rowtype;
  v_journal ${journals}%rowtype;
  v_period ${periods}%rowtype;
  v_row ${entries}%rowtype;
  v_date date;
  v_line record;
  v_amount bigint;
  v_functional bigint;
  v_rate numeric;
  v_currency text;
  v_account uuid;
  v_tax ${taxes}%rowtype;
  v_diff bigint;
  v_largest integer;
  v_accounts uuid[] := '{}';
  v_functionals bigint[] := '{}';
  v_amounts bigint[] := '{}';
  v_currencies text[] := '{}';
  v_rates numeric[] := '{}';
  v_taxes uuid[] := '{}';
  v_parties uuid[] := '{}';
  v_dimensions jsonb[] := '{}';
  v_descriptions text[] := '{}';
begin
  if accounting_post_source.source_type is null or accounting_post_source.source_id is null
    or ${known === "" ? "true" : `accounting_post_source.source_type not in (${known})`} then
    ${unknown}
  end if;
  ${dispatch}
  if v_doc is null or jsonb_typeof(v_doc -> 'lines') is distinct from 'array' then
    return null;
  end if;
  v_tenant := (v_doc ->> 'organizationId')::${idType};
  select * into v_settings from ${settings} y where y.${s("tenant")} = v_tenant;
  if not found then
    return null;
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'accounting-source:' || v_tenant::text || ':' || accounting_post_source.source_type || ':' || accounting_post_source.source_id, 0));
  select * into v_row from ${entries} y
  where y.${e("tenant")} = v_tenant and y.${e("sourceType")} = accounting_post_source.source_type
    and y.${e("sourceId")} = accounting_post_source.source_id and y.${e("status")} <> 'reversed';
  if found then
    return v_row.${e("id")};
  end if;
  v_date := coalesce((v_doc ->> 'entryDate')::date, current_date);
  v_kind := coalesce(v_doc ->> 'journal', v_kind);
  if coalesce(v_doc ->> 'journalId', '') ~ '^[0-9a-fA-F-]{36}$' then
    select * into v_journal from ${journals} y
    where y.${j("tenant")} = v_tenant and y.${j("id")} = (v_doc ->> 'journalId')::uuid;
  end if;
  if v_journal.${j("id")} is null then
    select * into v_journal from ${journals} y
    where y.${j("tenant")} = v_tenant and y.${j("type")} = v_kind order by y.${j("code")} limit 1;
  end if;
  if v_journal.${j("id")} is null then
    ${fail("ACCOUNTING_JOURNAL_NOT_FOUND", "the organization has no journal of the type this document books in", "P0002")}
  end if;
  for v_line in select q.value from jsonb_array_elements(v_doc -> 'lines') q loop
    v_amount := coalesce((v_line.value ->> 'debit')::bigint, 0) - coalesce((v_line.value ->> 'credit')::bigint, 0);
    continue when v_amount = 0;
    v_tax := null;
    if v_line.value ->> 'taxCode' is not null then
      select * into v_tax from ${taxes} y
      where y.${t("tenant")} = v_tenant and y.${t("code")} = v_line.value ->> 'taxCode' and y.${t("archivedAt")} is null
      order by y.${t("legalEntity")} nulls first limit 1;
    end if;
    if v_tax.${t("id")} is null and coalesce(v_line.value ->> 'taxRateBps', '') ~ '^[0-9]{1,6}$' then
      select * into v_tax from ${taxes} y
      where y.${t("tenant")} = v_tenant and ${fn("tax_rate_on")}(y.${t("id")}, v_date) = (v_line.value ->> 'taxRateBps')::integer
        and y.${t("type")} = case when v_journal.${j("type")} = 'purchase' then 'purchase' else 'sales' end
        and y.${t("archivedAt")} is null
      order by y.${t("legalEntity")} nulls first, y.${t("code")} limit 1;
    end if;
    v_account := null;
    if v_line.value ->> 'role' in ('tax_payable', 'tax_receivable') and v_tax.${t("id")} is not null then
      v_account := case when v_tax.${t("type")} = 'purchase' then v_tax.${t("purchaseAccount")}
        else coalesce(v_tax.${t("salesAccount")}, v_tax.${t("purchaseAccount")}) end;
    elsif coalesce(v_line.value ->> 'accountId', '') ~ '^[0-9a-fA-F-]{36}$' then
      ${account(`y.${a("id")} = (v_line.value ->> 'accountId')::uuid`)};
    elsif v_line.value ->> 'accountCode' is not null then
      ${account(`y.${a("code")} = v_line.value ->> 'accountCode'`)};
    elsif v_line.value ->> 'role' is not null then
      ${role("v_line.value ->> 'role'")};
    end if;
    if v_account is null then
      ${role("'suspense'")};
    end if;
    if v_account is null then
      ${fail("ACCOUNTING_ROLE_UNMAPPED", "no account plays the role a document line needs, and no account plays suspense", "P0002")}
    end if;
    v_currency := upper(coalesce(v_line.value ->> 'currency', v_doc ->> 'currency', v_settings.${s("functionalCurrency")}));
    v_rate := null;
    v_functional := v_amount;
    if v_currency <> v_settings.${s("functionalCurrency")} then
      v_rate := ${fn("accounting_fx_rate")}(v_tenant, v_currency, v_settings.${s("functionalCurrency")}, v_date);
      v_functional := round(v_amount * v_rate)::bigint;
      continue when v_functional = 0;
    end if;
    v_accounts := v_accounts || v_account;
    v_functionals := v_functionals || v_functional;
    v_amounts := v_amounts || v_amount;
    v_currencies := v_currencies || v_currency;
    v_rates := v_rates || v_rate;
    v_taxes := v_taxes || v_tax.${t("id")};
    v_parties := v_parties || case when coalesce(v_line.value ->> 'partyId', '') ~ '^[0-9a-fA-F-]{36}$' then (v_line.value ->> 'partyId')::uuid end;
    v_dimensions := v_dimensions || case when jsonb_typeof(v_line.value -> 'dimensions') = 'object' then v_line.value -> 'dimensions' else '{}'::jsonb end;
    v_descriptions := v_descriptions || left(nullif(trim(v_line.value ->> 'description'), ''), 500);
  end loop;
  if coalesce(array_length(v_accounts, 1), 0) < 2 then
    return null;
  end if;
  -- Converting each line rounds on its own; the difference goes to the
  -- largest line on the side that is short.
  select coalesce(sum(u), 0) into v_diff from unnest(v_functionals) u;
  if v_diff <> 0 then
    select q.n into v_largest from unnest(v_functionals) with ordinality q(amount, n)
    where sign(q.amount) = -sign(v_diff) order by abs(q.amount) desc limit 1;
    if v_largest is null then
      ${fail("ACCOUNTING_ENTRY_UNBALANCED", "the document's lines don't balance", "23514")}
    end if;
    v_functionals[v_largest] := v_functionals[v_largest] - v_diff;
  end if;
  insert into ${entries} (${e("tenant")}, ${e("journal")}, ${e("entryDate")}, ${e("reference")}, ${e("sourceType")}, ${e("sourceId")}, ${e("memo")}, ${e("createdBy")}, ${e("period")})
  values (v_tenant, v_journal.${j("id")}, v_date, left(nullif(trim(v_doc ->> 'reference'), ''), 200),
    accounting_post_source.source_type, accounting_post_source.source_id, left(nullif(trim(v_doc ->> 'memo'), ''), 2000), auth.uid(),
    (select y.${p("id")} from ${periods} y where y.${p("tenant")} = v_tenant and v_date >= y.${p("startsOn")} and v_date <= y.${p("endsOn")}))
  returning * into v_row;
  insert into ${lines} (${l("tenant")}, ${l("entry")}, ${l("position")}, ${l("account")}, ${l("debit")}, ${l("credit")}, ${l("currency")},
    ${l("amountCurrency")}, ${l("fxRate")}, ${l("taxCode")}, ${l("party")}, ${l("dimensions")}, ${l("description")})
  select v_tenant, v_row.${e("id")}, u.n, u.account, greatest(u.functional, 0), greatest(-u.functional, 0), u.currency,
    case when u.rate is null then u.functional else u.amount end, u.rate, u.tax, u.party, u.dimensions, u.description
  from unnest(v_accounts, v_functionals, v_amounts, v_currencies, v_rates, v_taxes, v_parties, v_dimensions, v_descriptions)
    with ordinality u(account, functional, amount, currency, rate, tax, party, dimensions, description, n);
${
  autoPost(ctx)
    ? `  select * into v_period from ${periods} y where y.${p("id")} = v_row.${e("period")};
  if found and v_period.${p("status")} = 'open'
    and (v_settings.${s("lockDate")} is null or v_date > v_settings.${s("lockDate")}) then
    perform ${fn("accounting_post")}(v_row.${e("id")});
  end if;
`
    : ""
}  return v_row.${e("id")};
end;
$$;
revoke execute on function ${fn("accounting_post_source")}(text, text) from public, anon, authenticated;

-- Books a document a block didn't book when it happened, such as one from
-- before the organization set up accounting.
create or replace function ${fn("post_accounting_source")}(source_type text, source_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
  v_row ${entries}%rowtype;
begin
  v_id := ${fn("accounting_post_source")}(post_accounting_source.source_type, post_accounting_source.source_id);
  if v_id is null then
    return null;
  end if;
  select * into v_row from ${entries} y where y.${e("id")} = v_id;
  if not ${sql.allowed(`v_row.${e("tenant")}`, sql.post)} then
    ${sql.forbidden("ACCOUNTING_ENTRY", "not allowed to post accounting entries")}
  end if;
  return ${entryJson(ctx, "v_row", true)};
end;
$$;
${userGrant(`${fn("post_accounting_source")}(text, text)`)}

-- Undoes the entry of a document a block voided or reversed: deletes a draft,
-- or reverses a posted entry on entry_date (default today). Returns the
-- reversal, or null when there was nothing posted.
create or replace function ${fn("accounting_reverse_source")}(tenant ${idType}, source_type text, source_id text, entry_date date default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${entries}%rowtype;
begin
  select * into v_row from ${entries} y
  where y.${e("tenant")} = accounting_reverse_source.tenant and y.${e("sourceType")} = accounting_reverse_source.source_type
    and y.${e("sourceId")} = accounting_reverse_source.source_id and y.${e("status")} <> 'reversed'
  for update;
  if not found then
    return null;
  end if;
  if v_row.${e("status")} = 'draft' then
    delete from ${entries} y where y.${e("id")} = v_row.${e("id")};
    return null;
  end if;
  return (${fn("accounting_reverse")}(v_row.${e("id")}, coalesce(accounting_reverse_source.entry_date, current_date))).${e("id")};
end;
$$;
revoke execute on function ${fn("accounting_reverse_source")}(${idType}, text, text, date) from public, anon, authenticated;

-- Keeps a dimension value in step with another block's record, such as a
-- project, so its documents can carry it: creates the dimension when it is
-- missing, and sets the value's name and whether it is archived.
create or replace function ${fn("accounting_sync_dimension_value")}(tenant ${idType}, dimension_key text, dimension_name text, code text, value_name text, archived boolean default false)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_dimension uuid;
begin
  insert into ${dimensions} (${d("tenant")}, ${d("key")}, ${d("name")})
  values (accounting_sync_dimension_value.tenant, accounting_sync_dimension_value.dimension_key, accounting_sync_dimension_value.dimension_name)
  on conflict (${d("tenant")}, ${d("key")}) do nothing;
  select y.${d("id")} into v_dimension from ${dimensions} y
  where y.${d("tenant")} = accounting_sync_dimension_value.tenant and y.${d("key")} = accounting_sync_dimension_value.dimension_key;
  insert into ${values} as y (${v("tenant")}, ${v("dimension")}, ${v("code")}, ${v("name")}, ${v("archivedAt")})
  values (accounting_sync_dimension_value.tenant, v_dimension, accounting_sync_dimension_value.code, left(accounting_sync_dimension_value.value_name, 200),
    case when accounting_sync_dimension_value.archived then now() end)
  on conflict (${v("dimension")}, ${v("code")}) do update
    set ${v("name")} = excluded.${v("name")},
      ${v("archivedAt")} = case when accounting_sync_dimension_value.archived then coalesce(y.${v("archivedAt")}, now()) end;
end;
$$;
revoke execute on function ${fn("accounting_sync_dimension_value")}(${idType}, text, text, text, text, boolean) from public, anon, authenticated;
`;
}

/**
 * `accounting_tax_report`: per tax code and report box, the base and the tax of
 * posted entries, sales as credits and purchases as debits.
 */
export function accountingTaxReport(ctx: BlockSqlContext): string {
  const settings = ctx.table("settings");
  const entries = ctx.table("entries");
  const lines = ctx.table("lines");
  const tx = ctx.of("tax");
  const taxes = tx.table("codes");
  const s = (column: string): string => ctx.col("settings", column);
  const e = (column: string): string => ctx.col("entries", column);
  const l = (column: string): string => ctx.col("lines", column);
  const t = (column: string): string => tx.col("codes", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;

  return `
-- The tax return of a date range: a line with a tax code counts as tax when it
-- is on the code's account and as base otherwise. Sales count credits and
-- purchases debits, so a credit note lowers both.
create or replace function ${fn("accounting_tax_report")}(tenant ${idType}, since date, until date)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with booked as (
    select y.${l("taxCode")} as tax_code, y.${l("account")} as account, y.${l("credit")} - y.${l("debit")} as net
    from ${lines} y join ${entries} z on z.${e("id")} = y.${l("entry")}
    where z.${e("tenant")} = accounting_tax_report.tenant and z.${e("status")} in ('posted', 'reversed')
      and y.${l("taxCode")} is not null
      and z.${e("entryDate")} >= accounting_tax_report.since and z.${e("entryDate")} <= accounting_tax_report.until
  ),
  codes as (
    select w.${t("id")} as id, w.${t("code")} as code, w.${t("name")} as name,
      (case when w.${t("type")} = 'purchase' then 'purchase' else 'sales' end) as kind,
      coalesce(${fn("tax_rate_on")}(w.${t("id")}, accounting_tax_report.until), 0) as rate_bps, w.${t("returnBoxes")} as boxes,
      (case when w.${t("type")} = 'purchase' then -1 else 1 end) * coalesce(sum(b.net) filter (where b.account is distinct from (case when w.${t("type")} = 'purchase' then w.${t("purchaseAccount")} else coalesce(w.${t("salesAccount")}, w.${t("purchaseAccount")}) end)), 0) as base,
      (case when w.${t("type")} = 'purchase' then -1 else 1 end) * coalesce(sum(b.net) filter (where b.account = (case when w.${t("type")} = 'purchase' then w.${t("purchaseAccount")} else coalesce(w.${t("salesAccount")}, w.${t("purchaseAccount")}) end)), 0) as tax
    from booked b join ${taxes} w on w.${t("id")} = b.tax_code
    group by w.${t("id")}
  )
  select jsonb_build_object(
    'organizationId', accounting_tax_report.tenant,
    'since', accounting_tax_report.since,
    'until', accounting_tax_report.until,
    'currency', (select st.${s("functionalCurrency")} from ${settings} st where st.${s("tenant")} = accounting_tax_report.tenant),
    'codes', coalesce((select jsonb_agg(jsonb_build_object('taxCodeId', c.id, 'code', c.code, 'name', c.name, 'kind', c.kind,
      'rateBps', c.rate_bps, 'reportBoxes', to_jsonb(c.boxes), 'base', c.base::text, 'tax', c.tax::text) order by c.code) from codes c), '[]'::jsonb),
    'boxes', coalesce((select jsonb_agg(jsonb_build_object('box', x.box, 'base', x.base::text, 'tax', x.tax::text) order by x.box)
      from (select q.box, sum(c.base) as base, sum(c.tax) as tax from codes c cross join unnest(c.boxes) q(box) group by q.box) x), '[]'::jsonb),
    'salesTax', coalesce((select sum(c.tax) from codes c where c.kind = 'sales'), 0)::text,
    'purchaseTax', coalesce((select sum(c.tax) from codes c where c.kind = 'purchase'), 0)::text,
    'netTax', coalesce((select sum(case when c.kind = 'sales' then c.tax else -c.tax end) from codes c), 0)::text
  )
$$;
${userGrant(`${fn("accounting_tax_report")}(${idType}, date, date)`)}
`;
}
