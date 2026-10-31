import type { BlockSqlContext } from "../context.ts";

import { pageSize, userGrant, writeExtraColumns } from "../shared.ts";
import { bankingSql, linked, STATEMENT_FORMATS } from "./banking-sql.ts";

const list = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

/**
 * The reference helpers: `bank_mod97` (ISO 7064 MOD 97-10 over letters and
 * digits) and `bank_reference`, the payload of an ISO 11649 RF creditor
 * reference or a Dutch betalingskenmerk, checked.
 */
function referenceFunctions(ctx: BlockSqlContext): string {
  const fn = (name: string): string => ctx.fn(name);

  return `
-- The ISO 7064 MOD 97-10 remainder of letters and digits, letters counting as
-- 10 to 35, as IBAN and ISO 11649 check them. Null for any other character.
create or replace function ${fn("bank_mod97")}(value text)
returns integer
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_rem integer := 0;
  v_n integer;
  v_char text;
begin
  if value is null or value = '' then
    return null;
  end if;
  foreach v_char in array regexp_split_to_array(value, '') loop
    if v_char between '0' and '9' then
      v_rem := (v_rem * 10 + ascii(v_char) - 48) % 97;
    elsif v_char between 'A' and 'Z' then
      v_n := ascii(v_char) - 55;
      v_rem := (v_rem * 100 + v_n) % 97;
    else
      return null;
    end if;
  end loop;
  return v_rem;
end;
$$;
revoke execute on function ${fn("bank_mod97")}(text) from public, anon, authenticated;

-- The payload of a structured payment reference: what follows RF and its
-- check digits in an ISO 11649 creditor reference, or the 15 digits after the
-- check digit of a 16-digit Dutch betalingskenmerk, without leading zeros.
-- Null when the check digits are wrong or the reference is neither.
create or replace function ${fn("bank_reference")}(reference text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_ref text := upper(regexp_replace(coalesce(reference, ''), '[^A-Za-z0-9]', '', 'g'));
  v_weights integer[] := array[2, 4, 8, 5, 10, 9, 7, 3, 6, 1, 2, 4, 8, 5, 10];
  v_sum integer := 0;
  v_check integer;
  v_i integer;
begin
  if v_ref ~ '^RF[0-9]{2}[A-Z0-9]{1,21}$' then
    if ${fn("bank_mod97")}(substr(v_ref, 5) || substr(v_ref, 1, 4)) = 1 then
      return substr(v_ref, 5);
    end if;
    return null;
  end if;
  if v_ref ~ '^[0-9]{16}$' then
    for v_i in 1..15 loop
      v_sum := v_sum + (ascii(substr(v_ref, 17 - v_i, 1)) - 48) * v_weights[v_i];
    end loop;
    v_check := 11 - v_sum % 11;
    v_check := case v_check when 10 then 1 when 11 then 0 else v_check end;
    if v_check = ascii(substr(v_ref, 1, 1)) - 48 then
      return nullif(ltrim(substr(v_ref, 2), '0'), '');
    end if;
  end if;
  return null;
end;
$$;
revoke execute on function ${fn("bank_reference")}(text) from public, anon, authenticated;
`;
}

