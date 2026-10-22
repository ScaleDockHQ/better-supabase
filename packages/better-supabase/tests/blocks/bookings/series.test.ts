import { describe, expect, it } from "vitest";

import { createBookings } from "../../../src/blocks/bookings/bookings.ts";
import {
  bookingSeriesOf,
  formatRecurrence,
  parseRecurrence,
} from "../../../src/blocks/bookings/series.ts";

const at = (text: string): Temporal.Instant => Temporal.Instant.from(text);

const BOOKING = {
  id: "b1",
  resourceId: "r1",
  serviceId: "s1",
  seat: 1,
  startsAt: "2030-03-18T08:00:00+00:00",
  endsAt: "2030-03-18T09:00:00+00:00",
  status: "confirmed",
  customerUserId: "u1",
  seriesId: "sr1",
};

const SERIES = {
  id: "sr1",
  organizationId: "org-1",
  serviceId: "s1",
  resourceId: "r1",
  rule: { freq: "weekly", weekdays: [1, 3], count: 4, interval: 1 },
  startsAt: "2030-03-18T08:00:00+00:00",
  tz: "Europe/Amsterdam",
  customerName: null,
  customerEmail: "bo@example.test",
  customerUserId: "u1",
  status: "active",
  endsAt: "2030-03-27T09:00:00+00:00",
  createdAt: "2030-03-01T08:00:00+00:00",
};

function recorder(results: Record<string, unknown>) {
  const calls: [string, Readonly<Record<string, unknown>>][] = [];

  const transport = {
    call(_schema: string, fn: string, args: Readonly<Record<string, unknown>>) {
      calls.push([fn, args]);

      return Promise.resolve(results[fn]);
    },
  };

  return { calls, bookings: createBookings({ transport }) };
}

describe("booking recurrence rules", () => {
  it("reads the RRULE subset a series supports", () => {
    expect(
      parseRecurrence(
        "RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;COUNT=6;UNTIL=20300601T000000Z",
      ),
    ).toEqual({
      freq: "weekly",
      interval: 2,
      weekdays: [1, 3],
      count: 6,
      until: at("2030-06-01T00:00:00Z"),
    });
    expect(parseRecurrence("freq=daily;count=3")).toEqual({
      freq: "daily",
      count: 3,
    });
  });

  it("refuses what a series can't book", () => {
    expect(() => parseRecurrence("FREQ=MONTHLY;COUNT=2")).toThrow(RangeError);
    expect(() => parseRecurrence("FREQ=WEEKLY;BYSETPOS=1")).toThrow(
      /Unsupported RRULE parts: BYSETPOS/,
    );
    expect(() => parseRecurrence("FREQ=WEEKLY;BYDAY=1MO")).toThrow(
      /BYDAY value "1MO"/,
    );
    expect(() => parseRecurrence("FREQ=WEEKLY;COUNT=-1")).toThrow(
      /COUNT must be a positive integer/,
    );
    expect(() => parseRecurrence("FREQ=WEEKLY;COUNT")).toThrow(
      /Invalid RRULE part/,
    );
  });

  it("writes a rule back as an RRULE", () => {
    const rule = {
      freq: "weekly",
      interval: 2,
      weekdays: [1, 5],
      count: 4,
      until: at("2030-06-01T00:00:00Z"),
    } as const;

    expect(formatRecurrence(rule)).toBe(
      "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,FR;COUNT=4;UNTIL=20300601T000000Z",
    );
    expect(parseRecurrence(formatRecurrence(rule))).toEqual(rule);
    expect(formatRecurrence({ freq: "daily", weekdays: [], count: 2 })).toBe(
      "FREQ=DAILY;COUNT=2",
    );
  });

  it("parses a series row", () => {
    const series = bookingSeriesOf({
      ...SERIES,
      rule: { freq: "daily", until: "2030-04-01T00:00:00Z" },
      endsAt: null,
    });

    expect(series).toMatchObject({
      id: "sr1",
      rule: { freq: "daily" },
      status: "active",
      customerEmail: "bo@example.test",
    });
    expect(series.rule.until?.toString()).toBe("2030-04-01T00:00:00Z");
    expect(series).not.toHaveProperty("endsAt");
    expect(series).not.toHaveProperty("customerName");
  });
});

