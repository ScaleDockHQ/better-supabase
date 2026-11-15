import type { DbError } from "./errors.ts";
import type { Result } from "./result.ts";

import { dbError } from "./errors.ts";
import { AsyncResult, err, ok, toDbError } from "./result.ts";

/** The most ids one `bulk` call takes when the block declares no limit. */
export const BULK_LIMIT = 500;

/** One id the action did not apply to, with the plain error it failed with. */
export interface BulkItemError {
  readonly id: string;
  readonly error: DbError;
}

/**
 * What every `bulk(ids, action)` returns (ADR 0854): the ids that changed and,
 * for each one that did not, the error. The call as a whole fails only for an
 * input the limit rejects.
 */
export interface BulkReport {
  readonly succeeded: readonly string[];
  readonly failed: readonly BulkItemError[];
}

export interface BulkCallOptions {
  /** The most ids the call takes. Default {@link BULK_LIMIT}. */
  readonly limit?: number;
}

/** The `bulk` method an entity declares (ADR 0854). */
export type EntityBulk<Action extends string = string> = (
  ids: readonly string[],
  action: Action,
  options?: BulkCallOptions,
) => AsyncResult<BulkReport>;

/**
 * Rejects an id list the limit does not allow: empty lists succeed with nothing
 * to do, a list over `limit` fails with `BULK_TOO_MANY` and nothing runs.
 */
export function checkBulkLimit(
  ids: readonly string[],
  limit: number = BULK_LIMIT,
): DbError | undefined {
  if (ids.length > limit) {
    return dbError(
      "invalid_input",
      `A bulk call takes at most ${String(limit)} ids, got ${String(ids.length)}`,
      { hint: "BULK_TOO_MANY" },
    );
  }

  return undefined;
}

/**
 * Runs `apply` once per distinct id, in order, and collects the outcome. A
 * thrown or failed id lands in `failed`; it never stops the others.
 */
export function bulk<Action extends string>(
  ids: readonly string[],
  action: Action,
  apply: (id: string, action: Action) => PromiseLike<Result<unknown>>,
  options: BulkCallOptions = {},
): AsyncResult<BulkReport> {
  return AsyncResult.from(async (): Promise<Result<BulkReport>> => {
    const unique = [...new Set(ids)];
    const rejected = checkBulkLimit(unique, options.limit);

    if (rejected) {
      return err(rejected);
    }

    const succeeded: string[] = [];
    const failed: BulkItemError[] = [];

    for (const id of unique) {
      try {
        const result = await apply(id, action);

        if (result.ok) {
          succeeded.push(id);
        } else {
          failed.push({ id, error: result.error });
        }
      } catch (error) {
        failed.push({ id, error: toDbError(error) });
      }
    }

    return ok({ succeeded, failed });
  });
}

/** One row of `bulkItems`: the id the report names, plus that row's own value. */
export interface BulkItem {
  readonly id: string;
}

/**
 * `bulk` for a value per row (ADR 1036): runs `apply` once per item, in order,
 * and collects the outcome. The report names each item by its `id`. A second
 * item with an id already seen fails with `BULK_DUPLICATE_ID` and never runs; a
 * thrown or failed item lands in `failed` and never stops the others. The limit
 * counts items.
 */
export function bulkItems<Item extends BulkItem>(
  items: readonly Item[],
  apply: (item: Item) => PromiseLike<Result<unknown>>,
  options: BulkCallOptions = {},
): AsyncResult<BulkReport> {
  return AsyncResult.from(async (): Promise<Result<BulkReport>> => {
    const rejected = checkBulkLimit(
      items.map((item) => item.id),
      options.limit,
    );

    if (rejected) {
      return err(rejected);
    }

    const seen = new Set<string>();
    const succeeded: string[] = [];
    const failed: BulkItemError[] = [];

    for (const item of items) {
      if (seen.has(item.id)) {
        failed.push({
          id: item.id,
          error: dbError(
            "invalid_input",
            `The id ${item.id} appears more than once in the call`,
            { hint: "BULK_DUPLICATE_ID" },
          ),
        });
        continue;
      }

      seen.add(item.id);

      try {
        const result = await apply(item);

        if (result.ok) {
          succeeded.push(item.id);
        } else {
          failed.push({ id: item.id, error: result.error });
        }
      } catch (error) {
        failed.push({ id: item.id, error: toDbError(error) });
      }
    }

    return ok({ succeeded, failed });
  });
}

/**
 * The `BulkReport` of a set function that returns the ids it changed and the
 * ids it skipped (`TaskSetResult`): one call for the whole list, a skipped id
 * is `not_found` in `failed`. The limit applies as in `bulk`.
 */
export function bulkOfSet(
  ids: readonly string[],
  run: (
    ids: readonly string[],
  ) => PromiseLike<
    Result<{
      readonly ids: readonly string[];
      readonly skipped: readonly string[];
    }>
  >,
  options: BulkCallOptions = {},
): AsyncResult<BulkReport> {
  return AsyncResult.from(async (): Promise<Result<BulkReport>> => {
    const unique = [...new Set(ids)];
    const rejected = checkBulkLimit(unique, options.limit);

    if (rejected) {
      return err(rejected);
    }

    if (unique.length === 0) {
      return ok({ succeeded: [], failed: [] });
    }

    const result = await run(unique);

    if (!result.ok) {
      return result;
    }

    return ok({
      succeeded: [...result.data.ids],
      failed: result.data.skipped.map((id) => ({
        id,
        error: dbError(
          "not_found",
          "No such row, or the caller cannot change it",
        ),
      })),
    });
  });
}

/** A per-row result as the `bulk-actions` SQL functions return it. */
export interface BulkRowLike {
  readonly id: string;
  readonly ok: boolean;
  readonly error: {
    readonly code: string | undefined;
    readonly message: string;
    readonly sqlstate: string | undefined;
  } | null;
}

/** The `BulkReport` of the per-row results a set-based SQL function returns. */
export function bulkReportOf(rows: readonly BulkRowLike[]): BulkReport {
  const succeeded: string[] = [];
  const failed: BulkItemError[] = [];

  for (const row of rows) {
    if (row.ok) {
      succeeded.push(row.id);
      continue;
    }

    failed.push({
      id: row.id,
      error: dbError("raised", row.error?.message ?? "The action failed", {
        ...(row.error?.sqlstate === undefined
          ? {}
          : { code: row.error.sqlstate }),
        ...(row.error?.code === undefined ? {} : { hint: row.error.code }),
      }),
    });
  }

  return { succeeded, failed };
}
