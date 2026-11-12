import { defineBlockList } from "@/lib/block-status-list";

export const REVIEW_STATUSES = ["pending", "published", "rejected"] as const;

/**
 * `/shop/reviews?status=`. The reviews block lists the moderation queue by
 * status, newest first, with a `before` cursor, and has no text search.
 */
export const reviewList = defineBlockList({
  facets: [{ key: "status", values: REVIEW_STATUSES }],
  sorts: ["newest"],
  defaultSort: "newest",
});

export const REVIEW_PAGE_SIZE = 50;
