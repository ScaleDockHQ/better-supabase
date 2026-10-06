import type { MutationOp } from "../../ir/types.ts";

import {
  definePlugin,
  type Plugin,
  type RequestContext,
} from "../../core/plugin.ts";
import { dbName, guardManaged, insertsOnly, withDefault } from "../shared.ts";

type Row = Readonly<Record<string, unknown>>;

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
 * who deleted the row. `impersonatedBy` gets `context.actor.impersonator` on
 * an impersonated insert or update and is left alone otherwise, so a user's
 * own update keeps the stamp, like the SQL modules' `track_actor`. Without an
 * actor (anonymous requests) nothing is set.
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
      const impersonated = dbName(table, flags.impersonatedBy);
      guardManaged(op, [created, updated, impersonated], "actor", options);
      const id = resolve(context);
      if (id === undefined) return op;
      const impersonator = context.actor?.impersonator;
      const stamp = (row: Row): Row => {
        const stamped = withDefault(row, updated, id);
        return impersonator === undefined
          ? stamped
          : withDefault(stamped, impersonated, impersonator);
      };
      switch (op.kind) {
        case "insert": {
          const stampCreated = insertsOnly(op);
          return {
            ...op,
            rows: op.rows.map((row) =>
              stamp(stampCreated ? withDefault(row, created, id) : row),
            ),
          };
        }
        case "update":
          return { ...op, set: stamp(op.set) };
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
