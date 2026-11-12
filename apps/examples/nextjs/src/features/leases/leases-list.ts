import { defineBlockList } from "@/lib/block-status-list";

export const LEASE_STATUSES = [
  "draft",
  "active",
  "ended",
  "terminated",
] as const;

/**
 * `/property/leases?status=`. The leases block filters by status, unit and
 * party and has no text search and no cursor, so the list is one filtered page
 * of at most `LEASE_PAGE_SIZE` leases.
 */
export const leaseList = defineBlockList({
  facets: [{ key: "status", values: LEASE_STATUSES }],
  sorts: ["newest"],
  defaultSort: "newest",
});

export const LEASE_PAGE_SIZE = 100;
