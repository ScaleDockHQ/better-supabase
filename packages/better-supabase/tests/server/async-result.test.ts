import { describe, expect, it } from "vitest";

import { dbError } from "../../src/core/errors.ts";
import { AsyncResult, err, ok } from "../../src/core/result.ts";

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

describe("AsyncResult.pipe", () => {
  it("returns the final result", async () => {
    const result = await AsyncResult.pipe(async (bind) => {
      const a = await bind(AsyncResult.ok(1));
      const b = await bind(AsyncResult.ok(2));

      return ok(a + b);
    });

    expect(result).toEqual(ok(3));
  });

  it("stops at the first error and keeps its DbError", async () => {
    const failure = dbError("not_found", "missing");
    let reached = false;

    const result = await AsyncResult.pipe(async (bind) => {
      await bind(AsyncResult.err<number>(failure));
      reached = true;

      return ok(1);
    });

    expect(reached).toBe(false);
    expect(result).toEqual(err(failure));
  });
});