describe("bookings series client", () => {
  it("books a series and reports skipped occurrences", async () => {
    const { calls, bookings } = recorder({
      book_series: {
        series: SERIES,
        bookings: [BOOKING],
        skipped: ["2030-03-20T08:00:00+00:00"],
      },
    });

    const booked = await bookings
      .bookSeries(
        "s1",
        "r1",
        at("2030-03-18T08:00:00Z"),
        {
          freq: "weekly",
          weekdays: [1, 3],
          count: 4,
          interval: 1,
          until: at("2030-04-01T00:00:00Z"),
          tz: "Europe/Amsterdam",
        },
        { email: "bo@example.test" },
        { skipConflicts: true },
      )
      .orThrow();

    expect(calls).toEqual([
      [
        "book_series",
        {
          service: "s1",
          resource: "r1",
          starts_at: "2030-03-18T08:00:00Z",
          rule: {
            freq: "weekly",
            interval: 1,
            weekdays: [1, 3],
            count: 4,
            until: "2030-04-01T00:00:00Z",
            tz: "Europe/Amsterdam",
          },
          customer: { email: "bo@example.test" },
          skip_conflicts: true,
        },
      ],
    ]);
    expect(booked.series).toMatchObject({
      id: "sr1",
      rule: { freq: "weekly", weekdays: [1, 3], count: 4, interval: 1 },
    });
    expect(booked.bookings.map((booking) => booking.seriesId)).toEqual(["sr1"]);
    expect(booked.skipped.map(String)).toEqual(["2030-03-20T08:00:00Z"]);
  });

  it("defaults to failing on conflicts, with no skipped list", async () => {
    const { calls, bookings } = recorder({
      book_series: { series: SERIES, bookings: [] },
    });

    const booked = await bookings
      .bookSeries("s1", "r1", at("2030-03-18T08:00:00Z"), { freq: "daily" })
      .orThrow();

    expect(calls[0]?.[1]).toMatchObject({
      rule: { freq: "daily" },
      customer: {},
      skip_conflicts: false,
    });
    expect(booked.skipped).toEqual([]);
  });

  it("reschedules, cancels and reads a series", async () => {
    const { calls, bookings } = recorder({
      reschedule_booking: [BOOKING],
      cancel_booking_series: 3,
      get_booking_series: { ...SERIES, bookings: [BOOKING] },
    });

    expect(
      await bookings.reschedule("b1", at("2030-03-18T10:00:00Z")).orThrow(),
    ).toHaveLength(1);
    await bookings
      .reschedule("b1", at("2030-03-18T10:00:00Z"), { scope: "following" })
      .orThrow();
    expect(await bookings.cancelSeries("b1").orThrow()).toBe(3);
    await bookings
      .cancelSeries("b1", { scope: "one", reason: "ill" })
      .orThrow();
    const series = await bookings.series("sr1").orThrow();
    expect(series.bookings.map((booking) => booking.id)).toEqual(["b1"]);
    expect(series.tz).toBe("Europe/Amsterdam");

    expect(calls).toEqual([
      [
        "reschedule_booking",
        { booking: "b1", starts_at: "2030-03-18T10:00:00Z", scope: "one" },
      ],
      [
        "reschedule_booking",
        {
          booking: "b1",
          starts_at: "2030-03-18T10:00:00Z",
          scope: "following",
        },
      ],
      [
        "cancel_booking_series",
        { booking: "b1", scope: "following", reason: null },
      ],
      ["cancel_booking_series", { booking: "b1", scope: "one", reason: "ill" }],
      ["get_booking_series", { series_id: "sr1" }],
    ]);
  });
});
