import type { BlockSqlContext } from "../context.ts";

import {
  extraFieldsArg,
  extraFieldsJson,
  fail,
  pageSize,
  writeExtraColumns,
  userGrant,
} from "../shared.ts";
import { requireSettings } from "./accounting-setup.ts";
import { accountingSql, ENTRY_RESERVED } from "./accounting-shared.ts";

/** The JSON of an entry (`row`), with its lines when `withLines`. */
export function entryJson(
  ctx: BlockSqlContext,
  row: string,
  withLines: boolean,
): string {
  const e = (column: string): string => ctx.col("entries", column);
  const l = (column: string): string => ctx.col("lines", column);
  const a = (column: string): string => ctx.col("accounts", column);
  const extras = ctx.extraColumns("entries", ENTRY_RESERVED);
  const lines = ctx.table("lines");

  const lineJson = `jsonb_build_object('id', el.${l("id")}, 'accountId', el.${l("account")}, 'accountCode', ea.${a("code")}, 'accountName', ea.${a("name")}, 'debit', el.${l("debit")}::text, 'credit', el.${l("credit")}::text, 'currency', el.${l("currency")}, 'amountCurrency', el.${l("amountCurrency")}::text, 'fxRate', el.${l("fxRate")}::text, 'taxCodeId', el.${l("taxCode")}, 'taxAmount', el.${l("taxAmount")}::text, 'partyId', el.${l("party")}, 'dimensions', el.${l("dimensions")}, 'description', el.${l("description")})`;

  const linesJson = withLines
    ? `, 'lines', coalesce((select jsonb_agg(${lineJson} order by el.${l("position")}, el.${l("id")}) from ${lines} el join ${ctx.table("accounts")} ea on ea.${a("id")} = el.${l("account")} where el.${l("entry")} = ${row}.${e("id")}), '[]'::jsonb)`
    : "";

  return `jsonb_build_object('id', ${row}.${e("id")}, 'organizationId', ${row}.${e("tenant")}, 'journalId', ${row}.${e("journal")}, 'number', ${row}.${e("number")}, 'fiscalYear', ${row}.${e("fiscalYear")}, 'entryDate', ${row}.${e("entryDate")}, 'periodId', ${row}.${e("period")}, 'status', ${row}.${e("status")}, 'reference', ${row}.${e("reference")}, 'sourceType', ${row}.${e("sourceType")}, 'sourceId', ${row}.${e("sourceId")}, 'reversesId', ${row}.${e("reverses")}, 'memo', ${row}.${e("memo")}, 'total', coalesce((select sum(et.${l("debit")}) from ${lines} et where et.${l("entry")} = ${row}.${e("id")}), 0)::text, 'postedAt', ${row}.${e("postedAt")}, 'postedBy', ${row}.${e("postedBy")}, 'createdBy', ${row}.${e("createdBy")}, 'createdAt', ${row}.${e("createdAt")}, 'updatedAt', ${row}.${e("updatedAt")}${linesJson}${extraFieldsJson(row, extras)})`;
}

