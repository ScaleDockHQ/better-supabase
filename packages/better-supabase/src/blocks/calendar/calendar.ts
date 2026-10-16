import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type {
  AttendeeResponse,
  AttendeeRole,
  CalendarAttendee,
  CalendarEventStatus,
  IcsEvent,
} from "./ics.ts";
import type {
  CalendarEvent,
  CalendarOccurrence,
  OccurrenceOptions,
  OccurrenceRange,
} from "./occurrences.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult } from "../../core/result.ts";
import {
  blockCall,
  oneOf,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";
import { parseIcs, toIcs } from "./ics.ts";
import { expandOccurrences, splitRule } from "./occurrences.ts";

export interface CalendarOptions {
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Calendar>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly transport: BlockTransport;
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

export interface CalendarInfo {
  readonly id: string;
  readonly name: string;
  readonly tz: string;
  readonly color?: string;
  readonly ownerType?: string;
  readonly ownerId?: string;
}

/** The fields of an event to write. Fields left out keep their value on update. */
export interface CalendarEventInput {
  readonly title?: string;
  readonly description?: string | null;
  readonly location?: string | null;
  readonly startsAt?: Temporal.Instant;
  readonly endsAt?: Temporal.Instant;
  readonly allDay?: boolean;
  readonly tz?: string;
  readonly status?: CalendarEventStatus;
  /** An RFC 5545 `RRULE` value, or `null` to end the recurrence. */
  readonly rrule?: string | null;
  readonly exdates?: readonly Temporal.Instant[];
  readonly subjectType?: string | null;
  readonly subjectId?: string | null;
  readonly color?: string | null;
  /** Only on insert. Default the new id. */
  readonly uid?: string;
}

export interface SavedCalendarEvent {
  readonly id: string;
  readonly uid: string;
  readonly created: boolean;
}

export interface CalendarImport {
  readonly created: number;
  readonly updated: number;
  /** Events without a UID or DTSTART, and overrides of an unknown series. */
  readonly skipped: number;
}

export interface Calendar {
  createCalendar(
    organizationId: string,
    name: string,
    options?: {
      readonly tz?: string;
      readonly ownerType?: string;
      readonly ownerId?: string;
    },
  ): AsyncResult<{ readonly id: string }>;
  deleteCalendar(id: string): AsyncResult<boolean>;
  listCalendars(organizationId: string): AsyncResult<CalendarInfo[]>;
  /** Inserts an event, or updates the one with `id`. */
  save(
    calendarId: string,
    input: CalendarEventInput & { readonly id?: string },
  ): AsyncResult<SavedCalendarEvent>;
  delete(eventId: string): AsyncResult<boolean>;
  /** The rows that can fall in the range: events, series and their overrides. */
  events(
    calendarIds: readonly string[],
    range: OccurrenceRange,
  ): AsyncResult<CalendarEvent[]>;
  /** The occurrences in the range, series expanded. */
  occurrences(
    calendarIds: readonly string[],
    range: OccurrenceRange,
    options?: OccurrenceOptions,
  ): AsyncResult<CalendarOccurrence[]>;
  /** Changes one occurrence: an override for a series, else the event. */
  editOccurrence(
    occurrence: CalendarOccurrence,
    changes: CalendarEventInput,
  ): AsyncResult<SavedCalendarEvent>;
  /**
   * Changes an occurrence and every later one: splits the series, unless the
   * occurrence is its first. Pass `rrule` when the change moves the weekday.
   */
  editFollowing(
    occurrence: CalendarOccurrence,
    changes: CalendarEventInput,
  ): AsyncResult<{ readonly id: string }>;
  /** Removes one occurrence of a series (an `EXDATE`), or a single event. */
  cancelOccurrence(occurrence: CalendarOccurrence): AsyncResult<boolean>;
  setAttendee(
    eventId: string,
    attendee: {
      readonly email: string;
      readonly name?: string;
      readonly userId?: string;
      readonly role?: AttendeeRole;
    },
  ): AsyncResult<boolean>;
  removeAttendee(eventId: string, email: string): AsyncResult<boolean>;
  /** The signed-in user answers an invitation. */
  respond(eventId: string, response: AttendeeResponse): AsyncResult<boolean>;
  /** Upserts the events of an iCalendar file by UID. */
  importIcs(calendarId: string, text: string): AsyncResult<CalendarImport>;
  /** The calendar's events as an iCalendar file. */
  exportIcs(
    calendar: CalendarInfo,
    range?: OccurrenceRange,
  ): AsyncResult<string>;
  /**
   * The iCalendar feed of a share link to a calendar (`subjectType:
   * "calendar"`), or `null` when the token is unknown, revoked or expired.
   */
  feed(token: string): AsyncResult<string | null>;
}

const ROLES: readonly AttendeeRole[] = [
  "chair",
  "required",
  "optional",
  "non-participant",
];
const RESPONSES: readonly AttendeeResponse[] = [
  "needs-action",
  "accepted",
  "declined",
  "tentative",
];
const STATUSES: readonly CalendarEventStatus[] = [
  "confirmed",
  "tentative",
  "cancelled",
];

function attendeeOf(value: Record<string, unknown>): CalendarAttendee {
  const name = optionalText(value["name"]);
  const userId = optionalText(value["userId"]);
  return {
    email: textOf(value["email"]),
    ...(name === undefined ? {} : { name }),
    ...(userId === undefined ? {} : { userId }),
    role: oneOf(value["role"], ROLES, "required"),
    response: oneOf(value["response"], RESPONSES, "needs-action"),
  };
}

/** A `list_calendar_events` or `calendar_feed` row as an event. */
export function calendarEventOf(value: unknown): CalendarEvent {
  const row = recordOf(value, "calendar event");
  const text = (key: string) => {
    const found = optionalText(row[key]);
    return found === undefined ? {} : { [key]: found };
  };
  const originalStart = optionalInstant(row["originalStart"]);
  const updatedAt = optionalInstant(row["updatedAt"]);
  const exdates = Array.isArray(row["exdates"]) ? row["exdates"] : [];
  return {
    id: textOf(row["id"]),
    calendarId: textOf(row["calendarId"]),
    uid: textOf(row["uid"]),
    title: optionalText(row["title"]) ?? "",
    ...text("description"),
    ...text("location"),
    startsAt: requiredInstant(row["startsAt"], "startsAt"),
    endsAt: requiredInstant(row["endsAt"], "endsAt"),
    allDay: row["allDay"] === true,
    tz: optionalText(row["tz"]) ?? "UTC",
    status: oneOf(row["status"], STATUSES, "confirmed"),
    ...text("rrule"),
    exdates: exdates.map((date) => requiredInstant(date, "exdate")),
    ...text("recurrenceId"),
    ...(originalStart === undefined ? {} : { originalStart }),
    ...text("subjectType"),
    ...text("subjectId"),
    ...text("color"),
    attendees: recordsOf(row["attendees"], "attendees").map(attendeeOf),
    ...(updatedAt === undefined ? {} : { updatedAt }),
  };
}

/** The jsonb `save_calendar_event` takes. */
function itemOf(
  input: CalendarEventInput & {
    readonly id?: string;
    readonly recurrenceId?: string;
    readonly originalStart?: Temporal.Instant;
  },
): Record<string, unknown> {
  const item: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(input)) {
    if (value === undefined) continue;
    if (key === "exdates" && Array.isArray(value)) {
      item[key] = value.map(String);
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
function importItem(event: IcsEvent): Record<string, unknown> {
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
    ...(event.originalStart === undefined
      ? {}
      : { originalStart: event.originalStart }),
  });
}

/** The fields of a series that an override or a new series starts from. */
function copyOf(event: CalendarEvent): CalendarEventInput {
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
  };
}

const INFINITE = { from: "-infinity", until: "infinity" } as const;

export function createCalendar(options: CalendarOptions): Calendar {
  const call = blockCall(options.transport, options.schema, options.mappers);
  const saved = (value: unknown): SavedCalendarEvent => {
    const row = recordOf(value, "save_calendar_event");
    return {
      id: textOf(row["id"]),
      uid: textOf(row["uid"]),
      created: row["created"] === true,
    };
  };
  const save = (
    calendarId: string,
    input: Parameters<typeof itemOf>[0],
  ): AsyncResult<SavedCalendarEvent> =>
    call(
      "save_calendar_event",
      { calendar_id: calendarId, item: itemOf(input) },
      saved,
    );
  const list = (
    calendarIds: readonly string[],
    range: OccurrenceRange | typeof INFINITE,
  ): AsyncResult<CalendarEvent[]> =>
    call(
      "list_calendar_events",
      {
        calendar_ids: [...calendarIds],
        range_start: range.from.toString(),
        range_end: range.until.toString(),
      },
      (value) => recordsOf(value, "list_calendar_events").map(calendarEventOf),
    );
  const client: Calendar = {
    createCalendar: (organizationId, name, extra = {}) =>
      call(
        "create_calendar",
        {
          tenant: organizationId,
          name,
          tz: extra.tz ?? "UTC",
          owner_type: extra.ownerType ?? null,
          owner_id: extra.ownerId ?? null,
        },
        (value) => ({ id: textOf(recordOf(value, "create_calendar")["id"]) }),
      ),
    deleteCalendar: (id) =>
      call("delete_calendar", { calendar_id: id }, (value) => value === true),
    listCalendars: (organizationId) =>
      call("list_calendars", { tenant: organizationId }, (value) =>
        recordsOf(value, "list_calendars").map((row) => {
          const extra: Record<string, string> = {};
          for (const key of ["color", "ownerType", "ownerId"]) {
            const found = optionalText(row[key]);
            if (found !== undefined) extra[key] = found;
          }
          return {
            id: textOf(row["id"]),
            name: textOf(row["name"]),
            tz: optionalText(row["tz"]) ?? "UTC",
            ...extra,
          };
        }),
      ),
    save,
    delete: (eventId) =>
      call(
        "delete_calendar_event",
        { event_id: eventId },
        (value) => value === true,
      ),
    events: list,
    occurrences: (calendarIds, range, occurrenceOptions) =>
      list(calendarIds, range).map((events) =>
        expandOccurrences(events, range, occurrenceOptions),
      ),
    editOccurrence: (occurrence, changes) => {
      const series = occurrence.series;
      if (!occurrence.recurring || series === undefined) {
        return save(occurrence.event.calendarId, {
          ...changes,
          id: occurrence.event.id,
        });
      }
      if (occurrence.event.recurrenceId !== undefined) {
        return save(occurrence.event.calendarId, {
          ...changes,
          id: occurrence.event.id,
        });
      }
      return save(series.calendarId, {
        ...copyOf(series),
        startsAt: occurrence.start,
        endsAt: occurrence.end,
        ...changes,
        rrule: null,
        exdates: [],
        recurrenceId: series.id,
        originalStart: occurrence.originalStart,
      });
    },
    editFollowing: (occurrence, changes) => {
      const series = occurrence.series;
      if (!occurrence.recurring || series?.rrule === undefined) {
        return save(occurrence.event.calendarId, {
          ...changes,
          id: occurrence.event.id,
        }).map(({ id }) => ({ id }));
      }
      if (occurrence.originalStart.equals(series.startsAt)) {
        return save(series.calendarId, { ...changes, id: series.id }).map(
          ({ id }) => ({ id }),
        );
      }
      let rules: ReturnType<typeof splitRule>;
      try {
        rules = splitRule(
          series.rrule,
          series.startsAt.toZonedDateTimeISO(series.tz),
          occurrence.originalStart,
        );
      } catch (cause) {
        return AsyncResult.err(
          dbError(
            "invalid_input",
            cause instanceof Error ? cause.message : String(cause),
            {
              hint: "CALENDAR_SPLIT_INVALID",
            },
          ),
        );
      }
      const length = series.endsAt.since(series.startsAt);
      return call(
        "split_calendar_event",
        {
          event_id: series.id,
          split_at: occurrence.originalStart.toString(),
          before_rrule: rules.before,
          item: itemOf({
            ...copyOf(series),
            startsAt: occurrence.originalStart,
            endsAt: occurrence.originalStart.add(length),
            rrule: rules.after,
            ...changes,
          }),
        },
        (value) => ({
          id: textOf(recordOf(value, "split_calendar_event")["id"]),
        }),
      );
    },
    cancelOccurrence: (occurrence) => {
      const series = occurrence.series;
      if (!occurrence.recurring || series === undefined) {
        return call(
          "delete_calendar_event",
          { event_id: occurrence.event.id },
          (value) => value === true,
        );
      }
      return call(
        "cancel_calendar_occurrence",
        {
          event_id: series.id,
          original_start: occurrence.originalStart.toString(),
        },
        (value) => value === true,
      );
    },
    setAttendee: (eventId, attendee) =>
      call(
        "set_calendar_attendee",
        {
          event_id: eventId,
          email: attendee.email,
          name: attendee.name ?? null,
          user_id: attendee.userId ?? null,
          role: attendee.role ?? "required",
        },
        (value) => value === true,
      ),
    removeAttendee: (eventId, email) =>
      call(
        "remove_calendar_attendee",
        { event_id: eventId, email },
        (value) => value === true,
      ),
    respond: (eventId, response) =>
      call(
        "respond_calendar_event",
        { event_id: eventId, response },
        (value) => value === true,
      ),
    importIcs: (calendarId, text) => {
      const parsed = parseIcs(text);
      return call(
        "import_calendar_events",
        {
          calendar_id: calendarId,
          source: { events: parsed.events.map(importItem) },
        },
        (value) => {
          const row = recordOf(value, "import_calendar_events");
          return {
            created: Number(row["created"] ?? 0),
            updated: Number(row["updated"] ?? 0),
            skipped: Number(row["skipped"] ?? 0) + parsed.skipped,
          };
        },
      );
    },
    exportIcs: (calendar, range) =>
      list([calendar.id], range ?? INFINITE).map((events) =>
        toIcs(events, { name: calendar.name, tz: calendar.tz }),
      ),
    feed: (token) =>
      call("calendar_feed", { token }, (value) => {
        if (value === null || value === undefined) return null;
        const row = recordOf(value, "calendar_feed");
        const info = recordOf(row["calendar"], "calendar_feed");
        return toIcs(
          recordsOf(row["events"], "calendar_feed").map(calendarEventOf),
          {
            name: textOf(info["name"]),
            tz: optionalText(info["tz"]) ?? "UTC",
          },
        );
      }),
  };
  return withBlockHooks(client, options.hooks, {
    block: "calendar",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
