import { describe, expect, it } from "vitest";

import type {
  BusyRange,
  FreeBusy,
} from "../../../src/blocks/calendar/availability.ts";

import {
  commonFreeTime,
  freeBusyOf,
  workingHoursOf,
} from "../../../src/blocks/calendar/availability.ts";
import { createCalendar } from "../../../src/blocks/calendar/calendar.ts";

const at = (value: string): Temporal.Instant => Temporal.Instant.from(value);

const span = (from: string, until: string): BusyRange => ({
  from: at(from),
  until: at(until),
});

const text = (ranges: readonly BusyRange[]): string[] =>
  ranges.map((range) => `${range.from.toString()}/${range.until.toString()}`);

const day = span("2030-03-06T00:00:00Z", "2030-03-07T00:00:00Z");

function member(overrides: Partial<FreeBusy> = {}): FreeBusy {
  return {
    userId: "u1",
    busy: [],
    outOfOffice: [],
    focusTime: [],
    ...overrides,
  };
}

describe("freeBusyOf", () => {
  it("parses ranges, working hours and the zone", () => {
    const [ada, bob] = freeBusyOf([
      {
        userId: "ada",
        busy: [
          {
            startsAt: "2030-03-06T08:00:00+00:00",
            endsAt: "2030-03-06T09:00:00+00:00",
          },
        ],
        outOfOffice: [],
        focusTime: [
          {
            startsAt: "2030-03-06T10:00:00+00:00",
            endsAt: "2030-03-06T11:00:00+00:00",
          },
        ],
        workingHours: [
          {
            startsAt: "2030-03-06T08:00:00+00:00",
            endsAt: "2030-03-06T16:00:00+00:00",
          },
        ],
        tz: "Europe/Amsterdam",
      },
      {
        userId: "bob",
        busy: [],
        outOfOffice: [],
        focusTime: [],
        workingHours: null,
        tz: null,
      },
    ]);

    expect(text(ada?.busy ?? [])).toEqual([
      "2030-03-06T08:00:00Z/2030-03-06T09:00:00Z",
    ]);
    expect(text(ada?.focusTime ?? [])).toEqual([
      "2030-03-06T10:00:00Z/2030-03-06T11:00:00Z",
    ]);
    expect(text(ada?.workingHours ?? [])).toEqual([
      "2030-03-06T08:00:00Z/2030-03-06T16:00:00Z",
    ]);
    expect(ada?.tz).toBe("Europe/Amsterdam");
    expect(bob).toEqual({
      userId: "bob",
      busy: [],
      outOfOffice: [],
      focusTime: [],
    });
  });

  it("rejects a non-list result", () => {
    expect(() => freeBusyOf({})).toThrow(/calendar_free_busy/u);
  });
});

describe("workingHoursOf", () => {
  it("keeps valid weekdays and defaults the zone to UTC", () => {
    expect(
      workingHoursOf([
        {
          userId: "ada",
          tz: null,
          hours: [
            { weekday: 1, start: "09:00", end: "17:00" },
            { weekday: 9, start: "09:00", end: "17:00" },
          ],
        },
      ]),
    ).toEqual([
      {
        userId: "ada",
        tz: "UTC",
        hours: [{ weekday: 1, start: "09:00", end: "17:00" }],
      },
    ]);
  });
});

describe("commonFreeTime", () => {
  it("subtracts every member's busy time", () => {
    const free = commonFreeTime(
      [
        member({
          busy: [
            span("2030-03-06T10:00:00Z", "2030-03-06T11:00:00Z"),
            span("2030-03-06T08:00:00Z", "2030-03-06T09:00:00Z"),
            span("2030-03-06T08:30:00Z", "2030-03-06T08:45:00Z"),
          ],
        }),
        member({
          userId: "u2",
          busy: [span("2030-03-06T10:30:00Z", "2030-03-06T12:00:00Z")],
        }),
      ],
      day,
    );

    expect(text(free)).toEqual([
      "2030-03-06T00:00:00Z/2030-03-06T08:00:00Z",
      "2030-03-06T09:00:00Z/2030-03-06T10:00:00Z",
      "2030-03-06T12:00:00Z/2030-03-07T00:00:00Z",
    ]);
  });

  it("narrows to working hours unless turned off", () => {
    const members = [
      member({
        workingHours: [
          span("2030-03-06T08:00:00Z", "2030-03-06T12:00:00Z"),
          span("2030-03-06T13:00:00Z", "2030-03-06T17:00:00Z"),
        ],
      }),
      member({
        userId: "u2",
        workingHours: [span("2030-03-06T11:00:00Z", "2030-03-06T20:00:00Z")],
      }),
      member({ userId: "u3" }),
    ];

    expect(text(commonFreeTime(members, day))).toEqual([
      "2030-03-06T11:00:00Z/2030-03-06T12:00:00Z",
      "2030-03-06T13:00:00Z/2030-03-06T17:00:00Z",
    ]);
    expect(text(commonFreeTime(members, day, { workingHours: false }))).toEqual(
      ["2030-03-06T00:00:00Z/2030-03-07T00:00:00Z"],
    );
  });

  it("drops ranges shorter than the minimum and empty busy ranges", () => {
    const free = commonFreeTime(
      [
        member({
          busy: [
            span("2030-03-06T00:20:00Z", "2030-03-06T23:00:00Z"),
            span("2030-03-06T05:00:00Z", "2030-03-06T05:00:00Z"),
          ],
        }),
      ],
      day,
      { minimum: Temporal.Duration.from({ minutes: 30 }) },
    );

    expect(text(free)).toEqual(["2030-03-06T23:00:00Z/2030-03-07T00:00:00Z"]);
  });

  it("returns nothing when one member is busy all day", () => {
    expect(
      commonFreeTime(
        [
          member({
            busy: [span("2030-03-05T00:00:00Z", "2030-03-08T00:00:00Z")],
          }),
        ],
        day,
      ),
    ).toEqual([]);
  });
});

