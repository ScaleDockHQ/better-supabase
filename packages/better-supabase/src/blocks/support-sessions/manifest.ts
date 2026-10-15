import type { Block } from "../define-block.ts";
import type { SupportSessionsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { supportSessionsEvents } from "./events.ts";
import { supportSessionsSqlOptions } from "./options.ts";

/** The `support-sessions` block's manifest (ADR 0029). */
export const supportSessionsBlock: Block<
  "support-sessions",
  never,
  never,
  SupportSessionsEvents
> = defineBlock({
  name: "support-sessions",
  sql: ["support-sessions"],
  options: {
    "support-sessions": supportSessionsSqlOptions,
  },
  events: supportSessionsEvents,
  category: "operations",
});
