import type { AccountingSource } from "../accounting-sources-sql.ts";
import type { BlockSqlContext } from "../context.ts";

/**
 * What banking books in accounting: a transaction a bank rule matched, in the
 * bank account's journal, between the journal's account (or the bank role) and
 * the rule's account, with the rule's party and dimensions. Transactions
 * matched to invoices book through the invoice payment instead.
 */
export function bankingAccountingSources(
  ctx: BlockSqlContext,
): readonly AccountingSource[] {
  const a = (column: string): string => ctx.col("accounts", column);
  const t = (column: string): string => ctx.col("transactions", column);
  const r = (column: string): string => ctx.col("rules", column);
  const accounting = ctx.of("accounting");
  const j = (column: string): string => accounting.col("journals", column);

  const bank = `case when w.${j("defaultAccount")} is not null
        then jsonb_build_object('accountId', w.${j("defaultAccount")})
        else jsonb_build_object('role', 'bank') end`;

  const other = `jsonb_strip_nulls(jsonb_build_object('accountId', y.${r("account")}, 'partyId', y.${r("party")}, 'dimensions', y.${r("dimensions")}, 'description', y.${r("name")}))`;

  return [
    {
      source: "bank_transaction",
      journal: "bank",
      fn: "accounting_bank_transaction_lines",
      comment:
        "The entry of a bank transaction a rule matched: the bank account against\nthe rule's account.",
      body: `  select jsonb_build_object(
    'organizationId', x.${t("tenant")},
    'entryDate', x.${t("bookedOn")},
    'journalId', z.${a("journal")},
    'currency', x.${t("currency")},
    'reference', left(coalesce(x.${t("endToEndId")}, x.${t("externalId")}), 200),
    'memo', left(coalesce(x.${t("remittance")}, x.${t("counterpartyName")}, y.${r("name")}), 2000),
    'lines', case when x.${t("amount")} > 0
      then jsonb_build_array(
        ${bank} || jsonb_build_object('debit', x.${t("amount")}::text),
        ${other} || jsonb_build_object('credit', x.${t("amount")}::text))
      else jsonb_build_array(
        ${other} || jsonb_build_object('debit', (-x.${t("amount")})::text),
        ${bank} || jsonb_build_object('credit', (-x.${t("amount")})::text))
      end
  )
  from ${ctx.table("transactions")} x
  join ${ctx.table("accounts")} z on z.${a("id")} = x.${t("account")}
  join ${ctx.table("rules")} y on y.${r("id")} = x.${t("rule")}
  left join ${accounting.table("journals")} w on w.${j("id")} = z.${a("journal")}
  where x.${t("id")}::text = source_id and x.${t("status")} = 'matched' and y.${r("account")} is not null`,
    },
  ];
}
