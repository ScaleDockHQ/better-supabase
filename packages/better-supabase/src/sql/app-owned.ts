import type { ResolvedBlock } from "../config/blocks.ts";
import type {
  BlockSqlContext,
  BlockSqlContextSource,
  BlockSqlNames,
  BlockSqlTableSpec,
} from "./context.ts";

import { sqlIdent } from "../core/template.ts";

interface Ownership {
  readonly module: string;
  readonly tables: Readonly<Record<string, BlockSqlTableSpec>>;
  readonly config: Pick<ResolvedBlock, "mode" | "tables">;
  readonly source: Pick<BlockSqlContextSource, "ownTables" | "overAppTables">;
  readonly tableName: BlockSqlContext["tableName"];
}

/**
 * The logical tables the app already has: those `ownTables` lists. The legacy
 * `adopt` mode says so for every table, apart from those adopted only when
 * mapped. A table mapped to `null` doesn't exist, custom mode creates nothing,
 * and a module without `overAppTables` always creates its tables.
 */
function appOwnedTables(input: Ownership): string[] {
  const { config, source } = input;

  const ownTables =
    source.overAppTables?.(input.module) === false
      ? undefined
      : source.ownTables;

  return Object.entries(input.tables)
    .filter(([logical, spec]) => {
      const mapped = config.tables[logical];

      if (mapped === null || config.mode === "custom") {
        return false;
      }

      if (config.mode === "adopt") {
        return spec.adoptOnlyWhenMapped !== true || mapped !== undefined;
      }

      const parts = input.tableName(logical);

      return (
        ownTables !== undefined &&
        Object.hasOwn(ownTables, `${parts.schema}.${parts.name}`)
      );
    })
    .map(([logical]) => logical);
}

/** `appOwned`, `owns` and `cast` of a module context. */
export function tableOwnership(
  module: string,
  names: BlockSqlNames,
  config: Ownership["config"],
  source: Ownership["source"],
  tableName: Ownership["tableName"],
  column: (table: string, logical: string) => string,
): Pick<BlockSqlContext, "appOwned" | "owns" | "cast"> {
  const input = { module, tables: names.tables, config, source, tableName };
  const appOwned = appOwnedTables(input);

  return {
    appOwned,
    owns: (logical) => {
      input.tableName(logical);

      return input.config.mode !== "custom" && !appOwned.includes(logical);
    },
    cast: (table, logical, value) => {
      if (input.tables[table]?.typed?.includes(logical) !== true) {
        throw new TypeError(
          `Module "${input.module}" casts ${table}.${logical}, which its names.tables.${table}.typed doesn't list`,
        );
      }

      if (!appOwned.includes(table)) {
        return value;
      }

      const parts = input.tableName(table);

      return `better_supabase.as_column_type(${value}, (null::${sqlIdent(parts.schema)}.${sqlIdent(parts.name)}).${sqlIdent(column(table, logical))})`;
    },
  };
}
