import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { Calendar } from "../../src/blocks/calendar/calendar.ts";
import type { TestUser } from "./block-session.ts";

import { createCalendar } from "../../src/blocks/calendar/calendar.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const at = (text: string): Temporal.Instant => Temporal.Instant.from(text);

const range = {
  from: at("2026-03-01T00:00:00Z"),
  until: at("2026-05-01T00:00:00Z"),
};

describe.skipIf(!live)("calendar block in Postgres", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  let session: BlockSession;
  let calendar: Calendar;
  let owner: TestUser;
  let member: TestUser;
  let viewer: TestUser;
  let outsider: TestUser;
  let org: string;
  let calendarId: string;
  let seriesId: string;

  beforeAll(async () => {
    session = await BlockSession.open(pool);
    await session.install(
      ["organizations", "calendar", "share-links", "reminders"],
      {
        modules: { calendar: { schema: "calendar_it" } },
      },
    );
    owner = await session.user("owner");
    member = await session.user("member");
    viewer = await session.user("viewer");
    outsider = await session.user("outsider");
    org = await session.organization(owner, { member, viewer });
    calendar = createCalendar({
      transport: sqlTransport(session.sql),
      schema: "calendar_it",
    });
  });

  afterAll(async () => {
    await session.close();
    await pool.end();
  });

  it("creates a calendar for a manager and refuses a member", async () => {
    await session.as(member);
    const refused = await calendar.createCalendar(org, "Nope");
    expect(refused.ok ? undefined : refused.error.hint).toBe(
      "CALENDAR_FORBIDDEN",
    );
    await session.as(owner);
    const bad = await calendar.createCalendar(org, "Bad", { tz: "Mars/Base" });
    expect(bad.ok ? undefined : bad.error.hint).toBe("CALENDAR_TZ_INVALID");
    ({ id: calendarId } = await calendar
      .createCalendar(org, "Team", { tz: "Europe/Amsterdam" })
      .orThrow());
    expect(await calendar.listCalendars(org).orThrow()).toEqual([
      { id: calendarId, name: "Team", tz: "Europe/Amsterdam" },
    ]);
  });

  it("saves a series as a member and expands it across DST", async () => {
    await session.as(member);

    const saved = await calendar
      .save(calendarId, {
        title: "Stand-up",
        startsAt: at("2026-03-23T08:00:00Z"),
        endsAt: at("2026-03-23T08:15:00Z"),
        tz: "Europe/Amsterdam",
        rrule: "FREQ=WEEKLY;BYDAY=MO;COUNT=6",
      })
      .orThrow();

    seriesId = saved.id;
    expect(saved).toMatchObject({ uid: saved.id, created: true });
    const found = await calendar.occurrences([calendarId], range).orThrow();
    expect(found.map((item) => item.start.toString())).toEqual([
      "2026-03-23T08:00:00Z",
      "2026-03-30T07:00:00Z",
      "2026-04-06T07:00:00Z",
      "2026-04-13T07:00:00Z",
      "2026-04-20T07:00:00Z",
      "2026-04-27T07:00:00Z",
    ]);
  });

  it("refuses a viewer and an invalid event", async () => {
    await session.as(viewer);

    const refused = await calendar.save(calendarId, {
      title: "x",
      startsAt: at("2026-03-01T08:00:00Z"),
      endsAt: at("2026-03-01T09:00:00Z"),
    });

    expect(refused.ok ? undefined : refused.error.hint).toBe(
      "CALENDAR_FORBIDDEN",
    );
    await session.as(member);

    const backwards = await calendar.save(calendarId, {
      title: "x",
      startsAt: at("2026-03-01T09:00:00Z"),
      endsAt: at("2026-03-01T08:00:00Z"),
    });

    expect(backwards.ok).toBe(false);

    const status = await calendar.save(calendarId, {
      id: seriesId,
      status: "done" as "confirmed",
    });

    expect(status.ok ? undefined : status.error.hint).toBe(
      "CALENDAR_EVENT_INVALID",
    );
  });

  it("overrides, cancels and splits occurrences", async () => {
    await session.as(member);
    let found = await calendar.occurrences([calendarId], range).orThrow();

    const override = await calendar
      .editOccurrence(found[1]!, {
        title: "Stand-up (late)",
        startsAt: at("2026-03-30T09:00:00Z"),
        endsAt: at("2026-03-30T09:15:00Z"),
      })
      .orThrow();

    expect(override.uid).toBe(seriesId);
    expect(await calendar.cancelOccurrence(found[2]!).orThrow()).toBe(true);
    found = await calendar.occurrences([calendarId], range).orThrow();
    expect(
      found.map((item) => [item.event.title, item.start.toString()]),
    ).toEqual([
      ["Stand-up", "2026-03-23T08:00:00Z"],
      ["Stand-up (late)", "2026-03-30T09:00:00Z"],
      ["Stand-up", "2026-04-13T07:00:00Z"],
      ["Stand-up", "2026-04-20T07:00:00Z"],
      ["Stand-up", "2026-04-27T07:00:00Z"],
    ]);

    const split = await calendar
      .editFollowing(found[3]!, { title: "Planning" })
      .orThrow();

    found = await calendar.occurrences([calendarId], range).orThrow();
    expect(
      found.map((item) => [item.event.title, item.start.toString()]),
    ).toEqual([
      ["Stand-up", "2026-03-23T08:00:00Z"],
      ["Stand-up (late)", "2026-03-30T09:00:00Z"],
      ["Stand-up", "2026-04-13T07:00:00Z"],
      ["Planning", "2026-04-20T07:00:00Z"],
      ["Planning", "2026-04-27T07:00:00Z"],
    ]);

    const rows = await session.rows<{ rrule: string; uid: string }>(
      "select rrule, uid from calendar_it.calendar_events where id = any($1) order by starts_at",
      [[seriesId, split.id]],
    );

    expect(rows).toEqual([
      { rrule: "FREQ=WEEKLY;BYDAY=MO;UNTIL=20260420T065959Z", uid: seriesId },
      {
        rrule: "FREQ=WEEKLY;BYDAY=MO;COUNT=2",
        uid: `${seriesId}-20260420T070000Z`,
      },
    ]);
  });

  it("mirrors each event into the reminders rules", async () => {
    const rules = await session.rows<{ rrule: string }>(
      "select rrule from better_supabase.recurrence_rules where subject_type = 'calendar_event' and subject_id = $1",
      [seriesId],
    );

    expect(rules).toEqual([
      { rrule: "FREQ=WEEKLY;BYDAY=MO;UNTIL=20260420T065959Z" },
    ]);
  });

  it("hides events from other tenants through the policies", async () => {
    await session.asRole(outsider);

    try {
      expect(await calendar.events([calendarId], range).orThrow()).toEqual([]);
    } finally {
      await session.as(owner);
    }

    await session.asRole(viewer);

    try {
      expect(await calendar.events([calendarId], range).orThrow()).toEqual([]);
    } finally {
      await session.as(owner);
    }

    await session.asRole(member);

    try {
      expect(
        (await calendar.events([calendarId], range).orThrow()).length,
      ).toBeGreaterThan(0);
    } finally {
      await session.as(owner);
    }
  });

  it("invites attendees and records their answer", async () => {
    await session.as(member);
    await calendar
      .setAttendee(seriesId, { email: viewer.email, role: "optional" })
      .orThrow();
    await session.as(viewer);
    expect(await calendar.respond(seriesId, "accepted").orThrow()).toBe(true);
    await session.as(outsider);
    const stranger = await calendar.respond(seriesId, "accepted");
    expect(stranger.ok ? undefined : stranger.error.hint).toBe(
      "CALENDAR_ATTENDEE_NOT_FOUND",
    );
    await session.as(member);
    const [event] = await calendar.events([calendarId], range).orThrow();
    expect(event?.attendees).toEqual([
      {
        email: viewer.email,
        userId: viewer.id,
        role: "optional",
        response: "accepted",
      },
    ]);
  });

  it("imports an iCalendar file idempotently by UID", async () => {
    await session.as(member);

    const ics = [
      "BEGIN:VCALENDAR",
      "BEGIN:VEVENT",
      "UID:review@example.test",
      "DTSTART;TZID=Europe/Amsterdam:20260401T100000",
      "DTEND;TZID=Europe/Amsterdam:20260401T110000",
      "RRULE:FREQ=DAILY;COUNT=3",
      "SUMMARY:Review",
      "END:VEVENT",
      "BEGIN:VEVENT",
      "UID:review@example.test",
      "RECURRENCE-ID;TZID=Europe/Amsterdam:20260402T100000",
      "DTSTART;TZID=Europe/Amsterdam:20260402T140000",
      "DTEND;TZID=Europe/Amsterdam:20260402T150000",
      "SUMMARY:Review (afternoon)",
      "END:VEVENT",
      "BEGIN:VEVENT",
      "UID:orphan@example.test",
      "RECURRENCE-ID:20260402T100000Z",
      "DTSTART:20260402T100000Z",
      "END:VEVENT",
      "END:VCALENDAR",
    ].join("\r\n");

    expect(await calendar.importIcs(calendarId, ics).orThrow()).toEqual({
      created: 2,
      updated: 0,
      skipped: 1,
    });
    expect(
      await calendar
        .importIcs(
          calendarId,
          ics.replace("SUMMARY:Review\r\n", "SUMMARY:Code review\r\n"),
        )
        .orThrow(),
    ).toEqual({ created: 0, updated: 2, skipped: 1 });

    const reviews = (
      await calendar
        .occurrences([calendarId], {
          from: at("2026-04-01T00:00:00Z"),
          until: at("2026-04-04T00:00:00Z"),
        })
        .orThrow()
    ).filter((item) => item.event.uid === "review@example.test");

    expect(
      reviews.map((item) => [item.event.title, item.start.toString()]),
    ).toEqual([
      ["Code review", "2026-04-01T08:00:00Z"],
      ["Review (afternoon)", "2026-04-02T12:00:00Z"],
      ["Code review", "2026-04-03T08:00:00Z"],
    ]);
  });

  it("serves an iCal feed to a share link and refuses others", async () => {
    await session.as(owner);

    const link = await session.value<{ token: string; id: string }>(
      "better_supabase.create_share_link($1, 'calendar', $2, 'view')",
      [org, calendarId],
    );

    const other = await session.organization(outsider);
    await session.as(outsider);

    expect(
      await session.hint(
        "better_supabase.create_share_link($1, 'calendar', $2, 'view')",
        [other, calendarId],
      ),
    ).toBe("SHARE_SUBJECT_NOT_FOUND");

    // The service role skips the subject check, so the feed's own tenant
    // check is what refuses this link.
    await session.service();

    const foreign = await session.value<{ token: string }>(
      "better_supabase.create_share_link($1, 'calendar', $2, 'view')",
      [other, calendarId],
    );

    await session.as("anon");
    const feed = await calendar.feed(link.token).orThrow();
    expect(feed).toContain("X-WR-CALNAME:Team\r\n");
    expect(feed).toContain(`UID:${seriesId}\r\n`);
    expect(feed).toContain("BEGIN:VTIMEZONE\r\n");
    expect(await calendar.feed(foreign.token).orThrow()).toBeNull();
    expect(await calendar.feed("short").orThrow()).toBeNull();
    await session.as(owner);
    await session.value("better_supabase.revoke_share_link($1)", [link.id]);
    await session.as("anon");
    expect(await calendar.feed(link.token).orThrow()).toBeNull();
  });

  it("deletes an event with its overrides and its reminders rule", async () => {
    await session.as(member);
    expect(await calendar.delete(seriesId).orThrow()).toBe(true);
    expect(
      await session.value<number>(
        "(select count(*)::int from calendar_it.calendar_events where id = $1 or recurrence_id = $1)",
        [seriesId],
      ),
    ).toBe(0);
    expect(
      await session.value<number>(
        "(select count(*)::int from better_supabase.recurrence_rules where subject_type = 'calendar_event' and subject_id = $1)",
        [seriesId],
      ),
    ).toBe(0);
  });
});
