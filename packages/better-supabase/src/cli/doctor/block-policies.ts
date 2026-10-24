import type { DoctorContext } from "./rules.ts";

import { adoptedTables } from "../../sql/index.ts";
import { appTablesOf } from "./app-tables.ts";

/** The prefix the render pass gives block policies on the app's tables. */
export const BLOCK_PREFIX = "bsb_";

/**
 * Whether permissive policies that overlap on `table` are one app policy and
 * one block policy on an app table a block runs over. BS347 reports the pair
 * when the block's condition is wider; otherwise the app's policy repeats it.
 */
export function appAndBlockPolicy(
  context: DoctorContext,
): (table: string, policies: readonly string[]) => boolean {
  const targets = new Set(
    adoptedTables(context.config.blocks, appTablesOf(context)).map(
      (table) => `${table.schema}.${table.table}`,
    ),
  );

  return (table, policies) =>
    targets.has(table) &&
    policies.length === 2 &&
    policies.filter((name) => name.startsWith(BLOCK_PREFIX)).length === 1;
}
