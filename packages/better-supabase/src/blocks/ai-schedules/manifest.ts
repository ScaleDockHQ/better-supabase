import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { createAiSchedules } from "./ai-schedules.ts";
import { aiSchedulesSqlOptions } from "./options.ts";

/** The `ai-schedules` block's manifest (ADR 0029). */
export const aiSchedulesBlock: BlockOf<
  "ai-schedules",
  typeof createAiSchedules,
  Record<never, never>,
  { readonly notifier: "optional" }
> = defineBlock({
  name: "ai-schedules",
  schedules: [
    {
      name: "tick",
      cron: "* * * * *",
      runs: "tick()",
      description:
        "Queues a run for each due AI task and computes its next occurrence.",
    },
  ],
  sql: ["ai-schedules"],
  options: { "ai-schedules": aiSchedulesSqlOptions },
  consumes: { notifier: "optional" },
  create: createAiSchedules,
  category: "ai",
  recipes: ["ai-task-queue"],
});
