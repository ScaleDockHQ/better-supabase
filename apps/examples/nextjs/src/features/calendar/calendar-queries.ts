import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";
import { unstable_rethrow } from "next/navigation";
import { Temporal } from "temporal-polyfill";

import { BOOKINGS_TAG } from "@/features/bookings/bookings-cache";
import { bsb } from "@/lib/supabase/server";

import { CALENDAR_TAG } from "./calendar-cache";

/** What a loader gives a component: the data, a failed read, or no organization. */
export type Loaded<T> =
  | { readonly kind: "ok"; readonly data: T }
  | { readonly kind: "error" }
  | { readonly kind: "no-organization" };

/**
 * Runs a loader and turns a thrown read into `{ kind: "error" }`, so the
 * component shows Retry. A failed read is never cached.
 */
export async function settle<T>(
  load: () => Promise<T | null>,
): Promise<Loaded<T>> {
  try {
    const data = await load();

    return data === null ? { kind: "no-organization" } : { kind: "ok", data };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}

export interface CalendarSummary {
  readonly id: string;
  readonly name: string;
  readonly tz: string;
}

export interface MonthEvent {
  readonly key: string;
  readonly calendarId: string;
  readonly title: string;
  /** The day it starts, `YYYY-MM-DD` in the month's zone. */
  readonly day: string;
  /** `HH:MM` in the month's zone; `null` for an all-day event. */
  readonly time: string | null;
}

export interface CalendarMonth {
  readonly calendars: readonly CalendarSummary[];
  /** The zone days are drawn in: the first calendar's, else UTC. */
  readonly tz: string;
  readonly events: readonly MonthEvent[];
}

const UPCOMING_EVENTS = 5;
const UPCOMING_DAYS = 14;

export interface UpcomingEvent {
  readonly id: string;
  readonly title: string;
  /** ISO 8601. */
  readonly startsAt: string;
  readonly allDay: boolean;
  readonly reminders: readonly {
    readonly id: string;
    readonly offsetMinutes: number;
  }[];
}

export interface UpcomingReminders {
  readonly calendars: readonly CalendarSummary[];
  readonly events: readonly UpcomingEvent[];
}

export interface CalendarPage {
  readonly month: CalendarMonth;
  readonly upcoming: UpcomingReminders;
}

/**
 * Everything /calendar shows, from one `calendar.bootstrap` call: the
 * organization's calendars, the occurrences (series expanded) from `from` up to
 * `until` (both `YYYY-MM-DD`), the next events of the coming two weeks and the
 * caller's reminders on them. Both cards read this entry, so the page makes one
 * database call for the calendar data instead of one per read.
 */
export async function loadCalendarPage(
  from: string,
  until: string,
): Promise<CalendarPage | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(CALENDAR_TAG, BOOKINGS_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const { calendar } = db;

  // The zone days are drawn in is the first calendar's, which the same call
  // returns, so the month's bounds are read in UTC first and widened by a day
  // on each side; the filter below keeps the days of the zone.
  const bound = (day: string) =>
    Temporal.PlainDate.from(day).toZonedDateTime("UTC").toInstant();

  const now = Temporal.Now.instant();

  const boot = await calendar
    .bootstrap({
      organizationId: tenant,
      range: {
        from: bound(from).subtract({ hours: 24 }),
        until: bound(until).add({ hours: 24 }),
      },
      upcoming: { from: now, until: now.add({ hours: UPCOMING_DAYS * 24 }) },
    })
    .orThrow();

  const calendars = boot.calendars.map((item) => ({
    id: item.id,
    name: item.name,
    tz: item.tz,
  }));

  const tz = calendars[0]?.tz ?? "UTC";

  const at = (day: string) =>
    Temporal.PlainDate.from(day).toZonedDateTime(tz).toInstant();

  const first = at(from);
  const last = at(until);

  const next = new Map<string, (typeof boot.upcoming)[number]>();

  for (const occurrence of boot.upcoming.toSorted((a, b) =>
    Temporal.Instant.compare(a.start, b.start),
  )) {
    const id = occurrence.series?.id ?? occurrence.event.id;

    if (!next.has(id) && next.size < UPCOMING_EVENTS) {
      next.set(id, occurrence);
    }
  }

  return {
    month: {
      calendars,
      tz,
      events: boot.occurrences
        .filter(
          (occurrence) =>
            Temporal.Instant.compare(occurrence.start, first) >= 0 &&
            Temporal.Instant.compare(occurrence.start, last) < 0,
        )
        .toSorted((a, b) => Temporal.Instant.compare(a.start, b.start))
        .map((occurrence) => {
          const start = occurrence.start.toZonedDateTimeISO(tz);

          return {
            key: occurrence.key,
            calendarId: occurrence.event.calendarId,
            title: occurrence.event.title,
            day: start.toPlainDate().toString(),
            time: occurrence.allDay
              ? null
              : start.toPlainTime().toString({ smallestUnit: "minute" }),
          };
        }),
    },
    upcoming: {
      calendars,
      events: [...next].map(([id, occurrence]) => ({
        id,
        title: occurrence.event.title,
        startsAt: occurrence.start.toString(),
        allDay: occurrence.allDay,
        reminders: boot.reminders
          .filter((reminder) => reminder.eventId === id)
          .slice(0, 20)
          .map(({ id: reminderId, offsetMinutes }) => ({
            id: reminderId,
            offsetMinutes,
          })),
      })),
    },
  };
}

/** The month part of `loadCalendarPage`. */
export async function loadCalendarMonth(
  from: string,
  until: string,
): Promise<CalendarMonth | null> {
  const page = await loadCalendarPage(from, until);

  return page?.month ?? null;
}

/**
 * The next events in the coming two weeks, one entry per event (a series shows
 * once, at its next occurrence), with the caller's reminders on each.
 */
export async function loadUpcomingReminders(
  from: string,
  until: string,
): Promise<UpcomingReminders | null> {
  const page = await loadCalendarPage(from, until);

  return page?.upcoming ?? null;
}
