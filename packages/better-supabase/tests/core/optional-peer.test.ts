import { describe, expect, it } from "vitest";

import { importOptionalPeer, memoized } from "../../src/core/optional-peer.ts";

describe("importOptionalPeer", () => {
  it("returns the module when it resolves", async () => {
    expect(await importOptionalPeer("node:path")).toBeDefined();
  });

  it("returns undefined when the package is missing", async () => {
    expect(await importOptionalPeer("not-a-real-package-xyz")).toBeUndefined();
  });
});

describe("memoized", () => {
  it("loads once and shares the promise", async () => {
    let calls = 0;
    const load = memoized(async () => ++calls);
    expect(await Promise.all([load(), load()])).toEqual([1, 1]);
    expect(calls).toBe(1);
  });

  it("does not keep a rejection", async () => {
    let calls = 0;
    const load = memoized(async () => {
      if (++calls === 1) throw new Error("first");
      return calls;
    });
    await expect(load()).rejects.toThrow("first");
    expect(await load()).toBe(2);
  });
});
