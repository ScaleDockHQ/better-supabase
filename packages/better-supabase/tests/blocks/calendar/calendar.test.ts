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
    expect(
      await calendar
        .cancelOccurrence({
          seriesId: "s1",
          originalStart: Temporal.Instant.from("2026-04-06T07:00:00Z"),
        })
        .orThrow(),
    ).toBe(true);
    expect(calls.slice(1)).toEqual([
      {
        fn: "cancel_calendar_occurrence",
        args: { event_id: "s1", original_start: "2026-03-30T07:00:00Z" },
      },
      { fn: "delete_calendar_event", args: { event_id: "e1" } },
      {
        fn: "cancel_calendar_occurrence",
        args: { event_id: "s1", original_start: "2026-04-06T07:00:00Z" },
      },
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

  it("deletes calendars and events, and lists the raw events", async () => {
    const { calls, calendar } = recorder({
      delete_calendar: true,
      delete_calendar_event: true,
      list_calendar_events: [SERIES],
      list_calendars: [
        {
          id: "c1",
          name: "Rooms",
          tz: null,
          color: "#f00",
          ownerType: "team",
          ownerId: "t1",
        },
      ],
      save_calendar_event: { id: "e1", uid: "e1", created: false },
    });

    expect(await calendar.deleteCalendar("c1").orThrow()).toBe(true);
    expect(await calendar.delete("e1").orThrow()).toBe(true);
    expect(await calendar.listCalendars("org").orThrow()).toEqual([
      {
        id: "c1",
        name: "Rooms",
        tz: "UTC",
        color: "#f00",
        ownerType: "team",
        ownerId: "t1",
      },
    ]);
    const [event] = await calendar.events(["c1"], range).orThrow();
    expect(event?.rrule).toBe(SERIES.rrule);
    expect(
      await calendar
        .upsert("c1", {
          title: "Review",
          startsAt: range.from,
          endsAt: range.from.add({ hours: 1 }),
          exdates: [range.from],
        })
        .orThrow(),
    ).toEqual({ id: "e1", uid: "e1", created: false });
    expect(calls.at(-1)?.args).toEqual({
      calendar_id: "c1",
      item: {
        title: "Review",
        startsAt: "2026-03-23T00:00:00Z",
        endsAt: "2026-03-23T01:00:00Z",
        exdates: ["2026-03-23T00:00:00Z"],
      },
    });
  });

  it("sets, removes and answers attendees", async () => {
    const { calls, calendar } = recorder({
      set_calendar_attendee: true,
      remove_calendar_attendee: true,
      respond_calendar_event: true,
    });

    await calendar.setAttendee("e1", { email: "a@example.test" }).orThrow();
    await calendar
      .setAttendee("e1", {
        email: "b@example.test",
        name: "Bea",
        userId: "u2",
        role: "optional",
      })
      .orThrow();
    await calendar.removeAttendee("e1", "a@example.test").orThrow();
    await calendar.respond("e1", "tentative").orThrow();
    expect(calls.map((call) => call.args)).toEqual([
      {
        event_id: "e1",
        email: "a@example.test",
        name: null,
        user_id: null,
        role: "required",
      },
      {
        event_id: "e1",
        email: "b@example.test",
        name: "Bea",
        user_id: "u2",
        role: "optional",
      },
      { event_id: "e1", email: "a@example.test" },
      { event_id: "e1", response: "tentative" },
    ]);
  });

  it("edits a single event, an override and a series' extra fields in place", async () => {
    const detailed = {
      ...SERIES,
      description: "Daily sync",
      location: "Room 1",
      subjectType: "project",
      subjectId: "p1",
      color: "blue",
    };

    const override = {
      ...SERIES,
      id: "o1",
      rrule: null,
      recurrenceId: "s1",
      originalStart: "2026-03-30T07:00:00+00:00",
      startsAt: "2026-03-30T09:00:00+00:00",
      endsAt: "2026-03-30T09:15:00+00:00",
      attendees: [{ email: "x@example.test", name: "X", role: "unknown" }],
    };

    const single = {
      ...SERIES,
      id: "e2",
      uid: "e2",
      rrule: null,
      status: "unknown",
      startsAt: "2026-04-01T08:00:00+00:00",
      endsAt: "2026-04-01T09:00:00+00:00",
    };

    const { calls, calendar } = recorder({
      list_calendar_events: [detailed, override, single],
      save_calendar_event: { id: "x", uid: "x", created: false },
    });

    const found = await calendar.occurrences(["c1"], range).orThrow();
    const moved = found.find((item) => item.event.id === "o1")!;
    const lone = found.find((item) => item.event.id === "e2")!;

    const third = found.find(
      (item) => item.start.toString() === "2026-04-06T07:00:00Z",
    )!;

    expect(moved.event.attendees[0]).toEqual({
      email: "x@example.test",
      name: "X",
      role: "required",
      response: "needs-action",
    });
    expect(lone.event.status).toBe("confirmed");
    await calendar.editOccurrence(moved, { title: "Again" }).orThrow();
    await calendar.editOccurrence(lone, { title: "Solo" }).orThrow();
    await calendar.editFollowing(lone, { title: "Solo 2" }).orThrow();
    await calendar.editOccurrence(third, {}).orThrow();
    expect(calls.slice(1).map((call) => call.args)).toEqual([
      { calendar_id: "c1", item: { title: "Again", id: "o1" } },
      { calendar_id: "c1", item: { title: "Solo", id: "e2" } },
      { calendar_id: "c1", item: { title: "Solo 2", id: "e2" } },
      {
        calendar_id: "c1",
        item: expect.objectContaining({
          description: "Daily sync",
          location: "Room 1",
          subjectType: "project",
          subjectId: "p1",
          color: "blue",
          recurrenceId: "s1",
        }),
      },
    ]);
  });

  it("refuses to split a series after its last occurrence", async () => {
    const { calls, calendar } = recorder({ list_calendar_events: [SERIES] });
    const [, , , last] = await calendar.occurrences(["c1"], range).orThrow();

    const beyond = {
      ...last!,
      originalStart: Temporal.Instant.from("2027-01-04T08:00:00Z"),
    };

    const result = await calendar.editFollowing(beyond, { title: "Never" });
    expect(result.ok ? undefined : result.error.hint).toBe(
      "CALENDAR_SPLIT_INVALID",
    );
    expect(calls).toHaveLength(1);
  });
});

