import type { BlockOf } from "../define-block.ts";
import type { CalendarEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createCalendar } from "./calendar.ts";
import { calendarEvents } from "./events.ts";
import { calendarSqlOptions } from "./options.ts";

/** The `calendar` block's manifest (ADR 0029). */
export const calendarBlock: BlockOf<
  "calendar",
  typeof createCalendar,
  CalendarEvents
> = defineBlock({
  name: "calendar",
  sql: ["calendar"],
  options: {
    calendar: calendarSqlOptions,
  },
  events: calendarEvents,
  create: createCalendar,
  client: "calendar",
  category: "scheduling",
  recipes: ["calendar-view"],
});
