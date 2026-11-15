import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `page`, `facets` and `count` accept for a deal (ADR 0749, 1077). The
 * manifest declares the same names, and the SQL list function `page_deals`
 * implements them. The list runs as the caller, so the deals row level security
 * hides stay out. A filter on a column the app's table lacks matches nothing;
 * `motion`, `priority` and `forecast` exist on the default table.
 */
export const dealListSurface: EntityListSurface = {
  sorts: ["createdAt", "closeOn", "amount", "name"],
  facets: ["outcome", "stageId", "ownerId", "priority", "motion", "forecast"],
  filters: [
    "pipelineId",
    "stageId",
    "outcome",
    "ownerId",
    "motion",
    "priority",
    "forecast",
    "currency",
    "companyId",
  ],
  search: ["name", "identifier"],
};
