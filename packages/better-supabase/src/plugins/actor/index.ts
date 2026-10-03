import type { MutationOp } from "../../ir/types.ts";

import {
  definePlugin,
  type Plugin,
  type RequestContext,
} from "../../core/plugin.ts";
import { dbName, guardManaged, insertsOnly, withDefault } from "../shared.ts";

export interface ActorOptions {
  /** Custom actor id resolution. Defaults to `context.actor.id` for users and services. */
  readonly resolve?: (context: RequestContext) => string | undefined;
}

function defaultActor(context: RequestContext): string | undefined {
  const actor = context.actor;
  return actor && actor.kind !== "anon" ? actor.id : undefined;
}

/**
 * Stamps the columns generated as `Flags.actor`: `createdBy` on insert and
 * `updatedBy` on insert and update. Soft deletes are updates, so they record
 * who deleted the row. Without an actor (anonymous requests) nothing is set.
 */
export function actor(options: ActorOptions = {}): Plugin<"actor"> {
  const resolve = options.resolve ?? defaultActor;
  return definePlugin({
    name: "actor",
    beforeMutation(op, { table, context, options }): MutationOp {
      const flags = table.flags.actor;
      if (!flags) return op;
      const created = dbName(table, flags.createdBy);
      const updated = dbName(table, flags.updatedBy);
      guardManaged(op, [created, updated], "actor", options);
      const id = resolve(context);
      if (id === undefined) return op;
      switch (op.kind) {
        case "insert": {
          const stampCreated = insertsOnly(op);
          return {
            ...op,
            rows: op.rows.map((row) =>
              withDefault(
                stampCreated ? withDefault(row, created, id) : row,
                updated,
                id,
              ),
            ),
          };
        }
        case "update":
          return { ...op, set: withDefault(op.set, updated, id) };
        case "delete":
          return op;
        default: {
          const exhaustive: never = op;
          return exhaustive;
        }
      }
    },
  });
}
