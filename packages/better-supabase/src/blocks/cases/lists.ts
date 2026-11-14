import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `cases.page`, `cases.facets` and `cases.count` accept for a case (ADR
 * 0749). The manifest declares the same names, and the SQL list function
 * `page_cases` implements them. `kind` takes case kind keys and `overdue` is a
 * flag filter: `["true"]` keeps the open cases past their `dueOn`.
 */
export const caseListSurface: EntityListSurface = {
  sorts: ["createdAt", "dueOn"],
  facets: ["status", "severity", "source"],
  filters: [
    "kind",
    "status",
    "severity",
    "source",
    "owner",
    "stage",
    "overdue",
  ],
  search: true,
};
