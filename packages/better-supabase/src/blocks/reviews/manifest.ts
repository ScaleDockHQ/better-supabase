import type { BlockOf } from "../define-block.ts";
import type { ReviewsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { reviewsEvents } from "./events.ts";
import { reviewsSqlOptions } from "./options.ts";
import { createReviews } from "./reviews.ts";

/** The `reviews` block's manifest (ADR 0029). */
export const reviewsBlock: BlockOf<
  "reviews",
  typeof createReviews,
  ReviewsEvents
> = defineBlock({
  name: "reviews",
  sql: ["reviews"],
  options: { reviews: reviewsSqlOptions },
  events: reviewsEvents,
  create: createReviews,
  category: "commerce",
});
