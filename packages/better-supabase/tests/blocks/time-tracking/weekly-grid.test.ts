import { describe, expect, it } from "vitest";

import { toWeeklyGrid } from "../../../src/blocks/time-tracking/index.ts";

const at = (text: string): Temporal.Instant => Temporal.Instant.from(text);

const entry = (
  id: string,
  start: string,
  end: string | undefined,
  extra: { subjectType?: string; subjectId?: string; billable?: boolean } = {},
) => ({
  id,
  startedAt: at(start),
  billable: extra.billable ?? false,
  ...(end === undefined ? {} : { endedAt: at(end) }),
  ...(extra.subjectType === undefined
    ? {}
    : { subjectType: extra.subjectType }),
  ...(extra.subjectId === undefined ? {} : { subjectId: extra.subjectId }),
});

describe("toWeeklyGrid", () => {
  it("adds entries up per record and day, Monday first", () => {
    const apollo = {
      subjectType: "project",
      subjectId: "apollo",
      billable: true,
    };

    const grid = toWeeklyGrid(
      [
        entry("a", "2026-10-06T09:00:00Z", "2026-10-06T11:00:00Z", apollo),
        entry("b", "2026-10-08T13:00:00Z", "2026-10-08T13:30:00Z", apollo),
        entry("c", "2026-10-07T23:00:00Z", "2026-10-08T01:00:00Z"),
        entry("outside", "2026-09-30T09:00:00Z", "2026-09-30T10:00:00Z"),
      ],
      { week: Temporal.PlainDate.from("2026-10-08"), timeZone: "UTC" },
    );

    expect(grid.days.map((day) => day.id)).toEqual([
      "2026-10-05",
      "2026-10-06",
      "2026-10-07",
      "2026-10-08",
      "2026-10-09",
      "2026-10-10",
      "2026-10-11",
    ]);
    expect(grid.rows).toEqual([
      {
        id: "project:apollo:true",
        subjectType: "project",
        subjectId: "apollo",
        billable: true,
        days: [0, 7200, 0, 1800, 0, 0, 0],
        seconds: 9000,
        entryIds: ["a", "b"],
      },
      {
        id: "::false",
        billable: false,
        days: [0, 0, 3600, 3600, 0, 0, 0],
        seconds: 7200,
        entryIds: ["c"],
      },
    ]);
    expect(grid.days.map((day) => day.seconds)).toEqual([
      0, 7200, 3600, 5400, 0, 0, 0,
    ]);
    expect(grid.seconds).toBe(16_200);
    expect(grid.billableSeconds).toBe(9000);
  });

  it("starts days in the time zone and runs open entries until now", () => {
    const grid = toWeeklyGrid([entry("a", "2026-10-05T22:30:00Z", undefined)], {
      week: Temporal.PlainDate.from("2026-10-05"),
      timeZone: "Europe/Amsterdam",
      now: at("2026-10-05T23:00:00Z"),
      rowKey: () => "all",
    });

    expect(grid.days[0]?.date.toString()).toBe("2026-10-05");
    expect(grid.rows[0]?.id).toBe("all");
    expect(grid.rows[0]?.days).toEqual([0, 1800, 0, 0, 0, 0, 0]);
  });

  it("uses the current time for a running entry by default", () => {
    const start = Temporal.Now.instant().subtract({ minutes: 1 });
    const today = Temporal.Now.plainDateISO("UTC");

    const grid = toWeeklyGrid(
      [{ id: "r", startedAt: start, billable: false }],
      { week: today, timeZone: "UTC" },
    );

    expect(grid.seconds).toBeGreaterThan(0);
  });
});
