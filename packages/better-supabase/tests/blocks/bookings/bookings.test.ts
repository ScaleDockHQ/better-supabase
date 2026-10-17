import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

import {
  BOOKING_EXPIRE_QUEUE,
  createBookings,
} from "../../../src/blocks/bookings/bookings.ts";
import {
  slotsByDay,
  toEventCalendarBookings,
} from "../../../src/blocks/bookings/event-calendar.ts";

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

  return { calls, bookings: createBookings({ transport, schema: "app" }) };
}

const at = (text: string): Temporal.Instant => Temporal.Instant.from(text);

const BOOKING = {
  id: "b1",
  resourceId: "r1",
  serviceId: "s1",
  seat: 1,
  startsAt: "2030-03-04T08:00:00+00:00",
  endsAt: "2030-03-04T08:30:00+00:00",
  status: "hold",
  holdExpiresAt: "2030-03-04T07:10:00+00:00",
  customerName: "Bo",
  customerEmail: "bo@example.test",
  customerUserId: null,
  notes: null,
  createdAt: "2030-03-04T07:00:00+00:00",
  cancelledAt: null,
  cancelReason: null,
};

const SLOT = {
  resourceId: "r1",
  startsAt: "2030-03-04T08:00:00+00:00",
  endsAt: "2030-03-04T08:30:00+00:00",
  localStart: "2030-03-04T09:00:00",
  seats: 1,
};

const range = {
  from: at("2030-03-04T00:00:00Z"),
  until: at("2030-03-05T00:00:00Z"),
};

describe("bookings client", () => {
  it("names the queue the SQL enqueues holds on", () => {
    const sql = readFileSync(
      new URL("../../sql/__golden__/bookings.sql", import.meta.url),
      "utf-8",
    );

    expect(sql).toContain(`queue => '${BOOKING_EXPIRE_QUEUE}'`);
  });

  it("saves resources and services with durations as ISO strings", async () => {
    const { calls, bookings } = recorder({
      save_booking_resource: { id: "r1", created: true },
      save_booking_service: { id: "s1", created: true },
      set_booking_availability: 2,
    });

    expect(
      await bookings
        .saveResource("o1", {
          name: "Ann",
          tz: "Europe/Amsterdam",
          calendarId: null,
        })
        .orThrow(),
    ).toEqual({ id: "r1" });
    await bookings
      .saveService("o1", {
        name: "Cut",
        duration: Temporal.Duration.from({ minutes: 30 }),
        bufferAfter: "PT15M",
        resourceKinds: ["staff"],
        step: null,
      })
      .orThrow();
    expect(
      await bookings
        .setAvailability("r1", [
          { weekday: 1, start: "09:00", end: "12:00" },
          { weekday: 2, start: "09:00", end: "12:00" },
        ])
        .orThrow(),
    ).toBe(2);
    expect(calls[0]?.args).toEqual({
      tenant: "o1",
      item: { name: "Ann", tz: "Europe/Amsterdam", calendarId: null },
    });
    expect(calls[1]?.args["item"]).toEqual({
      name: "Cut",
      duration: "PT30M",
      bufferAfter: "PT15M",
      resourceKinds: ["staff"],
      step: null,
    });
    expect(calls[2]?.args["source"]).toEqual({
      hours: [
        { weekday: 1, start: "09:00", end: "12:00" },
        { weekday: 2, start: "09:00", end: "12:00" },
      ],
    });
  });

  it("adds and deletes exceptions", async () => {
    const { calls, bookings } = recorder({
      add_booking_exception: { id: "e1" },
      delete_booking_exception: true,
    });

    await bookings
      .addException("r1", {
        startsAt: at("2030-03-04T08:00:00Z"),
        endsAt: at("2030-03-04T10:00:00Z"),
      })
      .orThrow();
    expect(await bookings.deleteException("e1").orThrow()).toBe(true);
    expect(calls[0]?.args).toEqual({
      resource: "r1",
      starts_at: "2030-03-04T08:00:00Z",
      ends_at: "2030-03-04T10:00:00Z",
      available: false,
      reason: null,
    });
  });

  it("parses slots with their local start", async () => {
    const { calls, bookings } = recorder({ available_slots: [SLOT] });

    const [slot] = await bookings
      .availableSlots("s1", range, { tz: "Europe/Amsterdam" })
      .orThrow();

    expect(slot?.startsAt.toString()).toBe("2030-03-04T08:00:00Z");
    expect(slot?.localStart.toString()).toBe("2030-03-04T09:00:00");
    expect(slot?.seats).toBe(1);
    expect(calls[0]?.args).toEqual({
      service: "s1",
      range_start: "2030-03-04T00:00:00Z",
      range_end: "2030-03-05T00:00:00Z",
      tz: "Europe/Amsterdam",
      resource: null,
    });
  });

  it("holds, confirms, cancels and lists bookings", async () => {
    const { calls, bookings } = recorder({
      hold_booking: { ...BOOKING, accessToken: "t".repeat(48) },
      confirm_booking: { ...BOOKING, status: "confirmed", holdExpiresAt: null },
      cancel_booking: { ...BOOKING, status: "cancelled", cancelReason: "ill" },
      list_bookings: [BOOKING],
    });

    const held = await bookings
      .hold("s1", "r1", at("2030-03-04T08:00:00Z"), { name: "Bo" })
      .orThrow();

    expect(held.accessToken).toHaveLength(48);
    expect(held.status).toBe("hold");
    expect(held.holdExpiresAt?.toString()).toBe("2030-03-04T07:10:00Z");
    expect(held).not.toHaveProperty("notes");
    expect(calls[0]?.args).toEqual({
      service: "s1",
      resource: "r1",
      starts_at: "2030-03-04T08:00:00Z",
      customer: { name: "Bo" },
      confirm: false,
    });
    expect((await bookings.confirm("b1").orThrow()).status).toBe("confirmed");
    expect((await bookings.cancel("b1", "ill").orThrow()).cancelReason).toBe(
      "ill",
    );
    expect(await bookings.list("o1", range).orThrow()).toHaveLength(1);
    expect(calls.at(-1)?.args["resource"]).toBeNull();
  });

  it("fills in a missing seat count and cancel reason", async () => {
    const { seat: _seat, ...seatless } = BOOKING;
    const { seats: _seats, ...open } = SLOT;

    const { calls, bookings } = recorder({
      cancel_booking: { ...seatless, status: "cancelled" },
      available_slots: [open],
    });

    expect((await bookings.cancel("b1").orThrow()).seat).toBe(1);
    expect(calls[0]?.args).toEqual({ booking: "b1", reason: null });
    const [slot] = await bookings.availableSlots("s1", range).orThrow();
    expect(slot?.seats).toBe(0);
  });

  it("runs the expire job on the service transport", async () => {
    const userCalls: string[] = [];
    const serviceCalls: string[] = [];

    const bookings = createBookings({
      transport: {
        call: (_schema, fn) => {
          userCalls.push(fn);

          return Promise.resolve(0);
        },
      },
      service: {
        call: (_schema, fn) => {
          serviceCalls.push(fn);

          return Promise.resolve(3);
        },
      },
    });

    expect(await bookings.expireHolds().orThrow()).toBe(3);
    await bookings.job({}, {} as never, new AbortController().signal);
    expect(serviceCalls).toEqual([
      "expire_booking_holds",
      "expire_booking_holds",
    ]);
    expect(userCalls).toEqual([]);
  });

  it("calls the public functions with the token", async () => {
    const { calls, bookings } = recorder({
      public_booking_service: {
        id: "s1",
        name: "Cut",
        duration: "00:30:00",
        resources: [{ id: "r1", name: "Ann", kind: "staff", tz: "UTC" }],
      },
      public_available_slots: [SLOT],
      public_hold_booking: { ...BOOKING, accessToken: "a".repeat(48) },
      public_change_booking: { ...BOOKING, status: "cancelled" },
    });

    const service = await bookings.public.service("tok").orThrow();
    expect(service.resources[0]?.name).toBe("Ann");
    await bookings.public.slots("tok", range).orThrow();
    await bookings.public
      .hold("tok", "r1", at("2030-03-04T08:00:00Z"), {
        name: "Guest",
        email: "g@example.test",
      })
      .orThrow();
    await bookings.public.confirm("b1", "a".repeat(48)).orThrow();
    await bookings.public.cancel("b1", "a".repeat(48)).orThrow();
    expect(calls.map((call) => call.fn)).toEqual([
      "public_booking_service",
      "public_available_slots",
      "public_hold_booking",
      "public_change_booking",
      "public_change_booking",
    ]);
    expect(calls[3]?.args["to_status"]).toBe("confirmed");
    expect(calls[4]?.args["to_status"]).toBe("cancelled");
  });

  it("returns database errors as results", async () => {
    const { bookings } = recorder({
      hold_booking: Object.assign(new Error("slot taken"), {
        code: "23P01",
        hint: "BOOKING_SLOT_UNAVAILABLE",
      }),
    });

    const result = await bookings.hold("s1", "r1", at("2030-03-04T08:00:00Z"));
    expect(result.ok ? undefined : result.error.kind).toBe("exclusion");
  });
});

