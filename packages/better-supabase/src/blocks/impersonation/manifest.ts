import type { Block } from "../define-block.ts";
import type { ImpersonationEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { impersonationEvents } from "./events.ts";
import { impersonationSqlOptions } from "./options.ts";

/** The `impersonation` block's manifest (ADR 0029). */
export const impersonationBlock: Block<
  "impersonation",
  never,
  never,
  ImpersonationEvents
> = defineBlock({
  name: "impersonation",
  sql: ["impersonation"],
  options: { impersonation: impersonationSqlOptions },
  events: impersonationEvents,
  category: "admin",
  recipes: ["support-session-banner"],
});
