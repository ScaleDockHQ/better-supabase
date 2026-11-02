import { describe, expect, it } from "vitest";

import {
  HOLIDAYS,
  HOLIDAY_YEARS,
  easter,
  nthWeekday,
} from "../../../src/sql/modules/calendar-holidays.ts";

const iso = (date: { year: number; month: number; day: number }): string =>
  `${date.year}-${String(date.month).padStart(2, "0")}-${String(date.day).padStart(2, "0")}`;

const on = (locale: string, key: string, year: number): string =>
  iso(HOLIDAYS[locale]!.rules.find((rule) => rule.key === key)!.on(year));

describe("holiday rules", () => {
  it("computes Easter Sunday", () => {
    expect(iso(easter(2026))).toBe("2026-04-05");
    expect(iso(easter(2027))).toBe("2027-03-28");
    expect(iso(easter(2028))).toBe("2028-04-16");
    expect(iso(easter(2030))).toBe("2030-04-21");
  });

  it("finds the nth and last weekday of a month", () => {
    expect(iso(nthWeekday(2026, 5, 1, -1))).toBe("2026-05-25");
    expect(iso(nthWeekday(2026, 11, 4, 4))).toBe("2026-11-26");
    expect(iso(nthWeekday(2026, 1, 1, 3))).toBe("2026-01-19");
  });

  it("derives days from Easter", () => {
    expect(on("nl", "good-friday", 2026)).toBe("2026-04-03");
    expect(on("de", "whit-monday", 2026)).toBe("2026-05-25");
    expect(on("fr", "ascension", 2026)).toBe("2026-05-14");
  });

  it("moves King's Day off a Sunday", () => {
    expect(on("nl", "kings-day", 2026)).toBe("2026-04-27");
    expect(on("nl", "kings-day", 2027)).toBe("2027-04-27");
    expect(on("nl", "kings-day", 2029)).toBe("2029-04-27");
    expect(on("nl", "kings-day", 2030)).toBe("2030-04-27");
    // 27 April 2025 was a Sunday, so the rule also covers it.
    expect(on("nl", "kings-day", 2031)).toBe("2031-04-26");
  });

  it("gives England and Wales substitute days", () => {
    expect(on("en-gb", "christmas", 2027)).toBe("2027-12-27");
    expect(on("en-gb", "boxing-day", 2027)).toBe("2027-12-28");
    expect(on("en-gb", "new-year", 2028)).toBe("2028-01-03");
    expect(on("en-gb", "christmas", 2028)).toBe("2028-12-25");
  });

  it("is a fixed year list, not relative to the build", () => {
    expect(HOLIDAY_YEARS).toEqual([2026, 2027, 2028, 2029, 2030]);
  });

  it("has unique keys in every set", () => {
    for (const set of Object.values(HOLIDAYS)) {
      const keys = set.rules.map((rule) => rule.key);

      expect(new Set(keys).size).toBe(keys.length);
    }
  });
});
