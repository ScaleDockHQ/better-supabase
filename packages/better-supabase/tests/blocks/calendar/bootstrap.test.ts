import { describe, expect, it } from "vitest";

import { createCalendar } from "../../../src/blocks/calendar/calendar.ts";

const event = (
  id: string,
  title: string,
  startsAt: string,
  endsAt: string,
) => ({
  id,
  calendarId: "c1",
  uid: id,
  title,
  startsAt,
  endsAt,
  allDay: false,
  tz: "UTC",
  status: "confirmed",
  rrule: null,
  exdates: [],
  recurrenceId: null,
  originalStart: null,
  updatedAt: "2030-01-01T00:00:00+00:00",
});

function recorder(result: unknown) {
  const calls: { fn: string; args: Readonly<Record<string, unknown>> }[] = [];

  const transport = {
    call(_schema: string, fn: string, args: Readonly<Record<string, unknown>>) {
      calls.push({ fn, args });

      return Promise.resolve(result);
    },
  };

  return { calls, calendar: createCalendar({ transport, schema: "app" }) };
}

const range = {
  from: Temporal.Instant.from("2030-03-01T00:00:00Z"),
  until: Temporal.Instant.from("2030-04-01T00:00:00Z"),
};

const upcoming = {
  from: Temporal.Instant.from("2030-03-10T00:00:00Z"),
  until: Temporal.Instant.from("2030-03-24T00:00:00Z"),
};

const BOOT = {
  calendarList: [{ id: "c1", name: "Team", tz: "Europe/Amsterdam" }],
  monthEvents: [
    event(
      "e1",
      "Planning",
      "2030-03-06T09:00:00+00:00",
      "2030-03-06T10:00:00+00:00",
    ),
  ],
  upcomingEvents: [
    event(
      "e2",
      "Review",
      "2030-03-12T09:00:00+00:00",
      "2030-03-12T10:00:00+00:00",
    ),
  ],
  myReminders: [{ id: "r1", subjectId: "e2", offsetMinutes: 15 }],
};

describe("calendar.bootstrap", () => {
  it("reads calendars, both ranges and reminders in one call", async () => {
    const { calls, calendar } = recorder(BOOT);

    const result = await calendar
      .bootstrap({ organizationId: "org1", range, upcoming })
      .orThrow();

    expect(calls).toEqual([
      {
        fn: "calendar_bootstrap",
        args: {
          tenant: "org1",
          range_start: range.from.toString(),
          range_end: range.until.toString(),
          upcoming_start: upcoming.from.toString(),
          upcoming_end: upcoming.until.toString(),
        },
      },
    ]);
    expect(result.calendars).toEqual([
      { id: "c1", name: "Team", tz: "Europe/Amsterdam" },
    ]);
    expect(result.occurrences.map((item) => item.event.title)).toEqual([
      "Planning",
    ]);
    expect(result.upcoming.map((item) => item.event.title)).toEqual(["Review"]);
    expect(result.reminders).toEqual([
      { id: "r1", eventId: "e2", offsetMinutes: 15 },
    ]);
  });

  it("sends no second range when none is given", async () => {
    const { calls, calendar } = recorder({
      ...BOOT,
      upcomingEvents: [],
      myReminders: [],
    });

    const result = await calendar
      .bootstrap({ organizationId: "org1", range })
      .orThrow();

    expect(Object.keys(calls[0]?.args ?? {})).toEqual([
      "tenant",
      "range_start",
      "range_end",
    ]);
    expect(result.upcoming).toEqual([]);
    expect(result.reminders).toEqual([]);
  });

  it("returns a failed call as an error", async () => {
    const { calendar } = recorder(null);

    const result = await calendar.bootstrap({ organizationId: "org1", range });

    expect(result.ok).toBe(false);
  });
});
