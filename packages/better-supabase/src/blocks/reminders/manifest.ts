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
  schedules: [
    {
      name: "schedule",
      cron: "*/5 * * * *",
      runs: "schedule()",
      description:
        "Enqueues a reminders.deliver job for each reminder due in the next day.",
    },
  ],
  sql: ["reminders", "recurrence"],
  options: { reminders: remindersSqlOptions },
  events: remindersEvents,
  consumes: { notifier: "optional" },
  create: createReminders,
  category: "scheduling",
  entities: {
    reminder: {
      mutability: "editable",
      emits: { update: false, delete: false },
    },
  },
  description:
    "Recurrence rules and reminders. Expansion follows RFC 5545 in TypeScript. Delivery is a job that records reminder.sent once per occurrence.",
  recipes: ["reminders-list", "my-work"],
});
