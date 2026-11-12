import type { BlockOf } from "../define-block.ts";
import type { DispatchEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createDispatch } from "./dispatch.ts";
import { dispatchEvents } from "./events.ts";
import { dispatchSqlOptions } from "./options.ts";
import { dispatchBinding } from "./record-binding.ts";
import { workOrderInputSchema, workOrderPartInputSchema } from "./schemas.ts";

/** The `dispatch` block's manifest (ADR 0029). */
export const dispatchBlock: BlockOf<
  "dispatch",
  typeof createDispatch,
  DispatchEvents,
  Record<never, never>,
  never,
  typeof dispatchBinding
> = defineBlock({
  name: "dispatch",
  sql: ["dispatch"],
  options: { dispatch: dispatchSqlOptions },
  events: dispatchEvents,
  schemas: {
    work_order: { input: workOrderInputSchema },
    work_order_part: { input: workOrderPartInputSchema },
  },
  create: createDispatch,
  record: dispatchBinding,
  category: "work",
  entities: {
    work_order: {
      mutability: "editable",
      emits: { create: true, update: true },
    },
    dispatch_route: { mutability: "state-machine" },
    work_order_part: {
      mutability: "append-only",
      emits: { create: false, delete: false },
    },
  },
  description:
    "Field service work orders at asset locations: a schedule board of technicians' slots, a status lifecycle from scheduled to done, day routes with ordered stops, and the parts each job used, linked to assets or inventory when those blocks are installed.",
  recipes: ["dispatch-board", "technician-day"],
});
