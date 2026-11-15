import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `page`, `facets` and `count` accept for a forecast snapshot (ADR 0749,
 * 1077). The manifest declares the same names, and the SQL list function
 * `page_forecast_snapshots` implements them. `since` and `until` are dates;
 * listing needs `forecasts.read`. A snapshot has no text, so there is no `q`.
 */
export const forecastSnapshotListSurface: EntityListSurface = {
  sorts: ["takenAt", "since", "dealCount"],
  facets: ["currency", "pipelineId"],
  filters: ["pipelineId", "currency", "since", "until"],
};
