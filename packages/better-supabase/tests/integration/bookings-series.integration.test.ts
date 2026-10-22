import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { AdmissionPasses } from "../../src/blocks/admission-passes/admission-passes.ts";
import type { Bookings } from "../../src/blocks/bookings/bookings.ts";
import type { Result } from "../../src/core/result.ts";
import type { TestUser } from "./block-session.ts";

import { createAdmissionPasses } from "../../src/blocks/admission-passes/admission-passes.ts";
import { createBookings } from "../../src/blocks/bookings/bookings.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const at = (text: string): Temporal.Instant => Temporal.Instant.from(text);

const starts = (rows: readonly { readonly startsAt: Temporal.Instant }[]) =>
  rows.map((row) => row.startsAt.toString());

const hint = (result: Result<unknown>) =>
  result.ok ? "ok" : result.error.hint;

const allWeek = ([1, 2, 3, 4, 5, 6, 7] as const).map((weekday) => ({
  weekday,
  start: "00:00",
  end: "23:59",
}));

describe.skipIf(!live)("recurring bookings and class credits", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  let session: BlockSession;
  let bookings: Bookings;
  let passes: AdmissionPasses;
  let owner: TestUser;
  let member: TestUser;
  let outsider: TestUser;
  let org: string;
  let studio: string;
  let yoga: string;

  beforeAll(async () => {
    session = await BlockSession.open(pool);
    await session.install(
      [
        "organizations",
        "outbox",
        "reminders",
        "calendar",
        "bookings",
        "passes",
      ],
      {
        modules: {
          bookings: { options: { recurring: true } },
          "admission-passes": { options: { credits: true } },
        },
      },
    );
    owner = await session.user("series-owner");
    member = await session.user("series-member");
    outsider = await session.user("series-outsider");
    org = await session.organization(owner, { member });
    await session.organization(outsider);
    bookings = createBookings({ transport: sqlTransport(session.sql) });
    passes = createAdmissionPasses({
      transport: sqlTransport(session.sql),
      tenant: org,
    });

    await session.as(owner);

    const calendar = await session.value<{ id: string }>(
      "better_supabase.create_calendar($1, 'Studio', 'Europe/Amsterdam', null, null)",
      [org],
    );

    studio = (
      await bookings
        .saveResource(org, {
          name: "Studio",
          tz: "Europe/Amsterdam",
          calendarId: calendar.id,
        })
        .orThrow()
    ).id;
    await bookings.setAvailability(studio, allWeek).orThrow();
    yoga = (
      await bookings
        .saveService(org, { name: "Yoga", duration: "PT1H" })
        .orThrow()
    ).id;
  });

  afterAll(async () => {
    await session.close();
    await pool.end();
  });

  it("books a weekly series that keeps its local time across daylight saving", async () => {
    await session.as(member);

    const booked = await bookings
      .bookSeries(yoga, studio, at("2030-03-18T08:00:00Z"), {
        freq: "weekly",
        count: 5,
      })
      .orThrow();

    expect(starts(booked.bookings)).toEqual([
      "2030-03-18T08:00:00Z",
      "2030-03-25T08:00:00Z",
      "2030-04-01T07:00:00Z",
      "2030-04-08T07:00:00Z",
      "2030-04-15T07:00:00Z",
    ]);
    expect(booked.series).toMatchObject({
      tz: "Europe/Amsterdam",
      status: "active",
      customerUserId: member.id,
      rule: { freq: "weekly", count: 5 },
    });
    expect(booked.series.endsAt?.toString()).toBe("2030-04-15T08:00:00Z");
    expect(
      booked.bookings.every(
        (booking) =>
          booking.seriesId === booked.series.id &&
          booking.status === "confirmed",
      ),
    ).toBe(true);
    expect(booked.skipped).toEqual([]);

    await session.asRole(member);
    const read = await bookings.series(booked.series.id).orThrow();
    expect(read.bookings.map((booking) => booking.id)).toEqual(
      booked.bookings.map((booking) => booking.id),
    );
  });

  it("fails a series on a taken occurrence, or skips it", async () => {
    await session.as(owner);

    const taken = await bookings.bookSeries(
      yoga,
      studio,
      at("2030-03-18T08:00:00Z"),
      { freq: "daily", count: 3 },
    );

    expect(hint(taken)).toBe("BOOKING_SERIES_CONFLICT");

    const skipped = await bookings
      .bookSeries(
        yoga,
        studio,
        at("2030-03-18T08:00:00Z"),
        { freq: "weekly", weekdays: [1, 2], count: 4 },
        { name: "Front desk" },
        { skipConflicts: true },
      )
      .orThrow();

    expect(starts(skipped.bookings)).toEqual([
      "2030-03-19T08:00:00Z",
      "2030-03-26T08:00:00Z",
    ]);
    expect(skipped.skipped.map(String)).toEqual([
      "2030-03-18T08:00:00Z",
      "2030-03-25T08:00:00Z",
    ]);

    const invalid = await bookings.bookSeries(
      yoga,
      studio,
      at("2030-05-01T08:00:00Z"),
      { freq: "weekly" },
    );

    expect(hint(invalid)).toBe("BOOKING_RULE_INVALID");
  });

  it("moves one occurrence or all following, all or nothing", async () => {
    await session.asRole(member);

    const series = (
      await bookings
        .list(org, {
          from: at("2030-03-01T00:00:00Z"),
          until: at("2030-05-01T00:00:00Z"),
        })
        .orThrow()
    ).filter((booking) => booking.customerUserId === member.id);

    const [first, second, third] = series;

    await session.as(member);

    const one = await bookings
      .reschedule(second!.id, at("2030-03-25T10:00:00Z"))
      .orThrow();

    expect(
      one.map((booking) => [booking.id, String(booking.startsAt)]),
    ).toEqual([[second!.id, "2030-03-25T10:00:00Z"]]);

    const mirrored = await session.rows<{ starts_at: Date }>(
      "select starts_at from better_supabase.calendar_events where uid = $1",
      [`booking-${second!.id}`],
    );

    expect(mirrored.map((row) => row.starts_at.toISOString())).toEqual([
      "2030-03-25T10:00:00.000Z",
    ]);

    const following = await bookings
      .reschedule(third!.id, at("2030-04-01T08:00:00Z"), { scope: "following" })
      .orThrow();

    expect(starts(following)).toEqual([
      "2030-04-01T08:00:00Z",
      "2030-04-08T08:00:00Z",
      "2030-04-15T08:00:00Z",
    ]);

    const clash = await bookings.reschedule(
      first!.id,
      at("2030-03-19T08:00:00Z"),
    );

    expect(hint(clash)).toBe("BOOKING_SLOT_UNAVAILABLE");

    await session.as(outsider);

    const stranger = await bookings.reschedule(
      first!.id,
      at("2030-03-18T10:00:00Z"),
    );

    expect(hint(stranger)).toBe("BOOKING_NOT_FOUND");

    await session.as(member);
    expect(
      await bookings
        .cancelSeries(following[1]!.id, { reason: "moving" })
        .orThrow(),
    ).toBe(2);
    const read = await bookings.series(first!.seriesId!).orThrow();
    expect(read.status).toBe("ended");
    expect(read.endsAt?.toString()).toBe("2030-04-01T09:00:00Z");
    expect(read.bookings.map((booking) => booking.status)).toEqual([
      "confirmed",
      "confirmed",
      "confirmed",
      "cancelled",
      "cancelled",
    ]);
    expect(
      await bookings.cancelSeries(first!.id, { scope: "one" }).orThrow(),
    ).toBe(1);
  });

  it("pays for classes with pass credits and refunds early cancellations", async () => {
    await session.as(owner);

    const pack = await passes
      .issue({
        kind: "pack",
        holderUserId: member.id,
        resourceId: studio,
        usesAllowed: 2,
      })
      .orThrow();

    await session.as(member);

    const book = (startsAt: string) =>
      passes.bookWithCredit(pack.id, {
        serviceId: yoga,
        resourceId: studio,
        startsAt: at(startsAt),
      });

    const first = await book("2030-06-03T08:00:00Z").orThrow();
    expect(first).toMatchObject({
      passId: pack.id,
      creditsLeft: 1,
      status: "confirmed",
      customerUserId: member.id,
    });
    const second = await book("2030-06-04T08:00:00Z").orThrow();
    expect(second.creditsLeft).toBe(0);
    expect(hint(await book("2030-06-05T08:00:00Z"))).toBe(
      "PASS_CREDITS_USED_UP",
    );

    await bookings.reschedule(second.id, at("2030-06-04T10:00:00Z")).orThrow();
    await bookings.cancel(first.id).orThrow();
    expect(
      (await passes.credits(pack.id).orThrow()).map((entry) => [
        entry.reason,
        entry.delta,
        entry.bookingId,
      ]),
    ).toEqual([
      ["refund", 1, first.id],
      ["booking", -1, second.id],
      ["booking", -1, first.id],
    ]);

    await session.client.query("reset role");
    await session.client.query(
      `update better_supabase.bookings
       set during = tstzrange(now() + interval '1 hour', now() + interval '2 hours'),
         blocked = tstzrange(now() + interval '1 hour', now() + interval '2 hours')
       where id = $1`,
      [second.id],
    );
    await session.as(member);
    await bookings.cancel(second.id).orThrow();

    await session.asRole(member);
    expect(await passes.credits(pack.id).orThrow()).toHaveLength(3);
    expect((await passes.get(pack.id).orThrow())?.uses).toBe(1);

    await session.as(outsider);
    expect(hint(await book("2030-06-06T08:00:00Z"))).toBe("PASS_NOT_FOUND");
    expect(hint(await passes.credits(pack.id))).toBe("PASS_NOT_FOUND");

    await session.as(owner);

    const visit = await bookings
      .hold(yoga, studio, at("2030-06-08T08:00:00Z"), {}, { confirm: true })
      .orThrow();

    const ticket = await passes.issue({ bookingId: visit.id }).orThrow();
    expect(
      hint(
        await passes.bookWithCredit(ticket.id, {
          serviceId: yoga,
          resourceId: studio,
          startsAt: at("2030-06-07T08:00:00Z"),
        }),
      ),
    ).toBe("PASS_NOT_CREDITS");
  });
});
