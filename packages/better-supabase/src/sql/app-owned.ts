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
  readonly source: Pick<BlockSqlContextSource, "ownTables">;
  readonly tableName: BlockSqlContext["tableName"];
}

/**
 * Whether the app's table can stand in for the module's logical table: its spec
 * has `app`, and the block maps it when the spec says `onlyWhenMapped`.
 */
export function canBeAppTable(
  spec: BlockSqlTableSpec,
  mapped: string | null | undefined,
): boolean {
  return (
    spec.app !== undefined &&
    mapped !== null &&
    (spec.app.onlyWhenMapped !== true || mapped !== undefined)
  );
}

/**
 * The logical tables the app already has: those `ownTables` lists and whose
 * spec lets them be the app's (`BlockSqlTableSpec.app`). A table mapped to
 * `null` doesn't exist, and custom mode creates nothing.
 */
function appOwnedTables(input: Ownership): string[] {
  const { config, source } = input;

  return Object.entries(input.tables)
    .filter(([logical, spec]) => {
      const mapped = config.tables[logical];

      if (config.mode === "custom" || !canBeAppTable(spec, mapped)) {
        return false;
      }

      if (config.mode === "adopt") {
        return true;
      }

      const parts = input.tableName(logical);

      return (
        source.ownTables !== undefined &&
        Object.hasOwn(source.ownTables, `${parts.schema}.${parts.name}`)
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
