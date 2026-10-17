import { describe, expect, it } from "vitest";

import {
  expandRule,
  weekdayName,
} from "../../../src/blocks/reminders/rrule.ts";

const utc = (text: string): Temporal.ZonedDateTime =>
  Temporal.Instant.from(text).toZonedDateTimeISO("UTC");

const days = (when: readonly Temporal.ZonedDateTime[]): string[] =>
  when.map((item) => item.toPlainDate().toString());

describe("expandRule", () => {
  it("expands a daily count from the RFC examples", () => {
    const found = expandRule({
      dtstart: utc("1997-09-02T09:00:00Z"),
      rrule: "FREQ=DAILY;COUNT=10",
    });

    expect(found).toHaveLength(10);
    expect(days(found)[0]).toBe("1997-09-02");
    expect(days(found)[9]).toBe("1997-09-11");
    expect(found[0]?.hour).toBe(9);
  });

  it("stops at an inclusive UNTIL", () => {
    const found = expandRule({
      dtstart: utc("1997-09-02T09:00:00Z"),
      rrule: "FREQ=DAILY;UNTIL=19970904T090000Z",
    });

    expect(days(found)).toEqual(["1997-09-02", "1997-09-03", "1997-09-04"]);
  });

  it("expands weekly Tuesday and Thursday", () => {
    const found = expandRule({
      dtstart: utc("1997-09-02T09:00:00Z"),
      rrule: "FREQ=WEEKLY;BYDAY=TU,TH;COUNT=4",
    });

    expect(days(found)).toEqual([
      "1997-09-02",
      "1997-09-04",
      "1997-09-09",
      "1997-09-11",
    ]);
  });

  it("expands the first Friday of each month", () => {
    const found = expandRule({
      dtstart: utc("1997-09-05T09:00:00Z"),
      rrule: "FREQ=MONTHLY;BYDAY=1FR;COUNT=3",
    });

    expect(days(found)).toEqual(["1997-09-05", "1997-10-03", "1997-11-07"]);
  });

  it("takes the last weekday of the month with BYSETPOS", () => {
    const found = expandRule({
      dtstart: utc("1997-09-30T09:00:00Z"),
      rrule: "FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;COUNT=2",
    });

    expect(days(found)).toEqual(["1997-09-30", "1997-10-31"]);
  });

  it("keeps the local time across a daylight-saving change", () => {
    const found = expandRule({
      dtstart: Temporal.ZonedDateTime.from(
        "2026-03-01T09:00:00[America/New_York]",
      ),
      rrule: "FREQ=WEEKLY;COUNT=3",
    });

    expect(found.map((item) => item.hour)).toEqual([9, 9, 9]);
    expect(days(found)).toEqual(["2026-03-01", "2026-03-08", "2026-03-15"]);
  });

  it("names weekdays and rejects a number outside Monday to Sunday", () => {
    expect(weekdayName(1)).toBe("MO");
    expect(() => weekdayName(0)).toThrow(TypeError);
    expect(() => weekdayName(8)).toThrow(TypeError);
  });

  it("skips daily occurrences that are not the requested weekday", () => {
    const found = expandRule({
      dtstart: utc("1997-09-02T09:00:00Z"),
      rrule: "FREQ=DAILY;BYDAY=MO;COUNT=2",
    });

    expect(days(found)).toEqual(["1997-09-08", "1997-09-15"]);
  });

  it("expands a yearly last day of January", () => {
    const found = expandRule({
      dtstart: utc("1997-01-31T09:00:00Z"),
      rrule: "FREQ=YEARLY;BYMONTH=1;BYMONTHDAY=-1;COUNT=2",
    });

    expect(days(found)).toEqual(["1997-01-31", "1998-01-31"]);
  });

  it("expands weekly columns and a monthly weekday column", () => {
    const weekly = expandRule({
      dtstart: utc("1997-09-02T09:00:00Z"),
      columns: { frequency: "weekly", weekDays: [2], count: 2 },
    });

    expect(days(weekly)).toEqual(["1997-09-02", "1997-09-09"]);

    const monthly = expandRule({
      dtstart: utc("1997-09-05T09:00:00Z"),
      columns: {
        frequency: "monthly",
        monthWeekday: 5,
        monthOrdinal: 1,
        count: 1,
      },
    });

    expect(days(monthly)).toEqual(["1997-09-05"]);
  });

  it("rejects a rule with no source, a bad frequency, or a bad interval", () => {
    expect(() => expandRule({ dtstart: utc("1997-09-02T09:00:00Z") })).toThrow(
      TypeError,
    );
    expect(() =>
      expandRule({
        dtstart: utc("1997-09-02T09:00:00Z"),
        rrule: "FREQ=HOURLY",
      }),
    ).toThrow(TypeError);
    expect(() =>
      expandRule({
        dtstart: utc("1997-09-02T09:00:00Z"),
        rrule: "FREQ=DAILY;INTERVAL=0",
      }),
    ).toThrow(TypeError);
  });

  it("expands a column-format monthly rule", () => {
    const found = expandRule({
      dtstart: utc("1997-09-15T09:00:00Z"),
      columns: { frequency: "monthly", monthDay: 15, interval: 1, count: 2 },
    });

    expect(days(found)).toEqual(["1997-09-15", "1997-10-15"]);
  });
});

