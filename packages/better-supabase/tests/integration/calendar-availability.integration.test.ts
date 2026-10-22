import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { Bookings } from "../../src/blocks/bookings/bookings.ts";
import type { Calendar } from "../../src/blocks/calendar/calendar.ts";
import type { TestUser } from "./block-session.ts";

import { createBookings } from "../../src/blocks/bookings/bookings.ts";
import { commonFreeTime } from "../../src/blocks/calendar/availability.ts";
import { createCalendar } from "../../src/blocks/calendar/calendar.ts";
import { createLeave } from "../../src/blocks/leave/index.ts";
import { expandRule } from "../../src/blocks/reminders/rrule.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const at = (text: string): Temporal.Instant => Temporal.Instant.from(text);

const strings = (
  ranges: readonly { from: Temporal.Instant; until: Temporal.Instant }[],
) =>
  ranges.map((range) => `${range.from.toString()}/${range.until.toString()}`);

// 2030-03-04 is a Monday; Amsterdam is UTC+1 then.
const week = {
  from: at("2030-03-04T00:00:00Z"),
  until: at("2030-03-09T00:00:00Z"),
};

const RULES: readonly (readonly [string, string, string])[] = [
  ["2026-01-05T09:00:00", "Europe/Amsterdam", "FREQ=DAILY;COUNT=10"],
  ["2026-01-05T09:00:00", "Europe/Amsterdam", "FREQ=DAILY;INTERVAL=3"],
  ["2026-03-23T09:00:00", "Europe/Amsterdam", "FREQ=WEEKLY;BYDAY=MO,WE,FR"],
  [
    "2026-01-01T08:30:00",
    "America/New_York",
    "FREQ=WEEKLY;INTERVAL=2;BYDAY=TU,TH;UNTIL=20261231T000000Z",
  ],
  ["2026-01-31T10:00:00", "UTC", "FREQ=MONTHLY"],
  ["2026-01-15T10:00:00", "Europe/Amsterdam", "FREQ=MONTHLY;BYDAY=-1FR"],
  ["2026-01-01T10:00:00", "Europe/Amsterdam", "FREQ=MONTHLY;BYDAY=2TU,4TU"],
  ["2026-01-01T10:00:00", "UTC", "FREQ=MONTHLY;BYMONTHDAY=1,15,-1"],
  [
    "2026-01-01T10:00:00",
    "UTC",
    "FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1",
  ],
  ["2024-02-29T12:00:00", "UTC", "FREQ=YEARLY"],
  ["2026-01-01T07:00:00", "Asia/Tokyo", "FREQ=YEARLY;BYMONTH=3,9;BYDAY=1SU"],
  [
    "2026-01-05T09:00:00",
    "Europe/Amsterdam",
    "FREQ=WEEKLY;WKST=SU;INTERVAL=2;BYDAY=SU,MO;COUNT=9",
  ],
  ["2026-03-27T02:30:00", "Europe/Amsterdam", "FREQ=DAILY;COUNT=4"],
  ["2026-10-23T02:30:00", "Europe/Amsterdam", "FREQ=DAILY;COUNT=4"],
];

const WINDOWS: readonly (readonly [string, string])[] = [
  ["2026-01-01T00:00:00Z", "2026-04-01T00:00:00Z"],
  ["2026-10-01T00:00:00Z", "2027-02-01T00:00:00Z"],
  ["2029-05-01T00:00:00Z", "2029-06-15T00:00:00Z"],
];

