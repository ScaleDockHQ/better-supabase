import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { Bookings } from "../../src/blocks/bookings/bookings.ts";
import type { TestUser } from "./block-session.ts";

import { createBookings } from "../../src/blocks/bookings/bookings.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const at = (text: string): Temporal.Instant => Temporal.Instant.from(text);

// 2030-03-04 is a Monday; Amsterdam is UTC+1 then.
const monday = {
  from: at("2030-03-04T00:00:00Z"),
  until: at("2030-03-05T00:00:00Z"),
};
const weekdays = ([1, 2, 3, 4, 5] as const).map((weekday) => ({
  weekday,
  start: "09:00",
  end: "12:00",
}));

describe.skipIf(!live)("bookings block in Postgres", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  let session: BlockSession;
  let bookings: Bookings;
  let owner: TestUser;
  let member: TestUser;
  let outsider: TestUser;
  let org: string;
  let resourceId: string;
  let serviceId: string;
  let calendarId: string;

  beforeAll(async () => {
    session = await BlockSession.open(pool);
    await session.install(
      [
        "organizations",
        "jobs",
        "rate-limit",
        "share-links",
        "reminders",
        "calendar",
        "bookings",
      ],
      {
        modules: {
          calendar: { schema: "bookings_it" },
          bookings: { schema: "bookings_it" },
        },
      },
    );
    owner = await session.user("owner");
    member = await session.user("member");
    outsider = await session.user("outsider");
    org = await session.organization(owner, { member });
    bookings = createBookings({
      transport: sqlTransport(session.sql),
      schema: "bookings_it",
    });
    await session.as(owner);
    calendarId = (
      await session.value<{ id: string }>(
        "bookings_it.create_calendar($1, 'Desk', 'Europe/Amsterdam', null, null)",
        [org],
      )
    ).id;
  });

  afterAll(async () => {
    await session.close();
    await pool.end();
  });

  it("lets managers set up resources and services, and refuses members", async () => {
    await session.as(member);
    const refused = await bookings.saveResource(org, { name: "Nope" });
    expect(refused.ok ? undefined : refused.error.hint).toBe(
      "BOOKING_FORBIDDEN",
    );

    await session.as(owner);
    resourceId = (
      await bookings
        .saveResource(org, {
          name: "Ann",
          kind: "staff",
          tz: "Europe/Amsterdam",
          calendarId,
        })
        .orThrow()
    ).id;
    expect(await bookings.setAvailability(resourceId, weekdays).orThrow()).toBe(
      5,
    );
    serviceId = (
      await bookings
        .saveService(org, {
          name: "Haircut",
          duration: Temporal.Duration.from({ minutes: 30 }),
          bufferAfter: "PT15M",
          resourceKinds: ["staff"],
          reminderOffsets: [60],
        })
        .orThrow()
    ).id;
  });

  it("returns slots inside the weekly hours, in the resource's zone", async () => {
    await session.as(member);
    const slots = await bookings.availableSlots(serviceId, monday).orThrow();
    expect(slots.map((slot) => slot.startsAt.toString())).toEqual([
      "2030-03-04T08:00:00Z",
      "2030-03-04T08:30:00Z",
      "2030-03-04T09:00:00Z",
      "2030-03-04T09:30:00Z",
      "2030-03-04T10:00:00Z",
      "2030-03-04T10:30:00Z",
    ]);
    expect(slots[0]?.localStart.toString()).toBe("2030-03-04T09:00:00");
    const tokyo = await bookings
      .availableSlots(serviceId, monday, { tz: "Asia/Tokyo" })
      .orThrow();
    expect(tokyo[0]?.localStart.toString()).toBe("2030-03-04T17:00:00");

    const badZone = await bookings.availableSlots(serviceId, monday, {
      tz: "Mars/Base",
    });
    expect(badZone.ok ? undefined : badZone.error.hint).toBe(
      "BOOKING_TZ_INVALID",
    );
  });

  it("closes slots for an exception and opens them again when it is deleted", async () => {
    await session.as(owner);
    const { id } = await bookings
      .addException(resourceId, {
        startsAt: at("2030-03-04T08:00:00Z"),
        endsAt: at("2030-03-04T10:00:00Z"),
        reason: "Dentist",
      })
      .orThrow();
    const closed = await bookings.availableSlots(serviceId, monday).orThrow();
    expect(closed.map((slot) => slot.startsAt.toString())).toEqual([
      "2030-03-04T10:00:00Z",
      "2030-03-04T10:30:00Z",
    ]);
    expect(await bookings.deleteException(id).orThrow()).toBe(true);
    expect(
      await bookings.availableSlots(serviceId, monday).orThrow(),
    ).toHaveLength(6);
  });

  it("holds a slot, blocks its buffer, and refuses a double booking", async () => {
    await session.as(member);
    const held = await bookings
      .hold(serviceId, resourceId, at("2030-03-04T08:00:00Z"), { name: "Bo" })
      .orThrow();
    expect(held.status).toBe("hold");
    expect(held.customerEmail).toBe(member.email);
    expect(held.holdExpiresAt).toBeDefined();
    expect(held.accessToken).toMatch(/^[0-9a-f]{48}$/);

    const left = await bookings.availableSlots(serviceId, monday).orThrow();
    expect(left.map((slot) => slot.startsAt.toString())).not.toContain(
      "2030-03-04T08:30:00Z",
    );

    const again = await bookings.hold(
      serviceId,
      resourceId,
      at("2030-03-04T08:00:00Z"),
    );
    expect(again.ok ? undefined : again.error.hint).toBe(
      "BOOKING_SLOT_UNAVAILABLE",
    );

    await bookings.cancel(held.id).orThrow();
  });

  it("enforces the exclusion constraint even for direct writes", async () => {
    await session.service();
    const insert = `insert into bookings_it.bookings
      (tenant_id, resource_id, service_id, seat, during, blocked, status)
      values ($1, $2, $3, 1, tstzrange($4, $5), tstzrange($4, $5), 'confirmed')`;
    await session.rows(insert, [
      org,
      resourceId,
      serviceId,
      "2030-03-05T08:00:00Z",
      "2030-03-05T08:30:00Z",
    ]);
    const clash = await session.hint(insert, [
      org,
      resourceId,
      serviceId,
      "2030-03-05T08:15:00Z",
      "2030-03-05T08:45:00Z",
    ]);
    expect(clash).toMatch(/bookings_no_overlap/);
  });

  it("books as many overlapping seats as the capacity allows", async () => {
    await session.as(owner);
    const room = (
      await bookings
        .saveResource(org, { name: "Studio", kind: "room", capacity: 2 })
        .orThrow()
    ).id;
    await bookings
      .setAvailability(room, [{ weekday: 1, start: "08:00", end: "09:00" }])
      .orThrow();
    const yoga = (
      await bookings
        .saveService(org, {
          name: "Yoga",
          duration: "PT1H",
          resourceKinds: ["room"],
        })
        .orThrow()
    ).id;
    const start = at("2030-03-04T08:00:00Z");
    const first = await bookings
      .hold(yoga, room, start, { name: "A" }, { confirm: true })
      .orThrow();
    const second = await bookings
      .hold(yoga, room, start, { name: "B" }, { confirm: true })
      .orThrow();
    expect([first.seat, second.seat].toSorted((a, b) => a - b)).toEqual([1, 2]);
    const third = await bookings.hold(yoga, room, start, { name: "C" });
    expect(third.ok ? undefined : third.error.hint).toBe(
      "BOOKING_SLOT_UNAVAILABLE",
    );
  });

  it("expires stale holds through the job and frees the slot", async () => {
    await session.as(member);
    const held = await bookings
      .hold(serviceId, resourceId, at("2030-03-04T09:00:00Z"))
      .orThrow();
    await session.service();
    await session.rows(
      "update bookings_it.bookings set hold_expires_at = now() - interval '1 second' where id = $1",
      [held.id],
    );
    expect(await bookings.expireHolds().orThrow()).toBe(1);
    const [row] = await session.rows<{ status: string }>(
      "select status from bookings_it.bookings where id = $1",
      [held.id],
    );
    expect(row?.status).toBe("cancelled");

    await session.asRole(member);
    const forbidden = await bookings.expireHolds();
    expect(forbidden.ok).toBe(false);
  });

  it("mirrors a confirmed booking into the calendar and reminders, and removes it on cancel", async () => {
    await session.as(member);
    const held = await bookings
      .hold(serviceId, resourceId, at("2030-03-04T10:00:00Z"), { name: "Cy" })
      .orThrow();
    await bookings.confirm(held.id).orThrow();
    await session.service();
    const events = await session.rows<{ title: string }>(
      "select title from bookings_it.calendar_events where uid = $1",
      [`booking-${held.id}`],
    );
    expect(events.map((event) => event.title)).toEqual(["Cy"]);
    const reminders = await session.rows<{ offset_minutes: number }>(
      "select offset_minutes from better_supabase.reminders where subject_type = 'booking' and subject_id = $1",
      [held.id],
    );
    expect(reminders.map((reminder) => reminder.offset_minutes)).toEqual([60]);

    await session.as(member);
    const cancelled = await bookings.cancel(held.id, "ill").orThrow();
    expect(cancelled.cancelReason).toBe("ill");
    await session.service();
    expect(
      await session.rows(
        "select 1 from bookings_it.calendar_events where uid = $1",
        [`booking-${held.id}`],
      ),
    ).toHaveLength(0);
  });

  it("lists bookings by policy", async () => {
    await session.as(owner);
    const all = await bookings.list(org, monday).orThrow();
    expect(all.length).toBeGreaterThan(0);
    await session.asRole(outsider);
    expect(await bookings.list(org, monday).orThrow()).toEqual([]);
  });

  it("takes guest bookings through a share link, with an access token and a rate limit", async () => {
    await session.as(owner);
    const link = await session.value<{ id: string; token: string }>(
      "better_supabase.create_share_link($1, 'booking_service', $2, 'view')",
      [org, serviceId],
    );

    await session.as("anon");
    const info = await bookings.public.service(link.token).orThrow();
    expect(info.name).toBe("Haircut");
    expect(info.resources.map((resource) => resource.id)).toEqual([resourceId]);
    const slots = await bookings.public.slots(link.token, monday).orThrow();
    expect(slots.length).toBeGreaterThan(0);

    const noEmail = await bookings.public.hold(
      link.token,
      resourceId,
      slots[0]!.startsAt,
      { name: "Guest", email: "nope" },
    );
    expect(noEmail.ok ? undefined : noEmail.error.hint).toBe(
      "BOOKING_CUSTOMER_INVALID",
    );

    const held = await bookings.public
      .hold(link.token, resourceId, slots[0]!.startsAt, {
        name: "Guest",
        email: "guest@example.test",
      })
      .orThrow();
    const wrong = await bookings.public.confirm(held.id, "0".repeat(48));
    expect(wrong.ok ? undefined : wrong.error.hint).toBe("BOOKING_FORBIDDEN");
    const confirmed = await bookings.public
      .confirm(held.id, held.accessToken)
      .orThrow();
    expect(confirmed.status).toBe("confirmed");

    const bad = await bookings.public.service("0".repeat(64));
    expect(bad.ok ? undefined : bad.error.hint).toBe("BOOKING_LINK_INVALID");

    await session.as(owner);
    const fresh = await session.value<{ token: string }>(
      "better_supabase.create_share_link($1, 'booking_service', $2, 'view')",
      [org, serviceId],
    );
    await session.service();
    await session.value("better_supabase.set_rate_limit('bookings.public', 1)");
    await session.as("anon");
    await bookings.public.service(fresh.token).orThrow();
    const limited = await bookings.public.service(fresh.token);
    expect(limited.ok ? undefined : limited.error.kind).toBe("rate_limited");
  });
});
