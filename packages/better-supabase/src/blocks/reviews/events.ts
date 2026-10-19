import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** `review.*`: which review changed, its subject and its state after the change. */
export interface ReviewEventData {
  readonly organizationId: string;
  /** The review. */
  readonly id: string;
  readonly subjectType: string;
  readonly subjectId: string;
  readonly authorId: string | null;
  readonly rating: number;
  readonly status: "pending" | "published" | "rejected";
  /** Whether the orders module shows a paid order for the product. */
  readonly verified: boolean;
}

/** The events of the `reviews` block: type to data. */
export type ReviewsEvents = {
  readonly "review.submitted": ReviewEventData;
  readonly "review.published": ReviewEventData;
  readonly "review.rejected": ReviewEventData;
  readonly "review.replied": ReviewEventData;
  readonly "review.deleted": ReviewEventData;
};

/** The `reviews` block's event types, for its manifest and `onBlockEvent`. */
export const reviewsEvents: Events<ReviewsEvents> = defineEvents({
  "review.submitted": event<ReviewEventData>(),
  "review.published": event<ReviewEventData>(),
  "review.rejected": event<ReviewEventData>(),
  "review.replied": event<ReviewEventData>(),
  "review.deleted": event<ReviewEventData>(),
});
