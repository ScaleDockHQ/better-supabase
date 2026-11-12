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
  entities: { support_session: { mutability: "state-machine" } },
  description:
    "Lets platform staff view the app as a user: time-limited, read-only by default, gated by is_platform() and a second admin's approval, recorded in the audit log, with the target's claims built by your access token hook.",
  recipes: ["support-session-banner"],
});
