import type { BlockOf } from "../define-block.ts";
import type { FundingEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { fundingEvents } from "./events.ts";
import { createFunding } from "./funding.ts";
import { fundingSqlOptions } from "./options.ts";
import { fundingAwardInputSchema } from "./schemas.ts";

/** The `funding` block's manifest (ADR 0029). */
export const fundingBlock: BlockOf<
  "funding",
  typeof createFunding,
  FundingEvents
> = defineBlock({
  name: "funding",
  sql: ["funding"],
  options: { funding: fundingSqlOptions },
  events: fundingEvents,
  schemas: { funding_award: { input: fundingAwardInputSchema } },
  create: createFunding,
  category: "commerce",
});
