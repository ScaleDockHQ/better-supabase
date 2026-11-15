import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `typePage`, `typeFacets` and `typeCount` accept for a qualification type
 * (ADR 0749, 1077). The manifest declares the same names, and the SQL list
 * function `page_qualification_types` implements them. `state` takes `active`
 * or `archived`, `expiry` takes `never` or `expires`.
 */
export const qualificationTypeListSurface: EntityListSurface = {
  sorts: ["name", "key"],
  facets: ["state", "expiry"],
  filters: ["state", "expiry"],
  search: ["name", "key"],
};
