import type { BlockSqlContext } from "../context.ts";

import { booksAccounting, unbookSource } from "../accounting-sources-sql.ts";
import { filterTreeSql } from "../filter-tree-sql.ts";
import { userGrant } from "../shared.ts";
import { batchSettle, hasBatches } from "./banking-batches.ts";
import {
  bankingSql,
  linked,
  MATCH_REFERENCE,
  UNMATCH_REFERENCE,
} from "./banking-sql.ts";

/** The match targets the installed blocks offer. */
function targets(ctx: BlockSqlContext): readonly string[] {
  const expenses = linked(ctx, "expenses");

  return [
    ...(linked(ctx, "invoices") ? ["invoice"] : []),
    ...(linked(ctx, "accounting") ? ["accounting_entry"] : []),
    ...(expenses?.hasTable("reports") ? ["expense_report"] : []),
    ...(hasBatches(ctx) ? ["payment_batch"] : []),
  ];
}

/**
 * The SQL that settles one match row `v_match` of transaction `v_row`, or
 * undoes it when `undo` is set: an invoice payment (a refund to undo), an
 * expense report reimbursed, or a posted entry linked.
 */
function settle(ctx: BlockSqlContext, undo: boolean): string {
  const q = bankingSql(ctx);
  const { m, t } = q;
  const branches: string[] = [];
  const invoices = linked(ctx, "invoices");
  const accounting = linked(ctx, "accounting");
  const expenses = linked(ctx, "expenses");

  if (invoices) {
    const i = (column: string): string => invoices.col("invoices", column);

    const purchase = invoices.has("invoices", "direction")
      ? `case when v_invoice.${i("direction")} = 'purchase' then -1 else 1 end`
      : "1";

    branches.push(`if v_match.${m("targetType")} = 'invoice' then
      select * into v_invoice from ${invoices.table("invoices")} x
      where x.${i("id")} = v_match.${m("targetId")} and x.${i("tenant")} = v_row.${t("tenant")};
      if not found then
        ${q.matchInvalid("no such invoice in the organization")}
      end if;
      perform ${invoices.fn("record_invoice_payment")}(v_invoice.${i("id")}, ${undo ? "-" : ""}v_match.${m("amount")} * ${purchase},
        v_row.${t("currency")}, ${undo ? "now()" : `v_row.${t("bookedOn")}::timestamptz`}, 'bank_transfer',
        '${undo ? UNMATCH_REFERENCE : MATCH_REFERENCE}' || v_match.${m("id")}::text,
        ${undo ? "'Bank match undone'" : `left(v_row.${t("remittance")}, 500)`});`);
  }

  if (accounting && !undo) {
    const e = (column: string): string => accounting.col("entries", column);

    branches.push(`if v_match.${m("targetType")} = 'accounting_entry' then
      if not exists (
        select 1 from ${accounting.table("entries")} x
        where x.${e("id")} = v_match.${m("targetId")} and x.${e("tenant")} = v_row.${t("tenant")} and x.${e("status")} = 'posted'
      ) then
        ${q.matchInvalid("no such posted accounting entry in the organization")}
      end if;`);
  }

  if (expenses?.hasTable("reports") && !undo) {
    const r = (column: string): string => expenses.col("reports", column);

    branches.push(`if v_match.${m("targetType")} = 'expense_report' then
      select x.${r("reimbursedAt")}, x.${r("currency")} into v_reimbursed, v_currency from ${expenses.table("reports")} x
      where x.${r("id")} = v_match.${m("targetId")} and x.${r("tenant")} = v_row.${t("tenant")};
      if not found or v_currency <> v_row.${t("currency")} then
        ${q.matchInvalid("no such expense report in the organization and currency")}
      end if;
      if v_reimbursed is null then
        perform ${expenses.fn("reimburse_expense_report")}(v_match.${m("targetId")}, v_row.${t("bookedOn")}::timestamptz,
          '${MATCH_REFERENCE}' || v_match.${m("id")}::text);
      end if;`);
  }

  if (hasBatches(ctx)) {
    branches.push(batchSettle(ctx, undo));
  }

  return branches.length === 0
    ? ""
    : `
    ${branches.map((branch, index) => (index === 0 ? branch : branch.replace(/^if /, "elsif "))).join("\n    ")}
    end if;`;
}

