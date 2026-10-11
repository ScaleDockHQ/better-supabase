import { describe, expect, it } from "vitest";

import { boundedTtlCache } from "../../src/core/ttl-cache.ts";

describe("boundedTtlCache", () => {
  it("returns a value until it expires", () => {
    let now = 0;
    const cache = boundedTtlCache<string, number>({ max: 4, now: () => now });
    cache.set("a", 1, 10);
    expect(cache.get("a")).toBe(1);
    now = 10;
    expect(cache.get("a")).toBeUndefined();
    expect(cache.size).toBe(0);
  });

  it("evicts the oldest entry when full and refreshes a rewritten key", () => {
    const cache = boundedTtlCache<string, number>({ max: 2, now: () => 0 });
    cache.set("a", 1, 10);
    cache.set("b", 2, 10);
    cache.set("a", 3, 10);
    cache.set("c", 4, 10);
    expect(cache.get("b")).toBeUndefined();
    expect(cache.get("a")).toBe(3);
    expect(cache.get("c")).toBe(4);
    expect(cache.size).toBe(2);
  });
});
