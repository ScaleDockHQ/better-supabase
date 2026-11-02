import * as v from "valibot";
import { describe, expect, it } from "vitest";

import {
  calendarEventOf,
  createCalendar,
} from "../../../src/blocks/calendar/calendar.ts";

interface Call {
  readonly fn: string;
  readonly args: Readonly<Record<string, unknown>>;
}

function recorder(results: Record<string, unknown>) {
  const calls: Call[] = [];

  const transport = {
    call(_schema: string, fn: string, args: Readonly<Record<string, unknown>>) {
      calls.push({ fn, args });

      return Promise.resolve(results[fn]);
    },
  };

  return { calls, calendar: createCalendar({ transport }) };
}

const BASE = {
  id: "s1",
  calendarId: "c1",
  uid: "s1",
  startsAt: "2026-03-23T08:00:00+00:00",
  endsAt: "2026-03-23T08:15:00+00:00",
};

const FULL = {
  ...BASE,
  title: "Stand-up",
  description: "Daily",
  location: "Room 1",
  allDay: false,
  tz: "Europe/Amsterdam",
  status: "tentative",
  rrule: "FREQ=WEEKLY;BYDAY=MO;COUNT=4",
  exdates: ["2026-03-30T07:00:00+00:00"],
  rdates: ["2026-03-25T08:00:00+00:00"],
  recurrenceId: null,
  subjectType: "project",
  subjectId: "p1",
  color: "#fff",
  kind: "focus_time",
  transparency: "transparent",
  autoDecline: true,
  visibility: "private",
  ownerId: "u1",
  alarms: [{ method: "audio", offsetMinutes: 5, related: "end" }],
  attendees: [],
  reminders: [],
  updatedAt: "2026-03-01T00:00:00+00:00",
  originalStart: "2026-03-23T08:00:00+00:00",
};

const range = {
  from: Temporal.Instant.from("2026-03-22T00:00:00Z"),
  until: Temporal.Instant.from("2026-04-30T00:00:00Z"),
};

describe("calendarEventOf", () => {
  it("fills defaults for a sparse row", () => {
    const event = calendarEventOf(BASE);

    expect(event).toMatchObject({
      title: "",
      tz: "UTC",
      status: "confirmed",
      allDay: false,
      exdates: [],
      attendees: [],
      reminders: [],
    });
    expect(event.rdates).toBeUndefined();
    expect(event.alarms).toBeUndefined();
    expect(event.kind).toBeUndefined();
    expect(event.visibility).toBeUndefined();
  });

  it("reads every optional column", () => {
    const event = calendarEventOf(FULL);

    expect(event).toMatchObject({
      status: "tentative",
      kind: "focus_time",
      transparency: "transparent",
      autoDecline: true,
      visibility: "private",
      ownerId: "u1",
      subjectType: "project",
      subjectId: "p1",
      color: "#fff",
    });
    expect(event.exdates).toHaveLength(1);
    expect(event.rdates).toHaveLength(1);
    expect(event.alarms).toEqual([
      { method: "audio", offsetMinutes: 5, related: "end" },
    ]);
    expect(event.originalStart?.toString()).toBe("2026-03-23T08:00:00Z");
    expect(event.updatedAt?.toString()).toBe("2026-03-01T00:00:00Z");
  });
});

