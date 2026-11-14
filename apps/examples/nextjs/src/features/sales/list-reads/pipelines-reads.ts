import type { EntityListReads } from "better-supabase/list";

import type { BlockListSpec } from "@/lib/array-list";
import type { AppDb } from "@/lib/array-reads";

import { arrayReads } from "@/lib/array-reads";

import type { PipelineRow } from "../pipeline/pipeline-queries";

/** The search, sort and facet of the pipelines list, shared with its overview. */
export const pipelinesSpec: BlockListSpec<PipelineRow> = {
  search: (pipeline) => `${pipeline.name} ${pipeline.key}`,
  defaultSort: "name",
  sorts: { name: (a, b) => a.name.localeCompare(b.name) },
};

/** The deal pipelines of the organization. */
export function pipelinesFrom(db: AppDb, tenant: string) {
  return db.pipelines
    .list({ organizationId: tenant, subjectType: "deal", limit: 100 })
    .map((pipelines) =>
      pipelines.map((pipeline): PipelineRow => ({
        id: pipeline.id,
        name: pipeline.name,
        key: pipeline.key,
        isDefault: pipeline.isDefault,
        stages: pipeline.stages.length,
      })),
    );
}

/** The reads module of the `app.pipelines` entity page (ADR 0894). */
export function pipelinesReads(db: AppDb): EntityListReads<PipelineRow> {
  return arrayReads({
    load: (tenant) => pipelinesFrom(db, tenant),
    spec: pipelinesSpec,
    wire: (pipeline) => pipeline,
  });
}
