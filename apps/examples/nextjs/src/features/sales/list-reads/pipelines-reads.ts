import type { EntityListReads } from "better-supabase/list";

import type { AppDb, EntityListMap } from "@/lib/block-entity-page";

import { blockEntityReads, organizationPager } from "@/lib/block-entity-page";

import type { PipelineRow } from "../pipeline/pipeline-queries";

/** The pipelines list's URL names on the pipelines block's page. */
export const pipelinesMap: EntityListMap = { sorts: { name: { by: "name" } } };

/** The deal pipelines' `page` and `facets` for an organization. */
export function pipelinesPager(db: AppDb, organizationId: string) {
  return organizationPager(organizationId, {
    page: (options) =>
      db.pipelines.page({
        ...options,
        filters: { ...options.filters, subjectType: ["deal"] },
      }),
    facets: (options) =>
      db.pipelines.facets({
        ...options,
        filters: { ...options.filters, subjectType: ["deal"] },
      }),
  });
}

/** The pipeline as the list shows it. */
export function pipelineOf(pipeline: {
  readonly id: string;
  readonly name: string;
  readonly key: string;
  readonly isDefault: boolean;
  readonly stages: readonly unknown[];
}): PipelineRow {
  return {
    id: pipeline.id,
    name: pipeline.name,
    key: pipeline.key,
    isDefault: pipeline.isDefault,
    stages: pipeline.stages.length,
  };
}

/** The reads module of the `app.pipelines` entity page (ADR 0894). */
export function pipelinesReads(db: AppDb): EntityListReads<PipelineRow> {
  return blockEntityReads({
    pager: (organizationId) => pipelinesPager(db, organizationId),
    map: pipelinesMap,
    wire: pipelineOf,
  });
}
