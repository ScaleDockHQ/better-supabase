import type { BlockOf } from "../define-block.ts";
import type { DispatchEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createDispatch } from "./dispatch.ts";
import { dispatchEvents } from "./events.ts";
import { dispatchSqlOptions } from "./options.ts";
import { workOrderInputSchema, workOrderPartInputSchema } from "./schemas.ts";
import { dispatchSection } from "./section.ts";

/** The `dispatch` block's manifest (ADR 0029). */
export const dispatchBlock: BlockOf<
  "dispatch",
  typeof createDispatch,
  DispatchEvents,
  Record<never, never>,
  never,
  { readonly dispatch: typeof dispatchSection }
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
  sections: { dispatch: dispatchSection },
  category: "work",
  recipes: ["dispatch-board", "technician-day"],
});