/** Suggestions, matching, unmatching, ignoring and the bank rules. */
export function bankingMatching(ctx: BlockSqlContext): string {
  const q = bankingSql(ctx);
  const { m, r, t } = q;
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const invoices = linked(ctx, "invoices");
  const accounting = linked(ctx, "accounting");
  const books = booksAccounting(ctx);
  const allowed = targets(ctx);

  const loadTransaction = (arg: string, lock: boolean) => `
  select * into v_row from ${q.transactions} x where x.${t("id")} = ${arg}${lock ? " for update" : ""};
  if not found then
    ${q.transactionMissing}
  end if;
  if not ${q.allowed(`v_row.${t("tenant")}`, q.reconcile)} then
    ${q.forbidden("not allowed to reconcile bank transactions")}
  end if;`;

  const declares = [
    "v_row %T%rowtype;",
    "v_match %M%rowtype;",
    ...(invoices ? [`v_invoice ${invoices.table("invoices")}%rowtype;`] : []),
    "v_reimbursed timestamptz;",
    "v_currency text;",
    ...(hasBatches(ctx)
      ? [`v_batch ${ctx.table("batches")}%rowtype;`, "v_group record;"]
      : []),
  ]
    .join("\n  ")
    .replace("%T", q.transactions)
    .replace("%M", q.matches);

  const suggestions = invoices
    ? (() => {
        const i = (column: string): string => invoices.col("invoices", column);

        const has = (column: string): boolean =>
          invoices.has("invoices", column);

        const balance = `(x.${i("total")} - x.${i("creditedTotal")} - x.${i("paidTotal")})`;

        const direction = has("direction")
          ? `x.${i("direction")} = case when v_row.${t("amount")} < 0 then 'purchase' else 'sales' end`
          : `v_row.${t("amount")} > 0`;

        const key = has("identifier")
          ? `upper(regexp_replace(coalesce(x.${i("identifier")}, ''), '[^A-Za-z0-9]', '', 'g'))`
          : "''";

        const party = ["companyId", "contactId"].filter(has);

        const sameParty =
          party.length === 0
            ? "false"
            : `exists (
          select 1 from ${q.matches} y
          join ${q.transactions} z on z.${t("id")} = y.${m("transaction")}
          join ${invoices.table("invoices")} w on w.${i("id")} = y.${m("targetId")}
          where y.${m("targetType")} = 'invoice' and z.${t("tenant")} = v_row.${t("tenant")}
            and z.${t("counterpartyIban")} = v_row.${t("counterpartyIban")} and z.${t("id")} <> v_row.${t("id")}
            and (${party.map((column) => `(w.${i(column)} is not null and w.${i(column)} = c.${i(column)})`).join(" or ")}))`;

        return `
  return coalesce((
    select jsonb_agg(jsonb_build_object('targetType', 'invoice', 'targetId', s.id, 'label', s.label,
      'balance', s.balance::text, 'currency', s.currency, 'score', s.score, 'reasons', to_jsonb(s.reasons))
      order by s.score desc, s.due_on nulls last, s.id)
    from (
      select c.${i("id")} as id, ${has("identifier") ? `coalesce(c.${i("identifier")}, c.${i("title")})` : `c.${i("title")}`} as label,
        c.balance, c.${i("currency")} as currency, c.${i("dueOn")} as due_on,
        array_remove(array[
          case when v_ref is not null and length(c.key) > 0 and (v_ref = c.key or v_ref = nullif(ltrim(regexp_replace(c.key, '[^0-9]', '', 'g'), '0'), '')) then 'reference' end,
          case when length(c.key) >= 4 and position(c.key in v_text) > 0 then 'remittance' end,
          case when c.balance = abs(v_row.${t("amount")}) then 'amount' end,
          case when v_row.${t("counterpartyIban")} is not null and ${sameParty} then 'counterparty' end
        ], null) as reasons,
        (case when v_ref is not null and length(c.key) > 0 and (v_ref = c.key or v_ref = nullif(ltrim(regexp_replace(c.key, '[^0-9]', '', 'g'), '0'), '')) then 100 else 0 end
          + case when length(c.key) >= 4 and position(c.key in v_text) > 0 then 80 else 0 end
          + case when c.balance = abs(v_row.${t("amount")}) then 30 else 0 end
          + case when v_row.${t("counterpartyIban")} is not null and ${sameParty} then 20 else 0 end) as score
      from (
        select x.*, ${balance} as balance, ${key} as key
        from ${invoices.table("invoices")} x
        where x.${i("tenant")} = v_row.${t("tenant")} and x.${i("currency")} = v_row.${t("currency")}
          and ${invoices.is("invoices", "kind", `x.${i("kind")}`, ["invoice"])}
          and ${invoices.is("invoices", "status", `x.${i("status")}`, ["issued", "partially_paid"])}
          and ${direction}
      ) c
    ) s
    where s.score >= 30
    limit 10
  ), '[]'::jsonb);`;
      })()
    : `
  return '[]'::jsonb;`;

  const postRule =
    books && accounting
      ? `
      if v_rule.${r("account")} is not null then
        update ${q.transactions} x set ${t("status")} = 'matched', ${t("rule")} = v_rule.${r("id")},
          ${t("matchedAt")} = now(), ${t("matchedBy")} = auth.uid(), ${t("updatedAt")} = now()
        where x.${t("id")} = v_row.${t("id")}
        returning * into v_row;
        v_entry := ${accounting.fn("accounting_post_source")}('bank_transaction', v_row.${t("id")}::text);
        if v_entry is not null then
          insert into ${q.matches} (${m("tenant")}, ${m("transaction")}, ${m("targetType")}, ${m("targetId")}, ${m("amount")}, ${m("createdBy")})
          values (v_row.${t("tenant")}, v_row.${t("id")}, 'accounting_entry', v_entry, v_row.${t("amount")}, auth.uid());
        end if;
        ${q.recordTransaction("bank_transaction.matched", "v_row", "matched a bank transaction by rule", `, 'matches', ${q.matchesOf("v_row")}, 'ruleId', v_rule.${r("id")}`)}
        v_matched := v_matched + 1;
        continue;
      end if;`
      : "";

  const ruleAccountCheck = accounting
    ? `
  if v_account is not null and not exists (
    select 1 from ${accounting.table("accounts")} y
    where y.${accounting.col("accounts", "id")} = v_account and y.${accounting.col("accounts", "tenant")} = v_tenant
  ) then
    ${q.ruleInvalid("the rule's account must be an accounting account of the organization")}
  end if;`
    : `
  if v_account is not null then
    ${q.ruleInvalid("a rule books to an account only with the accounting block")}
  end if;`;

  return `${filterTreeSql({
    fn: fn("bank_rule_condition"),
    comment:
      "Matches a bank rule's filter tree against a transaction's fields (ADR 0046).",
    invalid: q.ruleInvalid(
      "conditions must be a filter tree of known operators",
    ),
  })}
-- Invoices a transaction may pay, best first: the structured reference names
-- the invoice (an RF creditor reference or a Dutch betalingskenmerk, checked),
-- the remittance carries its identifier, the open balance equals the amount,
-- or the counterparty's IBAN paid the same company or contact before.
create or replace function ${fn("suggest_bank_matches")}(transaction_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${q.transactions}%rowtype;
  v_ref text;
  v_text text;
begin
  select * into v_row from ${q.transactions} x where x.${t("id")} = suggest_bank_matches.transaction_id;
  if not found then
    ${q.transactionMissing}
  end if;
  if not ${q.allowed(`v_row.${t("tenant")}`, q.read)} then
    ${q.forbidden("not allowed to read bank transactions")}
  end if;
  v_ref := coalesce(${fn("bank_reference")}(v_row.${t("structuredReference")}),
    nullif(upper(regexp_replace(coalesce(v_row.${t("structuredReference")}, ''), '[^A-Za-z0-9]', '', 'g')), ''));
  v_text := upper(regexp_replace(concat_ws(' ', v_row.${t("remittance")}, v_row.${t("structuredReference")}), '[^A-Za-z0-9]', '', 'g'));${suggestions}
end;
$$;
${userGrant(`${fn("suggest_bank_matches")}(uuid)`)}

-- Matches an unmatched transaction: matches is [{ targetType, targetId,
-- amount }], amounts signed like the transaction in minor units, summing to
-- it (one match without an amount takes all of it). An invoice records a
-- payment (a refund for a purchase invoice paid out), an expense report is
-- reimbursed when it isn't yet, and an accounting entry is linked.
create or replace function ${fn("match_bank_transaction")}(transaction_id uuid, matches jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  ${declares}
  v_item jsonb;
  v_amount bigint;
  v_sum bigint := 0;
begin${loadTransaction("match_bank_transaction.transaction_id", true)}
  if v_row.${t("status")} <> 'unmatched' then
    ${q.statusInvalid("v_row", "matched")}
  end if;
  if jsonb_typeof(match_bank_transaction.matches) is distinct from 'array' or jsonb_array_length(match_bank_transaction.matches) = 0 then
    ${q.matchInvalid("matches is a non-empty array")}
  end if;
  ${ctx.hook("before_bank_transaction_match", [
    ["uuid", `v_row.${t("id")}`],
    ["jsonb", "match_bank_transaction.matches"],
  ])}
  for v_item in select value from jsonb_array_elements(match_bank_transaction.matches) loop
    if coalesce(v_item ->> 'targetType', '') not in (${allowed.length === 0 ? "''" : allowed.map((target) => `'${target}'`).join(", ")})
      or coalesce(v_item ->> 'targetId', '') !~ '^[0-9a-fA-F-]{36}$'
      or coalesce(v_item ->> 'amount', '0') !~ '^-?[0-9]{1,18}$' then
      ${q.matchInvalid(`a match has a targetType (${allowed.join(", ") || "none installed"}), a targetId and an integer amount`)}
    end if;
    v_amount := coalesce((v_item ->> 'amount')::bigint,
      case when jsonb_array_length(match_bank_transaction.matches) = 1 then v_row.${t("amount")} end);
    if v_amount is null or v_amount = 0 or sign(v_amount) <> sign(v_row.${t("amount")}) then
      ${q.matchInvalid("a match's amount is nonzero and has the transaction's sign")}
    end if;
    v_sum := v_sum + v_amount;
    insert into ${q.matches} (${m("tenant")}, ${m("transaction")}, ${m("targetType")}, ${m("targetId")}, ${m("amount")}, ${m("createdBy")})
    values (v_row.${t("tenant")}, v_row.${t("id")}, v_item ->> 'targetType', (v_item ->> 'targetId')::uuid, v_amount, auth.uid())
    returning * into v_match;${settle(ctx, false)}
  end loop;
  if v_sum <> v_row.${t("amount")} then
    ${q.matchInvalid("the matches must add up to the transaction's amount")}
  end if;
  update ${q.transactions} x set ${t("status")} = 'matched', ${t("matchedAt")} = now(), ${t("matchedBy")} = auth.uid(), ${t("updatedAt")} = now()
  where x.${t("id")} = v_row.${t("id")}
  returning * into v_row;
  ${q.recordTransaction("bank_transaction.matched", "v_row", "matched a bank transaction", `, 'matches', ${q.matchesOf("v_row")}, 'ruleId', null`)}
  ${ctx.hook("after_bank_transaction_match", [["uuid", `v_row.${t("id")}`]])}
  return ${q.transactionJson("v_row")};
end;
$$;
${userGrant(`${fn("match_bank_transaction")}(uuid, jsonb)`)}

-- Undoes a match: an invoice payment is refunded, a rule's entry is reversed,
-- and the transaction is unmatched again. A reimbursed expense report stays
-- reimbursed.
create or replace function ${fn("unmatch_bank_transaction")}(transaction_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  ${declares}
begin${loadTransaction("unmatch_bank_transaction.transaction_id", true)}
  if v_row.${t("status")} <> 'matched' then
    ${q.statusInvalid("v_row", "unmatched")}
  end if;
  for v_match in select * from ${q.matches} y where y.${m("transaction")} = v_row.${t("id")} order by y.${m("createdAt")}, y.${m("id")} loop${settle(ctx, true)}
  end loop;
  if v_row.${t("rule")} is not null then
    ${unbookSource(ctx, "bank_transaction", `v_row.${t("tenant")}`, `v_row.${t("id")}`) || "null;"}
  end if;
  delete from ${q.matches} y where y.${m("transaction")} = v_row.${t("id")};
  update ${q.transactions} x set ${t("status")} = 'unmatched', ${t("rule")} = null, ${t("matchedAt")} = null,
    ${t("matchedBy")} = null, ${t("updatedAt")} = now()
  where x.${t("id")} = v_row.${t("id")}
  returning * into v_row;
  ${q.recordTransaction("bank_transaction.unmatched", "v_row", "unmatched a bank transaction")}
  return ${q.transactionJson("v_row")};
end;
$$;
${userGrant(`${fn("unmatch_bank_transaction")}(uuid)`)}

-- Sets an unmatched transaction aside (a transfer between own accounts, a
-- duplicate), or with ignored false brings it back.
create or replace function ${fn("ignore_bank_transaction")}(transaction_id uuid, ignored boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${q.transactions}%rowtype;
begin${loadTransaction("ignore_bank_transaction.transaction_id", true)}
  if v_row.${t("status")} <> (case when ignore_bank_transaction.ignored then 'unmatched' else 'ignored' end) then
    ${q.statusInvalid("v_row", "ignored")}
  end if;
  update ${q.transactions} x set
    ${t("status")} = case when ignore_bank_transaction.ignored then 'ignored' else 'unmatched' end,
    ${t("rule")} = null, ${t("updatedAt")} = now()
  where x.${t("id")} = v_row.${t("id")}
  returning * into v_row;
  return ${q.transactionJson("v_row")};
end;
$$;
${userGrant(`${fn("ignore_bank_transaction")}(uuid, boolean)`)}

-- Creates or updates a bank rule: { name, conditions (a filter tree over the
-- transaction), accountId, partyId, dimensions, priority, active }. A rule
-- with an account books the transactions it matches there; one without sets
-- them aside.
create or replace function ${fn("save_bank_rule")}(tenant ${idType}, input jsonb, rule_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_rule ${q.rules}%rowtype;
  v_tenant ${idType} := save_bank_rule.tenant;
  v_conditions jsonb;
  v_account uuid;
begin
  if not ${q.allowed("save_bank_rule.tenant", q.manage)} then
    ${q.forbidden("not allowed to manage bank rules")}
  end if;
  if jsonb_typeof(save_bank_rule.input) is distinct from 'object' then
    ${q.ruleInvalid("input must be an object")}
  end if;
  if save_bank_rule.rule_id is not null then
    select * into v_rule from ${q.rules} x
    where x.${r("id")} = save_bank_rule.rule_id and x.${r("tenant")} = save_bank_rule.tenant
    for update;
    if not found then
      ${q.ruleMissing}
    end if;
  end if;
  v_conditions := coalesce(save_bank_rule.input -> 'conditions', v_rule.${r("conditions")}, '{"type":"group","combinator":"and","rules":[]}'::jsonb);
  perform ${fn("bank_rule_condition")}(v_conditions, '{}'::jsonb);
  v_account := case when save_bank_rule.input ? 'accountId'
    then nullif(save_bank_rule.input ->> 'accountId', '')::uuid
    else v_rule.${r("account")} end;${ruleAccountCheck}
  if v_rule.${r("id")} is null then
    insert into ${q.rules} (${r("tenant")}, ${r("name")}, ${r("conditions")}, ${r("account")}, ${r("party")}, ${r("dimensions")}, ${r("priority")}, ${r("active")})
    values (save_bank_rule.tenant, trim(save_bank_rule.input ->> 'name'), v_conditions, v_account,
      nullif(save_bank_rule.input ->> 'partyId', '')::uuid,
      coalesce(save_bank_rule.input -> 'dimensions', '{}'::jsonb),
      coalesce((save_bank_rule.input ->> 'priority')::integer, 100),
      coalesce((save_bank_rule.input ->> 'active')::boolean, true))
    returning * into v_rule;
  else
    update ${q.rules} x set
      ${r("name")} = coalesce(trim(save_bank_rule.input ->> 'name'), x.${r("name")}),
      ${r("conditions")} = v_conditions,
      ${r("account")} = v_account,
      ${r("party")} = case when save_bank_rule.input ? 'partyId' then nullif(save_bank_rule.input ->> 'partyId', '')::uuid else x.${r("party")} end,
      ${r("dimensions")} = coalesce(save_bank_rule.input -> 'dimensions', x.${r("dimensions")}),
      ${r("priority")} = coalesce((save_bank_rule.input ->> 'priority')::integer, x.${r("priority")}),
      ${r("active")} = coalesce((save_bank_rule.input ->> 'active')::boolean, x.${r("active")}),
      ${r("updatedAt")} = now()
    where x.${r("id")} = v_rule.${r("id")}
    returning * into v_rule;
  end if;
  return ${q.ruleJson("v_rule")};
exception
  when check_violation or not_null_violation then
    ${q.ruleInvalid("a rule has a name of 1 to 200 characters, an object of dimensions and a priority")}
  when invalid_text_representation or numeric_value_out_of_range then
    ${q.ruleInvalid("accountId and partyId are uuids, priority an integer and active a boolean")}
end;
$$;
${userGrant(`${fn("save_bank_rule")}(${idType}, jsonb, uuid)`)}

create or replace function ${fn("list_bank_rules")}(tenant ${idType})
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${q.allowed("list_bank_rules.tenant", q.read)} then
    ${q.forbidden("not allowed to read bank rules")}
  end if;
  return coalesce((
    select jsonb_agg(${q.ruleJson("x")} order by x.${r("priority")}, x.${r("createdAt")}, x.${r("id")})
    from ${q.rules} x where x.${r("tenant")} = list_bank_rules.tenant
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_bank_rules")}(${idType})`)}

