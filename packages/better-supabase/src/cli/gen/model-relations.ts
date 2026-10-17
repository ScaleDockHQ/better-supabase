import type { DraftTable, ModelContext, RelationModel } from "./model-types.ts";

import { applyCasing } from "./model-types.ts";
import { sameColumns, singular } from "./shared.ts";

export function buildRelations(
  ctx: ModelContext,
  tables: readonly DraftTable[],
): Map<string, RelationModel[]> {
  const { config, keyOf } = ctx;
  const byKey = new Map<string, (typeof tables)[number]>();
  for (const entry of tables) {
    byKey.set(`${entry.table.schema}.${entry.table.name}`, entry);
  }
  const appName = (schema: string, table: string, column: string): string => {
    const entry = byKey.get(`${schema}.${table}`);
    return entry?.byDb.get(column)?.app ?? column;
  };

  // Relations: forward from each FK, reverse on the referenced table.
  const relations = new Map<string, RelationModel[]>();
  const push = (tableId: string, relation: RelationModel): void => {
    const list = relations.get(tableId);
    if (list) {
      list.push(relation);
    } else {
      relations.set(tableId, [relation]);
    }
  };

  for (const { table, casing, byDb: own } of tables) {
    const sourceId = `${table.schema}.${table.name}`;
    for (const fk of table.foreignKeys) {
      const targetId = `${fk.refSchema}.${fk.refTable}`;
      const target = byKey.get(targetId);
      if (!target) {
        continue;
      }
      const targetKey = keyOf.get(targetId) ?? fk.refTable;

      const sourceColumns = fk.columns.map((column) =>
        appName(table.schema, table.name, column),
      );
      const targetColumns = fk.refColumns.map((column) =>
        appName(fk.refSchema, fk.refTable, column),
      );
      const nullable =
        (config.relations.nullableUnderRls && target.table.rls) ||
        fk.columns.some((column) => own.get(column)?.nullable ?? true);
      const onDelete =
        fk.onDelete === "cascade" ||
        fk.onDelete === "set null" ||
        fk.onDelete === "set default"
          ? { onDelete: fk.onDelete }
          : {};
      const naming = namingColumns(fk.columns, fk.refColumns);
      const [only] = naming;
      const forwardBase =
        naming.length === 1 && only?.endsWith("_id")
          ? only.slice(0, -3)
          : singular(fk.refTable);
      push(sourceId, {
        name: applyCasing(forwardBase, casing),
        base: forwardBase,
        fkColumns: fk.columns,
        refColumns: fk.refColumns,
        meta: {
          table: targetKey,
          kind: "one",
          nullable,
          foreignKey: fk.name,
          columns: sourceColumns,
          references: targetColumns,
          direction: "forward",
          ...onDelete,
        },
      });

      const unique =
        fk.oneToOne ||
        sameColumns(table.primaryKey, fk.columns) ||
        table.uniques.some((key) => sameColumns(key.columns, fk.columns));
      const reverseBase = unique ? singular(table.name) : table.name;
      push(targetId, {
        name: applyCasing(reverseBase, target.casing),
        base: reverseBase,
        fkColumns: fk.columns,
        refColumns: fk.refColumns,
        meta: {
          table: keyOf.get(sourceId) ?? table.name,
          kind: unique ? "one" : "many",
          nullable: true,
          foreignKey: fk.name,
          columns: targetColumns,
          references: sourceColumns,
          direction: "reverse",
          ...onDelete,
        },
      });
    }
  }
  return relations;
}

/**
 * The columns that name a relation. A composite key that repeats a column on
 * both sides, such as `(customer_id, organization_id)` referencing
 * `(id, organization_id)` to keep rows in one tenant, is named by the rest.
 */
export function namingColumns(
  columns: readonly string[],
  references: readonly string[],
): readonly string[] {
  const own = columns.filter((column, index) => column !== references[index]);
  return own.length > 0 ? own : columns;
}
