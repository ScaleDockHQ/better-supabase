import type { BlockSqlNameMigration } from "./context.ts";
import type { ResolvedNames } from "./resolved-names.ts";

import { TABLE_RENAMES } from "../core/renames.ts";

/**
 * `module`'s 0.47 table renames (`TABLE_RENAMES`) as `NAMES.migrations`
 * entries, run on installs below version `from + 1`.
 */
export function tableMoves(
  module: string,
  from: number,
): readonly BlockSqlNameMigration[] {
  return Object.entries(TABLE_RENAMES[module] ?? {}).map(([table, rename]) => ({
    from,
    description: `The ${rename.from} table is ${rename.to} (ADR 0130).`,
    table,
    was: rename.from,
    objects: true,
  }));
}

const taken = new Set(
  Object.values(TABLE_RENAMES).flatMap((renames) =>
    Object.values(renames).map((rename) => rename.to),
  ),
);

/**
 * Whether `module` moves a table off a name another module's move takes, as
 * idempotency frees `leases` for the leases block. Its upgrade runs first.
 */
export const freesTableName = (module: string): boolean =>
  Object.values(TABLE_RENAMES[module] ?? {}).some((rename) =>
    taken.has(rename.from),
  );

/** Whether 0.47 renamed `module`'s logical `table`. */
const movedTable = (module: string, table: string): boolean =>
  Object.hasOwn(TABLE_RENAMES[module] ?? {}, table);

/**
 * The default name of a logical table before the config's renames. A table 0.47
 * renamed after an entity's new singular (`tasks`) starts from its old noun
 * (`work_items`) on an install that names the entity, so the install keeps its
 * table, as it keeps its function names.
 */
export const tableBase = (
  resolved: ResolvedNames,
  logical: string,
  name: string,
): string =>
  movedTable(resolved.module, logical)
    ? resolved.functionNouns.rename(name)
    : name;

/**
 * The default name of a logical column before the config's renames. A column a
 * migration renamed after an entity's new singular (`task_id`) starts from the
 * old noun (`work_item_id`) on an install that names the entity, as its table
 * does.
 */
export const columnBase = (
  resolved: ResolvedNames,
  migrations: readonly BlockSqlNameMigration[] | undefined,
  table: string,
  logical: string,
  name: string,
): string =>
  migrations?.some(
    (move) => move.table === table && move.columns?.[logical] !== undefined,
  )
    ? resolved.functionNouns.rename(name)
    : name;
