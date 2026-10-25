import type { Plugin } from "../../core/plugin.ts";
import type { MutationOp } from "../../ir/types.ts";

import { definePlugin } from "../../core/plugin.ts";
import {
  dbName,
  guardManaged,
  insertsOnly,
  withDefault,
} from "../extension-shared.ts";

/**
 * The `updated-at` block's repository extension. Stamps the columns generated
 * as `Flags.timestamps`: `createdAt` on insert, `updatedAt` on insert and
 * update. A call that sets either column fails with `invalid_request` unless it
 * passes `{ override: true }`, which keeps the caller's values. The block's
 * `track_updated_at` trigger covers writes that bypass the app, and every write
 * when the runtime has no Temporal.
 */
export interface UpdatedAtExtensionOptions {
  readonly stamp?: "client" | "trigger";
}

export function updatedAtExtension(
  extension: UpdatedAtExtensionOptions = {},
): Plugin<"timestamps"> {
  return definePlugin({
    name: "timestamps",
    describe(api): void {
      for (const { table } of api.resources) {
        const flags = table.flags.timestamps;

        if (flags?.createdAt) {
          api.markReadOnly(
            table.key,
            flags.createdAt,
            "Set by the server when the row is created.",
          );
        }

        if (flags?.updatedAt) {
          api.markReadOnly(
            table.key,
            flags.updatedAt,
            "Set by the server on every write.",
          );
        }
      }
    },
    beforeMutation(op, { table, now, options }): MutationOp {
      const flags = table.flags.timestamps;

      if (!flags) {
        return op;
      }

      const created = dbName(table, flags.createdAt);
      const updated = dbName(table, flags.updatedAt);
      guardManaged(op, [created, updated], "timestamps", options);

      if (op.kind === "delete" || extension.stamp === "trigger") {
        return op;
      }

      const stamp = readClock(now);

      if (stamp === undefined) {
        return op;
      }

      switch (op.kind) {
        case "insert": {
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

        case "update": {
          return { ...op, set: withDefault(op.set, updated, stamp) };
        }

        default: {
          const exhaustive: never = op;

          return exhaustive;
        }
      }
    },
  });
}

/**
 * The clock's reading, or `undefined` when the runtime has no Temporal. The
 * column defaults and the block's trigger fill the columns then.
 */
function readClock(now: () => Temporal.Instant): string | undefined {
  try {
    return now().toString();
  } catch (error) {
    if (error instanceof TypeError) {
      return undefined;
    }

    throw error;
  }
}
