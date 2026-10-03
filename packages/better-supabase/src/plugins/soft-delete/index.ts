import type { PrimaryKeyValue, TableMeta } from "../../schema/types.ts";

import {
  definePlugin,
  type HasFlag,
  type Plugin,
  type RepositoryExtension,
} from "../../core/plugin.ts";
import { AsyncResult, ok, type Result } from "../../core/result.ts";
import { scopeOperation } from "../../ir/scope.ts";
import { and, type MutationOp, type Operation } from "../../ir/types.ts";
import {
  dbName,
  guardManaged,
  insertsOnly,
  isNotNull,
  isNull,
  withDefault,
} from "../shared.ts";

export interface SoftDeleteFindArgs {
  /** Include soft-deleted rows of the queried table. */
  readonly withDeleted?: boolean;
  /** Only return soft-deleted rows of the queried table. */
  readonly onlyDeleted?: boolean;
}

export interface SoftDeleteDeleteArgs {
  /** Delete the row for real instead of setting the soft-delete column. */
  readonly hard?: boolean;
}

export interface SoftDeleteMethods<K> {
  /** Clears the soft-delete column. `not_found` when the row does not exist. */
  readonly restore: (
    key: K,
    args?: { readonly signal?: AbortSignal },
  ) => AsyncResult<void>;
}

export interface SoftDeleteExtension extends RepositoryExtension {
  readonly methods: HasFlag<this["M"], this["T"], "softDelete"> extends true
    ? SoftDeleteMethods<PrimaryKeyValue<this["M"], this["T"]>>
    : unknown;
  readonly findArgs: HasFlag<this["M"], this["T"], "softDelete"> extends true
    ? SoftDeleteFindArgs
    : unknown;
  readonly deleteArgs: HasFlag<this["M"], this["T"], "softDelete"> extends true
    ? SoftDeleteDeleteArgs
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
 * Soft delete for tables generated with `Flags.softDelete`:
 *
 * - reads, updates and deletes skip deleted rows, including inside includes
 *   and relation filters (`withDeleted` / `onlyDeleted` change the root table);
 * - `delete` sets the column instead (`{ hard: true }` really deletes);
 * - `restore(key)` clears it.
 *
 * Deletes become updates without `RETURNING`, so a SELECT policy that hides
 * deleted rows does not make them fail.
 */
export function softDelete(): Plugin<"softDelete", SoftDeleteExtension> {
  return definePlugin<"softDelete", SoftDeleteExtension>({
    name: "softDelete",
    // Runs first so other plugins see the delete as the update it becomes.
    enforce: "pre",
    transformQuery(op, { options }): Operation {
      const hardDelete = op.kind === "delete" && options["hard"] === true;
      const withDeleted = options["withDeleted"] === true || hardDelete;
      const onlyDeleted = options["onlyDeleted"] === true;
      const scoped = scopeOperation(op, scopeFor, !withDeleted && !onlyDeleted);
      const column = deletedColumn(op.table);
      if (!onlyDeleted || !column || scoped.kind === "insert") return scoped;
      return { ...scoped, where: and(scoped.where, isNotNull(column)) };
    },
    beforeMutation(op, { table, options, now }): MutationOp {
      const column = deletedColumn(table);
      if (!column) return op;
      guardManaged(op, [column], "softDelete", options);
      if (op.kind === "insert") {
        // An upsert that updates a soft-deleted row brings it back.
        if (insertsOnly(op)) return op;
        return {
          ...op,
          rows: op.rows.map((row) => withDefault(row, column, null)),
        };
      }
      if (op.kind !== "delete" || options["hard"] === true) return op;
      return {
        kind: "update",
        table,
        set: { [column]: now().toString() },
        where: op.where,
        returning: undefined,
      };
    },
    repository({ table, base }) {
      const flag = table.flags.softDelete;
      if (!flag) return;
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
              {
                ...args,
                withDeleted: true,
                returning: false,
                override: true,
              },
            );
            return result.ok ? ok(undefined) : result;
          }),
      };
    },
  });
}
