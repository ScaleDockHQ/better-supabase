import "server-only";
import { tenantOf } from "better-supabase/next";
import { unstable_rethrow } from "next/navigation";
import { Temporal } from "temporal-polyfill";

import { bsb } from "@/lib/supabase/server";

import { EVENT_SUBJECT } from "./calendar-subjects";

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

/**
 * The next events in the coming two weeks, one entry per event (a series shows
 * once, at its next occurrence), with the caller's reminders on each.
 */
export async function loadUpcomingReminders(): Promise<UpcomingReminders | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const { calendar, reminders } = db;
  const calendars = await calendar.listCalendars(tenant).orThrow();

  if (calendars.length === 0) {
    return { calendars: [], events: [] };
  }

  const from = Temporal.Now.instant();

  const occurrences = await calendar
    .occurrences({
      calendarIds: calendars.map((item) => item.id),
      range: { from, until: from.add({ hours: UPCOMING_DAYS * 24 }) },
    })
    .orThrow();

  const next = new Map<string, (typeof occurrences)[number]>();

  for (const occurrence of occurrences.toSorted((a, b) =>
    Temporal.Instant.compare(a.start, b.start),
  )) {
    const id = occurrence.series?.id ?? occurrence.event.id;

    if (!next.has(id) && next.size < UPCOMING_EVENTS) {
      next.set(id, occurrence);
    }
  }

  const events = await Promise.all(
    [...next].map(async ([id, occurrence]) => ({
      id,
      title: occurrence.event.title,
      startsAt: occurrence.start.toString(),
      allDay: occurrence.allDay,
      reminders: await reminders.list({ type: EVENT_SUBJECT, id }).orThrow(),
    })),
  );

  return {
    calendars: calendars.map((item) => ({
      id: item.id,
      name: item.name,
      tz: item.tz,
    })),
    events,
  };
}

/**
 * The organization's calendars and the occurrences (series expanded) from
 * `from` up to `until`, both `YYYY-MM-DD`, ordered by start.
 */
export async function loadCalendarMonth(
  from: string,
  until: string,
): Promise<CalendarMonth | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const { calendar } = db;
  const calendars = await calendar.listCalendars(tenant).orThrow();
  const tz = calendars[0]?.tz ?? "UTC";

  if (calendars.length === 0) {
    return { calendars: [], tz, events: [] };
  }

  const at = (day: string) =>
    Temporal.PlainDate.from(day).toZonedDateTime(tz).toInstant();

  const occurrences = await calendar
    .occurrences({
      calendarIds: calendars.map((item) => item.id),
      range: { from: at(from), until: at(until) },
    })
    .orThrow();

  return {
    calendars: calendars.map((item) => ({
      id: item.id,
      name: item.name,
      tz: item.tz,
    })),
    tz,
    events: occurrences
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
  };
}
