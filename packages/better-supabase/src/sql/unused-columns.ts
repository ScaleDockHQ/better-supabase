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
  /**
   * What turns the feature on: `tables.<table>: null` when the config switched
   * the table off, the boolean option whose `true` makes the render read the
   * column, or `no option found`.
   */
  readonly gating: string;
}

const NO_OPTION = "no option found";

/** The first off option that, set to `true`, makes the block read `key`. */
function gatingOption(
  block: string,
  layout: BlockSqlLayout & { readonly modules: AnyBlocksConfig },
  offFlags: ReadonlySet<string>,
  key: string,
): string {
  const config = layout.modules[block];

  for (const flag of [...offFlags].toSorted((a, b) => a.localeCompare(b))) {
    try {
      const { reads } = trackColumnReads(() =>
        moduleBody(block, {
          ...layout,
          modules: {
            ...layout.modules,
            // SAFETY: the probe sets one boolean option the module read.
            [block]: {
              ...config,
              options: {
                // SAFETY: `options` is a record when the config has one.
                ...(config as { options?: Record<string, unknown> }).options,
                [flag]: true,
              },
            },
          },
        }),
      );

      if (reads.has(key)) {
        return `options.${flag}`;
      }
    } catch {
      // The option needs another one to render; try the next.
    }
  }

  return NO_OPTION;
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

    const { reads, offFlags } = trackColumnReads(() =>
      moduleBody(block, layout),
    );

    for (const [table, entries] of Object.entries(columns)) {
      for (const [logical, entry] of Object.entries(entries ?? {})) {
        const column = typeof entry === "object" ? entry?.column : entry;

        if (
          typeof column === "string" &&
          logical !== "tenant" &&
          !reads.has(`${table}.${logical}`)
        ) {
          const tableOff =
            // SAFETY: `tables` maps logical tables to a name or `null`.
            (config.tables as Record<string, unknown> | undefined)?.[table] ===
            null;

          found.push({
            block,
            table,
            logical,
            column,
            gating: tableOff
              ? `tables.${table}: null`
              : gatingOption(block, layout, offFlags, `${table}.${logical}`),
          });
        }
      }
    }
  }

  return found;
}
