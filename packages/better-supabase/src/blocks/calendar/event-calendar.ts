import type { CalendarEvent, CalendarOccurrence } from "./occurrences.ts";

import { temporal } from "../../core/temporal-required.ts";

/**
 * The event shape of a headless event calendar such as ReUI's Event
 * Calendar (`CalendarEvent`), typed structurally: better-supabase imports
 * no UI library.
 */
export interface EventCalendarEvent<TData = unknown> {
  readonly id: string;
  readonly title: string;
  readonly start: Date;
  /** Exclusive. */
  readonly end: Date;
  readonly allDay?: boolean;
  readonly recurringEventId?: string;
  readonly originalStart?: Date;
  readonly color?: string;
  readonly readOnly?: boolean;
  readonly resourceId?: string;
  readonly data?: TData;
}

/** A row of a resource view (a person, room or calendar). */
export interface EventCalendarResource {
  readonly id: string;
  readonly title: string;
  readonly color?: string;
}

export interface EventCalendarOptions {
  /** The resource an occurrence belongs to. Default its calendar id. */
  readonly resourceOf?: (occurrence: CalendarOccurrence) => string | undefined;
  /** Marks occurrences the user cannot move. */
  readonly readOnly?: (occurrence: CalendarOccurrence) => boolean;
}

const toDate = (instant: Temporal.Instant): Date =>
  new Date(instant.epochMilliseconds);

/**
 * Occurrences as event calendar events. Each id is the occurrence key, so an
 * overridden occurrence keeps its id; `data` carries the occurrence for
 * `fromEventCalendarUpdate` and your own handlers.
 */
export function toEventCalendarEvents(
  occurrences: readonly CalendarOccurrence[],
  options: EventCalendarOptions = {},
): EventCalendarEvent<CalendarOccurrence>[] {
  return occurrences.map((occurrence) => {
    const color = occurrence.event.color;
    const resourceId =
      options.resourceOf === undefined
        ? occurrence.event.calendarId
        : options.resourceOf(occurrence);
    return {
      id: occurrence.key,
      title: occurrence.event.title,
      start: toDate(occurrence.start),
      end: toDate(occurrence.end),
      allDay: occurrence.allDay,
      ...(occurrence.recurring
        ? {
            recurringEventId: occurrence.series?.id ?? occurrence.event.id,
            originalStart: toDate(occurrence.originalStart),
          }
        : {}),
      ...(color === undefined ? {} : { color }),
      ...(options.readOnly?.(occurrence) === true ? { readOnly: true } : {}),
      ...(resourceId === undefined ? {} : { resourceId }),
      data: occurrence,
    };
  });
}

/** Calendars (or anything with an id and a name) as resources. */
export function toEventCalendarResources(
  items: readonly {
    readonly id: string;
    readonly name: string;
    readonly color?: string;
  }[],
): EventCalendarResource[] {
  return items.map((item) => ({
    id: item.id,
    title: item.name,
    ...(item.color === undefined ? {} : { color: item.color }),
  }));
}

/** What a drag or resize asks for, in the shape `editOccurrence` takes. */
export interface OccurrenceMove {
  readonly startsAt: Temporal.Instant;
  readonly endsAt: Temporal.Instant;
  readonly allDay?: boolean;
}

/**
 * The new times of an `onEventUpdate` from an event calendar, for
 * `calendar.editOccurrence(occurrence, move)` or `editFollowing`.
 */
export function fromEventCalendarUpdate(update: {
  readonly start: Date;
  readonly end: Date;
  readonly allDay?: boolean;
}): OccurrenceMove {
  const time = temporal();
  return {
    startsAt: time.Instant.fromEpochMilliseconds(update.start.getTime()),
    endsAt: time.Instant.fromEpochMilliseconds(update.end.getTime()),
    ...(update.allDay === undefined ? {} : { allDay: update.allDay }),
  };
}

/** The series of an occurrence, or the event itself. */
export const seriesOf = (occurrence: CalendarOccurrence): CalendarEvent =>
  occurrence.series ?? occurrence.event;
