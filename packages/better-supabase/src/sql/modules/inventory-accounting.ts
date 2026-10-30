import type { AccountingSource } from "../accounting-sources-sql.ts";
import type { BlockSqlContext } from "../context.ts";

import { columns } from "./inventory-stock.ts";

/**
 * What inventory books in accounting: a stock movement that moves value under
 * weighted average cost, in the general journal. The inventory account takes
 * the value; a receipt owes it to the supplier, a sale or return moves it to
 * cost of goods sold, production consumption and output to work in progress,
 * and an adjustment to expense. Transfers and movements without costing book
 * nothing.
 */
export function inventoryAccountingSources(
  ctx: BlockSqlContext,
): readonly AccountingSource[] {
  const ledger = ctx.of("ledger");
  const tx = columns(ledger, "transactions");
  const le = columns(ledger, "entries");
  const la = columns(ledger, "accounts");

  return [
    {
      source: "stock_movement",
      journal: "general",
      fn: "accounting_stock_movement_lines",
      comment:
        "The entry of a stock movement's value for accounting: inventory against the\nsupplier, cost of goods sold or expense.",
      body: `  select jsonb_build_object(
    'organizationId', y.${tx("tenant")},
    'entryDate', (y.${tx("effectiveAt")} at time zone 'UTC')::date,
    'currency', a.${la("unit")},
    'reference', y.${tx("referenceId")},
    'memo', 'Stock ' || (y.${tx("metadata")} ->> 'reason'),
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'inventory', 'debit', e.${le("amount")}::text),
      jsonb_build_object('role', case y.${tx("metadata")} ->> 'reason' when 'receipt' then 'payable' when 'sale' then 'cogs' when 'return' then 'cogs'
        when 'consumption' then 'work_in_progress' when 'production' then 'work_in_progress' else 'expense' end,
        'credit', e.${le("amount")}::text))
  )
  from ${ledger.table("transactions")} y
  join ${ledger.table("entries")} e on e.${le("transaction")} = y.${tx("id")}
  join ${ledger.table("accounts")} a on a.${la("id")} = e.${le("account")} and a.${la("kind")} = 'stock_value'
  where y.${tx("id")}::text = source_id and e.${le("amount")} <> 0
  limit 1`,
    },
  ];
}
