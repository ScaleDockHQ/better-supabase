import type { BlockOf } from "../define-block.ts";
import type { AccessRequestsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createAccessRequests } from "./access-requests.ts";
import { accessRequestsEvents } from "./events.ts";
import { accessRequestsSqlOptions } from "./options.ts";

/** The `access-requests` block's manifest (ADR 0029). */
export const accessRequestsBlock: BlockOf<
  "access-requests",
  typeof createAccessRequests,
  AccessRequestsEvents,
  Record<never, never>,
  "recordAccess"
> = defineBlock({
  name: "access-requests",
  sql: ["access-requests"],
  options: { "access-requests": accessRequestsSqlOptions },
  events: accessRequestsEvents,
  provides: { recordAccess: (client) => client },
  create: createAccessRequests,
  category: "identity",
  entities: { access_request: { mutability: "state-machine" } },
  description:
    "Members ask for a role or for access to one record, for a set time if they like. The request goes through approvals; the final approval grants it, and the grant ends early on request or when it expires. Emergency access opens a record at once and waits for a review.",
  recipes: ["access-requests-inbox"],
});
