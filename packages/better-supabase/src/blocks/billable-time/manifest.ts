import type { BlockOf } from "../define-block.ts";
import type { BillableTimeEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createBillableTime } from "./billable-time.ts";
import { billableTimeEvents } from "./events.ts";
import { timeRateInputSchema } from "./schemas.ts";
import { billableTimeSection } from "./section.ts";

/** The `billable-time` block's manifest (ADR 0029). */
export const billableTimeBlock: BlockOf<
  "billable-time",
  typeof createBillableTime,
  BillableTimeEvents,
  Record<never, never>,
  never,
  { readonly billableTime: typeof billableTimeSection }
> = defineBlock({
  name: "billable-time",
  sql: ["billable-time"],
  options: {},
  events: billableTimeEvents,
  schemas: { time_rate: { input: timeRateInputSchema } },
  create: createBillableTime,
  sections: { billableTime: billableTimeSection },
  category: "commerce",
});