-- Deletes a bank rule. Transactions it matched keep their entries and lose
-- the link to the rule.
create or replace function ${fn("delete_bank_rule")}(rule_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_rule ${q.rules}%rowtype;
begin
  select * into v_rule from ${q.rules} x where x.${r("id")} = delete_bank_rule.rule_id for update;
  if not found then
    ${q.ruleMissing}
  end if;
  if not ${q.allowed(`v_rule.${r("tenant")}`, q.manage)} then
    ${q.forbidden("not allowed to manage bank rules")}
  end if;
  delete from ${q.rules} x where x.${r("id")} = v_rule.${r("id")};
end;
$$;
${userGrant(`${fn("delete_bank_rule")}(uuid)`)}

-- Runs the active bank rules over a bank account's unmatched transactions,
-- lowest priority first, the first matching rule winning: a rule with an
-- account books the transaction${books ? "" : " (with the accounting block)"}, one without sets it aside.
create or replace function ${fn("apply_bank_rules")}(account_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_account ${q.accounts}%rowtype;
  v_row ${q.transactions}%rowtype;
  v_rule ${q.rules}%rowtype;
  v_entry uuid;
  v_matched integer := 0;
  v_ignored integer := 0;
begin
  select * into v_account from ${q.accounts} x where x.${q.a("id")} = apply_bank_rules.account_id;
  if not found then
    ${q.accountMissing}
  end if;
  if not ${q.allowed(`v_account.${q.a("tenant")}`, q.reconcile)} then
    ${q.forbidden("not allowed to reconcile bank transactions")}
  end if;
  for v_row in
    select * from ${q.transactions} x
    where x.${t("account")} = v_account.${q.a("id")} and x.${t("status")} = 'unmatched'
    order by x.${t("bookedOn")}, x.${t("createdAt")}
    for update skip locked
  loop
    select * into v_rule from ${q.rules} y
    where y.${r("tenant")} = v_row.${t("tenant")} and y.${r("active")}
      and ${fn("bank_rule_condition")}(y.${r("conditions")}, ${q.conditionPayload("v_row")})
    order by y.${r("priority")}, y.${r("createdAt")}, y.${r("id")}
    limit 1;
    if v_rule.${r("id")} is not null then${postRule}
      update ${q.transactions} x set ${t("status")} = 'ignored', ${t("rule")} = v_rule.${r("id")}, ${t("updatedAt")} = now()
      where x.${t("id")} = v_row.${t("id")};
      v_ignored := v_ignored + 1;
    end if;
  end loop;
  return jsonb_build_object('matched', v_matched, 'ignored', v_ignored);
end;
$$;
${userGrant(`${fn("apply_bank_rules")}(uuid)`)}
`;
}
