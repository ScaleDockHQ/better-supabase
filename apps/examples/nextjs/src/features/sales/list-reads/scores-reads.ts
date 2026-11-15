import type { EntityListReads } from "better-supabase/list";

import type { BlockListSpec } from "@/lib/array-list";
import type { AppDb } from "@/lib/array-reads";

import { arrayReads } from "@/lib/array-reads";
import { readAllPagesResult } from "@/lib/read-all-pages";

import type { ScoreModelRow } from "../automation/automation-queries";

/**
 * The search, sort and facet of the score models list, shared with its
 * overview.
 */
export const scoreModelsSpec: BlockListSpec<ScoreModelRow> = {
  search: (model) => `${model.name} ${model.key}`,
  facet: (model) => model.subjectType,
  defaultSort: "name",
  sorts: { name: (a, b) => a.name.localeCompare(b.name) },
};

/** The score models of the organization (the block reads them through RLS). */
export function scoreModelsFrom(db: AppDb) {
  return readAllPagesResult((page) => db.scores.modelPage(page)).map((models) =>
    models.map((model): ScoreModelRow => ({
      id: model.id,
      key: model.key,
      name: model.name,
      subjectType: model.subjectType,
      enabled: model.enabled,
      version: model.version,
      rules: model.rules.length,
      metrics: model.metrics.length,
      bands: model.bands.map((band) => band.label).join(", "),
    })),
  );
}

/** The reads module of the `app.scores` entity page (ADR 0894). */
export function scoreModelsReads(db: AppDb): EntityListReads<ScoreModelRow> {
  return arrayReads({
    load: () => scoreModelsFrom(db),
    facet: "subjectType",
    spec: scoreModelsSpec,
    wire: (model) => model,
  });
}