/** Bank accounts, statement import, the reads and the reconciliation status. */
export function bankingFunctions(ctx: BlockSqlContext): string {
  const q = bankingSql(ctx);
  const { a, s, t } = q;
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const accounting = linked(ctx, "accounting");

  const journalCheck = accounting
    ? `
  if v_journal is not null and not exists (
    select 1 from ${accounting.table("journals")} y
    where y.${accounting.col("journals", "id")} = v_journal and y.${accounting.col("journals", "tenant")} = save_bank_account.tenant
      and y.${accounting.col("journals", "type")} in ('bank', 'cash')
  ) then
    ${q.accountInvalid("the journal must be a bank or cash journal of the organization")}
  end if;`
    : "";

  const loadAccount = (arg: string, permission: string, lock = false) => `
  select * into v_account from ${q.accounts} x where x.${a("id")} = ${arg}${lock ? " for update" : ""};
  if not found then
    ${q.accountMissing}
  end if;
  if not ${q.allowed(`v_account.${a("tenant")}`, permission)} then
    ${q.forbidden("not allowed to do this with bank accounts")}
  end if;`;

  const ledgerBalance = accounting
    ? (() => {
        const j = (column: string): string =>
          accounting.col("journals", column);

        const e = (column: string): string => accounting.col("entries", column);

        const l = (column: string): string => accounting.col("lines", column);

        return `(select sum(y.${l("amountCurrency")})
      from ${accounting.table("lines")} y
      join ${accounting.table("entries")} z on z.${e("id")} = y.${l("entry")}
      join ${accounting.table("journals")} w on w.${j("id")} = v_account.${a("journal")}
      where y.${l("tenant")} = v_account.${a("tenant")} and y.${l("account")} = w.${j("defaultAccount")}
        and y.${l("currency")} = v_account.${a("currency")}
        and z.${e("status")} <> 'draft' and z.${e("entryDate")} <= v_as_of)`;
      })()
    : "null::bigint";

  return `${referenceFunctions(ctx)}
-- Creates or updates a bank account: name, iban, bic, currency and the
-- accounting journal its money moves through. The IBAN is stored upper case
-- without spaces and must pass its ISO 13616 check digits.
create or replace function ${fn("save_bank_account")}(tenant ${idType}, input jsonb, account_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_account ${q.accounts}%rowtype;
  v_iban text;
  v_bic text;
  v_currency text;
  v_journal uuid;
begin
  if not ${q.allowed("save_bank_account.tenant", q.manage)} then
    ${q.forbidden("not allowed to manage bank accounts")}
  end if;
  if jsonb_typeof(save_bank_account.input) is distinct from 'object' then
    ${q.accountInvalid("input must be an object")}
  end if;
  if save_bank_account.account_id is not null then
    select * into v_account from ${q.accounts} x
    where x.${a("id")} = save_bank_account.account_id and x.${a("tenant")} = save_bank_account.tenant
    for update;
    if not found then
      ${q.accountMissing}
    end if;
  end if;
  v_iban := case when save_bank_account.input ? 'iban'
    then nullif(upper(regexp_replace(save_bank_account.input ->> 'iban', '\\s', '', 'g')), '')
    else v_account.${a("iban")} end;
  if v_iban is not null and (v_iban !~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$'
    or ${fn("bank_mod97")}(substr(v_iban, 5) || substr(v_iban, 1, 4)) is distinct from 1) then
    ${q.accountInvalid("the IBAN's check digits don't match")}
  end if;
  v_bic := case when save_bank_account.input ? 'bic'
    then nullif(upper(regexp_replace(save_bank_account.input ->> 'bic', '\\s', '', 'g')), '')
    else v_account.${a("bic")} end;
  if v_bic is not null and v_bic !~ '^[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?$' then
    ${q.accountInvalid("a BIC has 8 or 11 letters and digits")}
  end if;
  v_currency := upper(coalesce(save_bank_account.input ->> 'currency', v_account.${a("currency")}));
  if v_currency is null or v_currency !~ '^[A-Z]{3}$' then
    ${q.accountInvalid("a bank account has an ISO 4217 currency")}
  end if;
  if v_account.${a("id")} is not null and v_currency <> v_account.${a("currency")} and exists (
    select 1 from ${q.transactions} y where y.${t("account")} = v_account.${a("id")}
  ) then
    ${q.accountInvalid("a bank account with transactions keeps its currency")}
  end if;
  v_journal := case when save_bank_account.input ? 'journalId'
    then nullif(save_bank_account.input ->> 'journalId', '')::uuid
    else v_account.${a("journal")} end;${journalCheck}
  if v_account.${a("id")} is null then
    insert into ${q.accounts} (${a("tenant")}, ${a("name")}, ${a("iban")}, ${a("bic")}, ${a("currency")}, ${a("journal")})
    values (save_bank_account.tenant, trim(save_bank_account.input ->> 'name'), v_iban, v_bic, v_currency, v_journal)
    returning * into v_account;
  else
    update ${q.accounts} x set
      ${a("name")} = coalesce(trim(save_bank_account.input ->> 'name'), x.${a("name")}),
      ${a("iban")} = v_iban,
      ${a("bic")} = v_bic,
      ${a("currency")} = v_currency,
      ${a("journal")} = v_journal,
      ${a("archivedAt")} = case when save_bank_account.input ? 'archived'
        then case when (save_bank_account.input ->> 'archived')::boolean then coalesce(x.${a("archivedAt")}, now()) end
        else x.${a("archivedAt")} end,
      ${a("updatedAt")} = now()
    where x.${a("id")} = v_account.${a("id")}
    returning * into v_account;
  end if;${writeExtraColumns(q.accounts, q.extras, "coalesce(save_bank_account.input -> 'fields', '{}'::jsonb)", `x.${a("id")} = v_account.${a("id")}`, "v_account")}
  return ${q.accountJson("v_account")};
exception
  when check_violation or not_null_violation then
    ${q.accountInvalid("a bank account has a name of 1 to 200 characters")}
  when unique_violation then
    ${q.accountInvalid("the organization already has a bank account with this IBAN")}
  when invalid_text_representation then
    ${q.accountInvalid("journalId must be a uuid")}
end;
$$;
${userGrant(`${fn("save_bank_account")}(${idType}, jsonb, uuid)`)}

create or replace function ${fn("list_bank_accounts")}(tenant ${idType}, include_archived boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${q.allowed("list_bank_accounts.tenant", q.read)} then
    ${q.forbidden("not allowed to read bank accounts")}
  end if;
  return coalesce((
    select jsonb_agg(${q.accountJson("x")} order by x.${a("name")}, x.${a("id")})
    from ${q.accounts} x
    where x.${a("tenant")} = list_bank_accounts.tenant
      and (list_bank_accounts.include_archived or x.${a("archivedAt")} is null)
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_bank_accounts")}(${idType}, boolean)`)}

