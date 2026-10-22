import type { EntitySchema } from "../entity-schema.ts";
import type { CalendarEventInput } from "./calendar.ts";

import { entitySchema } from "../entity-schema.ts";

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
      uid: { kind: "string", optional: true, description: "Only on insert." },
    },
  });
