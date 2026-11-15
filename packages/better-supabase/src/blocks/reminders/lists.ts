import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `page`, `facets` and `count` accept for the caller's reminders (ADR
 * 0749, 1077). The manifest declares the same names, and the SQL list function
 * `page_my_reminders` implements them. A reminder has no text, so there is no
 * `q`.
 */
export const reminderListSurface: EntityListSurface = {
  sorts: ["offsetMinutes", "subjectType"],
  facets: ["method", "subjectType"],
  filters: ["subjectType", "subjectId", "method"],
};
