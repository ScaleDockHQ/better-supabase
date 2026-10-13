import { describe, expect, it } from "vitest";

import { createCalendar } from "../../../src/blocks/calendar/calendar.ts";

interface Call {
  readonly fn: string;
  readonly args: Readonly<Record<string, unknown>>;
}

function recorder(results: Record<string, unknown>) {
  const calls: Call[] = [];
  const transport = {
    call(schema: string, fn: string, args: Readonly<Record<string, unknown>>) {
      expect(schema).toBe("app");
      calls.push({ fn, args });
      const result = results[fn];
      return result instanceof Error
        ? Promise.reject(result)
        : Promise.resolve(result);
    },
  };
  return { calls, calendar: createCalendar({ transport, schema: "app" }) };
}

const SERIES = {
  id: "s1",
  calendarId: "c1",
  uid: "s1",
  title: "Stand-up",
  startsAt: "2026-03-23T08:00:00+00:00",
  endsAt: "2026-03-23T08:15:00+00:00",
  allDay: false,
  tz: "Europe/Amsterdam",
  status: "confirmed",
  rrule: "FREQ=WEEKLY;BYDAY=MO;COUNT=4",
  exdates: [],
  recurrenceId: null,
  originalStart: null,
  attendees: [
    {
      email: "jane@example.test",
      name: null,
      userId: "u1",
      role: "chair",
      response: "accepted",
    },
  ],
  updatedAt: "2026-03-01T00:00:00+00:00",
};

const range = {
  from: Temporal.Instant.from("2026-03-23T00:00:00Z"),
  until: Temporal.Instant.from("2026-04-30T00:00:00Z"),
};

