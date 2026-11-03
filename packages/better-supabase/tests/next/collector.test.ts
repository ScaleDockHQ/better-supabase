import { afterEach, describe, expect, it, vi } from "vitest";

import type { Logger } from "../../src/core/logger.ts";

import {
  formatStats,
  requestIdOf,
  sharedCollector,
  StatsCollector,
} from "../../src/next/collector.ts";

const logger = () => ({
  debug: vi.fn<Logger["debug"]>(),
  info: vi.fn<Logger["info"]>(),
  warn: vi.fn<Logger["warn"]>(),
  error: vi.fn<Logger["error"]>(),
});

afterEach(() => {
  vi.useRealTimers();
});

describe("StatsCollector", () => {
  it("warns once a render goes idle over the budget", () => {
    vi.useFakeTimers();
    const log = logger();

    const collector = new StatsCollector({
      logger: log,
      warn: true,
      budget: { calls: 2, waves: 1 },
    });

    const recorder = collector.recorderFor("r1");
    expect(collector.recorderFor("r1")).toBe(recorder);
    recorder.begin("customers")();
    recorder.begin("notes")();
    vi.advanceTimersByTime(300);
    expect(log.warn).toHaveBeenCalledOnce();
    expect(log.warn.mock.calls[0]![0]).toMatch(
      /request r1 made 2 database calls in 2 waves, over the budget of 2 calls and 1 waves/,
    );
    expect(formatStats(collector.get("r1")!)).toMatch(/^2;2;[\d.]+;0;0$/);
  });

  it("stays within budget quietly and forgets old requests", () => {
    vi.useFakeTimers();
    const log = logger();

    const collector = new StatsCollector({
      logger: log,
      warn: true,
      budget: { calls: 5 },
      maxEntries: 2,
    });

    collector.recorderFor("a").begin("customers")();
    collector.recorderFor("b");
    collector.recorderFor("c");
    vi.advanceTimersByTime(300);
    expect(log.warn).not.toHaveBeenCalled();
    expect(collector.get("a")).toBeUndefined();
    expect(collector.get("c")).toMatchObject({ calls: 0 });
  });
});

describe("sharedCollector", () => {
  it("shares totals across views but warns with each view's own budget", () => {
    vi.useFakeTimers();
    const strictLog = logger();
    const quietLog = logger();

    const strict = sharedCollector({
      logger: strictLog,
      warn: true,
      budget: { calls: 1 },
    });

    const quiet = sharedCollector({ logger: quietLog, warn: false });
    const strictRecorder = strict.recorderFor("shared-strict");
    strictRecorder.begin("customers")();
    strictRecorder.begin("notes")();
    const quietRecorder = quiet.recorderFor("shared-quiet");
    quietRecorder.begin("customers")();
    quietRecorder.begin("notes")();
    vi.advanceTimersByTime(300);
    expect(strictLog.warn).toHaveBeenCalledOnce();
    expect(quietLog.warn).not.toHaveBeenCalled();
    expect(strict.get("shared-quiet")).toMatchObject({ calls: 2 });
  });
});

describe("requestIdOf", () => {
  it("prefers the proxy's id, then the trace id, x-vercel-id and x-request-id", () => {
    const of = (headers: Record<string, string>) =>
      requestIdOf(new Headers(headers));

    expect(of({ "x-bsb-request-id": "a", traceparent: "x" })).toBe("a");

    expect(
      of({
        traceparent: "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01",
        "x-vercel-id": "fra1::abc",
      }),
    ).toBe("trace:0af7651916cd43dd8448eb211c80319c");

    expect(of({ "x-vercel-id": "fra1::abc", "x-request-id": "r" })).toBe(
      "vercel:fra1::abc",
    );

    expect(of({ "x-request-id": "r" })).toBe("request:r");
    expect(of({ traceparent: "junk" })).toBeUndefined();
  });
});
