import { describe, expect, it } from "vitest";

import type { CalendarEvent } from "../../../src/blocks/calendar/occurrences.ts";

import {
  fromEventCalendarUpdate,
  seriesOf,
  toEventCalendarEvents,
  toEventCalendarResources,
} from "../../../src/blocks/calendar/event-calendar.ts";
import {
  expandOccurrences,
  splitRule,
} from "../../../src/blocks/calendar/occurrences.ts";
import { expandRule } from "../../../src/blocks/reminders/rrule.ts";

const at = (text: string): Temporal.Instant => Temporal.Instant.from(text);

const base = {
  calendarId: "c1",
  allDay: false,
  status: "confirmed",
  exdates: [],
  attendees: [],
} as const;

const standup: CalendarEvent = {
  ...base,
  id: "s1",
  uid: "s1",
  title: "Stand-up",
  tz: "Europe/Amsterdam",
  startsAt: at("2026-03-23T08:00:00Z"),
  endsAt: at("2026-03-23T08:15:00Z"),
  rrule: "FREQ=WEEKLY;BYDAY=MO,WE",
  exdates: [at("2026-03-25T08:00:00Z")],
};

const moved: CalendarEvent = {
  ...base,
  id: "o1",
  uid: "s1",
  title: "Stand-up (moved)",
  tz: "Europe/Amsterdam",
  startsAt: at("2026-04-02T07:00:00Z"),
  endsAt: at("2026-04-02T07:30:00Z"),
  recurrenceId: "s1",
  originalStart: at("2026-04-01T07:00:00Z"),
};

const lunch: CalendarEvent = {
  ...base,
  id: "l1",
  uid: "l1",
  title: "Lunch",
  tz: "UTC",
  startsAt: at("2026-03-30T11:00:00Z"),
  endsAt: at("2026-03-30T12:00:00Z"),
  color: "green",
};

const range = {
  from: at("2026-03-23T00:00:00Z"),
  until: at("2026-04-06T00:00:00Z"),
};

describe("expandOccurrences", () => {
  const found = expandOccurrences([standup, moved, lunch], range);

  it("expands series across DST, drops EXDATEs and applies overrides", () => {
    expect(found.map((item) => [item.event.id, item.start.toString()])).toEqual(
      [
        ["s1", "2026-03-23T08:00:00Z"],
        ["s1", "2026-03-30T07:00:00Z"],
        ["l1", "2026-03-30T11:00:00Z"],
        ["o1", "2026-04-02T07:00:00Z"],
      ],
    );
  });

  it("keeps the series' wall-clock length and key for each occurrence", () => {
    const second = found[1];
    expect(second?.end.toString()).toBe("2026-03-30T07:15:00Z");
    expect(second?.key).toBe("s1::2026-03-30T07:00:00Z");
    expect(second?.series?.id).toBe("s1");
    expect(found[3]).toMatchObject({
      key: "s1::2026-04-01T07:00:00Z",
      recurring: true,
    });
    expect(found[3]?.series?.id).toBe("s1");
  });

  it("hides an occurrence whose override moved out of the range", () => {
    const out = expandOccurrences(
      [
        standup,
        {
          ...moved,
          startsAt: at("2026-05-01T07:00:00Z"),
          endsAt: at("2026-05-01T07:30:00Z"),
        },
      ],
      range,
    );

    expect(out.map((item) => item.start.toString())).not.toContain(
      "2026-04-01T07:00:00Z",
    );
  });

  it("includes an occurrence that started before the range and ends in it", () => {
    const night: CalendarEvent = {
      ...base,
      id: "n1",
      uid: "n1",
      title: "Night shift",
      tz: "UTC",
      startsAt: at("2026-03-01T22:00:00Z"),
      endsAt: at("2026-03-02T06:00:00Z"),
      rrule: "FREQ=DAILY",
    };

    const out = expandOccurrences([night], {
      from: at("2026-03-10T00:00:00Z"),
      until: at("2026-03-10T12:00:00Z"),
    });

    expect(out.map((item) => item.start.toString())).toEqual([
      "2026-03-09T22:00:00Z",
    ]);
  });

  it("leaves out cancelled events unless asked", () => {
    const cancelled = { ...lunch, status: "cancelled" } as const;
    expect(expandOccurrences([cancelled], range)).toEqual([]);
    expect(
      expandOccurrences([cancelled], range, { includeCancelled: true }),
    ).toHaveLength(1);
  });
});

