import type { Result } from "./result.ts";

import { dbError } from "./errors.ts";
import { rankBetween } from "./rank-keys.ts";
import { err, ok } from "./result.ts";

/** Neighbour keys for a reorder; leave one out (or `null`) for an end. */
export interface RankNeighbors {
  readonly previous?: string | null;
  readonly next?: string | null;
}

/**
 * `rankBetween` as a result: an `invalid_request` error with the hint
 * `RANK_KEY_INVALID` instead of a `RangeError`.
 */
export function rankBetweenResult(neighbors: RankNeighbors): Result<string> {
  try {
    return ok(rankBetween(neighbors.previous ?? null, neighbors.next ?? null));
  } catch (cause) {
    const message = cause instanceof Error ? cause.message : String(cause);

    return err(
      dbError("invalid_request", message, { hint: "RANK_KEY_INVALID" }),
    );
  }
}

/**
 * The neighbours that put `id` at `toIndex` (0 is first) in `ordered`, a list
 * in rank order. The index counts the list without `id`, and one past the end
 * puts it last. Fails with `not_found` when `id` is not in the list and with
 * `RANK_MISSING` when a neighbour has no rank key (an unranked table).
 */
export function neighborsForIndex(
  ordered: readonly {
    readonly id: string;
    readonly rank?: string | undefined;
  }[],
  id: string,
  toIndex: number,
): Result<RankNeighbors> {
  if (!ordered.some((item) => item.id === id)) {
    return err(
      dbError("not_found", "The item is not in the list", {
        hint: "RANK_ITEM_UNKNOWN",
      }),
    );
  }

  const rest = ordered.filter((item) => item.id !== id);
  const at = Math.min(Math.max(Math.trunc(toIndex), 0), rest.length);
  const previous = at === 0 ? null : (rest[at - 1]?.rank ?? undefined);
  const next = at === rest.length ? null : (rest[at]?.rank ?? undefined);

  if (previous === undefined || next === undefined) {
    return err(
      dbError("invalid_request", "A neighbour has no rank key", {
        hint: "RANK_MISSING",
      }),
    );
  }

  return ok({ previous, next });
}
