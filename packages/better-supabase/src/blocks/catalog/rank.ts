import type { RankNeighbors } from "../../core/rank-result.ts";
import type { Result } from "../../core/result.ts";

import { dbError } from "../../core/errors.ts";
import { rankBetweenResult } from "../../core/rank-result.ts";
import { err, ok } from "../../core/result.ts";

/**
 * A whole-number position for a rank method when `options.rankType` is
 * `"integer"`.
 */
export interface RankPosition {
  readonly position: number;
}

/**
 * Where a rank method moves a row: between two neighbors' rank keys, or, with
 * integer ranks, at a position.
 */
export type CatalogRank = RankNeighbors | RankPosition;

const WHOLE_RANK = /^-?[0-9]{1,9}$/u;
const MAX_POSITION = 999_999_999;

const rankInvalid = (message: string): Result<string> =>
  err(dbError("invalid_request", message, { hint: "RANK_KEY_INVALID" }));

const isPosition = (value: number): boolean =>
  Number.isSafeInteger(value) && Math.abs(value) <= MAX_POSITION;

/**
 * The rank key a rank method writes: a base-62 key between the neighbors, or
 * with integer ranks the position, or a whole number between the neighbors.
 */
export function catalogRankKey(
  rank: CatalogRank,
  type: "text" | "integer",
): Result<string> {
  if ("position" in rank) {
    if (type !== "integer") {
      return rankInvalid(
        'a position needs blocks.catalog.options.rankType: "integer"; pass previous and next rank keys',
      );
    }

    return isPosition(rank.position)
      ? ok(String(rank.position))
      : rankInvalid("a position is a whole number of up to nine digits");
  }

  if (type === "text") {
    return rankBetweenResult(rank);
  }

  const bound = (
    value: string | null | undefined,
  ): number | null | undefined =>
    value === null || value === undefined
      ? null
      : WHOLE_RANK.test(value)
        ? Number(value)
        : undefined;

  const previous = bound(rank.previous);
  const next = bound(rank.next);

  if (previous === undefined || next === undefined) {
    return rankInvalid(
      "integer rank keys are whole numbers of up to nine digits",
    );
  }

  const key =
    previous === null
      ? next === null
        ? 1
        : next - 1
      : next === null
        ? previous + 1
        : next - previous >= 2
          ? Math.floor((previous + next) / 2)
          : undefined;

  return key === undefined
    ? rankInvalid(
        `no whole number lies between ${String(previous)} and ${String(next)}; pass a position`,
      )
    : isPosition(key)
      ? ok(String(key))
      : rankInvalid("a position is a whole number of up to nine digits");
}
