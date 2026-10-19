import type { BlockOf } from "../define-block.ts";
import type { LeaveEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { leaveEvents } from "./events.ts";
import { createLeave } from "./leave.ts";
import { leaveSqlOptions } from "./options.ts";

/** The `leave` block's manifest (ADR 0029). */
export const leaveBlock: BlockOf<"leave", typeof createLeave, LeaveEvents> =
  defineBlock({
    name: "leave",
    sql: ["leave"],
    options: {
      leave: leaveSqlOptions,
    },
    events: leaveEvents,
    create: createLeave,
    category: "people",
  });
