import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `page`, `facets` and `count` accept for an import run (ADR 0749). The
 * manifest declares the same names, and the SQL list function
 * `list_import_runs` implements them.
 */
export const importRunListSurface: EntityListSurface = {
  sorts: ["createdAt"],
  facets: ["source", "status"],
  filters: ["source", "status"],
};
