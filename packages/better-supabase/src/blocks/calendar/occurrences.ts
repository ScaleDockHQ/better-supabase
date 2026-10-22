import type {
  CalendarEventKind,
  CalendarTransparency,
} from "./availability.ts";
import type { CalendarAttendee, CalendarEventStatus } from "./ics.ts";

import { temporal } from "../../core/temporal-required.ts";
import { expandRule } from "../reminders/rrule.ts";

/** One row of `calendar_events`: a single event, a series or an override. */
export interface CalendarEvent {
  readonly id: string;
  readonly calendarId: string;
  readonly uid: string;
  readonly title: string;
  readonly description?: string;
  readonly location?: string;
  readonly startsAt: Temporal.Instant;
  /** Exclusive. */
  readonly endsAt: Temporal.Instant;
  readonly allDay: boolean;
  readonly tz: string;
  readonly status: CalendarEventStatus;
  /** The RFC 5545 `RRULE` value of a series, without the `RRULE:` prefix. */
  readonly rrule?: string;
  readonly exdates: readonly Temporal.Instant[];
  /** The series an override belongs to. */
  readonly recurrenceId?: string;
  /** The occurrence of the series an override replaces. */
  readonly originalStart?: Temporal.Instant;
  readonly subjectType?: string;
  readonly subjectId?: string;
  readonly color?: string;
  /** Absent when the table has no `kind` column; read it as `event`. */
  readonly kind?: CalendarEventKind;
  readonly transparency?: CalendarTransparency;
  /** An out-of-office or focus-time block that declines new invitations. */
  readonly autoDecline?: boolean;
  readonly attendees: readonly CalendarAttendee[];
  readonly updatedAt?: Temporal.Instant;
}

/** One occurrence in a range: a single event, or one instance of a series. */
export interface CalendarOccurrence {
  /** `${seriesId}::${originalStart}`, stable across edits of the occurrence. */
  readonly key: string;
  /** The row the occurrence comes from: the event, the series or its override. */
  readonly event: CalendarEvent;
  /** The series, for an occurrence of one (also when it is overridden). */
  readonly series?: CalendarEvent;
  readonly start: Temporal.Instant;
  readonly end: Temporal.Instant;
  /** Where the series put this occurrence before any override moved it. */
  readonly originalStart: Temporal.Instant;
  readonly allDay: boolean;
  readonly recurring: boolean;
}

export interface OccurrenceRange {
  readonly from: Temporal.Instant;
  readonly until: Temporal.Instant;
}

export interface OccurrenceOptions {
  /** Keep cancelled events and occurrences. Default false. */
  readonly includeCancelled?: boolean;
}

const keyOf = (id: string, start: Temporal.Instant): string =>
  `${id}::${start.toString()}`;

function overlaps(
  start: Temporal.Instant,
  end: Temporal.Instant,
  range: OccurrenceRange,
): boolean {
  const time = temporal();

  return (
    time.Instant.compare(start, range.until) < 0 &&
    (time.Instant.compare(end, range.from) > 0 ||
      (time.Instant.compare(start, end) === 0 &&
        time.Instant.compare(start, range.from) >= 0))
  );
}

/**
 * Expands events into the occurrences that overlap `[from, until)`. Series
 * expand with the reminders block's `expandRule` in their own zone, so a weekly
 * 09:00 meeting stays at 09:00 across DST. `EXDATE`s drop occurrences, and
 * overrides replace the occurrence they name, also when they move it out of the
 * range.
 */
