import type { BlockOf } from "../define-block.ts";
import type { BillingEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createBilling } from "./billing.ts";
import { billingEvents } from "./events.ts";
import { billingSqlOptions } from "./options.ts";

/** The `billing` block's manifest (ADR 0029). */
export const billingBlock: BlockOf<
  "billing",
  typeof createBilling,
  BillingEvents
> = defineBlock({
  name: "billing",
  sql: ["billing"],
  options: {
    billing: billingSqlOptions,
  },
  events: billingEvents,
  create: createBilling,
  category: "commerce",
  recipes: ["plan-picker"],
});
