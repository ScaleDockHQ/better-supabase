import { defineBlockList } from "@/lib/block-status-list";

export const CLAIM_STATUSES = [
  "draft",
  "submitted",
  "approved",
  "denied",
  "closed",
] as const;

/**
 * `/shop/warranty?status=`. The warranty block lists claims by status and has
 * no text search and no cursor, so the list is one filtered page of at most
 * `CLAIM_PAGE_SIZE` claims.
 */
export const claimList = defineBlockList({
  facets: [{ key: "status", values: CLAIM_STATUSES }],
  sorts: ["newest"],
  defaultSort: "newest",
});

export const CLAIM_PAGE_SIZE = 100;