describe("calendar availability client", () => {
  function recorder(results: Record<string, unknown>) {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];

    const transport = {
      call(_schema: string, fn: string, args: Record<string, unknown>) {
        calls.push({ fn, args });

        return Promise.resolve(results[fn]);
      },
    };

    return { calls, calendar: createCalendar({ transport, schema: "app" }) };
  }

  it("sets and lists working hours", async () => {
    const { calls, calendar } = recorder({
      set_calendar_working_hours: 2,
      list_calendar_working_hours: [
        {
          userId: "ada",
          tz: "Europe/Amsterdam",
          hours: [{ weekday: 1, start: "09:00", end: "17:00" }],
        },
      ],
    });

    expect(
      await calendar
        .setWorkingHours({
          organizationId: "org",
          input: {
            tz: "Europe/Amsterdam",
            hours: [
              { weekday: 1, start: "09:00", end: "12:00" },
              { weekday: 1, start: "13:00", end: "17:00" },
            ],
          },
        })
        .orThrow(),
    ).toBe(2);
    expect(calls[0]).toEqual({
      fn: "set_calendar_working_hours",
      args: {
        tenant: "org",
        user_id: null,
        tz: "Europe/Amsterdam",
        hours: [
          { weekday: 1, start: "09:00", end: "12:00" },
          { weekday: 1, start: "13:00", end: "17:00" },
        ],
      },
    });

    await calendar.workingHours({ organizationId: "org" }).orThrow();
    await calendar
      .workingHours({ organizationId: "org", userIds: ["ada"] })
      .orThrow();
    expect(calls[1]?.args).toEqual({ tenant: "org", user_ids: null });
    expect(calls[2]?.args).toEqual({ tenant: "org", user_ids: ["ada"] });
  });

  it("asks for free/busy over a range", async () => {
    const { calls, calendar } = recorder({ calendar_free_busy: [] });

    expect(
      await calendar
        .freeBusy({ organizationId: "org", userIds: ["ada"], range: day })
        .orThrow(),
    ).toEqual([]);
    expect(calls[0]).toEqual({
      fn: "calendar_free_busy",
      args: {
        tenant: "org",
        user_ids: ["ada"],
        range_start: "2030-03-06T00:00:00Z",
        range_end: "2030-03-07T00:00:00Z",
      },
    });
  });

  it("reads and copies an event's kind, transparency and auto-decline", async () => {
    const row = {
      id: "e1",
      calendarId: "c1",
      uid: "e1",
      title: "Deep work",
      startsAt: "2030-03-06T08:00:00+00:00",
      endsAt: "2030-03-06T10:00:00+00:00",
      allDay: false,
      tz: "UTC",
      status: "confirmed",
      rrule: null,
      exdates: [],
      recurrenceId: null,
      originalStart: null,
      attendees: [],
    };

    const { calls, calendar } = recorder({
      list_calendar_events: [
        { ...row, kind: "focus_time", transparency: "odd", autoDecline: true },
        { ...row, id: "e2", uid: "e2" },
      ],
      save_calendar_event: { id: "e3", uid: "e3", created: true },
    });

    const [focus, plain] = await calendar
      .events({ calendarIds: ["c1"], range: day })
      .orThrow();

    expect(focus).toMatchObject({
      kind: "focus_time",
      transparency: "opaque",
      autoDecline: true,
    });
    expect(plain).not.toHaveProperty("kind");

    await calendar
      .upsert({
        calendarId: "c1",
        input: {
          title: "Away",
          startsAt: at("2030-03-07T00:00:00Z"),
          endsAt: at("2030-03-08T00:00:00Z"),
          kind: "out_of_office",
          transparency: "opaque",
          autoDecline: true,
        },
      })
      .orThrow();
    expect(calls[1]?.args["item"]).toMatchObject({
      kind: "out_of_office",
      transparency: "opaque",
      autoDecline: true,
    });
  });

  it("counts a missing working-hours result as zero", async () => {
    const { calendar } = recorder({});

    expect(
      await calendar
        .setWorkingHours({
          organizationId: "org",
          input: { tz: "UTC", hours: [], userId: "bob" },
        })
        .orThrow(),
    ).toBe(0);
  });
});
