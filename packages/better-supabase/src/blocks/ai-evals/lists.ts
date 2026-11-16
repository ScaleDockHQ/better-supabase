import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `page`, `facets` and `count` accept for an evaluation dataset (ADR
 * 1077). The SQL list function `page_eval_datasets` implements them. `q`
 * searches the name. The default order is by name; without an organization the
 * page reads the system's datasets. A dataset has no enumerable column worth a
 * facet, so `facets` is empty and `filters` only takes the dataset ids.
 */
export const datasetListSurface: EntityListSurface = {
  sorts: ["name", "createdAt", "lastRunAt"],
  facets: [],
  filters: ["id"],
  search: ["name"],
};

/**
 * What `page`, `facets` and `count` accept for an evaluation run (ADR 1077).
 * `page_eval_runs` implements them. `q` searches the prompt name and the model.
 * The default order is newest first; without an organization the page reads the
 * system's runs.
 */
export const runListSurface: EntityListSurface = {
  sorts: ["createdAt", "finishedAt"],
  facets: ["status", "model", "promptName"],
  filters: ["datasetId", "status", "model", "promptName"],
  search: ["promptName", "model"],
};
