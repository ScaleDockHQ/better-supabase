import type { BlockOf } from "../define-block.ts";
import type { TimeTrackingEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { timeTrackingEvents } from "./events.ts";
import { timeTrackingSqlOptions } from "./options.ts";
import { createTimeTracking } from "./time-tracking.ts";

/** The `time-tracking` block's manifest (ADR 0029). */
export const timeTrackingBlock: BlockOf<
  "time-tracking",
  typeof createTimeTracking,
  TimeTrackingEvents
> = defineBlock({
  name: "time-tracking",
  sql: ["time-tracking"],
  options: {
    "time-tracking": timeTrackingSqlOptions,
  },
  events: timeTrackingEvents,
  create: createTimeTracking,
  category: "scheduling",
});
