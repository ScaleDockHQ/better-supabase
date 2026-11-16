import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What the time entry `page`, `facets` and `count` accept (ADR 0749, 1077). The
 * manifest declares the same names, and the SQL list function
 * `page_time_entries` implements them. `from` and `to` take one instant and
 * `archived` takes `true`.
 */
export const timeEntryListSurface: EntityListSurface = {
  sorts: ["startedAt", "endedAt", "seconds", "createdAt"],
  facets: ["subjectType", "billable"],
  filters: [
    "subjectType",
    "subjectId",
    "billable",
    "userId",
    "employeeId",
    "from",
    "to",
    "archived",
  ],
  search: ["note"],
};
