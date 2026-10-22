import type { BlockOf } from "../define-block.ts";
import type { ApprovalsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createApprovals } from "./approvals.ts";
import { approvalsEvents } from "./events.ts";
import { approvalsSqlOptions } from "./options.ts";

/** The `approvals` block's manifest (ADR 0029). */
export const approvalsBlock: BlockOf<
  "approvals",
  typeof createApprovals,
  ApprovalsEvents
> = defineBlock({
  name: "approvals",
  sql: ["approvals"],
  options: { approvals: approvalsSqlOptions },
  events: approvalsEvents,
  create: createApprovals,
  category: "work",
  recipes: ["approvals-queue", "my-work"],
});