describe("calendar writes", () => {
  it("sends the actor and the instants, dates and alarms of an event", async () => {
    const { calls, calendar } = recorder({
      save_calendar_event: { id: "e1", uid: "u", created: false },
    });

    await calendar
      .upsert({
        calendarId: "c1",
        actor: "u9",
        input: {
          title: "x",
          startsAt: Temporal.Instant.from("2026-03-23T08:00:00Z"),
          endsAt: Temporal.Instant.from("2026-03-23T09:00:00Z"),
          exdates: [Temporal.Instant.from("2026-03-30T08:00:00Z")],
          rdates: [Temporal.Instant.from("2026-03-25T08:00:00Z")],
          alarms: [{ method: "display", offsetMinutes: 10 }],
        },
      })
      .orThrow();

    expect(calls[0]?.args).toEqual({
      calendar_id: "c1",
      actor: "u9",
      item: {
        title: "x",
        startsAt: "2026-03-23T08:00:00Z",
        endsAt: "2026-03-23T09:00:00Z",
        exdates: ["2026-03-30T08:00:00Z"],
        rdates: ["2026-03-25T08:00:00Z"],
        alarms: [{ method: "display", offsetMinutes: 10 }],
      },
    });
  });

  it("creates a calendar with fields and attributes", async () => {
    const { calls, calendar } = recorder({ create_calendar: { id: "c1" } });

    await calendar
      .createCalendar({
        organizationId: "o",
        name: "Team",
        options: {
          ownerType: "user",
          ownerId: "u1",
          fields: { team: "x" },
          color: "#000",
          isDefault: true,
        },
      })
      .orThrow();

    expect(calls[0]?.args).toEqual({
      tenant: "o",
      name: "Team",
      tz: "UTC",
      owner_type: "user",
      owner_id: "u1",
      fields: { team: "x" },
      attrs: { color: "#000", isDefault: true },
    });
  });

  it("updates a calendar's name and zone with other attributes", async () => {
    const { calls, calendar } = recorder({ update_calendar: true });

    await calendar
      .updateCalendar({
        id: "c1",
        attributes: { name: "New", tz: "Europe/Paris", rank: "a" },
      })
      .orThrow();
    await calendar
      .updateCalendar({ id: "c1", attributes: { visibility: "private" } })
      .orThrow();

    expect(calls[0]?.args).toEqual({
      calendar_id: "c1",
      attrs: { rank: "a", name: "New", tz: "Europe/Paris" },
    });
    expect(calls[1]?.args).toEqual({
      calendar_id: "c1",
      attrs: { visibility: "private" },
    });
  });

  it("lists calendars with every optional column", async () => {
    const { calendar } = recorder({
      list_calendars: [
        {
          id: "c1",
          name: "Team",
          color: "#fff",
          ownerType: "user",
          ownerId: "u1",
          description: "d",
          rank: "a",
          visibility: "private",
          isDefault: true,
          fields: { k: 1 },
        },
        { id: "c2", name: "Bare", visibility: "odd" },
      ],
    });

    expect(await calendar.listCalendars("o").orThrow()).toEqual([
      {
        id: "c1",
        name: "Team",
        tz: "UTC",
        color: "#fff",
        ownerType: "user",
        ownerId: "u1",
        description: "d",
        rank: "a",
        visibility: "private",
        isDefault: true,
        fields: { k: 1 },
      },
      { id: "c2", name: "Bare", tz: "UTC", visibility: "shared" },
    ]);
  });

  it("reads and replaces default alarms without their ids", async () => {
    const { calls, calendar } = recorder({
      list_calendar_default_alarms: [
        {
          id: "a1",
          allDay: true,
          method: "email",
          offsetMinutes: 60,
          anchor: "08:00",
        },
        { allDay: false, anchor: "08:00" },
      ],
      set_calendar_default_alarms: [],
    });

    expect(await calendar.defaultAlarms("c1").orThrow()).toEqual([
      {
        id: "a1",
        allDay: true,
        method: "email",
        offsetMinutes: 60,
        anchor: "08:00",
      },
      { allDay: false, method: "display", offsetMinutes: 0 },
    ]);

    await calendar
      .setDefaultAlarms({
        calendarId: "c1",
        alarms: [{ id: "a1", allDay: true, offsetMinutes: 30 }],
      })
      .orThrow();

    expect(calls[1]?.args).toEqual({
      calendar_id: "c1",
      alarms: [{ allDay: true, offsetMinutes: 30 }],
    });
  });

  it("copies every series column into an override and clears its rdates", async () => {
    const { calls, calendar } = recorder({
      list_calendar_events: [FULL],
      save_calendar_event: { id: "o1", uid: "s1", created: true },
    });

    const found = await calendar
      .occurrences({ calendarIds: ["c1"], range })
      .orThrow();

    const second = found.find(
      (item) => item.start.toString() === "2026-03-25T08:00:00Z",
    );

    expect(second).toBeDefined();

    if (second === undefined) {
      return;
    }

    await calendar
      .editOccurrence({ occurrence: second, changes: { title: "Moved" } })
      .orThrow();

    expect(calls[1]?.args["item"]).toMatchObject({
      title: "Moved",
      description: "Daily",
      location: "Room 1",
      subjectType: "project",
      subjectId: "p1",
      color: "#fff",
      kind: "focus_time",
      transparency: "transparent",
      autoDecline: true,
      visibility: "private",
      alarms: [{ method: "audio", offsetMinutes: 5, related: "end" }],
      rrule: null,
      exdates: [],
      rdates: [],
      recurrenceId: "s1",
    });
  });
});

