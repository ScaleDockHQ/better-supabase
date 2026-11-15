import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `page`, `facets` and `count` accept for a pipeline (ADR 0749, 1077). The
 * manifest declares the same names, and the SQL list function `page_pipelines`
 * implements them. A page holds the active pipelines, in board order unless a
 * sort says otherwise.
 */
export const pipelineListSurface: EntityListSurface = {
  sorts: ["rank", "name", "key"],
  facets: ["subjectType"],
  filters: ["subjectType", "key", "scopeId"],
  search: ["name", "key"],
};
