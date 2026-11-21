import type { AnyBlocksConfig } from "../config/blocks.ts";
import type { BlockSqlLayout } from "./module-types.ts";

import { trackColumnReads } from "./context.ts";
import { moduleBody } from "./render.ts";

/** A `blocks.<block>.columns` entry that no rendered statement reads. */
export interface UnusedColumn {
  readonly block: string;
  readonly table: string;
  readonly logical: string;
  readonly column: string;
}

/**
 * The columns a config maps to a name that the render of that block never
 * reads, so every feature that would use them is off. Each block renders on its
 * own, so one instance's reads never hide another's.
 */
export function unusedDeclaredColumns(
  layout: BlockSqlLayout & { readonly modules: AnyBlocksConfig },
): readonly UnusedColumn[] {
  const found: UnusedColumn[] = [];

  for (const [block, config] of Object.entries(layout.modules)) {
    if (config === undefined || "block" in config) {
      continue;
    }

    // SAFETY: `columns` maps logical tables to logical columns to a mapping.
    const columns = config.columns;

    if (columns === undefined) {
      continue;
    }

    const { reads } = trackColumnReads(() => moduleBody(block, layout));

    for (const [table, entries] of Object.entries(columns)) {
      for (const [logical, entry] of Object.entries(entries ?? {})) {
        const column = typeof entry === "object" ? entry?.column : entry;

        if (
          typeof column === "string" &&
          logical !== "tenant" &&
          !reads.has(`${table}.${logical}`)
        ) {
          found.push({ block, table, logical, column });
        }
      }
    }
  }

  return found;
}
