import type { BlockOf } from "../define-block.ts";
import type { ImpersonationEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { impersonationEvents } from "./events.ts";
import { createImpersonation } from "./impersonation.ts";
import { impersonationSqlOptions } from "./options.ts";

/** The `impersonation` block's manifest (ADR 0029). */
export const impersonationBlock: BlockOf<
  "impersonation",
  typeof createImpersonation,
  ImpersonationEvents
> = defineBlock({
  name: "impersonation",
  sql: ["impersonation"],
  options: { impersonation: impersonationSqlOptions },
  events: impersonationEvents,
  create: createImpersonation,
  category: "admin",
  description:
    "Lets platform staff view the app as a user: time-limited, read-only by default, gated by is_platform() and a second admin's approval, recorded in the audit log, with the target's claims built by your access token hook.",
  recipes: ["support-session-banner"],
});
