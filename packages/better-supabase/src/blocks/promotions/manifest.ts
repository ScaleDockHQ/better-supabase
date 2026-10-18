import type { BlockOf } from "../define-block.ts";
import type { PromotionsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { promotionsEvents } from "./events.ts";
import { promotionsSqlOptions } from "./options.ts";
import { createPromotions } from "./promotions.ts";

/** The `promotions` block's manifest (ADR 0029). */
export const promotionsBlock: BlockOf<
  "promotions",
  typeof createPromotions,
  PromotionsEvents
> = defineBlock({
  name: "promotions",
  sql: ["promotions"],
  options: { promotions: promotionsSqlOptions },
  events: promotionsEvents,
  create: createPromotions,
  category: "commerce",
  recipes: ["promotion-code-field"],
});