describe("calendar custom event fields", () => {
  it("validates extra fields on write", async () => {
    const calls: Call[] = [];

    const calendar = createCalendar({
      fields: v.object({ room: v.string() }),
      logger: {
        error: () => undefined,
        warn: () => undefined,
        info: () => undefined,
        debug: () => undefined,
      },
      transport: {
        call(_schema, fn, args) {
          calls.push({ fn, args });

          return Promise.resolve({ id: "e1", uid: "u", created: true });
        },
      },
    });

    await calendar
      .upsert({
        calendarId: "c1",
        input: {
          title: "x",
          startsAt: Temporal.Instant.from("2026-03-23T08:00:00Z"),
          endsAt: Temporal.Instant.from("2026-03-23T09:00:00Z"),
          room: "R1",
        },
      })
      .orThrow();

    expect(calls[0]?.args["item"]).toMatchObject({ room: "R1" });
  });
});

describe("calendar imports and feeds", () => {
  it("imports recurrence overrides and transparency, and counts missing totals as zero", async () => {
    const { calls, calendar } = recorder({ import_calendar_events: {} });

    const result = await calendar
      .importIcs({
        calendarId: "c1",
        text: [
          "BEGIN:VCALENDAR",
          "BEGIN:VEVENT",
          "UID:x1",
          "DTSTART:20260302T090000Z",
          "DTEND:20260302T100000Z",
          "TRANSP:TRANSPARENT",
          "RECURRENCE-ID:20260302T090000Z",
          "RDATE:20260305T090000Z",
          "END:VEVENT",
          "END:VCALENDAR",
        ].join("\r\n"),
      })
      .orThrow();

    expect(result).toEqual({ created: 0, updated: 0, skipped: 0 });
    expect(calls[0]?.args["source"]).toMatchObject({
      events: [
        {
          uid: "x1",
          transparency: "transparent",
          originalStart: "2026-03-02T09:00:00Z",
          rdates: ["2026-03-05T09:00:00Z"],
        },
      ],
    });
  });

  it("returns null for unknown feed tokens, user feeds and feed data", async () => {
    const { calendar } = recorder({
      calendar_feed: null,
      calendar_user_feed: undefined,
    });

    expect(await calendar.feed("t").orThrow()).toBeNull();
    expect(await calendar.feedData("t").orThrow()).toBeNull();
    expect(await calendar.userFeed("t").orThrow()).toBeNull();
    expect(await calendar.userFeedData("t").orThrow()).toBeNull();
  });

  it("serves a feed with an organization and its creator, and a user feed with calendars", async () => {
    const { calendar } = recorder({
      calendar_feed: {
        calendar: { id: "c1", name: "Team", tz: "UTC", color: "#fff" },
        organization: { id: "o1", name: "Org" },
        createdBy: "u1",
        events: [BASE],
      },
      calendar_user_feed: {
        userId: "u1",
        organization: { id: "o1" },
        calendars: [{ id: "c1", name: "Team" }],
        events: [BASE],
      },
    });

    const data = await calendar.feedData("t").orThrow();

    expect(data).toMatchObject({
      organization: { id: "o1", name: "Org" },
      createdBy: "u1",
      calendar: { id: "c1", color: "#fff" },
    });
    expect(await calendar.feed("t").orThrow()).toContain("X-WR-CALNAME:Team");

    const user = await calendar.userFeedData("t").orThrow();

    expect(user).toMatchObject({
      userId: "u1",
      organization: { id: "o1" },
      calendars: [{ id: "c1", name: "Team", tz: "UTC" }],
    });
    expect(await calendar.userFeed("t").orThrow()).toContain("BEGIN:VCALENDAR");
  });

  it("ignores an organization that is not an object", async () => {
    const { calendar } = recorder({
      calendar_feed: {
        calendar: { id: "c1", name: "Team" },
        organization: "x",
        events: [],
      },
    });

    const data = await calendar.feedData("t").orThrow();

    expect(data?.organization).toBeUndefined();
    expect(data?.createdBy).toBeUndefined();
  });
});
