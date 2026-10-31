import type { BlockSqlContext } from "../context.ts";

/**
 * The `discountMatrix` option of the invoice line setter: it prices catalog
 * lines for the invoice's company, else its contact, on the day the lines are
 * set. Empty while the block option is off.
 */
export function invoiceDiscountMatrix(
  ctx: BlockSqlContext,
  table: string,
  idColumn: string,
  partyColumns: readonly string[],
): {
  readonly discountMatrix?: { readonly party: string; readonly on: string };
} {
  if (!ctx.flag("discountMatrix", false)) {
    return {};
  }

  const parties =
    partyColumns.map((column) => `x.${column}`).join(", ") || "null";

  return {
    discountMatrix: {
      party: `(select coalesce(${parties}) from ${table} x where x.${idColumn} = v_parent)`,
      on: "current_date",
    },
  };
}
