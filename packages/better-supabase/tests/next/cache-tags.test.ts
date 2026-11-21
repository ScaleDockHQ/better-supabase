import { describe, expect, it, vi } from "vitest";

const cacheTag = vi.hoisted(() => vi.fn<(...tags: string[]) => void>());

vi.mock(import("next/cache.js"), () => ({ cacheTag }));

const { applyCacheTags } = await import("../../src/next/cache-tags.ts");

describe("applyCacheTags", () => {
  it("passes a short list in one call", () => {
    applyCacheTags(["a", "b"]);
    expect(cacheTag).toHaveBeenCalledExactlyOnceWith("a", "b");
  });

  it("splits a list past 128 tags so Next drops none", () => {
    cacheTag.mockClear();
    const tags = Array.from({ length: 300 }, (_, index) => `t${String(index)}`);

    applyCacheTags(new Set(tags));

    expect(cacheTag.mock.calls.map((call) => call.length)).toEqual([
      128, 128, 44,
    ]);

    expect(cacheTag.mock.calls.flat()).toEqual(tags);
  });

  it("makes no call for an empty list", () => {
    cacheTag.mockClear();
    applyCacheTags([]);
    expect(cacheTag).not.toHaveBeenCalled();
  });
});
