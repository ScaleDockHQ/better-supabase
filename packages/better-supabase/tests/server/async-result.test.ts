import { describe, expect, it } from "vitest";

import { AsyncResult, ok } from "../../src/core/result.ts";

describe("AsyncResult.from", () => {
  it("starts the run synchronously", () => {
    let started = false;
    AsyncResult.from(() => {
      started = true;

      return Promise.resolve(ok(1));
    });

    expect(started).toBe(true);
  });

  it("turns a synchronous throw into an error result", async () => {
    const result = await AsyncResult.from<number>(() => {
      throw new Error("boom");
    });

    expect(result.ok).toBe(false);
    expect(result.error?.kind).toBe("unexpected");
  });
});
