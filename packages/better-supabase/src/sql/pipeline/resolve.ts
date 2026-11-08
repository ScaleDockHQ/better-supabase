import type { BlockSqlContext } from "../context.ts";
import type { BlockSqlLayout, BlockSql } from "../module-types.ts";

import { canBeAppTable } from "../app-owned.ts";

/**
 * The app's tables (`layout.ownTables`) that `module` names but can't run over
 * (no `app` in their spec, or `onlyWhenMapped` and unmapped), as
 * `schema.table`.
 */
export function ownTablesCreatedBy(
  module: BlockSql,
  ctx: BlockSqlContext,
  layout: BlockSqlLayout,
): ReadonlySet<string> {
  const { ownTables } = layout;

  if (!ctx.manages || ownTables === undefined) {
    return new Set();
  }

  return new Set(
    Object.entries(module.names?.tables ?? {})
      .filter(
        ([logical, spec]) =>
          ctx.config.tables[logical] !== null &&
          !canBeAppTable(spec, ctx.config.tables[logical]),
      )
      .map(([logical]) => {
        const parts = ctx.tableName(logical);

        return `${parts.schema}.${parts.name}`;
      })
      .filter((table) => Object.hasOwn(ownTables, table)),
  );
}

/** The app's tables a module runs over, as `schema.table`. */
export function appTableSet(
  ctx: BlockSqlContext,
  tables: readonly string[] = ctx.appOwned,
): Set<string> {
  return new Set(
    ctx.manages
      ? tables.map((table) => {
          const parts = ctx.tableName(table);

          return `${parts.schema}.${parts.name}`;
        })
      : [],
  );
}