describe("calendar adoption options", () => {
  it("creates and updates calendars with details and visibility", async () => {
    const { calls, calendar } = recorder({
      create_calendar: { id: "c2" },
      update_calendar: true,
      list_calendars: [
        {
          id: "c2",
          name: "Mine",
          tz: "UTC",
          visibility: "private",
          description: "Personal",
          rank: "a0",
          isDefault: true,
        },
      ],
    });

    await calendar
      .createCalendar("org", "Mine", {
        ownerType: "user",
        ownerId: "u1",
        visibility: "private",
        isDefault: true,
      })
      .orThrow();
    expect(calls[0]?.args["attrs"]).toEqual({
      visibility: "private",
      isDefault: true,
    });
    expect(
      await calendar
        .updateCalendar("c2", { name: "Mine (old)", rank: null })
        .orThrow(),
    ).toBe(true);
    expect(calls[1]).toEqual({
      fn: "update_calendar",
      args: { calendar_id: "c2", attrs: { rank: null, name: "Mine (old)" } },
    });
    expect(await calendar.listCalendars("org").orThrow()).toEqual([
      {
        id: "c2",
        name: "Mine",
        tz: "UTC",
        visibility: "private",
        description: "Personal",
        rank: "a0",
        isDefault: true,
      },
    ]);
  });

  it("keys attendees by subject and removes one by id", async () => {
    const { calls, calendar } = recorder({
      set_calendar_attendee: { id: "a1", created: true },
      remove_calendar_attendee: true,
      list_calendar_events: [
        {
          ...SERIES,
          attendees: [
            {
              id: "a1",
              email: null,
              name: "Ada",
              userId: null,
              role: "optional",
              response: "needs-action",
              subjectType: "contact",
              subjectId: "c-1",
              organizer: false,
              optional: true,
            },
          ],
        },
      ],
    });

    expect(
      await calendar
        .setAttendee("e1", {
          subjectType: "contact",
          subjectId: "c-1",
          optional: true,
        })
        .orThrow(),
    ).toBe(true);
    expect(calls[0]?.args).toEqual({
      event_id: "e1",
      attendee: { subjectType: "contact", subjectId: "c-1", optional: true },
    });
    expect(await calendar.removeAttendeeById("a1").orThrow()).toBe(true);
    expect(calls[1]?.args).toEqual({ attendee_id: "a1" });

    const [event] = await calendar.events(["c1"], range).orThrow();

    expect(event?.attendees).toEqual([
      {
        id: "a1",
        email: "",
        name: "Ada",
        role: "optional",
        response: "needs-action",
        subjectType: "contact",
        subjectId: "c-1",
        organizer: false,
        optional: true,
      },
    ]);
  });

  it("grants access to a calendar and lists the grants", async () => {
    const { calls, calendar } = recorder({
      set_calendar_grant: true,
      remove_calendar_grant: true,
      list_calendar_grants: [{ userId: "u2", role: "editor" }],
    });

    expect(await calendar.setGrant("c1", "u2", "editor").orThrow()).toBe(true);
    expect(await calendar.grants("c1").orThrow()).toEqual([
      { userId: "u2", role: "editor" },
    ]);
    expect(await calendar.removeGrant("c1", "u2").orThrow()).toBe(true);
    expect(calls.map((call) => call.fn)).toEqual([
      "set_calendar_grant",
      "list_calendar_grants",
      "remove_calendar_grant",
    ]);
  });

  it("expands RDATEs and serves a user's feed with them", async () => {
    const withDates = {
      ...SERIES,
      rrule: "FREQ=WEEKLY;BYDAY=MO;COUNT=2",
      rdates: ["2026-03-25T08:00:00+00:00"],
      visibility: "private",
      ownerId: "u1",
    };

    const { calendar } = recorder({
      list_calendar_events: [withDates],
      calendar_user_feed: { userId: "u1", calendars: [], events: [withDates] },
    });

    const found = await calendar.occurrences(["c1"], range).orThrow();

    expect(found.map((item) => item.start.toString())).toEqual([
      "2026-03-23T08:00:00Z",
      "2026-03-25T08:00:00Z",
      "2026-03-30T07:00:00Z",
    ]);
    expect(found[0]?.event).toMatchObject({
      visibility: "private",
      ownerId: "u1",
    });

    const ics = await calendar.userFeed("t".repeat(40)).orThrow();

    expect(ics).toContain("RDATE;TZID=Europe/Amsterdam:20260325T090000\r\n");
  });

  it("reads RDATEs from an iCalendar file", async () => {
    const { calls, calendar } = recorder({
      import_calendar_events: { created: 1, updated: 0, skipped: 0 },
    });

    await calendar
      .importIcs(
        "c1",
        [
          "BEGIN:VCALENDAR",
          "BEGIN:VEVENT",
          "UID:x1",
          "DTSTART:20260302T090000Z",
          "DTEND:20260302T100000Z",
          "RDATE:20260305T090000Z,20260306T090000Z/20260306T100000Z",
          "END:VEVENT",
          "END:VCALENDAR",
        ].join("\r\n"),
      )
      .orThrow();

    expect(calls[0]?.args["source"]).toMatchObject({
      events: [{ uid: "x1", rdates: ["2026-03-05T09:00:00Z"] }],
    });
  });
});