export function expandOccurrences(
  events: readonly CalendarEvent[],
  range: OccurrenceRange,
  options: OccurrenceOptions = {},
): CalendarOccurrence[] {
  const time = temporal();

  const keep = (event: CalendarEvent) =>
    options.includeCancelled === true || event.status !== "cancelled";

  const series = new Map<string, CalendarEvent>();
  const overrides = new Map<string, CalendarEvent>();

  for (const event of events) {
    if (event.recurrenceId !== undefined && event.originalStart !== undefined) {
      overrides.set(keyOf(event.recurrenceId, event.originalStart), event);
    } else if (event.rrule !== undefined) {
      series.set(event.id, event);
    }
  }

  const found: CalendarOccurrence[] = [];

  for (const event of events) {
    if (event.recurrenceId !== undefined) {
      const master = series.get(event.recurrenceId);

      if (
        event.originalStart !== undefined &&
        keep(event) &&
        overlaps(event.startsAt, event.endsAt, range)
      ) {
        found.push({
          key: keyOf(event.recurrenceId, event.originalStart),
          event,
          ...(master === undefined ? {} : { series: master }),
          start: event.startsAt,
          end: event.endsAt,
          originalStart: event.originalStart,
          allDay: event.allDay,
          recurring: true,
        });
      }

      continue;
    }

    if (event.rrule === undefined) {
      if (keep(event) && overlaps(event.startsAt, event.endsAt, range)) {
        found.push({
          key: keyOf(event.id, event.startsAt),
          event,
          start: event.startsAt,
          end: event.endsAt,
          originalStart: event.startsAt,
          allDay: event.allDay,
          recurring: false,
        });
      }

      continue;
    }

    if (!keep(event)) {
      continue;
    }

    const zoned = event.startsAt.toZonedDateTimeISO(event.tz);

    const length = zoned.until(event.endsAt.toZonedDateTimeISO(event.tz), {
      largestUnit: event.allDay ? "days" : "hours",
    });

    const reach = event.endsAt.since(event.startsAt).add({ hours: 25 });

    const skipped = new Set(
      event.exdates.map((date) => date.epochMilliseconds),
    );

    for (const when of expandRule({
      dtstart: zoned,
      rrule: event.rrule,
      window: { from: range.from.subtract(reach), until: range.until },
    })) {
      const start = when.toInstant();

      if (skipped.has(start.epochMilliseconds)) {
        continue;
      }

      if (overrides.has(keyOf(event.id, start))) {
        continue;
      }

      const end = when.add(length).toInstant();

      if (!overlaps(start, end, range)) {
        continue;
      }

      found.push({
        key: keyOf(event.id, start),
        event,
        series: event,
        start,
        end,
        originalStart: start,
        allDay: event.allDay,
        recurring: true,
      });
    }
  }

  return found.toSorted(
    (a, b) =>
      time.Instant.compare(a.start, b.start) || a.key.localeCompare(b.key),
  );
}

/** The rules of a series split at one of its occurrences. */
export interface SplitRules {
  /** The series up to the occurrence before `at`: `UNTIL` instead of `COUNT`. */
  readonly before: string;
  /** The series from `at` on: the remaining `COUNT`, or the old `UNTIL`. */
  readonly after: string;
}

function ruleParts(rrule: string): Map<string, string> {
  const parts = new Map<string, string>();

  for (const part of rrule.replace(/^RRULE:/i, "").split(";")) {
    const [key, value] = part.split("=");

    if (key !== undefined && key !== "" && value !== undefined) {
      parts.set(key.toUpperCase(), value);
    }
  }

  return parts;
}

const joinRule = (parts: ReadonlyMap<string, string>): string =>
  [...parts].map(([key, value]) => `${key}=${value}`).join(";");

/**
 * Splits a series for "this and following": the first rule ends one second
 * before `at` (RFC 5545 forbids `COUNT` with `UNTIL`, so it drops `COUNT`), and
 * the second keeps the occurrences that are left.
 */
export function splitRule(
  rrule: string,
  dtstart: Temporal.ZonedDateTime,
  at: Temporal.Instant,
): SplitRules {
  const parts = ruleParts(rrule);
  const time = temporal();

  if (time.Instant.compare(at, dtstart.toInstant()) <= 0) {
    throw new RangeError("splitRule: at must come after the first occurrence");
  }

  const before = new Map(parts);
  before.delete("COUNT");
  const until = at.subtract({ seconds: 1 }).toZonedDateTimeISO("UTC");
  before.set(
    "UNTIL",
    `${String(until.year).padStart(4, "0")}${String(until.month).padStart(2, "0")}${String(until.day).padStart(2, "0")}T${String(until.hour).padStart(2, "0")}${String(until.minute).padStart(2, "0")}${String(until.second).padStart(2, "0")}Z`,
  );
  const after = new Map(parts);
  const count = parts.get("COUNT");

  if (count !== undefined) {
    const used = expandRule({
      dtstart,
      rrule,
      window: { from: dtstart.toInstant(), until: at },
      limit: Number(count),
    }).length;

    const left = Number(count) - used;

    if (left <= 0) {
      throw new RangeError(
        "splitRule: the series has no occurrence at or after at",
      );
    }

    after.set("COUNT", String(left));
  }

  return { before: joinRule(before), after: joinRule(after) };
}
