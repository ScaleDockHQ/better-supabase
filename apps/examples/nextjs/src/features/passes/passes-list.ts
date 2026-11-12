import { defineBlockList } from "@/lib/block-status-list";

export const PASS_STATUSES = ["active", "revoked"] as const;

/**
 * `/shop/passes?status=&after=`. The passes block filters by status and pages
 * back from `createdAt`; it has no text search, so the toolbar shows none.
 */
export const passList = defineBlockList({
  facets: [{ key: "status", values: PASS_STATUSES }],
  sorts: ["newest"],
  defaultSort: "newest",
});

export const PASS_PAGE_SIZE = 25;
