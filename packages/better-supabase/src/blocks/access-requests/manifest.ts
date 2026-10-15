import type { BlockOf } from "../define-block.ts";
import type { AccessRequestsEvents } from "./events.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { createAccessRequests } from "./access-requests.ts";
import { accessRequestsEvents } from "./events.ts";

/** The `access-requests` block's manifest (ADR 0029). */
export const accessRequestsBlock: BlockOf<
  "access-requests",
  typeof createAccessRequests,
  AccessRequestsEvents
> = defineBlock({
  name: "access-requests",
  sql: ["access-requests"],
  options: {
    "access-requests": optionKeys(["roles", "policy", "maxDuration", "join"]),
  },
  events: accessRequestsEvents,
  create: createAccessRequests,
  category: "work",
});
