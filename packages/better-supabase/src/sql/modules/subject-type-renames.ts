import type { BlockSqlContext } from "../context.ts";
import type { BlockSqlLayout } from "../module-types.ts";

import { blockFormerSubjectTypes } from "../../config/block-subjects.ts";
import { SUBJECT_TYPE_RENAMES } from "../../core/renames.ts";
import { sqlString } from "../../core/template.ts";
import { moduleContext } from "../module-context.ts";

/** The logical columns that store a subject type. */
const TYPE_COLUMNS = ["subjectType", "sourceType", "targetType"] as const;

/**
 * Modules whose rows are history: a guard trigger refuses updates, and the
 * audit log's hash chain covers the stored type.
 */
const APPEND_ONLY = new Set(["accounting", "audit", "billable-time", "ledger"]);

/**
 * The module's subject types that 0.47 renamed, old to new. An install that
 * names the entity itself keeps its type, and so does an old type the app's
 * `config.subjects` still declares.
 */
function renamedTypes(
  ctx: BlockSqlContext,
): readonly { readonly old: string; readonly next: string }[] {
  return Object.values(ctx.resolved.entities).flatMap((entity) => {
    const old = entity.formerly?.from.singular;
    const next = entity.to.singular;

    return old === undefined ||
      entity.subject === undefined ||
      SUBJECT_TYPE_RENAMES[old] !== next ||
      Object.hasOwn(ctx.subjects, old)
      ? []
      : [{ old, next }];
  });
}

/**
 * Every installed block's renamed subject types, new to old. An app subject
 * that happens to have a new type, such as its own `task` table, has none.
 */
export function formerSubjectTypes(
  ctx: BlockSqlContext,
): ReadonlyMap<string, string> {
  return blockFormerSubjectTypes(
    ctx.installedModules,
    ctx.modules,
    ctx.subjects,
  );
}

/** One installed module column that stores a subject type. */
interface TypeColumn {
  readonly table: string;
  readonly column: string;
  /** The column's database name. */
  readonly name: string;
}

/** Every installed module column that stores a subject type. */
function typeColumns(
  ctx: BlockSqlContext,
  layout: BlockSqlLayout,
): readonly TypeColumn[] {
  return ctx.installedModules.flatMap((module) => {
    if (APPEND_ONLY.has(module)) {
      return [];
    }

    // Every installed module's tables, read or not: `ctx.of` only reaches
    // the modules this one requires or integrates.
    const other = moduleContext(module, layout, ctx.installedModules);

    return Object.entries(other.names.tables).flatMap(([table, { columns }]) =>
      other.hasTable(table)
        ? TYPE_COLUMNS.filter(
            (column) => column in columns && other.has(table, column),
          ).map((column) => ({
            table: other.table(table),
            column: other.col(table, column),
            name: other.colName(table, column),
          }))
        : [],
    );
  });
}

/**
 * Moves the rows that store one of the module's old subject types (0.47:
 * `work_item`, `engagement`, `policy`) to the new type, in every installed
 * module table with a subject type column. It runs again harmlessly.
 *
 * Each update runs only when its column exists: a module installed after this
 * one, or a table or column that only some options add, has no rows to move
 * yet.
 */
export function subjectTypeRenames(
  ctx: BlockSqlContext,
  layout: BlockSqlLayout,
): string {
  const types = renamedTypes(ctx);

  if (types.length === 0) {
    return "";
  }

  const columns = new Map(
    typeColumns(ctx, layout).map((entry) => [
      `${entry.table}.${entry.column}`,
      entry,
    ]),
  );

  const updates = [...columns.values()].map(({ table, column, name }) => {
    const moves = types.map(
      ({ old, next }) =>
        `update ${table} set ${column} = ${sqlString(next)} where ${column} = ${sqlString(old)};`,
    );

    return `do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass(${sqlString(table)}) and attname = ${sqlString(name)} and not attisdropped) then ${moves.join(" ")} end if; end $$;`;
  });

  return [
    "-- Subject types renamed in 0.47 (`codemod 0.47`).",
    ...updates,
  ].join("\n");
}
