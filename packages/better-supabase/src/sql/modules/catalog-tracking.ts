import type { BlockSqlContext } from "../context.ts";

/**
 * SQL that is true when variant row `alias` of `catalog` tracks inventory: its
 * own column, else its product's, else true.
 */
export function variantTracked(
  catalog: BlockSqlContext,
  alias: string,
): string {
  const v = (column: string): string => catalog.col("variants", column);
  const p = (column: string): string => catalog.col("products", column);

  if (catalog.has("variants", "trackInventory")) {
    return `${alias}.${v("trackInventory")}`;
  }

  return catalog.has("products", "trackInventory")
    ? `coalesce((select tp.${p("trackInventory")} from ${catalog.table("products")} tp where tp.${p("id")} = ${alias}.${v("product")}), true)`
    : "true";
}
