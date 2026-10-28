import type { EntitySchema } from "../entity-schema.ts";
import type { CalendarAlarm } from "./alarms.ts";
import type { CalendarEventInput } from "./calendar.ts";

import { entitySchema } from "../entity-schema.ts";

/** One alarm (`VALARM`) of an event. */
export const calendarAlarmSchema: EntitySchema<CalendarAlarm> =
  entitySchema<CalendarAlarm>({
    title: "CalendarAlarm",
    fields: {
      id: { kind: "string", optional: true },
      action: { kind: "enum", values: ["display", "email", "audio"] },
      triggerMinutes: {
        kind: "integer",
        optional: true,
        minimum: -525_600,
        maximum: 525_600,
        description:
          "Minutes from the start (or end), RFC 5545 sign: -15 fires 15 minutes before.",
      },
      related: { kind: "enum", values: ["start", "end"], optional: true },
      triggerAt: {
        kind: "instant",
        optional: true,
        description: "An absolute trigger, instead of triggerMinutes.",
      },
      repeat: { kind: "integer", optional: true, minimum: 0 },
      repeatMinutes: { kind: "integer", optional: true, minimum: 1 },
      description: { kind: "string", optional: true },
      summary: { kind: "string", optional: true },
    },
  });

/**
 * What `upsert` takes for an event. Fields left out keep their value on update,
 * so every field is optional.
 */
export const calendarEventInputSchema: EntitySchema<CalendarEventInput> =
  entitySchema<CalendarEventInput>({
    title: "CalendarEventInput",
    fields: {
      title: { kind: "string", optional: true, minLength: 1 },
      description: { kind: "string", optional: true, nullable: true },
      location: { kind: "string", optional: true, nullable: true },
      startsAt: { kind: "instant", optional: true },
      endsAt: { kind: "instant", optional: true },
      allDay: { kind: "boolean", optional: true },
      tz: { kind: "string", optional: true, minLength: 1 },
      status: {
        kind: "enum",
        values: ["confirmed", "tentative", "cancelled"],
        optional: true,
      },
      rrule: {
        kind: "string",
        optional: true,
        nullable: true,
        description: "An RFC 5545 `RRULE` value; `null` ends the recurrence.",
      },
      exdates: { kind: "instant", optional: true, array: true },
      rdates: { kind: "instant", optional: true, array: true },
      visibility: {
        kind: "enum",
        values: ["public", "private"],
        optional: true,
      },
      subjectType: { kind: "string", optional: true, nullable: true },
      subjectId: { kind: "string", optional: true, nullable: true },
      color: { kind: "string", optional: true, nullable: true },
      kind: {
        kind: "enum",
        values: ["event", "out_of_office", "focus_time"],
        optional: true,
      },
      transparency: {
        kind: "enum",
        values: ["opaque", "transparent"],
        optional: true,
        description: "`transparent` events don't make anyone busy.",
      },
      autoDecline: {
        kind: "boolean",
        optional: true,
        description:
          "On an out-of-office or focus-time block: decline the invitations it covers.",
      },
      alarms: {
        kind: "custom",
        schema: calendarAlarmSchema,
        optional: true,
        array: true,
        description: "Replaces the event's alarms.",
      },
      uid: { kind: "string", optional: true, description: "Only on insert." },
    },
  });
