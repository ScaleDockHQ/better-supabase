import type { BlockOf } from "../define-block.ts";
import type { PromotionsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { promotionsEvents } from "./events.ts";
import { createPromotions } from "./promotions.ts";

/** The `promotions` block's manifest (ADR 0029). */
export const promotionsBlock: BlockOf<
  "promotions",
  typeof createPromotions,
  PromotionsEvents
> = defineBlock({
  name: "promotions",
  sql: ["promotions"],
  events: promotionsEvents,
  create: createPromotions,
  category: "commerce",
  description:
    "Percentage, fixed and free-shipping promotions, automatic or by code, with usage limits and stacking rules, priced into orders carts.",
  recipes: ["promotion-code-field"],
});
