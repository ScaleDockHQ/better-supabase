import { defineBlockList } from "@/lib/block-list";

export const GIFT_STATUSES = [
  "pending",
  "posted",
  "failed",
  "refunded",
] as const;

/**
 * `/shop/donations?status=`. The donations block filters gifts by status, fund
 * and donor and has no text search and no cursor, so the list is one filtered
 * page of at most `GIFT_PAGE_SIZE` gifts.
 */
export const giftList = defineBlockList({
  facets: [{ key: "status", values: GIFT_STATUSES }],
  sorts: ["newest"],
  defaultSort: "newest",
});

export const GIFT_PAGE_SIZE = 100;
