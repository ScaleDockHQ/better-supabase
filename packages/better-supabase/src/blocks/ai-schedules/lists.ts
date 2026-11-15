import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `page`, `facets` and `count` accept for a scheduled task (ADR 0749,
 * 1077). The SQL list function `page_ai_tasks` implements them. `all` is a flag
 * filter: `["true"]` reads every task the caller can see in the tenant, not
 * just their own. `enabled` takes `"true"` or `"false"`. `q` searches the title
 * and the prompt. The default order is newest first.
 */
export const taskListSurface: EntityListSurface = {
  sorts: ["createdAt", "title", "nextRunAt"],
  facets: ["enabled"],
  filters: ["enabled", "all"],
  search: ["title", "prompt"],
};
