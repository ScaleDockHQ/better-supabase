import type { BlockOf } from "../define-block.ts";
import type { LeaveEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { leaveEvents } from "./events.ts";
import { createLeave } from "./leave.ts";
import { leaveSqlOptions } from "./options.ts";
import { leaveBinding } from "./record-binding.ts";

/** The `leave` block's manifest (ADR 0029). */
export const leaveBlock: BlockOf<
  "leave",
  typeof createLeave,
  LeaveEvents,
  Record<never, never>,
  never,
  typeof leaveBinding
> = defineBlock({
  name: "leave",
  sql: ["leave"],
  options: { leave: leaveSqlOptions },
  events: leaveEvents,
  create: createLeave,
  record: leaveBinding,
  category: "people",
  entities: {
    leave_request: {
      mutability: "editable",
      emits: { update: true },
      permissions: {
        read: "leave.read",
        create: "leave.request",
        approve: "leave.approve",
        manage: "leave.manage",
      },
    },
    leave_type: {
      mutability: "editable",
      emits: { update: false },
      permissions: { read: "leave.read", manage: "leave.manage" },
    },
  },
  concerns: ["lifecycle"],
  description:
    'Leave types, requests that go through approvals, and a balance ledger per member and year with accruals, adjustments and a year-end carryover. With employees, requests carry the employee_id of their member, or belong to an employee with owner "employee". Balances can live in the app\'s own table of signed amounts instead of the ledger.',
});