describe("expandRule with a window", () => {
  const amsterdam = (text: string): Temporal.ZonedDateTime =>
    Temporal.ZonedDateTime.from(`${text}[Europe/Amsterdam]`);

  it.each([
    "FREQ=DAILY;INTERVAL=3",
    "FREQ=WEEKLY;BYDAY=MO,TH",
    "FREQ=WEEKLY;INTERVAL=2;BYDAY=FR;WKST=SU",
    "FREQ=MONTHLY;BYMONTHDAY=31",
    "FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1",
    "FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU",
  ])("matches the full expansion inside the window for %s", (rrule) => {
    const dtstart = amsterdam("2024-01-05T09:00:00+01:00");
    const from = Temporal.Instant.from("2026-02-10T00:00:00Z");
    const until = Temporal.Instant.from("2026-06-01T00:00:00Z");

    const all = expandRule({ dtstart, rrule, limit: 366 * 4 }).filter(
      (when) =>
        Temporal.Instant.compare(when.toInstant(), from) >= 0 &&
        Temporal.Instant.compare(when.toInstant(), until) < 0,
    );

    const windowed = expandRule({ dtstart, rrule, window: { from, until } });
    expect(windowed.map(String)).toEqual(all.map(String));
  });

  it("keeps the wall-clock time across DST", () => {
    const found = expandRule({
      dtstart: amsterdam("2026-03-23T09:00:00+01:00"),
      rrule: "FREQ=WEEKLY",
      window: {
        from: Temporal.Instant.from("2026-03-20T00:00:00Z"),
        until: Temporal.Instant.from("2026-04-10T00:00:00Z"),
      },
    });

    expect(found.map((when) => when.hour)).toEqual([9, 9, 9]);
    expect(found[1]?.offset).toBe("+02:00");
  });

  it("counts COUNT from dtstart, not from the window", () => {
    const found = expandRule({
      dtstart: utc("2026-01-01T09:00:00Z"),
      rrule: "FREQ=DAILY;COUNT=10",
      window: {
        from: Temporal.Instant.from("2026-01-08T00:00:00Z"),
        until: Temporal.Instant.from("2026-02-01T00:00:00Z"),
      },
    });

    expect(days(found)).toEqual(["2026-01-08", "2026-01-09", "2026-01-10"]);
  });

  it("skips ahead for a long-running daily series", () => {
    const found = expandRule({
      dtstart: utc("2000-01-01T09:00:00Z"),
      rrule: "FREQ=DAILY",
      window: {
        from: Temporal.Instant.from("2030-01-01T00:00:00Z"),
        until: Temporal.Instant.from("2030-01-03T00:00:00Z"),
      },
    });

    expect(days(found)).toEqual(["2030-01-01", "2030-01-02"]);
  });
});
