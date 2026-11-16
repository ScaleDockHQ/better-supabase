import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `pickListPage`, `pickListFacets` and `pickListCount` accept for a pick
 * list (ADR 0749). The manifest declares the same names, and the SQL list
 * function `list_pick_lists` implements them. `mine` is `["true"]`, and `q`
 * matches the document id and type.
 */
export const pickListListSurface: EntityListSurface = {
  sorts: ["createdAt", "pickedAt"],
  facets: ["status", "documentType"],
  filters: ["waveId", "status", "documentType", "documentId", "mine"],
  search: ["documentId", "documentType"],
};

/** The same for a pick wave (`page_pick_waves`). */
export const pickWaveListSurface: EntityListSurface = {
  sorts: ["createdAt", "name"],
  facets: ["status", "locationId"],
  filters: ["status", "locationId"],
  search: ["name"],
};

/**
 * The same for a putaway rule (`list_putaway_rules`). `active` is `["true"]` or
 * `["false"]`.
 */
export const putawayRuleListSurface: EntityListSurface = {
  sorts: ["priority", "createdAt"],
  facets: ["active"],
  filters: ["locationId", "variantId", "active"],
};

/**
 * The same for a count plan (`page_count_plans`). `active` is `["true"]` or
 * `["false"]`.
 */
export const countPlanListSurface: EntityListSurface = {
  sorts: ["nextRunOn", "name"],
  facets: ["active"],
  filters: ["active", "locationId"],
  search: ["name"],
};
