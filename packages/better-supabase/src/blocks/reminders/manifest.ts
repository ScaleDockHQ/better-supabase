import type { BlockOf } from "../define-block.ts";
import type { RemindersEvents } from "./events.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { remindersEvents } from "./events.ts";
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
  options: {
    reminders: optionKeys(["ruleFormat"]),
  },
  events: remindersEvents,
  consumes: { notifier: "optional" },
  create: createReminders,
  category: "scheduling",
});
