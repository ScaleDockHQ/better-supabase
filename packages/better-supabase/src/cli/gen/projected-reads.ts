import type { ResolvedConfig } from "../../config/index.ts";
import type { SchemaMeta } from "../../schema/types.ts";

import { blockTables } from "../../sql/index.ts";
import { projectionsOf } from "../powersync/projection.ts";

/**
 * The app's projection views over block tables, as the typed client sees them
 * (ADR 0421).
 */
export interface ProjectedReads {
  /**
   * The `db` keys of the views over a block table, by `schema.table` of the
   * table: a write to the table reaches every read served from one of them.
   */
  readonly viewKeys: ReadonlyMap<string, readonly string[]>;
  /**
   * The `db` keys of block tables a view projects. Clients read the view, so
   * `hooks.ts` writes none for these.
   */
  readonly baseKeys: ReadonlySet<string>;
}

export const NO_PROJECTED_READS: ProjectedReads = {
  viewKeys: new Map(),
  baseKeys: new Set(),
};

/**
 * Finds the views the app's schema files create over tables a block owns, and
 * the keys the typed client gives them. A view the typed client has no key for
 * (outside `config.schemas`) is left out.
 */
export function projectedReads(
  config: ResolvedConfig,
  meta: SchemaMeta,
  texts: readonly { readonly text: string }[],
): ProjectedReads {
  const projections = projectionsOf(texts);

  if (projections.size === 0 || config.blockNames.length === 0) {
    return NO_PROJECTED_READS;
  }

  const owned = new Set(
    Object.values(blockTables(config).byBlock).flatMap((tables) =>
      Object.values(tables).map((table) => table.table),
    ),
  );

  const keys = new Map(
    Object.values(meta.tables).map((table) => [
      `${table.schema}.${table.name}`,
      table.key,
    ]),
  );

  const viewKeys = new Map<string, readonly string[]>();
  const baseKeys = new Set<string>();

  for (const [base, projection] of projections) {
    const viewKey = keys.get(projection.view);

    if (!owned.has(base) || viewKey === undefined) {
      continue;
    }

    viewKeys.set(base, [...(viewKeys.get(base) ?? []), viewKey]);

    const baseKey = keys.get(base);

    if (baseKey !== undefined) {
      baseKeys.add(baseKey);
    }
  }

  return { viewKeys, baseKeys };
}
