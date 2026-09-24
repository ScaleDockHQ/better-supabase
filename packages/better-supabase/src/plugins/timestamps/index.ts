import type { MutationOp } from '../../ir/types.ts';

import { definePlugin, type Plugin } from '../../core/plugin.ts';
import { dbName, insertsOnly, withDefault } from '../shared.ts';

/**
 * Stamps the columns generated as `Flags.timestamps`: `createdAt` on insert,
 * `updatedAt` on insert and update. Values the caller passes win. Pair it with
 * the `updated-at` SQL kit trigger to cover writes that bypass the app.
 */
export function timestamps(): Plugin<'timestamps'> {
  return definePlugin({
    name: 'timestamps',
    beforeMutation(op, { table, now }): MutationOp {
      const flags = table.flags.timestamps;
      if (!flags) return op;
      const created = dbName(table, flags.createdAt);
      const updated = dbName(table, flags.updatedAt);
      const stamp = now().toISOString();
      switch (op.kind) {
        case 'insert': {
          const stampCreated = insertsOnly(op);
          return {
            ...op,
            rows: op.rows.map((row) =>
              withDefault(
                stampCreated ? withDefault(row, created, stamp) : row,
                updated,
                stamp,
              ),
            ),
          };
        }
        case 'update':
          return { ...op, set: withDefault(op.set, updated, stamp) };
        case 'delete':
          return op;
        default: {
          const exhaustive: never = op;
          return exhaustive;
        }
      }
    },
  });
}
