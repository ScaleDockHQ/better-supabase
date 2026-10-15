import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { sessionsSqlOptions } from "./options.ts";

/** The `sessions` block's manifest (ADR 0029). */
export const sessionsBlock: Block<"sessions"> = defineBlock({
  name: "sessions",
  sql: ["sessions"],
  options: {
    sessions: sessionsSqlOptions,
  },
  category: "foundation",
});
