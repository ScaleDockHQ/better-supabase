import type { BlockOf } from "../define-block.ts";
import type { DeadlinesEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createDeadlines } from "./deadlines.ts";
import { deadlinesEvents } from "./events.ts";

/** The `deadlines` block's manifest. */
export const deadlinesBlock: BlockOf<
  "deadlines",
  typeof createDeadlines,
  DeadlinesEvents
> = defineBlock({
  name: "deadlines",
  sql: ["deadlines"],
  events: deadlinesEvents,
  schemas: {},
  create: createDeadlines,
  recipes: [],
  category: "work",
  description:
    "Platform-owned rule sets per jurisdiction and kind, versioned and approved once with a content hash: groups of cited rules with conditions, exceptions and counts, and the deadlines computed from a subject's facts per group: due on a date, unknown with the facts still missing, or the reason there is none.",
});
