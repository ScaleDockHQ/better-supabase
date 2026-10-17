/*
 * Fractional rank keys (ADR 0021): base-62 strings that sort by byte order
 * (`collate "C"` in Postgres), so a row moves by rewriting one key. A key is
 * never empty and never ends in "0", which leaves room before every key.
 * `rank_between` in the rank SQL module runs the same steps; the shared
 * vectors in tests/core/fixtures/rank-vectors.json check both.
 */

/** The queue `move()` enqueues on when a key grows past 24 digits. */
export const RANK_REBALANCE_QUEUE = "rank.rebalance";

/** The digits, in byte order. */
export const RANK_ALPHABET =
  "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

const BASE = RANK_ALPHABET.length;
const KEY = /^[0-9A-Za-z]*[1-9A-Za-z]$/;

/** True for a key `rankBetween` can take: base-62 digits, not ending in "0". */
export function isRankKey(value: unknown): value is string {
  return typeof value === "string" && KEY.test(value);
}

function digitAt(key: string, index: number): number {
  return index < key.length ? RANK_ALPHABET.indexOf(key.charAt(index)) : 0;
}

/**
 * A key that sorts after `previous` and before `next`. `null` is an open end:
 * `rankBetween(null, null)` is the first key of an empty list. Throws a
 * `RangeError` for an invalid key or when `previous` is not below `next`.
 */
export function rankBetween(
  previous: string | null,
  next: string | null,
): string {
  if (previous !== null && !KEY.test(previous)) {
    throw new RangeError(`"${previous}" is not a rank key`);
  }
  if (next !== null && !KEY.test(next)) {
    throw new RangeError(`"${next}" is not a rank key`);
  }
  if (previous !== null && next !== null && previous >= next) {
    throw new RangeError(`"${previous}" must sort before "${next}"`);
  }
  const low = previous ?? "";
  let key = "";
  let bounded = next !== null;
  for (let index = 0; ; index += 1) {
    const lowDigit = digitAt(low, index);
    const highDigit = bounded && next !== null ? digitAt(next, index) : BASE;
    if (highDigit === lowDigit) {
      key += RANK_ALPHABET.charAt(lowDigit);
      continue;
    }
    if (highDigit - lowDigit > 1) {
      return key + RANK_ALPHABET.charAt(Math.floor((lowDigit + highDigit) / 2));
    }
    if (bounded && next !== null && index + 1 < next.length) {
      return key + next.charAt(index);
    }
    key += RANK_ALPHABET.charAt(lowDigit);
    bounded = false;
  }
}

/**
 * `count` keys spread evenly, in order: what the rebalance job writes. No key
 * is longer than the fewest base-62 digits that can number `count` rows.
 */
export function rankKeys(count: number): string[] {
  if (!Number.isSafeInteger(count) || count < 0) {
    throw new RangeError("count must be a whole number of keys");
  }
  let width = 1;
  while (BASE ** width <= count) {
    width += 1;
  }
  const step = Math.floor(BASE ** width / (count + 1));
  return Array.from({ length: count }, (_, index) => {
    let value = step * (index + 1);
    let key = "";
    for (let place = 0; place < width; place += 1) {
      key = RANK_ALPHABET.charAt(value % BASE) + key;
      value = Math.floor(value / BASE);
    }
    return key.replace(/0+$/, "");
  });
}
