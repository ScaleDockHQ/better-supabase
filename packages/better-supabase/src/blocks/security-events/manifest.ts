import type { BlockOf } from "../define-block.ts";
import type { SecurityEventsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { securityEventsEvents } from "./events.ts";
import { securityEventsSqlOptions } from "./options.ts";
import { createSecurityEvents } from "./security-events.ts";

/** The `security-events` block's manifest (ADR 0029). */
export const securityEventsBlock: BlockOf<
  "security-events",
  typeof createSecurityEvents,
  SecurityEventsEvents
> = defineBlock({
  name: "security-events",
  sql: ["security-events"],
  options: { "security-events": securityEventsSqlOptions },
  events: securityEventsEvents,
  create: createSecurityEvents,
  category: "developer",
});
