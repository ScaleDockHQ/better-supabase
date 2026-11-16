import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What the care plan `page`, `facets` and `count` accept (ADR 0749, 1077). The
 * manifest declares the same names, and the SQL list function `page_care_plans`
 * implements them. `archived` takes `true`.
 */
export const carePlanListSurface: EntityListSurface = {
  sorts: ["createdAt", "title", "version", "startsOn", "reviewOn"],
  facets: ["status"],
  filters: ["subjectType", "subjectId", "status", "archived"],
  search: ["title"],
};
