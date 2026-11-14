import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `incidents.page`, `incidents.facets` and `incidents.count` accept for an
 * incident (ADR 0749). The manifest declares the same names, and the SQL list
 * function `page_incidents` implements them.
 */
export const incidentListSurface: EntityListSurface = {
  sorts: ["startedAt", "severity"],
  facets: ["status", "severity"],
  filters: ["status", "severity", "componentId"],
  search: true,
};
