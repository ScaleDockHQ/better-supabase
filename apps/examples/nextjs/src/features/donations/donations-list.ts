import { defineBlockList } from "@/lib/block-status-list";

export const GIFT_STATUSES = [
  "pending",
  "posted",
  "failed",
  "refunded",
] as const;

/**
 * `/shop/donations?q=&status=&after=`. The donations block searches the donor
 * id, payment reference and note and pages back from the date received, so the
 * only sort is newest.
 */
export const giftList = defineBlockList({
  facets: [{ key: "status", values: GIFT_STATUSES }],
  sorts: ["newest"],
  defaultSort: "newest",
});

export const GIFT_PAGE_SIZE = 100;
