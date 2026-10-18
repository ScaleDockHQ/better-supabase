import type { BlockOf } from "../define-block.ts";
import type { DataLifecycleEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createDataLifecycle } from "./data-lifecycle.ts";
import { dataLifecycleEvents } from "./events.ts";
import { dataLifecycleSqlOptions } from "./options.ts";

/** The `data-lifecycle` block's manifest (ADR 0029). */
export const dataLifecycleBlock: BlockOf<
  "data-lifecycle",
  typeof createDataLifecycle,
  DataLifecycleEvents
> = defineBlock({
  name: "data-lifecycle",
  sql: ["data-lifecycle"],
  options: {
    "data-lifecycle": dataLifecycleSqlOptions,
  },
  events: dataLifecycleEvents,
  create: createDataLifecycle,
  category: "admin",
});
