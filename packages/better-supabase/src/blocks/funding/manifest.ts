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
  entities: {
    funding_product: { mutability: "editable", emits: { update: false } },
    funding_award: {
      mutability: "editable",
      emits: { create: true, update: true },
    },
    funding_delivery: { mutability: "state-machine" },
    funding_claim: {
      mutability: "state-machine",
      emits: { create: true, delete: true },
    },
    funding_claim_line: { mutability: "read-only" },
  },
  concerns: ["lifecycle"],
  description:
    "Products a funder pays for, awards of units per period to a record from a funder in contacts, care delivered against an award from time entries, bookings or by hand, usage against the award per period, and claims per funder and period with the funder's response per line, rendered and sent through app-supplied formats and channels.",
});
