import type { BlockOf } from "../define-block.ts";

import { bookingsBlock } from "../bookings/manifest.ts";
import { calendarBlock } from "../calendar/manifest.ts";
import { defineBlock } from "../define-block.ts";
import { remindersBlock } from "../reminders/manifest.ts";
import { createScheduling } from "./scheduling.ts";

/** The blocks `scheduling` is made of, by block name. */
export const schedulingParts: {
  readonly bookings: typeof bookingsBlock;
  readonly calendar: typeof calendarBlock;
  readonly reminders: typeof remindersBlock;
} = {
  bookings: bookingsBlock,
  calendar: calendarBlock,
  reminders: remindersBlock,
};

export type SchedulingParts = typeof schedulingParts;

/**
 * The `scheduling` composite (ADR 0196): bookings on the calendar, with
 * reminders. It installs its parts and sets their defaults; the parts stay
 * ordinary blocks in the config.
 */
export const schedulingBlock: BlockOf<"scheduling", typeof createScheduling> =
  defineBlock({
    name: "scheduling",
    composes: schedulingParts,
    create: createScheduling,
    category: "scheduling",
  });
