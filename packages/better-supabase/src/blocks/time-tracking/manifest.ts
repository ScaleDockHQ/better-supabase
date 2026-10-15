import type { BlockOf } from "../define-block.ts";
import type { TimeTrackingEvents } from "./events.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { timeTrackingEvents } from "./events.ts";
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
    "time-tracking": optionKeys(["subjects", "policy", "timeZone"]),
  },
  events: timeTrackingEvents,
  create: createTimeTracking,
  category: "scheduling",
});
