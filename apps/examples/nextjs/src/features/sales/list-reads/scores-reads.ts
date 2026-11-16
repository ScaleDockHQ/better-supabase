import type { EntityListReads } from "better-supabase/list";

import type { AppDb, EntityListMap } from "@/lib/block-entity-page";

import { blockEntityReads, organizationPager } from "@/lib/block-entity-page";

import type { ScoreModelRow } from "../automation/automation-queries";

/** The score models list's URL names on the scores block's `modelPage`. */
export const scoreModelsMap: EntityListMap = {
  sorts: { name: { by: "name" } },
  filters: { f: "subjectType" },
  facets: { f: "subjectType" },
};

/** The scores block's `modelPage` and `modelFacets` for an organization. */
export function scoreModelsPager(db: AppDb, organizationId: string) {
  return organizationPager(organizationId, {
    page: (options) => db.scores.modelPage(options),
    facets: (options) => db.scores.modelFacets(options),
  });
}

/** The score model as the list shows it. */
export function scoreModelOf(model: {
  readonly id: string;
  readonly key: string;
  readonly name: string;
  readonly subjectType: string;
  readonly enabled: boolean;
  readonly version: number;
  readonly rules: readonly unknown[];
  readonly metrics: readonly unknown[];
  readonly bands: readonly { readonly label: string }[];
}): ScoreModelRow {
  return {
    id: model.id,
    key: model.key,
    name: model.name,
    subjectType: model.subjectType,
    enabled: model.enabled,
    version: model.version,
    rules: model.rules.length,
    metrics: model.metrics.length,
    bands: model.bands.map((band) => band.label).join(", "),
  };
}

/** The reads module of the `app.scores` entity page (ADR 0894). */
export function scoreModelsReads(db: AppDb): EntityListReads<ScoreModelRow> {
  return blockEntityReads({
    pager: (organizationId) => scoreModelsPager(db, organizationId),
    map: scoreModelsMap,
    wire: scoreModelOf,
  });
}
