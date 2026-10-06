import { afterEach, describe, expect, it, vi } from "vitest";

import { deadline, isTimeout } from "../../src/core/timeout.ts";

afterEach(() => {
  vi.useRealTimers();
});

describe("deadline", () => {
  it("returns the caller's signal unchanged without a timeout", () => {
    const controller = new AbortController();
    const limit = deadline(controller.signal, undefined);
    expect(limit.signal).toBe(controller.signal);
    expect(limit.timedOut()).toBe(false);
    limit.clear();
    expect(deadline(undefined, undefined).signal).toBeUndefined();
  });

  it("aborts after the timeout and reports it", () => {
    vi.useFakeTimers();
    const limit = deadline(undefined, 50);
    expect(limit.signal?.aborted).toBe(false);
    vi.advanceTimersByTime(50);
    expect(limit.signal?.aborted).toBe(true);
    expect(limit.timedOut()).toBe(true);
  });

  it("aborts with the caller's signal, which is not a timeout", () => {
    const controller = new AbortController();
    const limit = deadline(controller.signal, 10_000);
    controller.abort();
    expect(limit.signal?.aborted).toBe(true);
    expect(limit.timedOut()).toBe(false);
    limit.clear();
  });

  it("stops the timer on clear", () => {
    vi.useFakeTimers();
    const limit = deadline(new AbortController().signal, 50);
    limit.clear();
    vi.advanceTimersByTime(100);
    expect(limit.signal?.aborted).toBe(false);
  });

  it("composes signals by hand where AbortSignal.any is missing", () => {
    vi.useFakeTimers();
    // SAFETY: the test removes AbortSignal.any to exercise the fallback.
    const statics = AbortSignal as { any?: unknown };
    const any = statics.any;
    statics.any = undefined;
    try {
      const caller = new AbortController();
      const first = deadline(caller.signal, 50);
      caller.abort();
      expect(first.signal?.aborted).toBe(true);
      expect(first.timedOut()).toBe(false);
      first.clear();

      const second = deadline(new AbortController().signal, 50);
      vi.advanceTimersByTime(50);
      expect(second.signal?.aborted).toBe(true);
      expect(second.timedOut()).toBe(true);
      second.clear();

      const gone = new AbortController();
      gone.abort();
      expect(deadline(gone.signal, 50).signal?.aborted).toBe(true);
    } finally {
      statics.any = any;
    }
  });
});

describe("isTimeout", () => {
  it.each([
    [1, true],
    [0.5, true],
    [0, false],
    [-1, false],
    [Number.POSITIVE_INFINITY, false],
    [Number.NaN, false],
    ["10", false],
  ])("%j is %s", (value, expected) => {
    expect(isTimeout(value)).toBe(expected);
  });
});
