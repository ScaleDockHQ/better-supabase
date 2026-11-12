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
  entities: {
    review: {
      mutability: "state-machine",
      emits: { create: false, delete: true },
    },
  },
  description:
    "Ratings and reviews of catalog products and other subjects: one per user and subject, verified against paid orders, moderated before or after publishing through the moderation block, with a per-subject aggregate public storefronts can read.",
});
