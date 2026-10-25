import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";

/**
 * A row of `table` as the API's JSON. On the app's table `to_jsonb` would
 * return the app's own names and its other columns, so the object names each
 * column the table has under the module's default name. `whole` is what
 * `to_jsonb` reads on the module's own table (`x.*` or the row variable).
 */
export function lifecycleJson(
  ctx: BlockSqlContext,
  table: string,
  row: string,
  whole: string = row,
): string {
  if (ctx.owns(table)) {
    return `to_jsonb(${whole})`;
  }

  const columns = ctx.names.tables[table]?.columns ?? {};

  return `jsonb_build_object(${Object.entries(columns)
    .filter(([logical]) => ctx.has(table, logical))
    .map(
      ([logical, name]) =>
        `${sqlString(name)}, ${row}.${ctx.col(table, logical)}`,
    )
    .join(", ")})`;
}

/** `value` as text where the app's column may have its own type. */
export const asText = (
  ctx: BlockSqlContext,
  table: string,
  value: string,
): string => (ctx.owns(table) ? value : `${value}::text`);
