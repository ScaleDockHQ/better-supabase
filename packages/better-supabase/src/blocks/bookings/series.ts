import type { Booking } from "./bookings.ts";

import { temporal } from "../../core/temporal-required.ts";
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

const RRULE_DAYS = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"] as const;

const DAY_NUMBERS: Readonly<Record<string, BookingWeekday>> = {
  MO: 1,
  TU: 2,
  WE: 3,
  TH: 4,
  FR: 5,
  SA: 6,
  SU: 7,
};

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
 * `UNTIL` (UTC, `YYYYMMDDTHHMMSSZ`). Throws a `RangeError` for anything else.
 */
export function parseRecurrence(rrule: string): BookingRecurrence {
  const parts = new Map<string, string>();

  for (const part of rrule.replace(/^RRULE:/iu, "").split(";")) {
    const [key, value, extra] = part.split("=");

    if (!key || value === undefined || extra !== undefined) {
      throw new RangeError(`Invalid RRULE part "${part}"`);
    }

    parts.set(key.toUpperCase(), value.toUpperCase());
  }

  const freq = parts.get("FREQ");

  if (freq !== "DAILY" && freq !== "WEEKLY") {
    throw new RangeError("A series repeats DAILY or WEEKLY");
  }

  const unknown = [...parts.keys()].filter(
    (key) => !["FREQ", "INTERVAL", "BYDAY", "COUNT", "UNTIL"].includes(key),
  );

  if (unknown.length > 0) {
    throw new RangeError(`Unsupported RRULE parts: ${unknown.join(", ")}`);
  }

  const integer = (key: string): number | undefined => {
    const raw = parts.get(key);

    if (raw === undefined) {
      return undefined;
    }

    if (!/^\d+$/u.test(raw)) {
      throw new RangeError(`${key} must be a positive integer`);
    }

    return Number(raw);
  };

  const weekdays = parts
    .get("BYDAY")
    ?.split(",")
    .map((day) => {
      const weekday = DAY_NUMBERS[day];

      if (weekday === undefined) {
        throw new RangeError(`Unsupported BYDAY value "${day}"`);
      }

      return weekday;
    });

  const rawUntil = parts.get("UNTIL");

  const until =
    rawUntil === undefined
      ? undefined
      : temporal().Instant.from(
          rawUntil.replace(
            /^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z$/u,
            "$1-$2-$3T$4:$5:$6Z",
          ),
        );

  const interval = integer("INTERVAL");
  const count = integer("COUNT");

  return {
    freq: freq === "DAILY" ? "daily" : "weekly",
    ...(interval === undefined ? {} : { interval }),
    ...(weekdays === undefined ? {} : { weekdays }),
    ...(count === undefined ? {} : { count }),
    ...(until === undefined ? {} : { until }),
  };
}

/** The rule as an RRULE value, the inverse of `parseRecurrence`. */
export function formatRecurrence(rule: BookingRecurrence): string {
  const until = rule.until
    ?.toString({ smallestUnit: "second" })
    .replaceAll(/[-:]/gu, "");

  return [
    `FREQ=${rule.freq.toUpperCase()}`,
    ...(rule.interval === undefined ? [] : [`INTERVAL=${rule.interval}`]),
    ...(rule.weekdays === undefined || rule.weekdays.length === 0
      ? []
      : [`BYDAY=${rule.weekdays.map((day) => RRULE_DAYS[day - 1]).join(",")}`]),
    ...(rule.count === undefined ? [] : [`COUNT=${rule.count}`]),
    ...(until === undefined ? [] : [`UNTIL=${until}`]),
  ].join(";");
}

/** What `bookSeries` booked. */
export interface BookedSeries<B extends Booking = Booking> {
  readonly series: BookingSeries;
  readonly bookings: readonly B[];
  /** The starts `skipConflicts` left out because they were taken. */
  readonly skipped: readonly Temporal.Instant[];
}
