import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `page`, `facets` and `count` accept for a hostname (ADR 0749). The
 * manifest declares the same names, and the SQL list function `list_hostnames`
 * implements them.
 */
export const hostnameListSurface: EntityListSurface = {
  sorts: ["hostname", "createdAt"],
  facets: ["kind", "verified"],
  filters: ["kind", "verified"],
};
