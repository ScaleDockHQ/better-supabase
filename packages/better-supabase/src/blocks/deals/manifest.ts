import type { BlockOf } from "../define-block.ts";
import type { DealsEvents } from "./events.ts";

import { blockLink } from "../composition.ts";
import { defineBlock } from "../define-block.ts";
import { createDeals } from "./deals.ts";
import { dealsEvents } from "./events.ts";
import { dealsSqlOptions } from "./options.ts";
import { dealsBinding } from "./record-binding.ts";
import { dealChangeSchema, dealInputSchema } from "./schemas.ts";

/** The `deals` block's manifest (ADR 0029). */
export const dealsBlock: BlockOf<
  "deals",
  typeof createDeals,
  DealsEvents,
  Record<never, never>,
  never,
  typeof dealsBinding
> = defineBlock({
  name: "deals",
  sql: ["deals"],
  options: { deals: dealsSqlOptions },
  events: dealsEvents,
  create: createDeals,
  record: dealsBinding,
  category: "crm",
  entities: {
    deal: {
      mutability: "editable",
      expectedVersion: true,
      idempotent: ["create"],
      emits: { create: true, update: true, delete: true },
    },
  },
  links: [
    blockLink("contact", "reference", "deal", "contacts", "person"),
    blockLink("company", "reference", "deal", "contacts", "company"),
  ],
  concerns: ["lifecycle", "search"],
  description:
    "Deals on pipelines: amounts in minor units, a company and contacts, a deal team, line items, forecast calls with attainment, close-date slips, a next step, locking and batched edits with per-change rejections.",
  recipes: ["deal-board"],
  schemas: { deal: { input: dealInputSchema, change: dealChangeSchema } },
});
