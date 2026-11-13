import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `pickListPage`, `pickListFacets` and `pickListCount` accept for a pick
 * list (ADR 0749). The manifest declares the same names, and the SQL list
 * function `list_pick_lists` implements them. `mine` is `["true"]`.
 */
export const pickListListSurface: EntityListSurface = {
  sorts: ["createdAt", "pickedAt"],
  facets: ["status", "documentType"],
  filters: ["waveId", "status", "documentType", "documentId", "mine"],
};
