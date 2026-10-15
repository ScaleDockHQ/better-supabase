import type { BlockOf } from "../define-block.ts";
import type { ApprovalsEvents } from "./events.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { createApprovals } from "./approvals.ts";
import { approvalsEvents } from "./events.ts";

/** The `approvals` block's manifest (ADR 0029). */
export const approvalsBlock: BlockOf<
  "approvals",
  typeof createApprovals,
  ApprovalsEvents
> = defineBlock({
  name: "approvals",
  sql: ["approvals"],
  options: {
    approvals: optionKeys(["subjects", "policies"]),
  },
  events: approvalsEvents,
  create: createApprovals,
  category: "work",
});
