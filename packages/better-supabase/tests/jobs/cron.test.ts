import { describe, expect, it } from "vitest";

import { assertCron, nextCronRun } from "../../src/jobs/cron.ts";

const at = (iso: string) => Temporal.Instant.from(iso);
const next = (cron: string, after: string, zone = "UTC") =>
  nextCronRun(cron, zone, at(after)).toString();

describe("nextCronRun", () => {
  it("finds the next minute that matches", () => {
    expect(next("0 3 * * *", "2026-01-01T02:59:30Z")).toBe(
      "2026-01-01T03:00:00Z",
    );
    expect(next("0 3 * * *", "2026-01-01T03:00:00Z")).toBe(
      "2026-01-02T03:00:00Z",
    );
    expect(next("*/15 * * * *", "2026-01-01T10:16:00Z")).toBe(
      "2026-01-01T10:30:00Z",
    );
    expect(next("5,10-12 8 * * *", "2026-01-01T08:10:00Z")).toBe(
      "2026-01-01T08:11:00Z",
    );
  });

  it("reads steps on ranges and on single values", () => {
    expect(next("0 1-10/3 * * *", "2026-01-01T05:00:00Z")).toBe(
      "2026-01-01T07:00:00Z",
    );
    expect(next("0 20/2 * * *", "2026-01-01T21:00:00Z")).toBe(
      "2026-01-01T22:00:00Z",
    );
  });

  it("matches either a restricted day of month or day of week", () => {
    // 2026-01-02 is a Friday.
    expect(next("0 0 15 * 5", "2026-01-01T00:00:00Z")).toBe(
      "2026-01-02T00:00:00Z",
    );
    expect(next("0 0 15 * *", "2026-01-01T00:00:00Z")).toBe(
      "2026-01-15T00:00:00Z",
    );
    expect(next("0 0 * * 0", "2026-01-01T00:00:00Z")).toBe(
      "2026-01-04T00:00:00Z",
    );
    expect(next("0 0 * * 7", "2026-01-01T00:00:00Z")).toBe(
      "2026-01-04T00:00:00Z",
    );
  });

  it("accepts month and weekday names and macros", () => {
    expect(next("0 9 * * MON-FRI", "2026-01-02T10:00:00Z")).toBe(
      "2026-01-05T09:00:00Z",
    );
    expect(next("0 0 1 FEB *", "2026-01-01T00:00:00Z")).toBe(
      "2026-02-01T00:00:00Z",
    );
    expect(next("@daily", "2026-01-01T12:00:00Z")).toBe("2026-01-02T00:00:00Z");
    expect(next("@hourly", "2026-01-01T12:30:00Z")).toBe(
      "2026-01-01T13:00:00Z",
    );
  });

  it("reads the fields in the time zone", () => {
    expect(next("0 9 * * *", "2026-01-01T00:00:00Z", "Europe/Amsterdam")).toBe(
      "2026-01-01T08:00:00Z",
    );
    expect(next("0 9 * * *", "2026-07-01T00:00:00Z", "Europe/Amsterdam")).toBe(
      "2026-07-01T07:00:00Z",
    );
  });

  it("runs a time the DST change skips after the gap", () => {
    // Clocks in Amsterdam jump from 02:00 to 03:00 on 2026-03-29.
    expect(next("30 2 * * *", "2026-03-28T12:00:00Z", "Europe/Amsterdam")).toBe(
      "2026-03-29T01:30:00Z",
    );
  });

  it("counts intervals from the last run", () => {
    expect(next("30 seconds", "2026-01-01T00:00:10Z")).toBe(
      "2026-01-01T00:00:40Z",
    );
    expect(next("5 minutes", "2026-01-01T00:00:00Z")).toBe(
      "2026-01-01T00:05:00Z",
    );
    expect(next("2 hours", "2026-01-01T00:00:00Z")).toBe(
      "2026-01-01T02:00:00Z",
    );
    expect(() => next("0 seconds", "2026-01-01T00:00:00Z")).toThrow(/positive/);
  });

  it("rejects invalid expressions", () => {
    expect(() => {
      assertCron("* * * *");
    }).toThrow(/5 fields/);
    expect(() => {
      assertCron("60 * * * *");
    }).toThrow(/outside/);
    expect(() => {
      assertCron("*/0 * * * *");
    }).toThrow(/outside/);
    expect(() => {
      assertCron("5-1 * * * *");
    }).toThrow(/outside/);
    expect(() => {
      assertCron("a * * * *");
    }).toThrow(/not a cron field/);
    expect(() => next("0 0 30 2 *", "2026-01-01T00:00:00Z")).toThrow(
      /never matches/,
    );
    expect(() => {
      assertCron("10 minutes");
    }).not.toThrow();
  });
});