describe("splitRule", () => {
  const dtstart = standup.startsAt.toZonedDateTimeISO("Europe/Amsterdam");

  it("ends the first series with UNTIL one second before the split", () => {
    expect(
      splitRule("FREQ=WEEKLY;BYDAY=MO,WE", dtstart, at("2026-04-01T07:00:00Z")),
    ).toEqual({
      before: "FREQ=WEEKLY;BYDAY=MO,WE;UNTIL=20260401T065959Z",
      after: "FREQ=WEEKLY;BYDAY=MO,WE",
    });
  });

  it("carries the occurrences left of a COUNT over to the second series", () => {
    const rrule = "FREQ=WEEKLY;BYDAY=MO,WE;COUNT=6";
    const split = splitRule(rrule, dtstart, at("2026-04-01T07:00:00Z"));
    expect(split.after).toBe("FREQ=WEEKLY;BYDAY=MO,WE;COUNT=3");
    const first = expandRule({ dtstart, rrule: split.before });
    expect(first).toHaveLength(3);
  });

  it("refuses a split at or before the first occurrence, or after the last", () => {
    expect(() => splitRule("FREQ=DAILY", dtstart, standup.startsAt)).toThrow(
      RangeError,
    );
    expect(() =>
      splitRule("FREQ=DAILY;COUNT=2", dtstart, at("2027-01-01T00:00:00Z")),
    ).toThrow(RangeError);
  });
});

describe("event calendar adapters", () => {
  const found = expandOccurrences([standup, moved, lunch], range);

  it("maps occurrences to the event calendar shape", () => {
    const events = toEventCalendarEvents(found, {
      readOnly: (item) => item.event.id === "l1",
    });

    expect(events[0]).toMatchObject({
      id: "s1::2026-03-23T08:00:00Z",
      title: "Stand-up",
      allDay: false,
      recurringEventId: "s1",
      resourceId: "c1",
    });
    expect(events[0]?.start).toEqual(new Date("2026-03-23T08:00:00Z"));
    expect(events[0]?.originalStart).toEqual(new Date("2026-03-23T08:00:00Z"));
    expect(events[2]).toMatchObject({ color: "green", readOnly: true });
    expect(events[2]?.recurringEventId).toBeUndefined();
    expect(events[3]?.recurringEventId).toBe("s1");
    expect(events[3]?.data?.event.id).toBe("o1");
  });

  it("maps resources and updates", () => {
    expect(
      toEventCalendarResources([{ id: "c1", name: "Team", color: "blue" }]),
    ).toEqual([{ id: "c1", title: "Team", color: "blue" }]);

    const move = fromEventCalendarUpdate({
      start: new Date("2026-03-23T09:00:00Z"),
      end: new Date("2026-03-23T09:15:00Z"),
      allDay: false,
    });

    expect(move.startsAt.toString()).toBe("2026-03-23T09:00:00Z");
    expect(move).toMatchObject({ allDay: false });
  });

  it("leaves out the fields an occurrence or update does not have", () => {
    expect(toEventCalendarResources([{ id: "c1", name: "Team" }])).toEqual([
      { id: "c1", title: "Team" },
    ]);
    expect(
      fromEventCalendarUpdate({
        start: new Date("2026-03-23T09:00:00Z"),
        end: new Date("2026-03-23T09:15:00Z"),
      }),
    ).not.toHaveProperty("allDay");

    const [first] = toEventCalendarEvents(found, {
      resourceOf: () => undefined,
    });

    expect(first).not.toHaveProperty("resourceId");
    expect(first).not.toHaveProperty("readOnly");
    expect(seriesOf(found[0]!).id).toBe("s1");
    expect(seriesOf(found[2]!).id).toBe("l1");
  });
});