-- Imports a statement or a feed's page of transactions into a bank account:
-- { reference, fromOn, untilOn, openingBalance, closingBalance, format,
-- attachmentId, transactions: [{ externalId, bookedOn, valueOn, amount,
-- currency, counterpartyName, counterpartyIban, remittance,
-- structuredReference, endToEndId }] }, amounts in minor units. A
-- transaction's externalId is unique per account, so importing the same file
-- or page again adds nothing; without one it is a hash of its fields and its
-- position. A statement reference the account already has adds to that
-- statement.
create or replace function ${fn("import_bank_statement")}(account_id uuid, statement jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_account ${q.accounts}%rowtype;
  v_statement ${q.statements}%rowtype;
  v_reference text;
  v_format text;
  v_item record;
  v_amount text;
  v_currency text;
  v_external text;
  v_imported integer := 0;
  v_total integer := 0;
begin${loadAccount("import_bank_statement.account_id", q.import, true)}
  if v_account.${a("archivedAt")} is not null then
    ${q.statementInvalid("an archived bank account takes no statements")}
  end if;
  if jsonb_typeof(import_bank_statement.statement) is distinct from 'object'
    or jsonb_typeof(import_bank_statement.statement -> 'transactions') is distinct from 'array' then
    ${q.statementInvalid("a statement is an object with a transactions array")}
  end if;
  v_format := coalesce(import_bank_statement.statement ->> 'format', 'feed');
  if v_format not in (${list(STATEMENT_FORMATS)}) then
    ${q.statementInvalid("a statement's format is camt053, mt940, csv or feed")}
  end if;
  if coalesce(import_bank_statement.statement ->> 'openingBalance', '0') !~ '^-?[0-9]{1,18}$'
    or coalesce(import_bank_statement.statement ->> 'closingBalance', '0') !~ '^-?[0-9]{1,18}$'
    or coalesce(import_bank_statement.statement ->> 'fromOn', '2000-01-01') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    or coalesce(import_bank_statement.statement ->> 'untilOn', '2000-01-01') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
    ${q.statementInvalid("balances are integers of minor units and dates are YYYY-MM-DD")}
  end if;
  v_reference := left(nullif(trim(import_bank_statement.statement ->> 'reference'), ''), 200);
  if v_reference is not null then
    select * into v_statement from ${q.statements} x
    where x.${s("account")} = v_account.${a("id")} and x.${s("reference")} = v_reference;
  end if;
  if v_statement.${s("id")} is null then
    insert into ${q.statements} (${s("tenant")}, ${s("account")}, ${s("reference")}, ${s("fromOn")}, ${s("untilOn")},
      ${s("openingBalance")}, ${s("closingBalance")}, ${s("format")}, ${s("attachment")}, ${s("importedBy")})
    values (v_account.${a("tenant")}, v_account.${a("id")}, v_reference,
      (import_bank_statement.statement ->> 'fromOn')::date, (import_bank_statement.statement ->> 'untilOn')::date,
      (import_bank_statement.statement ->> 'openingBalance')::bigint, (import_bank_statement.statement ->> 'closingBalance')::bigint,
      v_format, nullif(import_bank_statement.statement ->> 'attachmentId', '')::uuid, auth.uid())
    returning * into v_statement;
  end if;
  for v_item in
    select e.value as tx, e.ordinality as n
    from jsonb_array_elements(import_bank_statement.statement -> 'transactions') with ordinality e
  loop
    v_total := v_total + 1;
    v_amount := v_item.tx ->> 'amount';
    v_currency := upper(coalesce(v_item.tx ->> 'currency', v_account.${a("currency")}));
    if jsonb_typeof(v_item.tx) is distinct from 'object'
      or coalesce(v_amount, '') !~ '^-?[0-9]{1,18}$' or v_amount ~ '^-?0+$'
      or coalesce(v_item.tx ->> 'bookedOn', '') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
      or coalesce(v_item.tx ->> 'valueOn', '2000-01-01') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
      ${q.statementInvalid("each transaction has a bookedOn date and a nonzero amount of minor units")}
    end if;
    if v_currency <> v_account.${a("currency")} then
      ${q.statementInvalid("a transaction is in its bank account's currency")}
    end if;
    v_external := coalesce(
      left(nullif(trim(v_item.tx ->> 'externalId'), ''), 200),
      md5(concat_ws('|', v_item.tx ->> 'bookedOn', v_amount, v_item.tx ->> 'counterpartyIban', v_item.tx ->> 'remittance',
        v_item.tx ->> 'structuredReference', v_item.tx ->> 'endToEndId', v_reference, v_item.n::text)));
    insert into ${q.transactions} (${t("tenant")}, ${t("account")}, ${t("statement")}, ${t("bookedOn")}, ${t("valueOn")}, ${t("amount")},
      ${t("currency")}, ${t("counterpartyName")}, ${t("counterpartyIban")}, ${t("remittance")}, ${t("structuredReference")},
      ${t("endToEndId")}, ${t("externalId")})
    values (v_account.${a("tenant")}, v_account.${a("id")}, v_statement.${s("id")}, (v_item.tx ->> 'bookedOn')::date,
      (v_item.tx ->> 'valueOn')::date, v_amount::bigint, v_currency,
      left(nullif(trim(v_item.tx ->> 'counterpartyName'), ''), 500),
      left(nullif(upper(regexp_replace(coalesce(v_item.tx ->> 'counterpartyIban', ''), '\\s', '', 'g')), ''), 34),
      left(nullif(trim(v_item.tx ->> 'remittance'), ''), 2000),
      left(nullif(trim(v_item.tx ->> 'structuredReference'), ''), 100),
      left(nullif(trim(v_item.tx ->> 'endToEndId'), ''), 100),
      v_external)
    on conflict (${t("account")}, ${t("externalId")}) do nothing;
    if found then
      v_imported := v_imported + 1;
    end if;
  end loop;
  ${ctx.record({
    type: "bank_statement.imported",
    payload: `jsonb_build_object('organizationId', v_statement.${s("tenant")}, 'id', v_statement.${s("id")}, 'accountId', v_statement.${s("account")}, 'reference', v_statement.${s("reference")}, 'imported', v_imported)`,
    subject: `'bank-statements/' || v_statement.${s("id")}::text`,
    tenant: `v_statement.${s("tenant")}`,
    audit: {
      category: "billing",
      targetType: "bank_statement",
      recordId: `v_statement.${s("id")}::text`,
      targetLabel: `coalesce(v_statement.${s("reference")}, v_account.${a("name")})`,
      summary: "'imported a bank statement'",
    },
  })}
  ${ctx.hook("after_bank_statement_import", [
    ["uuid", `v_statement.${s("id")}`],
    ["integer", "v_imported"],
  ])}
  return jsonb_build_object('statement', ${q.statementJson("v_statement")}, 'imported', v_imported, 'skipped', v_total - v_imported);
end;
$$;
${userGrant(`${fn("import_bank_statement")}(uuid, jsonb)`)}

create or replace function ${fn("list_bank_statements")}(account_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_account ${q.accounts}%rowtype;
begin${loadAccount("list_bank_statements.account_id", q.read)}
  return coalesce((
    select jsonb_agg(${q.statementJson("x")} order by x.${s("untilOn")} desc nulls last, x.${s("createdAt")} desc)
    from ${q.statements} x where x.${s("account")} = v_account.${a("id")}
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_bank_statements")}(uuid)`)}

-- A bank account's transactions, newest first, with their matches. filter:
-- { status, since, until, limit (default 100, at most 500), offset }.
create or replace function ${fn("list_bank_transactions")}(account_id uuid, filter jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_account ${q.accounts}%rowtype;
  v_filter jsonb := coalesce(list_bank_transactions.filter, '{}'::jsonb);
begin${loadAccount("list_bank_transactions.account_id", q.read)}
  return coalesce((
    select jsonb_agg(${q.transactionJson("x")} order by x.${t("bookedOn")} desc, x.${t("createdAt")} desc, x.${t("id")})
    from (
      select * from ${q.transactions} y
      where y.${t("account")} = v_account.${a("id")}
        and (v_filter ->> 'status' is null or y.${t("status")} = v_filter ->> 'status')
        and (v_filter ->> 'since' is null or y.${t("bookedOn")} >= (v_filter ->> 'since')::date)
        and (v_filter ->> 'until' is null or y.${t("bookedOn")} <= (v_filter ->> 'until')::date)
      order by y.${t("bookedOn")} desc, y.${t("createdAt")} desc, y.${t("id")}
      limit ${pageSize("(v_filter ->> 'limit')::integer", 100, 500)}
      offset greatest(coalesce((v_filter ->> 'offset')::integer, 0), 0)
    ) x
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_bank_transactions")}(uuid, jsonb)`)}

create or replace function ${fn("get_bank_transaction")}(transaction_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${q.transactions}%rowtype;
begin
  select * into v_row from ${q.transactions} x where x.${t("id")} = get_bank_transaction.transaction_id;
  if not found then
    return null;
  end if;
  if not ${q.allowed(`v_row.${t("tenant")}`, q.read)} then
    ${q.forbidden("not allowed to read bank transactions")}
  end if;
  return ${q.transactionJson("v_row")};
end;
$$;
${userGrant(`${fn("get_bank_transaction")}(uuid)`)}

-- Where a bank account stands on a day: the closing balance of the last
-- statement up to it, the sum of the transactions up to it, how many are
-- still unmatched, and with accounting the balance of the account's journal
-- account in the bank's currency. reconciled: nothing unmatched and the
-- statement agrees with the books.
create or replace function ${fn("bank_reconciliation_status")}(account_id uuid, as_of date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_account ${q.accounts}%rowtype;
  v_statement ${q.statements}%rowtype;
  v_as_of date := coalesce(bank_reconciliation_status.as_of, current_date);
  v_total bigint;
  v_unmatched integer;
  v_unmatched_total bigint;
  v_ledger bigint;
begin${loadAccount("bank_reconciliation_status.account_id", q.read)}
  select * into v_statement from ${q.statements} x
  where x.${s("account")} = v_account.${a("id")} and x.${s("closingBalance")} is not null
    and coalesce(x.${s("untilOn")}, x.${s("createdAt")}::date) <= v_as_of
  order by coalesce(x.${s("untilOn")}, x.${s("createdAt")}::date) desc, x.${s("createdAt")} desc
  limit 1;
  select coalesce(sum(x.${t("amount")}), 0),
    count(*) filter (where x.${t("status")} = 'unmatched'),
    coalesce(sum(x.${t("amount")}) filter (where x.${t("status")} = 'unmatched'), 0)
  into v_total, v_unmatched, v_unmatched_total
  from ${q.transactions} x
  where x.${t("account")} = v_account.${a("id")} and x.${t("bookedOn")} <= v_as_of;
  v_ledger := ${ledgerBalance};
  return jsonb_build_object(
    'accountId', v_account.${a("id")},
    'asOf', v_as_of,
    'currency', v_account.${a("currency")},
    'statementId', v_statement.${s("id")},
    'statementBalance', v_statement.${s("closingBalance")}::text,
    'transactionTotal', v_total::text,
    'unmatchedCount', v_unmatched,
    'unmatchedTotal', v_unmatched_total::text,
    'ledgerBalance', v_ledger::text,
    'difference', (v_statement.${s("closingBalance")} - v_ledger)::text,
    'reconciled', v_unmatched = 0 and coalesce(v_statement.${s("closingBalance")} = v_ledger, true));
end;
$$;
${userGrant(`${fn("bank_reconciliation_status")}(uuid, date)`)}
`;
}
