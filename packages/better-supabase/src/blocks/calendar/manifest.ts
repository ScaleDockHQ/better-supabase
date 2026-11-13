import type { BlockOf } from "../define-block.ts";
import type { CalendarEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createCalendar } from "./calendar.ts";
import { calendarEvents } from "./events.ts";
import { calendarSqlOptions } from "./options.ts";
import { calendarEventInputSchema } from "./schemas.ts";

/** The `calendar` block's manifest (ADR 0029). */
export const calendarBlock: BlockOf<
  "calendar",
  typeof createCalendar,
  CalendarEvents
> = defineBlock({
  name: "calendar",
  sql: ["calendar"],
  options: { calendar: calendarSqlOptions },
  events: calendarEvents,
  schemas: {
    calendar_event: {
      input: calendarEventInputSchema,
      change: calendarEventInputSchema,
    },
  },
  create: createCalendar,
  client: "calendar",
  category: "scheduling",
  entities: {
    calendar_event: {
      mutability: "editable",
      emits: { create: true, update: true, delete: true },
    },
    calendar: {
      mutability: "editable",
      emits: { create: true, update: true, delete: false },
    },
  },
  concerns: ["lifecycle", "search"],
  description:
    "Calendars, events with RFC 5545 recurrence (RRULE, EXDATE and per-occurrence overrides) and attendees, working hours, out-of-office and focus-time blocks, and a free/busy query that counts approved leave. Series expand in TypeScript with the reminders block's expandRule and in SQL for free/busy; a share link serves an iCal feed.",
  recipes: [
    "calendar-view",
    "record-calendar",
    "record-gantt",
    "record-timeline",
  ],
});
