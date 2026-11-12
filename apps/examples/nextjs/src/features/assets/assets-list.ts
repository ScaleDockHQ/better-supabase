import { defineBlockList } from "@/lib/block-status-list";

export const ASSET_STATUSES = ["active", "maintenance", "retired"] as const;

/**
 * `/assets?q=&status=&after=`. The assets block searches the name, tag and
 * serial number and pages back from `createdAt`, so the only sort is newest.
 */
export const assetList = defineBlockList({
  facets: [{ key: "status", values: ASSET_STATUSES }],
  sorts: ["newest"],
  defaultSort: "newest",
});

export const ASSET_PAGE_SIZE = 25;