describe("booking adapters", () => {
  it("turns bookings into resource-view events and drops cancelled ones", async () => {
    const { bookings } = recorder({
      list_bookings: [
        BOOKING,
        { ...BOOKING, id: "b2", status: "confirmed", customerName: null },
        { ...BOOKING, id: "b3", status: "cancelled" },
      ],
    });

    const rows = await bookings.list("o1", range).orThrow();

    const events = toEventCalendarBookings(rows, {
      colorOf: (booking) =>
        booking.status === "confirmed" ? "emerald" : undefined,
    });

    expect(
      events.map((event) => [event.id, event.title, event.resourceId]),
    ).toEqual([
      ["b1", "Bo", "r1"],
      ["b2", "Booking", "r1"],
    ]);
    expect(events[0]?.readOnly).toBe(true);
    expect(events[1]?.color).toBe("emerald");
    expect(events[0]?.start.toISOString()).toBe("2030-03-04T08:00:00.000Z");
  });

  it("groups slots by local day in start order", async () => {
    const { bookings } = recorder({
      available_slots: [
        {
          ...SLOT,
          startsAt: "2030-03-05T08:00:00+00:00",
          localStart: "2030-03-05T09:00:00",
        },
        SLOT,
        {
          ...SLOT,
          startsAt: "2030-03-04T23:30:00+00:00",
          localStart: "2030-03-05T00:30:00",
        },
      ],
    });

    const days = slotsByDay(
      await bookings.availableSlots("s1", range).orThrow(),
    );

    expect([...days.keys()]).toEqual(["2030-03-04", "2030-03-05"]);
    expect(
      days.get("2030-03-05")?.map((slot) => slot.localStart.toString()),
    ).toEqual(["2030-03-05T00:30:00", "2030-03-05T09:00:00"]);
  });
});
