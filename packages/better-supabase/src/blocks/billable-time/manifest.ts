import type { BlockOf } from "../define-block.ts";
import type { BillableTimeEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createBillableTime } from "./billable-time.ts";
import { billableTimeEvents } from "./events.ts";
import { billableTimeBinding } from "./record-binding.ts";
import { timeRateInputSchema } from "./schemas.ts";

/** The `billable-time` block's manifest (ADR 0029). */
export const billableTimeBlock: BlockOf<
  "billable-time",
  typeof createBillableTime,
  BillableTimeEvents,
  Record<never, never>,
  never,
  typeof billableTimeBinding
> = defineBlock({
  name: "billable-time",
  sql: ["billable-time"],
  options: {},
  events: billableTimeEvents,
  schemas: { time_rate: { input: timeRateInputSchema } },
  create: createBillableTime,
  record: billableTimeBinding,
  category: "commerce",
  entities: {
    time_rate: {
      mutability: "editable",
      emits: { update: false, delete: false },
    },
  },
  concerns: ["lifecycle"],
  description:
    "A rate card for time entries, by member, record or organization with effective dates, and draft invoices from unbilled billable time with one line per record, member or entry, in bigint minor units. Billed entries lock until the invoice is voided.",
});