describe.skipIf(!live)("calendar availability in Postgres", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  let session: BlockSession;
  let calendar: Calendar;
  let bookings: Bookings;
  let owner: TestUser;
  let ada: TestUser;
  let bob: TestUser;
  let outsider: TestUser;
  let org: string;
  let adaCalendar: string;
  let bobCalendar: string;

  beforeAll(async () => {
    session = await BlockSession.open(pool);
    await session.install(
      ["organizations", "outbox", "approvals", "leave", "calendar", "bookings"],
      {
        modules: {
          calendar: { schema: "availability_it" },
          bookings: { schema: "availability_it" },
        },
      },
    );
    owner = await session.user("owner");
    ada = await session.user("ada");
    bob = await session.user("bob");
    outsider = await session.user("outsider");
    org = await session.organization(owner, { member: ada, member2: bob });
    calendar = createCalendar({
      transport: sqlTransport(session.sql),
      schema: "availability_it",
    });
    bookings = createBookings({
      transport: sqlTransport(session.sql),
      schema: "availability_it",
    });
    await session.as(owner);
    ({ id: adaCalendar } = await calendar
      .createCalendar(org, "Ada", {
        tz: "Europe/Amsterdam",
        ownerType: "user",
        ownerId: ada.id,
      })
      .orThrow());
    ({ id: bobCalendar } = await calendar
      .createCalendar(org, "Bob", {
        tz: "Europe/Amsterdam",
        ownerType: "user",
        ownerId: bob.id,
      })
      .orThrow());
  });

  afterAll(async () => {
    await session.close();
    await pool.end();
  });

  it("expands RRULEs in SQL the way expandRule does in TypeScript", async () => {
    for (const [start, tz, rrule] of RULES) {
      const dtstart = Temporal.PlainDateTime.from(start).toZonedDateTime(tz);

      for (const [from, until] of WINDOWS) {
        const expected = expandRule({
          dtstart,
          rrule,
          window: { from: at(from), until: at(until) },
        }).map((when) => when.toInstant().toString());

        const rows = await session.rows<{ at: Date }>(
          "select s as at from availability_it.calendar_rule_starts($1, $2, $3, $4, $5) s",
          [dtstart.toInstant().toString(), tz, rrule, from, until],
        );

        expect(
          rows.map((row) =>
            Temporal.Instant.fromEpochMilliseconds(row.at.getTime()).toString(),
          ),
          `${rrule} in ${from}`,
        ).toEqual(expected);
      }
    }
  });

  it("treats an unreadable rule as one occurrence", async () => {
    const rows = await session.rows<{ at: Date }>(
      "select s as at from availability_it.calendar_rule_starts('2030-03-04T09:00:00Z', 'UTC', 'FREQ=HOURLY', '2030-03-01T00:00:00Z', '2030-03-10T00:00:00Z') s",
    );

    expect(rows).toHaveLength(1);
  });

  it("stores working hours for yourself and refuses other people's", async () => {
    await session.as(ada);

    const weekdays = ([1, 2, 3, 4, 5] as const).map((weekday) => ({
      weekday,
      start: "09:00",
      end: "17:00",
    }));

    expect(
      await calendar
        .setWorkingHours(org, { tz: "Europe/Amsterdam", hours: weekdays })
        .orThrow(),
    ).toBe(5);

    const refused = await calendar.setWorkingHours(org, {
      tz: "UTC",
      hours: [],
      userId: bob.id,
    });

    expect(refused.ok ? undefined : refused.error.hint).toBe(
      "CALENDAR_FORBIDDEN",
    );

    const invalid = await calendar.setWorkingHours(org, {
      tz: "UTC",
      hours: [{ weekday: 1, start: "17:00", end: "09:00" }],
    });

    expect(invalid.ok ? undefined : invalid.error.hint).toBe(
      "CALENDAR_HOURS_INVALID",
    );
    await session.as(owner);
    expect(
      await calendar
        .setWorkingHours(org, {
          tz: "Europe/Amsterdam",
          hours: [{ weekday: 3, start: "13:00", end: "24:00" }],
          userId: bob.id,
        })
        .orThrow(),
    ).toBe(1);
    expect(await calendar.workingHours(org, [bob.id]).orThrow()).toEqual([
      {
        userId: bob.id,
        tz: "Europe/Amsterdam",
        hours: [{ weekday: 3, start: "13:00", end: "24:00" }],
      },
    ]);
  });

  it("answers free/busy from events, invitations, blocks and leave", async () => {
    await session.as(ada);
    await calendar
      .save(adaCalendar, {
        title: "Stand-up",
        startsAt: at("2030-03-04T08:00:00Z"),
        endsAt: at("2030-03-04T08:15:00Z"),
        tz: "Europe/Amsterdam",
        rrule: "FREQ=DAILY;COUNT=3",
      })
      .orThrow();
    await calendar
      .save(adaCalendar, {
        title: "Lunch walk",
        startsAt: at("2030-03-04T11:00:00Z"),
        endsAt: at("2030-03-04T12:00:00Z"),
        transparency: "transparent",
      })
      .orThrow();
    await calendar
      .save(adaCalendar, {
        title: "Writing",
        kind: "focus_time",
        startsAt: at("2030-03-05T12:00:00Z"),
        endsAt: at("2030-03-05T14:00:00Z"),
      })
      .orThrow();

    const meeting = await calendar
      .save(bobCalendar, {
        title: "Review",
        startsAt: at("2030-03-04T13:00:00Z"),
        endsAt: at("2030-03-04T14:00:00Z"),
      })
      .orThrow();

    await calendar
      .setAttendee(meeting.id, { email: "ada@example.test", userId: ada.id })
      .orThrow();

    const leave = createLeave({ transport: sqlTransport(session.sql) });
    await session.as(owner);

    const type = await leave
      .saveType(org, { key: "vacation", name: "Vacation", tracked: false })
      .orThrow();

    await session.as(ada);

    const away = await leave
      .request(org, {
        typeId: type.id,
        startsOn: Temporal.PlainDate.from("2030-03-07"),
        partial: "afternoon",
      })
      .orThrow();

    await session.as(owner);
    await session.value("better_supabase.decide_approval($1, 'approved')", [
      away.approvalId,
    ]);

    await session.as(bob);

    const [found] = await calendar.freeBusy(org, [ada.id], week).orThrow();

    expect(strings(found?.busy ?? [])).toEqual([
      "2030-03-04T08:00:00Z/2030-03-04T08:15:00Z",
      "2030-03-04T13:00:00Z/2030-03-04T14:00:00Z",
      "2030-03-05T08:00:00Z/2030-03-05T08:15:00Z",
      "2030-03-05T12:00:00Z/2030-03-05T14:00:00Z",
      "2030-03-06T08:00:00Z/2030-03-06T08:15:00Z",
      "2030-03-07T11:00:00Z/2030-03-07T23:00:00Z",
    ]);
    expect(strings(found?.focusTime ?? [])).toEqual([
      "2030-03-05T12:00:00Z/2030-03-05T14:00:00Z",
    ]);
    expect(strings(found?.outOfOffice ?? [])).toEqual([
      "2030-03-07T11:00:00Z/2030-03-07T23:00:00Z",
    ]);
    expect(found?.tz).toBe("Europe/Amsterdam");
    expect(found?.workingHours).toHaveLength(5);

    await session.as(ada);
    await calendar.respond(meeting.id, "declined").orThrow();

    const [declined] = await calendar.freeBusy(org, [ada.id], week).orThrow();

    expect(strings(declined?.busy ?? [])).not.toContain(
      "2030-03-04T13:00:00Z/2030-03-04T14:00:00Z",
    );

    const both = await calendar.freeBusy(org, [ada.id, bob.id], week).orThrow();

    expect(
      strings(
        commonFreeTime(both, {
          from: at("2030-03-06T00:00:00Z"),
          until: at("2030-03-07T00:00:00Z"),
        }),
      ),
    ).toEqual(["2030-03-06T12:00:00Z/2030-03-06T16:00:00Z"]);
  });

  it("refuses outsiders and oversized ranges", async () => {
    await session.as(outsider);

    const refused = await calendar.freeBusy(org, [ada.id], week);

    expect(refused.ok ? undefined : refused.error.hint).toBe(
      "CALENDAR_FORBIDDEN",
    );
    await session.as(ada);

    const long = await calendar.freeBusy(org, [ada.id], {
      from: at("2030-01-01T00:00:00Z"),
      until: at("2030-06-01T00:00:00Z"),
    });

    expect(long.ok ? undefined : long.error.hint).toBe(
      "CALENDAR_RANGE_INVALID",
    );
  });

  it("auto-declines invitations an out-of-office block covers", async () => {
    await session.as(bob);
    await calendar
      .save(bobCalendar, {
        title: "Conference",
        kind: "out_of_office",
        autoDecline: true,
        startsAt: at("2030-03-11T00:00:00Z"),
        endsAt: at("2030-03-13T00:00:00Z"),
      })
      .orThrow();

    const sync = await calendar
      .save(adaCalendar, {
        title: "Sync",
        startsAt: at("2030-03-12T10:00:00Z"),
        endsAt: at("2030-03-12T10:30:00Z"),
      })
      .orThrow();

    await calendar
      .setAttendee(sync.id, { email: "bob@example.test", userId: bob.id })
      .orThrow();

    const later = await calendar
      .save(adaCalendar, {
        title: "Retro",
        startsAt: at("2030-03-14T10:00:00Z"),
        endsAt: at("2030-03-14T10:30:00Z"),
      })
      .orThrow();

    await calendar
      .setAttendee(later.id, { email: "bob@example.test", userId: bob.id })
      .orThrow();

    const responses = await session.rows<{ title: string; response: string }>(
      `select e.title, a.response from availability_it.calendar_attendees a
       join availability_it.calendar_events e on e.id = a.event_id
       where a.user_id = $1 order by e.starts_at`,
      [bob.id],
    );

    expect(responses).toEqual([
      { title: "Sync", response: "declined" },
      { title: "Retro", response: "needs-action" },
    ]);

    // A block saved over an open invitation declines it too.
    await calendar
      .save(bobCalendar, {
        title: "Dentist",
        kind: "out_of_office",
        autoDecline: true,
        startsAt: at("2030-03-14T09:00:00Z"),
        endsAt: at("2030-03-14T11:00:00Z"),
      })
      .orThrow();

    const after = await session.value<string>(
      "(select response from availability_it.calendar_attendees where event_id = $1)",
      [later.id],
    );

    expect(after).toBe("declined");
  });

  it("offers appointment slots only when the host is free", async () => {
    await session.as(owner);

    const resource = await bookings
      .saveResource(org, {
        name: "Ada's office hours",
        tz: "Europe/Amsterdam",
        hostUserId: ada.id,
        checkBusy: true,
        calendarId: adaCalendar,
      })
      .orThrow();

    await bookings
      .setAvailability(resource.id, [
        { weekday: 3, start: "09:00", end: "12:00" },
      ])
      .orThrow();

    const service = await bookings
      .saveService(org, {
        name: "Intro call",
        duration: Temporal.Duration.from({ minutes: 30 }),
      })
      .orThrow();

    const slots = await bookings
      .availableSlots(service.id, {
        from: at("2030-03-06T00:00:00Z"),
        until: at("2030-03-07T00:00:00Z"),
      })
      .orThrow();

    // 09:00 to 12:00 Amsterdam, minus the 09:00 to 09:15 stand-up.
    expect(slots.map((slot) => slot.startsAt.toString())).toEqual([
      "2030-03-06T08:30:00Z",
      "2030-03-06T09:00:00Z",
      "2030-03-06T09:30:00Z",
      "2030-03-06T10:00:00Z",
      "2030-03-06T10:30:00Z",
    ]);

    const booked = await bookings
      .hold(
        service.id,
        resource.id,
        at("2030-03-06T09:00:00Z"),
        { name: "Grace", email: "grace@example.test" },
        { confirm: true },
      )
      .orThrow();

    expect(booked.status).toBe("confirmed");

    const left = await bookings
      .availableSlots(service.id, {
        from: at("2030-03-06T00:00:00Z"),
        until: at("2030-03-07T00:00:00Z"),
      })
      .orThrow();

    // The booking's own calendar event doesn't hide any other slot.
    expect(left.map((slot) => slot.startsAt.toString())).toEqual([
      "2030-03-06T08:30:00Z",
      "2030-03-06T09:30:00Z",
      "2030-03-06T10:00:00Z",
      "2030-03-06T10:30:00Z",
    ]);
  });
});
