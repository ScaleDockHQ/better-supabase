import type { BlockOf } from "../define-block.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { createAiTasks } from "./ai-tasks.ts";

/** The `ai-tasks` block's manifest (ADR 0029). */
export const aiTasksBlock: BlockOf<
  "ai-tasks",
  typeof createAiTasks,
  Record<never, never>,
  { readonly notifier: "optional" }
> = defineBlock({
  name: "ai-tasks",
  sql: ["ai-tasks"],
  options: {
    "ai-tasks": optionKeys(["queue", "staleAfter", "maxPrompt"]),
  },
  consumes: { notifier: "optional" },
  create: createAiTasks,
  category: "ai",
});
