import type { ResolvedBlock } from "../config/blocks.ts";
import type {
  BlockSqlContext,
  BlockSqlContextSource,
  BlockSqlTableSpec,
} from "./context.ts";

import { sqlIdent } from "../core/template.ts";
import { asColumnType, tryColumnType } from "./column-type.ts";
import { UNMAPPED_COLUMN, UNMAPPED_TABLE } from "./over-app-tables.ts";

interface Ownership {
  readonly module: string;
  readonly tables: Readonly<Record<string, BlockSqlTableSpec>>;
  readonly config: Pick<ResolvedBlock, "mode" | "tables" | "schema">;
  readonly source: Pick<BlockSqlContextSource, "ownTables" | "ownViews">;
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

      const parts = input.tableName(logical);

      return (
        source.ownTables !== undefined &&
        Object.hasOwn(source.ownTables, `${parts.schema}.${parts.name}`)
      );
    })
    .map(([logical]) => logical);
}

/**
 * `appOwned`, `owns` and `cast` of a module context, and its `tableName` and
 * `col`. Over the app's tables, a table or column the block maps to `null` gets
 * a marker name, so the DDL that builds it still renders; the render drops that
 * DDL and refuses any other use.
 */
export function tableOwnership(
  input: Ownership,
  column: (table: string, logical: string) => string | null,
  requiredColumn: (table: string, logical: string) => string,
): Pick<
  BlockSqlContext,
  "appOwned" | "appViews" | "owns" | "cast" | "tableName" | "col"
> {
  const appOwned = appOwnedTables(input);
  const overApp = appOwned.length > 0;
  const views = input.source.ownViews ?? {};

  return {
    appOwned,
    appViews: appOwned.filter((logical) => {
      const parts = input.tableName(logical);

      return Object.hasOwn(views, `${parts.schema}.${parts.name}`);
    }),
    owns: (logical) => {
      input.tableName(logical);

      return input.config.mode !== "custom" && !appOwned.includes(logical);
    },
    tableName: (logical) =>
      overApp &&
      input.config.tables[logical] === null &&
      input.tables[logical] !== undefined
        ? { schema: input.config.schema, name: `${UNMAPPED_TABLE}${logical}` }
        : input.tableName(logical),
    col: (table, logical) =>
      sqlIdent(
        column(table, logical) === null && appOwned.includes(table)
          ? `${UNMAPPED_COLUMN}${table}.${logical}`
          : requiredColumn(table, logical),
      ),
    cast: (table, logical, value, invalid = "raise") => {
      if (input.tables[table]?.typed?.includes(logical) !== true) {
        throw new TypeError(
          `Module "${input.module}" casts ${table}.${logical}, which its names.tables.${table}.typed doesn't list`,
        );
      }

      if (!appOwned.includes(table)) {
        return value;
      }

      const parts = input.tableName(table);

      return (invalid === "null" ? tryColumnType : asColumnType)(
        `${sqlIdent(parts.schema)}.${sqlIdent(parts.name)}`,
        requiredColumn(table, logical),
        value,
      );
    },
  };
}
