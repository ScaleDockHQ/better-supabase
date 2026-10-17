import { describe, expect, it } from "vitest";

import {
  RANK_ALPHABET,
  isRankKey,
  rankBetween,
  rankKeys,
} from "../../src/core/rank-keys.ts";
import VECTORS from "./fixtures/rank-vectors.json" with { type: "json" };

const byBytes = (left: string, right: string): number =>
  left < right ? -1 : left > right ? 1 : 0;

describe("rank keys", () => {
  it("has the base-62 digits in byte order", () => {
    expect(RANK_ALPHABET).toHaveLength(62);
    expect(RANK_ALPHABET.split("").toSorted(byBytes).join("")).toBe(
      RANK_ALPHABET,
    );
  });

  it.each(VECTORS.between)(
    "rankBetween($previous, $next) is $key",
    ({ previous, next, key }) => {
      expect(rankBetween(previous, next)).toBe(key);
      expect(isRankKey(key)).toBe(true);
      expect(previous === null || previous < key).toBe(true);
      expect(next === null || key < next).toBe(true);
    },
  );

  it.each(VECTORS.invalid)(
    "rankBetween($previous, $next) throws",
    ({ previous, next }) => {
      expect(() => rankBetween(previous, next)).toThrow(RangeError);
    },
  );

  it.each(VECTORS.keys)("rankKeys($count)", ({ count, keys }) => {
    expect(rankKeys(count)).toStrictEqual(keys);
    expect(keys.toSorted(byBytes)).toStrictEqual(keys);
    expect(new Set(keys.map((key) => key.length)).size).toBeLessThanOrEqual(2);
    expect(keys.every((key) => isRankKey(key))).toBe(true);
  });

  it("returns no keys for zero and rejects a negative count", () => {
    expect(rankKeys(0)).toStrictEqual([]);
    expect(() => rankKeys(-1)).toThrow(RangeError);
  });

  it("keeps a list ordered through many random inserts", () => {
    let seed = 7;
    const random = (): number => {
      seed = (seed * 1_103_515_245 + 12_345) % 2_147_483_648;
      return seed / 2_147_483_648;
    };
    const list: string[] = [];
    for (let step = 0; step < 2000; step += 1) {
      const at = Math.floor(random() * (list.length + 1));
      const key = rankBetween(list[at - 1] ?? null, list[at] ?? null);
      list.splice(at, 0, key);
    }
    expect(list.toSorted(byBytes)).toStrictEqual(list);
    expect(new Set(list).size).toBe(list.length);
  });

  it("grows by about one digit per insert at the same spot", () => {
    let key = rankBetween(null, null);
    const next = "W";
    for (let step = 0; step < 30; step += 1) {
      key = rankBetween(key, next);
    }
    expect(key.length).toBeLessThanOrEqual(32);
    expect(key < next).toBe(true);
  });

  it("rejects keys that end in zero or hold other characters", () => {
    expect(isRankKey("V")).toBe(true);
    expect(isRankKey("V0")).toBe(false);
    expect(isRankKey("")).toBe(false);
    expect(isRankKey("a b")).toBe(false);
    expect(isRankKey(1)).toBe(false);
  });
});
