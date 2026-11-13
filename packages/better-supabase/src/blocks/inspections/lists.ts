import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `inspections.page`, `inspections.facets` and `inspections.count` accept for an inspection (ADR
 * 0749). The manifest declares the same names, and the SQL list function
 * `list_inspections` implements them. `from` and `to` are dates (`2026-03-01`), each a list of one.
 */
export const inspectionListSurface: EntityListSurface = {
  sorts: ["plannedStart", "number"],
  facets: ["status", "kind"],
  filters: [
    "programId",
    "kind",
    "status",
    "leadId",
    "from",
    "to",
    "auditeeType",
    "auditeeId",
  ],
  search: true,
};
