import type { RecurrenceRule } from "../../core/recurrence.ts";
import type { Booking } from "./bookings.ts";

import { formatRrule, parseRrule, weekdayName } from "../../core/recurrence.ts";
import {
  oneOf,
  optionalInstant,
  optionalText,
  recordOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

/** An ISO weekday: 1 is Monday, 7 is Sunday. */
export type BookingWeekday = 1 | 2 | 3 | 4 | 5 | 6 | 7;

/**
 * When a series repeats. Every occurrence keeps the first one's wall-clock time
 * in `tz` (default the resource's zone), so it follows daylight saving. Give
 * `count`, `until` or both; a series books at most 366 occurrences within two
 * years.
 */
export interface BookingRecurrence {
  readonly freq: "daily" | "weekly";
  /** Every `interval` days or weeks. Default 1, at most 52. */
  readonly interval?: number;
  /** The weekdays a weekly series falls on. Default the first one's. */
  readonly weekdays?: readonly BookingWeekday[];
  readonly count?: number;
  /** The last moment an occurrence may start. */
  readonly until?: Temporal.Instant;
  readonly tz?: string;
}

export type BookingSeriesStatus = "active" | "ended" | "cancelled";

export interface BookingSeries {
  readonly id: string;
  readonly organizationId: string;
  readonly serviceId: string;
  readonly resourceId: string;
  readonly rule: BookingRecurrence;
  readonly startsAt: Temporal.Instant;
  readonly tz: string;
  readonly status: BookingSeriesStatus;
  /** The end of the last live occurrence. */
  readonly endsAt?: Temporal.Instant;
  readonly customerName?: string;
  readonly customerEmail?: string;
  readonly customerUserId?: string;
}

/**
 * Which occurrences a change touches: this one, or this one and every later
 * one.
 */
export type BookingSeriesScope = "one" | "following";

const FREQS = ["daily", "weekly"] as const;

const SERIES_STATUSES: readonly BookingSeriesStatus[] = [
  "active",
  "ended",
  "cancelled",
];

const numberOf = (value: unknown): number | undefined =>
  typeof value === "number" ? value : undefined;

const isWeekday = (value: number): value is BookingWeekday =>
  Number.isInteger(value) && value >= 1 && value <= 7;

/** The rule as the jsonb `book_series` takes. */
export function recurrenceItem(
  rule: BookingRecurrence,
): Record<string, unknown> {
  return {
    freq: rule.freq,
    ...(rule.interval === undefined ? {} : { interval: rule.interval }),
    ...(rule.weekdays === undefined ? {} : { weekdays: [...rule.weekdays] }),
    ...(rule.count === undefined ? {} : { count: rule.count }),
    ...(rule.until === undefined ? {} : { until: String(rule.until) }),
    ...(rule.tz === undefined ? {} : { tz: rule.tz }),
  };
}

function recurrenceOf(value: unknown): BookingRecurrence {
  const row = recordOf(value, "rule");

  const weekdays = Array.isArray(row["weekdays"])
    ? row["weekdays"].map(Number).filter(isWeekday)
    : undefined;

  const until = optionalInstant(row["until"]);
  const interval = numberOf(row["interval"]);
  const count = numberOf(row["count"]);

  return {
    freq: oneOf(row["freq"], FREQS, "weekly"),
    ...(interval === undefined ? {} : { interval }),
    ...(weekdays === undefined ? {} : { weekdays }),
    ...(count === undefined ? {} : { count }),
    ...(until === undefined ? {} : { until }),
  };
}

/** A series row as `book_series` and `get_booking_series` return it. */
export function bookingSeriesOf(value: unknown): BookingSeries {
  const row = recordOf(value, "booking series");
  const endsAt = optionalInstant(row["endsAt"]);

  const text = (key: string) => {
    const found = optionalText(row[key]);

    return found === undefined ? {} : { [key]: found };
  };

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    serviceId: textOf(row["serviceId"]),
    resourceId: textOf(row["resourceId"]),
    rule: recurrenceOf(row["rule"]),
    startsAt: requiredInstant(row["startsAt"], "startsAt"),
    tz: textOf(row["tz"]),
    status: oneOf(row["status"], SERIES_STATUSES, "active"),
    ...(endsAt === undefined ? {} : { endsAt }),
    ...text("customerName"),
    ...text("customerEmail"),
    ...text("customerUserId"),
  };
}

/**
 * Reads the subset of an iCalendar RRULE (RFC 5545) a series supports:
 * `FREQ=DAILY|WEEKLY`, `INTERVAL`, `BYDAY` (plain weekdays), `COUNT` and
 * `UNTIL` (UTC, `YYYYMMDDTHHMMSSZ`). The shared recurrence reader parses it; a
 * part a series does not support throws a `RangeError`.
 */
export function parseRecurrence(rrule: string): BookingRecurrence {
  const text = rrule.replace(/^RRULE:/iu, "");
  const names = text
    .split(";")
    .map((item) => item.split("=")[0]?.toUpperCase());

  const unknown = names.filter(
    (key) =>
      key === undefined ||
      !["FREQ", "INTERVAL", "BYDAY", "COUNT", "UNTIL"].includes(key),
  );

  if (unknown.length > 0) {
    throw new RangeError(`Unsupported RRULE parts: ${unknown.join(", ")}`);
  }

  let rule: RecurrenceRule;

  try {
    rule = parseRrule(text.toUpperCase());
  } catch (error) {
    throw new RangeError(
      error instanceof Error ? error.message : "Invalid RRULE",
      { cause: error },
    );
  }

  if (rule.frequency !== "daily" && rule.frequency !== "weekly") {
    throw new RangeError("A series repeats DAILY or WEEKLY");
  }

  const ordinal = rule.byDay.find((item) => item.ordinal !== undefined);

  if (ordinal !== undefined) {
    throw new RangeError(
      `Unsupported BYDAY value "${ordinal.ordinal}${weekdayName(ordinal.day)}"`,
    );
  }

  const weekdays = rule.byDay.map((item) => item.day).filter(isWeekday);

  return {
    freq: rule.frequency,
    ...(names.includes("INTERVAL") ? { interval: rule.interval } : {}),
    ...(weekdays.length === 0 ? {} : { weekdays }),
    ...(rule.count === undefined ? {} : { count: rule.count }),
    ...(rule.until === undefined ? {} : { until: rule.until }),
  };
}

/** The rule as an RRULE value, the inverse of `parseRecurrence`. */
export function formatRecurrence(rule: BookingRecurrence): string {
  return formatRrule({
    frequency: rule.freq,
    ...(rule.interval === undefined ? {} : { interval: rule.interval }),
    byDay: (rule.weekdays ?? []).map((day) => ({ day })),
    ...(rule.count === undefined ? {} : { count: rule.count }),
    ...(rule.until === undefined ? {} : { until: rule.until }),
  });
}

/** What `bookSeries` booked. */
export interface BookedSeries<B extends Booking = Booking> {
  readonly series: BookingSeries;
  readonly bookings: readonly B[];
  /** The starts `skipConflicts` left out because they were taken. */
  readonly skipped: readonly Temporal.Instant[];
}
