import type { ModulesConfig } from "../config/modules.ts";

import { moduleContext, SQL_MODULES } from "./registry.ts";
import { declaredTableColumns } from "./schema-scan.ts";

/**
 * Adopt-mode modules that default an optional column to its physical name
 * while the adopted `create table` has no such column. `sql sync` refuses
 * those configs so `has()` does not treat a missing column as present.
 */
export function adoptedColumnProblems(
  modules: ModulesConfig,
  files: readonly { readonly text: string }[],
  schemas: readonly string[],
): readonly string[] {
  const declared = declaredTableColumns(files, schemas);
  const problems: string[] = [];
  for (const name of Object.keys(modules)) {
    if ((modules[name]?.mode ?? "managed") !== "adopt") continue;
    const spec = SQL_MODULES[name]?.names?.tables;
    if (spec === undefined) continue;
    const ctx = moduleContext(name, { modules }, Object.keys(modules));
    for (const [logical, table] of Object.entries(spec)) {
      if (!ctx.hasTable(logical)) continue;
      const { schema, name: tableName } = ctx.tableName(logical);
      const columns = declared.get(`${schema}.${tableName}`);
      if (columns === undefined) continue;
      for (const [column, physical] of Object.entries(table.columns)) {
        if (!table.optional?.includes(column) || !ctx.has(logical, column))
          continue;
        const mapped = ctx.config.columns[logical]?.[column];
        const used = mapped ?? physical;
        if (columns.has(used)) continue;
        problems.push(
          `sql.modules.${name} is in adopt mode and uses ${schema}.${tableName}.${used} (${logical}.${column}), but that column is not in the table. Map sql.modules.${name}.columns.${logical}.${column} to null, or add the column.`,
        );
      }
    }
  }
  return problems;
}
