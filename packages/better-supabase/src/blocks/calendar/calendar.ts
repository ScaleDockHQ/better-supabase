import type { BlockFields, FieldsOf } from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { CalendarAlarm } from "./alarms.ts";
import type {
  CalendarEventKind,
  CalendarTransparency,
  FreeBusy,
  WorkingHours,
  WorkingHoursInput,
} from "./availability.ts";
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

import {
  allWithFields,
  blockFields,
  extraOf,
} from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult } from "../../core/result.ts";
import {
  blockCall,
  isRecord,
  oneOf,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";
import { alarmItem, alarmOf, reminderOf } from "./alarms.ts";
import {
  CALENDAR_EVENT_KINDS,
  CALENDAR_TRANSPARENCIES,
  freeBusyOf,
  workingHoursOf,
} from "./availability.ts";
import { parseIcs, toIcs } from "./ics.ts";
import { expandOccurrences, splitRule } from "./occurrences.ts";

export interface CalendarOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> {
  /**
   * A Standard Schema for the event columns the app adds
   * (`blocks.calendar.options.extraColumns`), keyed by column name. It types
   * and parses them on `events`, and validates them on `upsert` and the
   * occurrence edits, which return a `validation` error for a bad value.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Calendar<FieldsOf<S>>>>;
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
  /** With `options.calendarExtraColumns`: the calendar's own columns. */
  readonly fields?: Readonly<Record<string, unknown>>;
  readonly visibility?: CalendarVisibility;
  readonly description?: string;
  readonly rank?: string;
  readonly isDefault?: boolean;
}

export type CalendarVisibility = "shared" | "private";

/** What a calendar share link reads, for an app that renders the feed itself. */
export interface CalendarFeedData<F extends object = Record<never, never>> {
  readonly calendar: Pick<CalendarInfo, "id" | "name" | "tz" | "color">;
  /** The organization, with the organizations block. */
  readonly organization?: { readonly id: string; readonly name?: string };
  /** The member who created the link. */
  readonly createdBy?: string;
  /** With their reminders, attendees and extra columns. */
  readonly events: readonly (CalendarEvent & F)[];
}

/** What a `calendar_user` share link reads: every calendar its user reads. */
export interface CalendarUserFeedData<F extends object = Record<never, never>> {
  readonly userId: string;
  readonly organization?: { readonly id: string; readonly name?: string };
  readonly calendars: readonly Pick<
    CalendarInfo,
    "id" | "name" | "tz" | "color"
  >[];
  readonly events: readonly (CalendarEvent & F)[];
}

export type CalendarGrantRole = "viewer" | "editor";

export interface CalendarGrant {
  readonly userId: string;
  readonly role: CalendarGrantRole;
}

export interface CalendarAttributes {
  readonly name?: string;
  readonly tz?: string;
  readonly color?: string | null;
  readonly visibility?: CalendarVisibility;
  readonly description?: string | null;
  readonly rank?: string | null;
  readonly isDefault?: boolean;
}

export interface CalendarAttendeeInput {
  readonly email?: string;
  readonly name?: string;
  readonly userId?: string;
  readonly role?: AttendeeRole;
  readonly subjectType?: string;
  readonly subjectId?: string;
  readonly organizer?: boolean;
  readonly optional?: boolean;
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
  readonly rdates?: readonly Temporal.Instant[];
  readonly visibility?: "public" | "private";
  readonly subjectType?: string | null;
  readonly subjectId?: string | null;
  readonly color?: string | null;
  /** Default `event`. */
  readonly kind?: CalendarEventKind;
  /** Default `opaque`; `transparent` events don't make anyone busy. */
  readonly transparency?: CalendarTransparency;
  /**
   * On an `out_of_office` or `focus_time` block: decline the owner's open
   * invitations to single events it covers, and new ones. Default `false`.
   */
  readonly autoDecline?: boolean;
  /**
   * Replaces the event's alarms (`VALARM`), which every reader of the event
   * gets in exports and feeds. Left out, they stay as they are.
   */
  readonly alarms?: readonly CalendarAlarm[];
  /** Only on insert. Default the new id. */
  readonly uid?: string;
}

export interface CalendarOccurrenceRef {
  readonly seriesId: string;
  readonly originalStart: Temporal.Instant;
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

/** `F` is the extra event fields `options.fields` describes. */
export interface Calendar<F extends object = Record<never, never>> {
  createCalendar(
    organizationId: string,
    name: string,
    options?: {
      readonly tz?: string;
      readonly ownerType?: string;
      readonly ownerId?: string;
      /** With `options.calendarExtraColumns`: values for those columns. */
      readonly fields?: Readonly<Record<string, unknown>>;
    } & Omit<CalendarAttributes, "name" | "tz">,
  ): AsyncResult<{ readonly id: string }>;
  updateCalendar(
    id: string,
    attributes: CalendarAttributes,
  ): AsyncResult<boolean>;
  deleteCalendar(id: string): AsyncResult<boolean>;
  listCalendars(organizationId: string): AsyncResult<CalendarInfo[]>;
  /**
   * Inserts an event, or updates the one with `id`. Keys besides the input's
   * own are the event's extra columns.
   */
  upsert(
    calendarId: string,
    input: CalendarEventInput & Partial<F> & { readonly id?: string },
  ): AsyncResult<SavedCalendarEvent>;
  delete(eventId: string): AsyncResult<boolean>;
  /** The rows that can fall in the range: events, series and their overrides. */
  events(
    calendarIds: readonly string[],
    range: OccurrenceRange,
  ): AsyncResult<(CalendarEvent & F)[]>;
  /** The occurrences in the range, series expanded. */
  occurrences(
    calendarIds: readonly string[],
    range: OccurrenceRange,
    options?: OccurrenceOptions,
  ): AsyncResult<CalendarOccurrence[]>;
  /** Changes one occurrence: an override for a series, else the event. */
  editOccurrence(
    occurrence: CalendarOccurrence,
    changes: CalendarEventInput & Partial<F>,
  ): AsyncResult<SavedCalendarEvent>;
  /**
   * Changes an occurrence and every later one: splits the series, unless the
   * occurrence is its first. Pass `rrule` when the change moves the weekday.
   */
  editFollowing(
    occurrence: CalendarOccurrence,
    changes: CalendarEventInput & Partial<F>,
  ): AsyncResult<{ readonly id: string }>;
  /** Removes one occurrence of a series (an `EXDATE`), or a single event. */
  cancelOccurrence(
    occurrence: CalendarOccurrence | CalendarOccurrenceRef,
  ): AsyncResult<boolean>;
  setAttendee(
    eventId: string,
    attendee: CalendarAttendeeInput,
  ): AsyncResult<boolean>;
  removeAttendee(eventId: string, email: string): AsyncResult<boolean>;
  removeAttendeeById(attendeeId: string): AsyncResult<boolean>;
  setGrant(
    calendarId: string,
    userId: string,
    role: CalendarGrantRole,
  ): AsyncResult<boolean>;
  removeGrant(calendarId: string, userId: string): AsyncResult<boolean>;
  grants(calendarId: string): AsyncResult<CalendarGrant[]>;
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
  userFeed(token: string): AsyncResult<string | null>;
  /**
   * What `feed` serializes, parsed: the calendar with its colour, the
   * organization, the link's creator and the events with their reminders and
   * extra columns, or `null` for an unknown, revoked or expired token.
   */
  feedData(token: string): AsyncResult<CalendarFeedData<F> | null>;
  /** What `userFeed` serializes, parsed. */
  userFeedData(token: string): AsyncResult<CalendarUserFeedData<F> | null>;
  /** Replaces a member's weekly working hours. Returns how many stretches. */
  setWorkingHours(
    organizationId: string,
    input: WorkingHoursInput,
  ): AsyncResult<number>;
  /** The working hours of the members that set them (all when omitted). */
  workingHours(
    organizationId: string,
    userIds?: readonly string[],
  ): AsyncResult<WorkingHours[]>;
  /**
   * When each member is busy in the range (at most 62 days, 100 members):
   * events on calendars they own, invitations they haven't declined,
   * out-of-office and focus-time blocks, and approved leave. It returns ranges,
   * never titles.
   */
  freeBusy(
    organizationId: string,
    userIds: readonly string[],
    range: OccurrenceRange,
  ): AsyncResult<FreeBusy[]>;
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
  const text = (key: string) => {
    const found = optionalText(value[key]);

    return found === undefined ? {} : { [key]: found };
  };

  const flag = (key: string) =>
    typeof value[key] === "boolean" ? { [key]: value[key] } : {};

  return {
    email: optionalText(value["email"]) ?? "",
    ...text("name"),
    ...text("userId"),
    role: oneOf(value["role"], ROLES, "required"),
    response: oneOf(value["response"], RESPONSES, "needs-action"),
    ...text("id"),
    ...text("subjectType"),
    ...text("subjectId"),
    ...flag("organizer"),
    ...flag("optional"),
  };
}

function feedCalendarOf(
  value: unknown,
): Pick<CalendarInfo, "id" | "name" | "tz" | "color"> {
  const row = recordOf(value, "calendar feed");
  const color = optionalText(row["color"]);

  return {
    id: textOf(row["id"]),
    name: textOf(row["name"]),
    tz: optionalText(row["tz"]) ?? "UTC",
    ...(color === undefined ? {} : { color }),
  };
}

function feedOrganizationOf(
  value: unknown,
): { readonly id: string; readonly name?: string } | undefined {
  if (!isRecord(value)) {
    return undefined;
  }

  const name = optionalText(value["name"]);

  return { id: textOf(value["id"]), ...(name === undefined ? {} : { name }) };
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
  const rdates = Array.isArray(row["rdates"]) ? row["rdates"] : undefined;

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
    ...(row["kind"] === undefined
      ? {}
      : { kind: oneOf(row["kind"], CALENDAR_EVENT_KINDS, "event") }),
    ...(row["transparency"] === undefined
      ? {}
      : {
          transparency: oneOf(
            row["transparency"],
            CALENDAR_TRANSPARENCIES,
            "opaque",
          ),
        }),
    ...(typeof row["autoDecline"] === "boolean"
      ? { autoDecline: row["autoDecline"] }
      : {}),
    attendees: recordsOf(row["attendees"], "attendees").map(attendeeOf),
    reminders: recordsOf(row["reminders"], "reminders").map(reminderOf),
    ...(row["alarms"] === undefined
      ? {}
      : { alarms: recordsOf(row["alarms"], "alarms").map(alarmOf) }),
    ...(updatedAt === undefined ? {} : { updatedAt }),
    ...(rdates === undefined
      ? {}
      : { rdates: rdates.map((date) => requiredInstant(date, "rdate")) }),
    ...(row["visibility"] === undefined
      ? {}
      : {
          visibility: oneOf(
            row["visibility"],
            ["public", "private"] as const,
            "public",
          ),
        }),
    ...text("ownerId"),
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

const INFINITE = { from: "-infinity", until: "infinity" } as const;

function attributesOf(
  input: Omit<CalendarAttributes, "name" | "tz">,
): Record<string, unknown> {
  const attrs: Record<string, unknown> = {};

  for (const key of [
    "color",
    "visibility",
    "description",
    "rank",
    "isDefault",
  ] as const) {
    if (input[key] !== undefined) {
      attrs[key] = input[key];
    }
  }

  return attrs;
}

/** The keys of an event write the block types itself. */
const EVENT_INPUT: ReadonlySet<string> = new Set([
  "id",
  "title",
  "description",
  "location",
  "startsAt",
  "endsAt",
  "allDay",
  "tz",
  "status",
  "rrule",
  "exdates",
  "rdates",
  "visibility",
  "subjectType",
  "subjectId",
  "color",
  "kind",
  "transparency",
  "autoDecline",
  "alarms",
  "uid",
  "recurrenceId",
  "originalStart",
]);

export function createCalendar<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: CalendarOptions<S>): Calendar<FieldsOf<S>> {
  type F = FieldsOf<S>;

  const call = blockCall(options.transport, options.schema, options.mappers);
  const fields: BlockFields<F> = blockFields(options.fields, "event fields");

  /** The item a write sends, with its extra fields validated. */
  const checked = (
    input: Parameters<typeof itemOf>[0],
  ): AsyncResult<Record<string, unknown>> =>
    AsyncResult.from(() => fields.write(extraOf(input, EVENT_INPUT))).map(
      (extra) => ({ ...extra, ...itemOf(input) }),
    );

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
    checked(input).andThen((item) =>
      call("save_calendar_event", { calendar_id: calendarId, item }, saved),
    );

  const list = (
    calendarIds: readonly string[],
    range: OccurrenceRange | typeof INFINITE,
  ): AsyncResult<(CalendarEvent & F)[]> =>
    call(
      "list_calendar_events",
      {
        calendar_ids: [...calendarIds],
        range_start: range.from.toString(),
        range_end: range.until.toString(),
      },
      (value) =>
        recordsOf(value, "list_calendar_events").map(
          (raw) => [raw, calendarEventOf(raw)] as const,
        ),
    ).andThen((rows) => allWithFields(fields, rows));

  const feedEvents = (
    value: unknown,
    fn: string,
  ): AsyncResult<(CalendarEvent & F)[]> =>
    AsyncResult.from(() =>
      allWithFields(
        fields,
        recordsOf(value, fn).map((raw) => [raw, calendarEventOf(raw)] as const),
      ),
    );

  const client: Calendar<F> = {
    createCalendar: (organizationId, name, extra = {}) => {
      const attrs = attributesOf(extra);

      return call(
        "create_calendar",
        {
          tenant: organizationId,
          name,
          tz: extra.tz ?? "UTC",
          owner_type: extra.ownerType ?? null,
          owner_id: extra.ownerId ?? null,
          ...(extra.fields === undefined ? {} : { fields: extra.fields }),
          ...(Object.keys(attrs).length === 0 ? {} : { attrs }),
        },
        (value) => ({ id: textOf(recordOf(value, "create_calendar")["id"]) }),
      );
    },
    updateCalendar: (id, attributes) =>
      call(
        "update_calendar",
        {
          calendar_id: id,
          attrs: {
            ...attributesOf(attributes),
            ...(attributes.name === undefined ? {} : { name: attributes.name }),
            ...(attributes.tz === undefined ? {} : { tz: attributes.tz }),
          },
        },
        (value) => value === true,
      ),
    deleteCalendar: (id) =>
      call("delete_calendar", { calendar_id: id }, (value) => value === true),
    listCalendars: (organizationId) =>
      call("list_calendars", { tenant: organizationId }, (value) =>
        recordsOf(value, "list_calendars").map((row) => {
          const extra: Record<string, string> = {};

          for (const key of [
            "color",
            "ownerType",
            "ownerId",
            "description",
            "rank",
          ]) {
            const found = optionalText(row[key]);

            if (found !== undefined) {
              extra[key] = found;
            }
          }

          return {
            id: textOf(row["id"]),
            name: textOf(row["name"]),
            tz: optionalText(row["tz"]) ?? "UTC",
            ...extra,
            ...(row["visibility"] === undefined
              ? {}
              : {
                  visibility: oneOf(
                    row["visibility"],
                    ["shared", "private"] as const,
                    "shared",
                  ),
                }),
            ...(typeof row["isDefault"] === "boolean"
              ? { isDefault: row["isDefault"] }
              : {}),
            ...(isRecord(row["fields"])
              ? { fields: { ...row["fields"] } }
              : {}),
          };
        }),
      ),
    upsert: save,
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
        ...(series.rdates === undefined ? {} : { rdates: [] }),
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
            { hint: "CALENDAR_SPLIT_INVALID" },
          ),
        );
      }

      const length = series.endsAt.since(series.startsAt);

      return checked({
        ...copyOf(series),
        startsAt: occurrence.originalStart,
        endsAt: occurrence.originalStart.add(length),
        rrule: rules.after,
        ...changes,
      }).andThen((item) =>
        call(
          "split_calendar_event",
          {
            event_id: series.id,
            split_at: occurrence.originalStart.toString(),
            before_rrule: rules.before,
            item,
          },
          (value) => ({
            id: textOf(recordOf(value, "split_calendar_event")["id"]),
          }),
        ),
      );
    },
    cancelOccurrence: (occurrence) => {
      if ("seriesId" in occurrence) {
        return call(
          "cancel_calendar_occurrence",
          {
            event_id: occurrence.seriesId,
            original_start: occurrence.originalStart.toString(),
          },
          (value) => value === true,
        );
      }

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
      attendee.email === undefined ||
      attendee.subjectType !== undefined ||
      attendee.subjectId !== undefined ||
      attendee.organizer !== undefined ||
      attendee.optional !== undefined
        ? call(
            "set_calendar_attendee",
            { event_id: eventId, attendee: { ...attendee } },
            (value) => isRecord(value) && typeof value["id"] === "string",
          )
        : call(
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
    removeAttendeeById: (attendeeId) =>
      call(
        "remove_calendar_attendee",
        { attendee_id: attendeeId },
        (value) => value === true,
      ),
    setGrant: (calendarId, userId, role) =>
      call(
        "set_calendar_grant",
        { calendar_id: calendarId, user_id: userId, role },
        (value) => value === true,
      ),
    removeGrant: (calendarId, userId) =>
      call(
        "remove_calendar_grant",
        { calendar_id: calendarId, user_id: userId },
        (value) => value === true,
      ),
    grants: (calendarId) =>
      call("list_calendar_grants", { calendar_id: calendarId }, (value) =>
        recordsOf(value, "list_calendar_grants").map((row) => ({
          userId: textOf(row["userId"]),
          role: oneOf(row["role"], ["viewer", "editor"] as const, "viewer"),
        })),
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
      client
        .feedData(token)
        .map((data) =>
          data === null
            ? null
            : toIcs(data.events, {
                name: data.calendar.name,
                tz: data.calendar.tz,
              }),
        ),
    userFeed: (token) =>
      client
        .userFeedData(token)
        .map((data) => (data === null ? null : toIcs(data.events))),
    feedData: (token) =>
      call("calendar_feed", { token }, (value) => value).andThen((value) => {
        if (value === null || value === undefined) {
          return AsyncResult.ok(null);
        }

        const row = recordOf(value, "calendar_feed");
        const organization = feedOrganizationOf(row["organization"]);
        const createdBy = optionalText(row["createdBy"]);

        return feedEvents(row["events"], "calendar_feed").map((events) => ({
          calendar: feedCalendarOf(row["calendar"]),
          ...(organization === undefined ? {} : { organization }),
          ...(createdBy === undefined ? {} : { createdBy }),
          events,
        }));
      }),
    userFeedData: (token) =>
      call("calendar_user_feed", { token }, (value) => value).andThen(
        (value) => {
          if (value === null || value === undefined) {
            return AsyncResult.ok(null);
          }

          const row = recordOf(value, "calendar_user_feed");
          const organization = feedOrganizationOf(row["organization"]);

          return feedEvents(row["events"], "calendar_user_feed").map(
            (events) => ({
              userId: textOf(row["userId"]),
              ...(organization === undefined ? {} : { organization }),
              calendars: recordsOf(row["calendars"], "calendar_user_feed").map(
                feedCalendarOf,
              ),
              events,
            }),
          );
        },
      ),
    setWorkingHours: (organizationId, input) =>
      call(
        "set_calendar_working_hours",
        {
          tenant: organizationId,
          user_id: input.userId ?? null,
          tz: input.tz,
          hours: input.hours.map((hour) => ({ ...hour })),
        },
        (value) => Number(value ?? 0),
      ),
    workingHours: (organizationId, userIds) =>
      call(
        "list_calendar_working_hours",
        {
          tenant: organizationId,
          user_ids: userIds === undefined ? null : [...userIds],
        },
        workingHoursOf,
      ),
    freeBusy: (organizationId, userIds, range) =>
      call(
        "calendar_free_busy",
        {
          tenant: organizationId,
          user_ids: [...userIds],
          range_start: range.from.toString(),
          range_end: range.until.toString(),
        },
        freeBusyOf,
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "calendar",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
