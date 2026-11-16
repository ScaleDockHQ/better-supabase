import type { CalendarEventInput } from "./calendar.ts";
import type { IcsEvent } from "./ics.ts";
import type { CalendarEvent } from "./occurrences.ts";

import { alarmItem } from "./alarms.ts";

/** The jsonb `save_calendar_event` takes. */
export function itemOf(
  input: CalendarEventInput & {
    readonly id?: string;
    readonly recurrenceId?: string;
    readonly originalStart?: Temporal.Instant;
  },
): Record<string, unknown> {
  const item: Record<string, unknown> = {};

  for (const [key, value] of Object.entries(input)) {
    if (value === undefined) {
      continue;
    }

    if ((key === "exdates" || key === "rdates") && Array.isArray(value)) {
      item[key] = value.map(String);
    } else if (key === "alarms" && Array.isArray(value)) {
      item[key] = value.map(alarmItem);
    } else if (
      key === "startsAt" ||
      key === "endsAt" ||
      key === "originalStart"
    ) {
      item[key] = String(value);
    } else {
      item[key] = value;
    }
  }

  return item;
}

/** An imported event as the jsonb `import_calendar_events` takes. */
export function importItem(event: IcsEvent): Record<string, unknown> {
  return itemOf({
    uid: event.uid,
    title: event.title,
    description: event.description ?? null,
    location: event.location ?? null,
    startsAt: event.startsAt,
    endsAt: event.endsAt,
    allDay: event.allDay,
    tz: event.tz,
    status: event.status,
    rrule: event.rrule ?? null,
    exdates: event.exdates,
    ...(event.rdates === undefined ? {} : { rdates: event.rdates }),
    ...(event.originalStart === undefined
      ? {}
      : { originalStart: event.originalStart }),
    ...(event.transparency === undefined
      ? {}
      : { transparency: event.transparency }),
    alarms: event.alarms ?? [],
  });
}

/** The fields of a series that an override or a new series starts from. */
export function copyOf(event: CalendarEvent): CalendarEventInput {
  return {
    title: event.title,
    ...(event.description === undefined
      ? {}
      : { description: event.description }),
    ...(event.location === undefined ? {} : { location: event.location }),
    allDay: event.allDay,
    tz: event.tz,
    status: event.status,
    ...(event.subjectType === undefined
      ? {}
      : { subjectType: event.subjectType }),
    ...(event.subjectId === undefined ? {} : { subjectId: event.subjectId }),
    ...(event.color === undefined ? {} : { color: event.color }),
    ...(event.kind === undefined ? {} : { kind: event.kind }),
    ...(event.transparency === undefined
      ? {}
      : { transparency: event.transparency }),
    ...(event.autoDecline === undefined
      ? {}
      : { autoDecline: event.autoDecline }),
    ...(event.visibility === undefined ? {} : { visibility: event.visibility }),
    ...(event.alarms === undefined ? {} : { alarms: event.alarms }),
  };
}
