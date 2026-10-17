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
