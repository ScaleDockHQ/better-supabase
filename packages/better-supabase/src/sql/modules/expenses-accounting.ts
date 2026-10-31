import type { AccountingSource } from "../accounting-sources-sql.ts";
import type { BlockSqlContext } from "../context.ts";

import { expensesStandalone } from "./expenses-standalone.ts";

/**
 * What expenses books in accounting: an approved report in the purchase journal
 * (expense, with the dimensions of its lines, against payable to the member)
 * and its reimbursement in the bank journal (payable against bank). Standalone
 * expenses book nothing.
 */
export function expenseAccountingSources(
  ctx: BlockSqlContext,
): readonly AccountingSource[] {
  if (expensesStandalone(ctx)) {
    return [];
  }

  const reports = ctx.table("reports");
  const lines = ctx.table("lines");
  const r = (column: string): string => ctx.col("reports", column);
  const x = (column: string): string => ctx.col("lines", column);
  const total = `(select coalesce(sum(y.${x("amount")}), 0) from ${lines} y where y.${x("report")} = v.${r("id")})`;

  // One expense line per set of line dimensions, or the total without them.
  const expenseLines = ctx.has("lines", "dimensions")
    ? `coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('role', 'expense', 'debit', g.amount::text, 'description', v.${r("title")}, 'dimensions', nullif(g.dim, '{}'::jsonb))) order by g.dim::text)
        from (select coalesce(y.${x("dimensions")}, '{}'::jsonb) as dim, sum(y.${x("amount")}) as amount from ${lines} y where y.${x("report")} = v.${r("id")} group by 1) g),
      jsonb_build_array(jsonb_build_object('role', 'expense', 'debit', ${total}::text, 'description', v.${r("title")})))`
    : `jsonb_build_array(jsonb_build_object('role', 'expense', 'debit', ${total}::text, 'description', v.${r("title")}))`;

  const entry = (date: string, memo: string, entryLines: string): string =>
    `  select jsonb_build_object(
    'organizationId', v.${r("tenant")},
    'entryDate', (${date} at time zone 'UTC')::date,
    'currency', v.${r("currency")},
    'reference', left(v.${r("id")}::text, 8),
    'memo', left(${memo} || v.${r("title")}, 500),
    'lines', ${entryLines}
  )
  from ${reports} v
  where v.${r("id")}::text = source_id and v.${r("cancelledAt")} is null`;

  return [
    {
      source: "expense_report",
      journal: "purchase",
      fn: "accounting_expense_report_lines",
      comment:
        "The entry of an approved expense report for accounting: its lines as\nexpenses (one per set of line dimensions), owed to the member.",
      body: `${entry(
        `v.${r("approvedAt")}`,
        "'Expenses: '",
        `${expenseLines}
      || jsonb_build_array(jsonb_build_object('role', 'payable', 'credit', ${total}::text, 'partyId', v.${r("user")}::text))`,
      )} and v.${r("approvedAt")} is not null`,
    },
    {
      source: "expense_reimbursement",
      journal: "bank",
      fn: "accounting_expense_reimbursement_lines",
      comment:
        "The entry of a reimbursed expense report for accounting: the payable to the\nmember settled from the bank.",
      body: `${entry(
        `v.${r("reimbursedAt")}`,
        "'Reimbursed: '",
        `jsonb_build_array(
      jsonb_build_object('role', 'payable', 'debit', ${total}::text, 'partyId', v.${r("user")}::text),
      jsonb_build_object('role', 'bank', 'credit', ${total}::text))`,
      )} and v.${r("reimbursedAt")} is not null`,
    },
  ];
}
