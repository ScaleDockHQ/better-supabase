import type { ResolvedBlock } from "../config/blocks.ts";
import type { BlockSqlContext, BlockSqlTableSpec } from "./context.ts";

import { sqlIdent } from "../core/template.ts";

interface Ownership {
  readonly module: string;
  readonly tables: Readonly<Record<string, BlockSqlTableSpec>>;
  readonly config: Pick<ResolvedBlock, "mode" | "tables">;
  /** `layout.ownTables`, as `schema.table`. */
  readonly ownTables: Readonly<Record<string, string>> | undefined;
  readonly tableName: BlockSqlContext["tableName"];
  readonly column: (table: string, logical: string) => string;
}

/**
 * The logical tables the app already has: those `ownTables` lists. The legacy
 * `adopt` mode says so for every table, apart from those adopted only when
 * mapped. A table mapped to `null` doesn't exist, and custom mode creates
 * nothing.
 */
function appOwnedTables(input: Ownership): string[] {
  const { config, ownTables } = input;

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
  input: Ownership,
): Pick<BlockSqlContext, "appOwned" | "owns" | "cast"> {
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

      return `better_supabase.as_column_type(${value}, (null::${sqlIdent(parts.schema)}.${sqlIdent(parts.name)}).${sqlIdent(input.column(table, logical))})`;
    },
  };
}
