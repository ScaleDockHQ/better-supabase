import type { BlockOf } from "../define-block.ts";
import type { RemindersEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { remindersEvents } from "./events.ts";
import { remindersSqlOptions } from "./options.ts";
import { createReminders } from "./reminders.ts";

/** The `reminders` block's manifest (ADR 0029). */
export const remindersBlock: BlockOf<
  "reminders",
  typeof createReminders,
  RemindersEvents,
  { readonly notifier: "optional" }
> = defineBlock({
  name: "reminders",
  sql: ["reminders"],
  options: { reminders: remindersSqlOptions },
  events: remindersEvents,
  consumes: { notifier: "optional" },
  create: createReminders,
  category: "scheduling",
  recipes: ["reminders-list"],
});
