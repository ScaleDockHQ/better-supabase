import type { BlockOf } from "../define-block.ts";
import type { WarrantyEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { warrantyEvents } from "./events.ts";
import { warrantyClaimListSurface } from "./lists.ts";
import { createWarranty } from "./warranty.ts";

/** The `warranty` block's manifest (ADR 0029). */
export const warrantyBlock: BlockOf<
  "warranty",
  typeof createWarranty,
  WarrantyEvents
> = defineBlock({
  name: "warranty",
  sql: ["warranty"],
  events: warrantyEvents,
  create: createWarranty,
  recipes: [],
  category: "work",
  entities: {
    warranty_claim: {
      ...warrantyClaimListSurface,
      mutability: "state-machine",
      emits: { create: true },
    },
  },
  concerns: ["lifecycle", "search"],
  description:
    "Warranty claims for an asset: the supplier or manufacturer, the covered amount, a status, a decision and attachments on the claim.",
});
