import type {
  HasFlag,
  Plugin,
  RepositoryExtension,
} from "../../core/plugin.ts";
import type { Result } from "../../core/result.ts";
import type { MutationOp, Operation } from "../../ir/types.ts";
import type { PrimaryKeyValue, TableMeta } from "../../schema/types.ts";

import { definePlugin } from "../../core/plugin.ts";
import { AsyncResult, ok } from "../../core/result.ts";
import { scopeOperation } from "../../ir/scope.ts";
import { and } from "../../ir/types.ts";
import {
  dbName,
  guardManaged,
  insertsOnly,
  isNotNull,
  isNull,
  withDefault,
} from "../extension-shared.ts";

export interface TrashFindArgs {
  /** Include soft-deleted rows of the queried table. */
  readonly withDeleted?: boolean;
  /** Only return soft-deleted rows of the queried table. */
  readonly onlyDeleted?: boolean;
}

export interface TrashDeleteArgs {
  /** Delete the row for real instead of setting the soft-delete column. */
  readonly hard?: boolean;
}

export interface TrashMethods<K> {
  /** Clears the soft-delete column. `not_found` when the row does not exist. */
  readonly restore: (
    key: K,
    args?: { readonly signal?: AbortSignal },
  ) => AsyncResult<void>;
}

export interface TrashExtension extends RepositoryExtension {
  readonly methods: HasFlag<this["M"], this["T"], "softDelete"> extends true
    ? TrashMethods<PrimaryKeyValue<this["M"], this["T"]>>
    : unknown;
  readonly findArgs: HasFlag<this["M"], this["T"], "softDelete"> extends true
    ? TrashFindArgs
    : unknown;
  readonly deleteArgs: HasFlag<this["M"], this["T"], "softDelete"> extends true
    ? TrashDeleteArgs
    : unknown;
}

function deletedColumn(table: TableMeta): string | undefined {
  return dbName(table, table.flags.softDelete);
}

function scopeFor(table: TableMeta) {
  const column = deletedColumn(table);

  return column ? isNull(column) : undefined;
}

type UpdateFn = (
  key: unknown,
  patch: unknown,
  args: unknown,
) => AsyncResult<unknown>;

/**
 * The `trash` block's repository extension, for tables generated with
 * `Flags.softDelete`:
 *
 * - Reads, updates and deletes skip deleted rows, including inside includes and
 *   relation filters (`withDeleted` / `onlyDeleted` change the root table);
 * - `delete` sets the column instead (`{ hard: true }` really deletes);
 * - `restore(key)` clears it.
 *
 * Deletes become updates without `RETURNING`, so a SELECT policy that hides
 * deleted rows does not make them fail. `delete({ where }, { returning: true
 * })` keeps `RETURNING`, which needs a SELECT policy that still shows the row.
 */
export function trashExtension(): Plugin<"softDelete", TrashExtension> {
  return definePlugin<"softDelete", TrashExtension>({
    name: "softDelete",
    // Runs first so other plugins see the delete as the update it becomes.
    enforce: "pre",
    scopes: ["softDelete"],
    describe(api): void {
      for (const { table } of api.resources) {
        const flag = table.flags.softDelete;

        if (!flag) {
          continue;
        }

        api.markReadOnly(
          table.key,
          flag,
          "Set when the row is deleted. Deleted rows are not returned, and delete sets this column instead of removing the row.",
        );
      }
    },
    transformQuery(op, { options }): Operation {
      const hardDelete = op.kind === "delete" && options["hard"] === true;
      const withDeleted = options["withDeleted"] === true || hardDelete;
      const onlyDeleted = options["onlyDeleted"] === true;
      const scoped = scopeOperation(op, scopeFor, !withDeleted && !onlyDeleted);
      const column = deletedColumn(op.table);

      if (!onlyDeleted || !column || scoped.kind === "insert") {
        return scoped;
      }

      return { ...scoped, where: and(scoped.where, isNotNull(column)) };
    },
    beforeMutation(op, { table, options, now }): MutationOp {
      const column = deletedColumn(table);

      if (!column) {
        return op;
      }

      guardManaged(op, [column], "softDelete", options);

      if (op.kind === "insert") {
        // An upsert that updates a soft-deleted row brings it back.
        if (insertsOnly(op)) {
          return op;
        }

        return {
          ...op,
          rows: op.rows.map((row) => withDefault(row, column, null)),
        };
      }

      if (op.kind !== "delete" || options["hard"] === true) {
        return op;
      }

      return {
        kind: "update",
        intent: "softDelete",
        table,
        set: { [column]: deletedAt(now) },
        where: op.where,
        returning: options["returning"] === true ? op.returning : undefined,
        ...(op.maxAffected === undefined
          ? {}
          : { maxAffected: op.maxAffected }),
        ...(op.count === undefined ? {} : { count: op.count }),
      };
    },
    repository({ table, base }) {
      const flag = table.flags.softDelete;

      if (!flag) {
        return;
      }

      // SAFETY: every repository has an update method with this signature;
      // plugins receive it untyped.
      // oxlint-disable-next-line anti-slop/no-chained-type-assertions -- plugins receive `base` as an untyped method map.
      const update = base["update"] as unknown as UpdateFn;

      return {
        restore: (key: unknown, args?: { readonly signal?: AbortSignal }) =>
          AsyncResult.from(async (): Promise<Result<void>> => {
            const result = await update(
              key,
              { [flag]: null },
              { ...args, withDeleted: true, returning: false, override: true },
            );

            return result.ok ? ok(undefined) : result;
          }),
      };
    },
  });
}

/**
 * The clock's reading, or the system clock's when the runtime has no Temporal:
 * a soft delete needs a time, and no trigger sets one.
 */
function deletedAt(now: () => Temporal.Instant): string {
  try {
    return now().toString();
  } catch (error) {
    if (error instanceof TypeError) {
      return new Date().toISOString();
    }

    throw error;
  }
}
