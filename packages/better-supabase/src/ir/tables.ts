import type { SchemaMeta } from '../schema/types.ts';
import type { Condition, Operation, Selection } from './types.ts';

/**
 * App keys of every table an operation reads or writes: its own table, each
 * included relation and each relation used in a filter. Cached reads of these
 * tables go stale when any of them changes.
 */
export function touchedTables(op: Operation): string[] {
  const tables = new Set<string>([op.table.key]);
  const selection = op.kind === 'select' ? op.selection : op.returning;
  if (selection) visitSelection(selection, tables);
  if (op.kind !== 'insert') visitCondition(op.where, tables);
  return [...tables];
}

function visitSelection(selection: Selection, tables: Set<string>): void {
  for (const include of selection.includes) {
    tables.add(include.target.key);
    visitSelection(include.selection, tables);
    visitCondition(include.where, tables);
  }
}

function visitCondition(
  condition: Condition | undefined,
  tables: Set<string>,
): void {
  if (!condition) return;
  switch (condition.kind) {
    case 'and':
    case 'or':
      for (const item of condition.items) visitCondition(item, tables);
      return;
    case 'not':
      visitCondition(condition.item, tables);
      return;
    case 'column':
      return;
    case 'relation':
      tables.add(condition.target.key);
      visitCondition(condition.where, tables);
      return;
    default: {
      const exhaustive: never = condition;
      return exhaustive;
    }
  }
}

/**
 * Tables whose rows can change when rows of `table` change: the table itself
 * plus every table whose foreign key cascades or sets a value on delete,
 * followed through chains of cascades.
 */
export function invalidationTargets(meta: SchemaMeta, table: string): string[] {
  const targets = new Set<string>([table]);
  const queue = [table];
  for (let key = queue.shift(); key !== undefined; key = queue.shift()) {
    const relations = meta.tables[key]?.relations ?? {};
    for (const relation of Object.values(relations)) {
      if (relation.direction !== 'reverse' || !relation.onDelete) continue;
      if (targets.has(relation.table)) continue;
      targets.add(relation.table);
      if (relation.onDelete === 'cascade') queue.push(relation.table);
    }
  }
  return [...targets];
}