describe("calendar client", () => {
  it("creates and lists calendars", async () => {
    const { calls, calendar } = recorder({
      create_calendar: { id: "c1" },
      list_calendars: [
        { id: "c1", name: "Team", tz: "Europe/Amsterdam", color: null },
      ],
    });
    expect(
      await calendar
        .createCalendar("org", "Team", { tz: "Europe/Amsterdam" })
        .orThrow(),
    ).toEqual({ id: "c1" });
    expect(calls[0]?.args).toEqual({
      tenant: "org",
      name: "Team",
      tz: "Europe/Amsterdam",
      owner_type: null,
      owner_id: null,
    });
    expect(await calendar.listCalendars("org").orThrow()).toEqual([
      { id: "c1", name: "Team", tz: "Europe/Amsterdam" },
    ]);
  });

  it("expands occurrences from the listed rows", async () => {
    const { calls, calendar } = recorder({ list_calendar_events: [SERIES] });
    const found = await calendar.occurrences(["c1"], range).orThrow();
    expect(found.map((item) => item.start.toString())).toEqual([
      "2026-03-23T08:00:00Z",
      "2026-03-30T07:00:00Z",
      "2026-04-06T07:00:00Z",
      "2026-04-13T07:00:00Z",
    ]);
    expect(found[0]?.event.attendees).toEqual([
      {
        email: "jane@example.test",
        userId: "u1",
        role: "chair",
        response: "accepted",
      },
    ]);
    expect(calls[0]?.args).toEqual({
      calendar_ids: ["c1"],
      range_start: "2026-03-23T00:00:00Z",
      range_end: "2026-04-30T00:00:00Z",
    });
  });

  it("overrides one occurrence of a series", async () => {
    const { calls, calendar } = recorder({
      list_calendar_events: [SERIES],
      save_calendar_event: { id: "o1", uid: "s1", created: true },
    });
    const [, second] = await calendar.occurrences(["c1"], range).orThrow();
    const saved = await calendar
      .editOccurrence(second!, { title: "Moved" })
      .orThrow();
    expect(saved).toEqual({ id: "o1", uid: "s1", created: true });
    expect(calls[1]).toEqual({
      fn: "save_calendar_event",
      args: {
        calendar_id: "c1",
        item: {
          title: "Moved",
          allDay: false,
          tz: "Europe/Amsterdam",
          status: "confirmed",
          startsAt: "2026-03-30T07:00:00Z",
          endsAt: "2026-03-30T07:15:00Z",
          rrule: null,
          exdates: [],
          recurrenceId: "s1",
          originalStart: "2026-03-30T07:00:00Z",
        },
      },
    });
  });

  it("splits a series for this and following", async () => {
    const { calls, calendar } = recorder({
      list_calendar_events: [SERIES],
      split_calendar_event: { id: "s2", uid: "s1-20260406T070000Z" },
    });
    const [, , third] = await calendar.occurrences(["c1"], range).orThrow();
    const result = await calendar
      .editFollowing(third!, { title: "Later" })
      .orThrow();
    expect(result).toEqual({ id: "s2" });
    expect(calls[1]?.fn).toBe("split_calendar_event");
    expect(calls[1]?.args).toMatchObject({
      event_id: "s1",
      split_at: "2026-04-06T07:00:00Z",
      before_rrule: "FREQ=WEEKLY;BYDAY=MO;UNTIL=20260406T065959Z",
      item: {
        title: "Later",
        startsAt: "2026-04-06T07:00:00Z",
        endsAt: "2026-04-06T07:15:00Z",
        rrule: "FREQ=WEEKLY;BYDAY=MO;COUNT=2",
      },
    });
  });

  it("edits the whole series from its first occurrence", async () => {
    const { calls, calendar } = recorder({
      list_calendar_events: [SERIES],
      save_calendar_event: { id: "s1", uid: "s1", created: false },
    });
    const [first] = await calendar.occurrences(["c1"], range).orThrow();
    await calendar.editFollowing(first!, { title: "Renamed" });
    expect(calls[1]).toEqual({
      fn: "save_calendar_event",
      args: { calendar_id: "c1", item: { title: "Renamed", id: "s1" } },
    });
  });

  it("cancels an occurrence with an EXDATE and deletes a single event", async () => {
    const single = { ...SERIES, id: "e1", rrule: null };
    const { calls, calendar } = recorder({
      list_calendar_events: [SERIES, single],
      cancel_calendar_occurrence: true,
      delete_calendar_event: true,
    });
    const found = await calendar.occurrences(["c1"], range).orThrow();
    const occurrence = found.find(
      (item) =>
        item.event.id === "s1" &&
        item.start.toString() === "2026-03-30T07:00:00Z",
    );
    const event = found.find((item) => item.event.id === "e1");
    expect(await calendar.cancelOccurrence(occurrence!).orThrow()).toBe(true);
    expect(await calendar.cancelOccurrence(event!).orThrow()).toBe(true);
    expect(calls.slice(1)).toEqual([
      {
        fn: "cancel_calendar_occurrence",
        args: { event_id: "s1", original_start: "2026-03-30T07:00:00Z" },
      },
      { fn: "delete_calendar_event", args: { event_id: "e1" } },
    ]);
  });

  it("imports an iCalendar file and exports one", async () => {
    const { calls, calendar } = recorder({
      import_calendar_events: { created: 1, updated: 0, skipped: 0 },
      list_calendar_events: [SERIES],
    });
    const ics = [
      "BEGIN:VCALENDAR",
      "BEGIN:VEVENT",
      "UID:a@example.test",
      "DTSTART:20260401T100000Z",
      "DTEND:20260401T110000Z",
      "SUMMARY:Review",
      "END:VEVENT",
      "BEGIN:VEVENT",
      "SUMMARY:No uid",
      "END:VEVENT",
      "END:VCALENDAR",
    ].join("\r\n");
    expect(await calendar.importIcs("c1", ics).orThrow()).toEqual({
      created: 1,
      updated: 0,
      skipped: 1,
    });
    expect(calls[0]?.args).toMatchObject({
      calendar_id: "c1",
      source: {
        events: [
          {
            uid: "a@example.test",
            title: "Review",
            startsAt: "2026-04-01T10:00:00Z",
            endsAt: "2026-04-01T11:00:00Z",
            tz: "UTC",
            rrule: null,
            exdates: [],
          },
        ],
      },
    });
    const out = await calendar
      .exportIcs({ id: "c1", name: "Team", tz: "Europe/Amsterdam" })
      .orThrow();
    expect(out).toContain("X-WR-CALNAME:Team\r\n");
    expect(out).toContain("RRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=4\r\n");
    expect(calls[1]?.args).toMatchObject({
      range_start: "-infinity",
      range_end: "infinity",
    });
  });

  it("serves a share link feed, or null for an unknown token", async () => {
    const { calendar } = recorder({
      calendar_feed: {
        calendar: { id: "c1", name: "Team", tz: "UTC" },
        events: [SERIES],
      },
    });
    const feed = await calendar.feed("t".repeat(48)).orThrow();
    expect(feed).toContain("UID:s1\r\n");
    const none = recorder({ calendar_feed: null });
    expect(await none.calendar.feed("bad").orThrow()).toBeNull();
  });

  it("maps a database error to a Result", async () => {
    const { calendar } = recorder({
      delete_calendar_event: Object.assign(new Error("event not found"), {
        code: "P0002",
        hint: "CALENDAR_EVENT_NOT_FOUND",
      }),
    });
    const result = await calendar.delete("missing");
    expect(result.ok).toBe(false);
  });
});
