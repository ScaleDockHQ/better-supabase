import type { AccountingSource } from "../accounting-sources-sql.ts";
import type { BlockSqlContext } from "../context.ts";

/**
 * What donations books in accounting: each posted gift in the bank journal
 * (bank against donation revenue). A refund reverses the gift's entry.
 */
export function donationAccountingSources(
  ctx: BlockSqlContext,
): readonly AccountingSource[] {
  const donations = ctx.table("donations");
  const d = (column: string): string => ctx.col("donations", column);

  return [
    {
      source: "gift",
      journal: "bank",
      fn: "accounting_gift_lines",
      comment:
        "The entry of a posted gift for accounting: bank against donation revenue.",
      body: `  select jsonb_build_object(
    'organizationId', v.${d("tenant")},
    'entryDate', v.${d("receivedOn")},
    'currency', v.${d("currency")},
    'memo', 'Gift',
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'bank', 'debit', v.${d("amount")}::text),
      jsonb_build_object('role', 'revenue', 'credit', v.${d("amount")}::text, 'partyId', v.${d("donorId")}))
  )
  from ${donations} v
  where v.${d("id")}::text = source_id and v.${d("status")} = 'posted' and v.${d("amount")} <> 0`,
    },
  ];
}