/** Draft entries, posting, reversal and the entry reads. */
export function accountingEntryFunctions(ctx: BlockSqlContext): string {
  const settings = ctx.table("settings");
  const accounts = ctx.table("accounts");
  const journals = ctx.table("journals");
  const periods = ctx.table("periods");
  const entries = ctx.table("entries");
  const lines = ctx.table("lines");
  const dimensions = ctx.table("dimensions");
  const values = ctx.table("dimensionValues");
  const taxes = ctx.of("tax").table("codes");
  const s = (column: string): string => ctx.col("settings", column);
  const a = (column: string): string => ctx.col("accounts", column);
  const j = (column: string): string => ctx.col("journals", column);
  const p = (column: string): string => ctx.col("periods", column);
  const e = (column: string): string => ctx.col("entries", column);
  const l = (column: string): string => ctx.col("lines", column);
  const d = (column: string): string => ctx.col("dimensions", column);
  const v = (column: string): string => ctx.col("dimensionValues", column);
  const t = (column: string): string => ctx.of("tax").col("codes", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const sql = accountingSql(ctx);
  const { allowed } = sql;
  const extras = ctx.extraColumns("entries", ENTRY_RESERVED);
  const extra = extraFieldsArg(extras);

  const invalid = (message: string): string =>
    sql.invalid("ACCOUNTING_ENTRY", message);

  const posted = fail(
    "ACCOUNTING_ENTRY_POSTED",
    "a posted entry can't change; reverse it",
    "55000",
  );

  const entryNotFound = sql.notFound("ACCOUNTING_ENTRY", "entry not found");

  const postedPayload = (row: string): string =>
    `jsonb_build_object('organizationId', ${row}.${e("tenant")}, 'id', ${row}.${e("id")}, 'journalId', ${row}.${e("journal")}, 'number', ${row}.${e("number")}, 'entryDate', ${row}.${e("entryDate")}, 'sourceType', ${row}.${e("sourceType")}, 'sourceId', ${row}.${e("sourceId")}, 'reversesId', ${row}.${e("reverses")}, 'total', v_total::text)`;

  const saveTypes = "uuid, date, jsonb, text, text, text, text, uuid";

  return `
-- Posts a draft entry: balanced in the functional currency, dated in an open
-- period after the lock date, with known dimension values; then numbers it per
-- journal and fiscal year. Called by the posting, reversal and year close
-- functions; closing skips the closed period and lock date checks. A locked
-- period refuses every post. A ledger import (import mode) may post into a
-- closed period, and the organization's lock date still applies to it.
create or replace function ${fn("accounting_post")}(entry_id uuid, closing boolean default false)
returns ${entries}
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${entries}%rowtype;
  v_settings ${settings}%rowtype;
  v_period ${periods}%rowtype;
  v_journal ${journals}%rowtype;
  v_total numeric;
  v_credits numeric;
  v_count integer;
  v_sequence integer;
begin
  select * into v_row from ${entries} y where y.${e("id")} = accounting_post.entry_id for update;
  if not found then
    ${entryNotFound}
  end if;
  if v_row.${e("status")} <> 'draft' then
    ${posted}
  end if;
  ${requireSettings(ctx, `v_row.${e("tenant")}`)}
  select count(*), coalesce(sum(y.${l("debit")}), 0), coalesce(sum(y.${l("credit")}), 0) into v_count, v_total, v_credits
  from ${lines} y where y.${l("entry")} = v_row.${e("id")};
  if v_count < 2 then
    ${invalid("an entry needs at least two lines")}
  end if;
  if v_total <> v_credits then
    ${fail("ACCOUNTING_ENTRY_UNBALANCED", "the debits and credits of the entry differ in the functional currency", "23514")}
  end if;
  if exists (
    select 1 from ${lines} y join ${accounts} z on z.${a("id")} = y.${l("account")}
    where y.${l("entry")} = v_row.${e("id")} and (z.${a("archivedAt")} is not null or not z.${a("active")})
  ) then
    ${sql.invalid("ACCOUNTING_ACCOUNT", "an account of the entry is archived or inactive")}
  end if;
  if exists (
    select 1 from ${lines} y, jsonb_each(y.${l("dimensions")}) dim
    where y.${l("entry")} = v_row.${e("id")}
      and (jsonb_typeof(dim.value) <> 'string' or not exists (
        select 1 from ${dimensions} z join ${values} w on w.${v("dimension")} = z.${d("id")}
        where z.${d("tenant")} = v_row.${e("tenant")} and z.${d("key")} = dim.key
          and w.${v("code")} = dim.value #>> '{}' and w.${v("archivedAt")} is null
      ))
  ) then
    ${fail("ACCOUNTING_DIMENSION_INVALID", "a line names a dimension or value that doesn't exist or is archived", "22023")}
  end if;
  select * into v_period from ${periods} y
  where y.${p("tenant")} = v_row.${e("tenant")} and v_row.${e("entryDate")} >= y.${p("startsOn")} and v_row.${e("entryDate")} <= y.${p("endsOn")};
  if not found then
    ${fail("ACCOUNTING_PERIOD_NOT_FOUND", "no period covers the entry date; open its fiscal year first", "P0002")}
  end if;
  if v_period.${p("status")} = 'locked' then
    ${fail("ACCOUNTING_PERIOD_LOCKED", "the entry date is in a locked period", "55000")}
  end if;
  if not coalesce(accounting_post.closing, false) and (
    (v_period.${p("status")} = 'closed' and better_supabase.import_run() is null)
    or (v_settings.${s("lockDate")} is not null and v_row.${e("entryDate")} <= v_settings.${s("lockDate")})
  ) then
    ${fail("ACCOUNTING_PERIOD_CLOSED", "the entry date is in a closed period or on or before the lock date", "55000")}
  end if;
  ${ctx.hook("before_accounting_entry_post", [["uuid", `v_row.${e("id")}`]])}
  select * into v_journal from ${journals} y where y.${j("id")} = v_row.${e("journal")};
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_journal.${j("id")}::text || ':' || v_period.${p("fiscalYear")}::text, 0));
  select coalesce(max(y.${e("sequence")}), 0) + 1 into v_sequence from ${entries} y
  where y.${e("journal")} = v_journal.${j("id")} and y.${e("fiscalYear")} = v_period.${p("fiscalYear")};
  update ${entries} y set ${e("status")} = 'posted', ${e("fiscalYear")} = v_period.${p("fiscalYear")}, ${e("sequence")} = v_sequence,
    ${e("number")} = v_journal.${j("code")} || '-' || v_period.${p("fiscalYear")}::text || '-' || lpad(v_sequence::text, 5, '0'),
    ${e("period")} = v_period.${p("id")}, ${e("postedAt")} = now(), ${e("postedBy")} = auth.uid(), ${e("updatedAt")} = now()
  where y.${e("id")} = v_row.${e("id")}
  returning * into v_row;
  ${ctx.record({
    type: "accounting_entry.posted",
    payload: postedPayload("v_row"),
    subject: `'accounting-entries/' || v_row.${e("id")}::text`,
    tenant: `v_row.${e("tenant")}`,
    audit: {
      category: "data",
      targetType: "accounting_entry",
      recordId: `v_row.${e("id")}::text`,
      targetLabel: `v_row.${e("number")}`,
      summary: `'posted entry ' || v_row.${e("number")}`,
    },
  })}
  ${ctx.hook("after_accounting_entry_post", [["uuid", `v_row.${e("id")}`]])}
  return v_row;
end;
$$;
revoke execute on function ${fn("accounting_post")}(uuid, boolean) from public, anon, authenticated;

-- Creates a draft entry, or replaces a draft's header and lines (entry_id).
-- Each line names an account (accountId or accountCode) and a debit or a
-- credit in minor units of the functional currency. A line in another
-- currency gives amountCurrency (signed, positive is a debit) and either the
-- functional amount or an fxRate; without both, the rate on the entry date
-- converts it.
${extra.drop(fn("save_accounting_entry"), saveTypes)}
create or replace function ${fn("save_accounting_entry")}(journal_id uuid, entry_date date, lines jsonb, memo text default null, reference text default null, source_type text default null, source_id text default null, entry_id uuid default null${extra.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_journal ${journals}%rowtype;
  v_settings ${settings}%rowtype;
  v_row ${entries}%rowtype;
  v_line record;
  v_account ${accounts}%rowtype;
  v_currency text;
  v_debit bigint;
  v_credit bigint;
  v_amount bigint;
  v_rate numeric;
  v_functional bigint;
  v_tax uuid;
  v_party uuid;
  v_dimensions jsonb;
begin
  select * into v_journal from ${journals} y where y.${j("id")} = save_accounting_entry.journal_id;
  if not found then
    ${sql.notFound("ACCOUNTING_JOURNAL", "journal not found")}
  end if;
  if not ${allowed(`v_journal.${j("tenant")}`, sql.write)} then
    ${sql.forbidden("ACCOUNTING_ENTRY", "not allowed to write accounting entries")}
  end if;
  ${requireSettings(ctx, `v_journal.${j("tenant")}`)}
  if save_accounting_entry.entry_date is null then
    ${invalid("an entry needs a date")}
  end if;
  if jsonb_typeof(save_accounting_entry.lines) is distinct from 'array' or jsonb_array_length(save_accounting_entry.lines) < 2 then
    ${invalid("an entry needs at least two lines")}
  end if;
  if (save_accounting_entry.source_type is null) <> (save_accounting_entry.source_id is null)
    or coalesce(save_accounting_entry.source_type, 'x') !~ '^[a-z][a-z0-9_]{0,62}$' then
    ${invalid("source_type (lower-case) and source_id go together")}
  end if;
  if save_accounting_entry.source_type is not null and exists (
    select 1 from ${entries} y
    where y.${e("tenant")} = v_journal.${j("tenant")} and y.${e("sourceType")} = save_accounting_entry.source_type
      and y.${e("sourceId")} = save_accounting_entry.source_id and y.${e("status")} <> 'reversed'
      and y.${e("id")} is distinct from save_accounting_entry.entry_id
  ) then
    ${fail("ACCOUNTING_ENTRY_DUPLICATE", "the source already has an entry; reverse it first", "23505")}
  end if;
  if save_accounting_entry.entry_id is null then
    insert into ${entries} (${e("tenant")}, ${e("journal")}, ${e("entryDate")}, ${e("reference")}, ${e("sourceType")}, ${e("sourceId")}, ${e("memo")}, ${e("createdBy")}, ${e("period")})
    values (v_journal.${j("tenant")}, v_journal.${j("id")}, save_accounting_entry.entry_date, nullif(trim(save_accounting_entry.reference), ''),
      save_accounting_entry.source_type, save_accounting_entry.source_id, nullif(trim(save_accounting_entry.memo), ''), auth.uid(),
      (select y.${p("id")} from ${periods} y where y.${p("tenant")} = v_journal.${j("tenant")} and save_accounting_entry.entry_date >= y.${p("startsOn")} and save_accounting_entry.entry_date <= y.${p("endsOn")}))
    returning * into v_row;
  else
    select * into v_row from ${entries} y where y.${e("id")} = save_accounting_entry.entry_id and y.${e("tenant")} = v_journal.${j("tenant")} for update;
    if not found then
      ${entryNotFound}
    end if;
    if v_row.${e("status")} <> 'draft' then
      ${posted}
    end if;
    delete from ${lines} y where y.${l("entry")} = v_row.${e("id")};
    update ${entries} y set ${e("journal")} = v_journal.${j("id")}, ${e("entryDate")} = save_accounting_entry.entry_date,
      ${e("reference")} = nullif(trim(save_accounting_entry.reference), ''), ${e("sourceType")} = save_accounting_entry.source_type,
      ${e("sourceId")} = save_accounting_entry.source_id, ${e("memo")} = nullif(trim(save_accounting_entry.memo), ''),
      ${e("period")} = (select z.${p("id")} from ${periods} z where z.${p("tenant")} = v_journal.${j("tenant")} and save_accounting_entry.entry_date >= z.${p("startsOn")} and save_accounting_entry.entry_date <= z.${p("endsOn")}),
      ${e("updatedAt")} = now()
    where y.${e("id")} = v_row.${e("id")}
    returning * into v_row;
  end if;
  for v_line in select q.value, q.ordinality from jsonb_array_elements(save_accounting_entry.lines) with ordinality q loop
    if jsonb_typeof(v_line.value) is distinct from 'object' then
      ${invalid("every line is an object")}
    end if;
    if coalesce(v_line.value ->> 'accountId', '') ~ '^[0-9a-fA-F-]{36}$' then
      select * into v_account from ${accounts} y where y.${a("id")} = (v_line.value ->> 'accountId')::uuid and y.${a("tenant")} = v_journal.${j("tenant")};
    else
      select * into v_account from ${accounts} y where y.${a("code")} = v_line.value ->> 'accountCode' and y.${a("tenant")} = v_journal.${j("tenant")};
    end if;
    if v_account.${a("id")} is null or v_account.${a("archivedAt")} is not null then
      ${sql.notFound("ACCOUNTING_ACCOUNT", "a line's account doesn't exist here or is archived")}
    end if;
    if not v_account.${a("active")} then
      ${sql.invalid("ACCOUNTING_ACCOUNT", "a line's account is inactive")}
    end if;
    if coalesce(v_line.value ->> 'debit', '0') !~ '^[0-9]{1,18}$' or coalesce(v_line.value ->> 'credit', '0') !~ '^[0-9]{1,18}$'
      or coalesce(v_line.value ->> 'amountCurrency', '0') !~ '^-?[0-9]{1,18}$'
      or coalesce(v_line.value ->> 'taxAmount', '0') !~ '^[0-9]{1,18}$'
      or coalesce(v_line.value ->> 'fxRate', '1') !~ '^[0-9]+(\\.[0-9]+)?$' then
      ${invalid("debit and credit are non-negative integers, amountCurrency an integer and fxRate a positive decimal")}
    end if;
    v_debit := coalesce((v_line.value ->> 'debit')::bigint, 0);
    v_credit := coalesce((v_line.value ->> 'credit')::bigint, 0);
    v_currency := upper(coalesce(nullif(v_line.value ->> 'currency', ''), v_settings.${s("functionalCurrency")}));
    if v_currency !~ '^[A-Z]{3}$' then
      ${invalid("a line's currency must be an ISO 4217 code such as EUR")}
    end if;
    if v_account.${a("currency")} is not null and v_account.${a("currency")} <> v_currency then
      ${invalid("the account takes lines in its own currency only")}
    end if;
    v_rate := null;
    if v_currency = v_settings.${s("functionalCurrency")} then
      v_amount := v_debit - v_credit;
    else
      v_amount := (v_line.value ->> 'amountCurrency')::bigint;
      if v_amount is null or v_amount = 0 then
        ${invalid("a line in another currency needs a non-zero amountCurrency")}
      end if;
      v_rate := coalesce((v_line.value ->> 'fxRate')::numeric,
        ${fn("accounting_fx_rate")}(v_journal.${j("tenant")}, v_currency, v_settings.${s("functionalCurrency")}, save_accounting_entry.entry_date));
      if v_rate <= 0 then
        ${invalid("fxRate must be positive")}
      end if;
      if v_debit = 0 and v_credit = 0 then
        v_functional := round(abs(v_amount) * v_rate)::bigint;
        if v_amount > 0 then
          v_debit := v_functional;
        else
          v_credit := v_functional;
        end if;
      elsif (v_amount > 0) <> (v_debit > 0) then
        ${invalid("amountCurrency and the functional amount must be on the same side")}
      end if;
    end if;
    if (v_debit = 0) = (v_credit = 0) then
      ${invalid("every line has either a debit or a credit")}
    end if;
    v_tax := case when v_line.value ? 'taxCodeId' then null else v_account.${a("defaultTaxCode")} end;
    if v_line.value ->> 'taxCodeId' is not null then
      select y.${t("id")} into v_tax from ${taxes} y
      where y.${t("id")}::text = v_line.value ->> 'taxCodeId' and y.${t("tenant")} = v_journal.${j("tenant")};
      if v_tax is null then
        ${sql.notFound("ACCOUNTING_TAX_CODE", "tax code not found")}
      end if;
    end if;
    if coalesce(v_line.value ->> 'partyId', '00000000-0000-0000-0000-000000000000') !~ '^[0-9a-fA-F-]{36}$' then
      ${invalid("partyId must be a uuid")}
    end if;
    v_party := (v_line.value ->> 'partyId')::uuid;
    if coalesce((v_line.value ->> 'taxAmount')::bigint, 0) > v_debit + v_credit then
      ${invalid("a line's taxAmount can't exceed its amount")}
    end if;
    v_dimensions := coalesce(v_line.value -> 'dimensions', '{}'::jsonb);
    if jsonb_typeof(v_dimensions) = 'null' then
      v_dimensions := '{}'::jsonb;
    end if;
    if jsonb_typeof(v_dimensions) <> 'object' then
      ${fail("ACCOUNTING_DIMENSION_INVALID", "a line's dimensions are an object of dimension keys to value codes", "22023")}
    end if;
    insert into ${lines} (${l("tenant")}, ${l("entry")}, ${l("position")}, ${l("account")}, ${l("debit")}, ${l("credit")}, ${l("currency")},
      ${l("amountCurrency")}, ${l("fxRate")}, ${l("taxCode")}, ${l("taxAmount")}, ${l("party")}, ${l("dimensions")}, ${l("description")})
    values (v_journal.${j("tenant")}, v_row.${e("id")}, v_line.ordinality, v_account.${a("id")}, v_debit, v_credit, v_currency,
      v_amount, v_rate, v_tax, coalesce((v_line.value ->> 'taxAmount')::bigint, 0), v_party, v_dimensions, nullif(trim(v_line.value ->> 'description'), ''));
  end loop;${writeExtraColumns(entries, extras, "save_accounting_entry.fields", `x.${e("id")} = v_row.${e("id")}`, "v_row")}
  return ${entryJson(ctx, "v_row", true)};
end;
$$;
${userGrant(`${fn("save_accounting_entry")}(${saveTypes}${extra.type})`)}

create or replace function ${fn("post_accounting_entry")}(entry_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${entries}%rowtype;
begin
  select * into v_row from ${entries} y where y.${e("id")} = post_accounting_entry.entry_id;
  if not found then
    ${entryNotFound}
  end if;
  if not ${allowed(`v_row.${e("tenant")}`, sql.post)} then
    ${sql.forbidden("ACCOUNTING_ENTRY", "not allowed to post accounting entries")}
  end if;
  v_row := ${fn("accounting_post")}(v_row.${e("id")});
  return ${entryJson(ctx, "v_row", true)};
end;
$$;
${userGrant(`${fn("post_accounting_entry")}(uuid)`)}

-- Reverses a posted entry with a new entry of opposite lines, dated
-- entry_date (default the original's date), and marks the original reversed.
-- Called by reverse_accounting_entry and when a block undoes a document.
create or replace function ${fn("accounting_reverse")}(entry_id uuid, entry_date date default null)
returns ${entries}
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${entries}%rowtype;
  v_reversal ${entries}%rowtype;
begin
  select * into v_row from ${entries} y where y.${e("id")} = accounting_reverse.entry_id for update;
  if not found then
    ${entryNotFound}
  end if;
  if v_row.${e("status")} = 'reversed' then
    ${fail("ACCOUNTING_ENTRY_REVERSED", "the entry is already reversed", "55000")}
  end if;
  if v_row.${e("status")} <> 'posted' then
    ${invalid("only a posted entry can be reversed; delete a draft instead")}
  end if;
  ${ctx.hook("before_accounting_entry_reverse", [["uuid", `v_row.${e("id")}`]])}
  insert into ${entries} (${e("tenant")}, ${e("journal")}, ${e("entryDate")}, ${e("reference")}, ${e("reverses")}, ${e("memo")}, ${e("createdBy")})
  values (v_row.${e("tenant")}, v_row.${e("journal")}, coalesce(accounting_reverse.entry_date, v_row.${e("entryDate")}), v_row.${e("number")},
    v_row.${e("id")}, 'Reversal of ' || v_row.${e("number")}, auth.uid())
  returning * into v_reversal;
  insert into ${lines} (${l("tenant")}, ${l("entry")}, ${l("position")}, ${l("account")}, ${l("debit")}, ${l("credit")}, ${l("currency")},
    ${l("amountCurrency")}, ${l("fxRate")}, ${l("taxCode")}, ${l("party")}, ${l("dimensions")}, ${l("description")})
  select y.${l("tenant")}, v_reversal.${e("id")}, y.${l("position")}, y.${l("account")}, y.${l("credit")}, y.${l("debit")}, y.${l("currency")},
    -y.${l("amountCurrency")}, y.${l("fxRate")}, y.${l("taxCode")}, y.${l("party")}, y.${l("dimensions")}, y.${l("description")}
  from ${lines} y where y.${l("entry")} = v_row.${e("id")};
  v_reversal := ${fn("accounting_post")}(v_reversal.${e("id")});
  update ${entries} y set ${e("status")} = 'reversed', ${e("updatedAt")} = now() where y.${e("id")} = v_row.${e("id")}
  returning * into v_row;
  ${ctx.record({
    type: "accounting_entry.reversed",
    payload: `jsonb_build_object('organizationId', v_row.${e("tenant")}, 'id', v_row.${e("id")}, 'journalId', v_row.${e("journal")}, 'number', v_row.${e("number")}, 'sourceType', v_row.${e("sourceType")}, 'sourceId', v_row.${e("sourceId")}, 'reversalId', v_reversal.${e("id")})`,
    subject: `'accounting-entries/' || v_row.${e("id")}::text`,
    tenant: `v_row.${e("tenant")}`,
    audit: {
      category: "data",
      targetType: "accounting_entry",
      recordId: `v_row.${e("id")}::text`,
      targetLabel: `v_row.${e("number")}`,
      summary: `'reversed entry ' || v_row.${e("number")} || ' with ' || v_reversal.${e("number")}`,
    },
  })}
  ${ctx.hook("after_accounting_entry_reverse", [["uuid", `v_row.${e("id")}`]])}
  return v_reversal;
end;
$$;
revoke execute on function ${fn("accounting_reverse")}(uuid, date) from public, anon, authenticated;

create or replace function ${fn("reverse_accounting_entry")}(entry_id uuid, entry_date date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${entries}%rowtype;
begin
  select * into v_row from ${entries} y where y.${e("id")} = reverse_accounting_entry.entry_id;
  if not found then
    ${entryNotFound}
  end if;
  if not ${allowed(`v_row.${e("tenant")}`, sql.post)} then
    ${sql.forbidden("ACCOUNTING_ENTRY", "not allowed to post accounting entries")}
  end if;
  v_row := ${fn("accounting_reverse")}(v_row.${e("id")}, reverse_accounting_entry.entry_date);
  return ${entryJson(ctx, "v_row", true)};
end;
$$;
${userGrant(`${fn("reverse_accounting_entry")}(uuid, date)`)}

create or replace function ${fn("delete_accounting_entry")}(entry_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${entries}%rowtype;
  v_json jsonb;
begin
  select * into v_row from ${entries} y where y.${e("id")} = delete_accounting_entry.entry_id for update;
  if not found then
    ${entryNotFound}
  end if;
  if not ${allowed(`v_row.${e("tenant")}`, sql.write)} then
    ${sql.forbidden("ACCOUNTING_ENTRY", "not allowed to write accounting entries")}
  end if;
  if v_row.${e("status")} <> 'draft' then
    ${posted}
  end if;
  v_json := ${entryJson(ctx, "v_row", true)};
  delete from ${entries} y where y.${e("id")} = v_row.${e("id")};
  return v_json;
end;
$$;
${userGrant(`${fn("delete_accounting_entry")}(uuid)`)}

create or replace function ${fn("get_accounting_entry")}(entry_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${entryJson(ctx, "x", true)} from ${entries} x where x.${e("id")} = get_accounting_entry.entry_id
$$;
${userGrant(`${fn("get_accounting_entry")}(uuid)`)}

-- Entries, the newest first, without their lines.
create or replace function ${fn("list_accounting_entries")}(tenant ${idType}, journal_id uuid default null, status text default null, since date default null, until date default null, page_size integer default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(z.entry order by z.entry_date desc, z.created_at desc), '[]'::jsonb)
  from (
    select ${entryJson(ctx, "x", false)} as entry, x.${e("entryDate")} as entry_date, x.${e("createdAt")} as created_at
    from ${entries} x
    where x.${e("tenant")} = list_accounting_entries.tenant
      and (list_accounting_entries.journal_id is null or x.${e("journal")} = list_accounting_entries.journal_id)
      and (list_accounting_entries.status is null or x.${e("status")} = list_accounting_entries.status)
      and (list_accounting_entries.since is null or x.${e("entryDate")} >= list_accounting_entries.since)
      and (list_accounting_entries.until is null or x.${e("entryDate")} <= list_accounting_entries.until)
    order by x.${e("entryDate")} desc, x.${e("createdAt")} desc
    limit ${pageSize("list_accounting_entries.page_size", 50, 500)}
  ) z
$$;
${userGrant(`${fn("list_accounting_entries")}(${idType}, uuid, text, date, date, integer)`)}
`;
}
