import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `assets.page`, `assets.facets` and `assets.count` accept for an asset
 * (ADR 0749). The manifest declares the same names, and the SQL list function
 * `page_assets` implements them. `includeSublocations` is a flag filter: with
 * `locationId`, `["true"]` also reads the assets below the location.
 */
export const assetListSurface: EntityListSurface = {
  sorts: ["createdAt", "name"],
  facets: ["status", "kind"],
  filters: [
    "kind",
    "status",
    "assigneeType",
    "assigneeId",
    "locationId",
    "includeSublocations",
  ],
  search: true,
};
