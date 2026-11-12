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
  entities: {
    approval: { mutability: "state-machine", emits: { create: false } },
  },
  description:
    "Approval requests with steps per subject type and action: approvers by permission, role, team, user or the requester's manager, a required count, delegation, expiry and reminders. Tenants tighten the configured policies with conditions and a confirm or authorize mode, and an approval is consumed once against a request fingerprint. The final approval runs a state-machine transition or a job.",
  recipes: ["approvals-queue", "my-work"],
});
