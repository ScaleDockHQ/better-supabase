import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `frameworkPage`, `frameworkFacets` and `frameworkCount` accept for a
 * control framework (ADR 0749, 1077). The manifest declares the same names, and
 * the SQL list function implements them. Row level security decides what the
 * caller reads.
 */
export const frameworkListSurface: EntityListSurface = {
  sorts: ["name", "key"],
  facets: ["kind"],
  filters: ["kind"],
  search: ["name", "key"],
};

/**
 * What `evidenceTaskPage`, `evidenceTaskFacets` and `evidenceTaskCount` accept
 * for an evidence task (ADR 0749, 1077). The manifest declares the same names,
 * and the SQL list function implements them. `overdue` is a flag filter:
 * `["true"]` keeps the overdue tasks. Row level security decides what the
 * caller reads.
 */
export const evidenceTaskListSurface: EntityListSurface = {
  sorts: ["dueOn", "title"],
  facets: ["controlId"],
  filters: ["controlId", "assigneeId", "overdue"],
  search: ["title"],
};

/**
 * What `policyPage`, `policyFacets` and `policyCount` accept for a compliance
 * policy (ADR 0749, 1077). The manifest declares the same names, and the SQL
 * list function implements them. Archived policies are hidden unless `archived`
 * is `["true"]` (only the archived ones). `controls` stays an array read,
 * because a control carries the app's custom fields, which the client parses
 * per row.
 */
export const policyListSurface: EntityListSurface = {
  sorts: ["title", "publishedAt"],
  facets: ["requiresAcknowledgement"],
  filters: ["ownerId", "requiresAcknowledgement", "archived"],
  search: ["title", "key"],
};
