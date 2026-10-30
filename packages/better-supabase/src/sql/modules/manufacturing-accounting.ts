import type { AccountingSource } from "../accounting-sources-sql.ts";
import type { BlockSqlContext } from "../context.ts";

/**
 * What manufacturing books in accounting: a completed production order's labor,
 * in the general journal, debited to work in progress and credited to expense.
 * The components and the output book through the inventory block's stock
 * movements, which move their value through work in progress too.
 */
export function manufacturingAccountingSources(
  ctx: BlockSqlContext,
): readonly AccountingSource[] {
  const po = (column: string): string => ctx.col("orders", column);

  return [
    {
      source: "production_order",
      journal: "general",
      fn: "accounting_production_order_lines",
      comment:
        "The entry of a completed production order's labor for accounting: work in\nprogress against expense.",
      body: `  select jsonb_build_object(
    'organizationId', x.${po("tenant")},
    'entryDate', (x.${po("completedAt")} at time zone 'UTC')::date,
    'currency', x.${po("currency")},
    'reference', x.${po("number")},
    'memo', 'Production labor ' || x.${po("number")},
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'work_in_progress', 'debit', x.${po("laborCost")}::text),
      jsonb_build_object('role', 'expense', 'credit', x.${po("laborCost")}::text))
  )
  from ${ctx.table("orders")} x
  where x.${po("id")}::text = source_id and x.${po("status")} = 'done' and x.${po("laborCost")} > 0`,
    },
  ];
}
