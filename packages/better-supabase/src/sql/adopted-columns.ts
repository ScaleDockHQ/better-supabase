import type { AnyBlocksConfig } from "../config/blocks.ts";

import { moduleContext } from "./module-context.ts";
import { SQL_MODULES } from "./registry.ts";
import { declaredTableColumns } from "./schema-scan.ts";

/** A table an adopt-mode module reads and writes, with the columns it uses. */
export interface AdoptedTable {
  readonly module: string;
  readonly logical: string;
  readonly schema: string;
  readonly table: string;
  /** Logical column to the physical column the module's SQL names. */
  readonly columns: Readonly<Record<string, string>>;
}

/**
 * Every table the adopt-mode modules in `modules` use, with the columns
 * their SQL names: mapped to `null` and unused optional columns are left out.
 */
export function adoptedTables(
  modules: AnyBlocksConfig,
): readonly AdoptedTable[] {
  const tables: AdoptedTable[] = [];
  for (const name of Object.keys(modules)) {
    if ((modules[name]?.mode ?? "managed") !== "adopt") {
      continue;
    }
    const spec = SQL_MODULES[name]?.names?.tables;
    if (spec === undefined) {
      continue;
    }
    const ctx = moduleContext(name, { modules }, Object.keys(modules));
    const unchecked = SQL_MODULES[name]?.adoptOptional?.(ctx) ?? {};
    for (const [logical, table] of Object.entries(spec)) {
      if (!ctx.hasTable(logical)) {
        continue;
      }
      const columns: Record<string, string> = {};
      for (const [column, physical] of Object.entries(table.columns)) {
        if (!ctx.has(logical, column) || unchecked[logical]?.includes(column)) {
          continue;
        }
        columns[column] = ctx.config.columns[logical]?.[column] ?? physical;
      }
      const { schema, name: tableName } = ctx.tableName(logical);
      tables.push({ module: name, logical, schema, table: tableName, columns });
    }
    for (const extra of SQL_MODULES[name]?.adoptSubjectTables?.(ctx) ?? []) {
      const columns: Record<string, string> = {};
      for (const [column, physical] of Object.entries(extra.columns)) {
        if (physical !== null) {
          columns[column] = physical;
        }
      }
      tables.push({
        module: name,
        logical: extra.logical,
        schema: extra.schema,
        table: extra.table,
        columns,
      });
    }
  }
  return tables;
}

/**
 * Adopt-mode modules that default an optional column to its physical name
 * while the adopted `create table` has no such column. `sql sync` refuses
 * those configs so `has()` does not treat a missing column as present.
 */
export function adoptedColumnProblems(
  modules: AnyBlocksConfig,
  files: readonly { readonly text: string }[],
  schemas: readonly string[],
): readonly string[] {
  const declared = declaredTableColumns(files, schemas);
  const problems: string[] = [];
  for (const name of Object.keys(modules)) {
    if ((modules[name]?.mode ?? "managed") !== "adopt") {
      continue;
    }
    const spec = SQL_MODULES[name]?.names?.tables;
    if (spec === undefined) {
      continue;
    }
    const ctx = moduleContext(name, { modules }, Object.keys(modules));
    const unchecked = SQL_MODULES[name]?.adoptOptional?.(ctx) ?? {};
    for (const [logical, table] of Object.entries(spec)) {
      if (!ctx.hasTable(logical)) {
        continue;
      }
      const { schema, name: tableName } = ctx.tableName(logical);
      const columns = declared.get(`${schema}.${tableName}`);
      if (columns === undefined) {
        continue;
      }
      for (const [column, physical] of Object.entries(table.columns)) {
        if (
          !table.optional?.includes(column) ||
          !ctx.has(logical, column) ||
          unchecked[logical]?.includes(column)
        ) {
          continue;
        }
        const mapped = ctx.config.columns[logical]?.[column];
        const used = mapped ?? physical;
        if (columns.has(used)) {
          continue;
        }
        problems.push(
          `blocks.${name} is in adopt mode and uses ${schema}.${tableName}.${used} (${logical}.${column}), but that column is not in the table. Map blocks.${name}.columns.${logical}.${column} to null, or add the column.`,
        );
      }
    }
    for (const extra of SQL_MODULES[name]?.adoptSubjectTables?.(ctx) ?? []) {
      const columns = declared.get(`${extra.schema}.${extra.table}`);
      if (columns === undefined) {
        continue;
      }
      for (const [column, physical] of Object.entries(extra.columns)) {
        if (physical === null || columns.has(physical)) {
          continue;
        }
        problems.push(
          `blocks.${name} is in adopt mode and uses ${extra.schema}.${extra.table}.${physical} (${extra.logical}.${column}), but that column is not in the table. Set options.subjects so that column matches the table, or add the column.`,
        );
      }
    }
  }
  return problems;
}
