import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `deadlines.page`, `deadlines.facets` and `deadlines.count` accept for a
 * deadline (ADR 0749). The manifest declares the same names, and the SQL list
 * function `page_deadlines` implements them. `dueBefore` is a date (a list of
 * one) and `provisional` takes `"true"` or `"false"`.
 */
export const deadlineListSurface: EntityListSurface = {
  sorts: ["dueOn", "createdAt"],
  facets: ["state", "result", "groupKey"],
  filters: [
    "subjectType",
    "subjectId",
    "groupKey",
    "period",
    "state",
    "result",
    "provisional",
    "dueBefore",
  ],
};
