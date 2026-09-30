import { afterEach, describe, expect, it, vi } from "vitest";

import type { Logger } from "../../src/core/logger.ts";

import { formatStats, StatsCollector } from "../../src/next/collector.ts";

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
    expect(log.warn).toHaveBeenCalledTimes(1);
    expect(log.warn.mock.calls[0]![0]).toMatch(
      /request r1 made 2 database calls in 2 waves, over the budget of 2 calls and 1 waves/,
    );
    expect(formatStats(collector.get("r1")!)).toMatch(/^2;2;[\d.]+$/);
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
