import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `definitions.page`, `definitions.facets` and `definitions.count` accept
 * (ADR 0749, 1077). The SQL list function `page_workflow_definitions`
 * implements them. `state` is `published`, `draft` (a draft and no published
 * version) or `new` (neither); `q` searches the name and the slug.
 */
export const workflowDefinitionListSurface: EntityListSurface = {
  sorts: ["name", "updatedAt", "createdAt"],
  facets: ["state"],
  filters: ["state"],
  search: ["name", "slug"],
};
