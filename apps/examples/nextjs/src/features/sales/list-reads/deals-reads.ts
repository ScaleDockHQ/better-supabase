import type { FacetOptions, PageOptions } from "better-supabase/blocks";
import type { EntityListReads } from "better-supabase/list";

import { AsyncResult, ok } from "better-supabase";
import { money, moneyToJson } from "better-supabase/commerce";
import { Temporal } from "temporal-polyfill";

import type {
  AppDb,
  EntityListMap,
  EntityPager,
} from "@/lib/block-entity-page";

import { blockEntityReads, organizationPager } from "@/lib/block-entity-page";
import { getAllPagesResult } from "@/lib/read-all-pages";

import type { DealRow, DealsData } from "../pipeline/pipeline-queries";

/**
 * The default deal pipeline with every deal on its board. `undefined` means the
 * pipeline does not exist yet.
 */
export function dealsFrom(
  db: AppDb,
  tenant: string,
): AsyncResult<DealsData | undefined> {
  return getAllPagesResult((page) =>
    db.pipelines.page({
      organizationId: tenant,
      filters: { subjectType: ["deal"] },
      ...page,
    }),
  ).andThen(async (pipelines) => {
    const pipeline = pipelines.find((item) => item.isDefault) ?? pipelines[0];

    if (!pipeline) {
      return ok(undefined);
    }

    const [board, columns] = await Promise.all([
      db.deals.board({ pipelineId: pipeline.id }),
      db.pipelines.board({ subjectType: "deal", pipelineId: pipeline.id }),
    ]);

    if (!board.ok) {
      return board;
    }

    if (!columns.ok) {
      return columns;
    }

    const weightedOf = new Map(
      columns.data.map((column) => [
        column.stageId,
        column.totals.map((total) => total.weighted),
      ]),
    );

    return ok({
      pipeline: { id: pipeline.id, name: pipeline.name },
      stages: board.data.stages.map((stage) => ({
        id: stage.id,
        name: stage.name,
        category: stage.category,
        probability: stage.probability,
        count: stage.count,
        totals: stage.totals.map((total) =>
          money(BigInt(total.amount), total.currency),
        ),
        weighted: weightedOf.get(stage.id) ?? [],
      })),
      deals: board.data.stages.flatMap((stage) =>
        stage.deals.map((deal): DealRow => ({
          id: deal.id,
          identifier: deal.identifier,
          name: deal.name,
          stageId: stage.id,
          stage: stage.name,
          category: stage.category,
          amount: money(BigInt(deal.amount), deal.currency),
          ownerId: deal.ownerId,
          closeOn: deal.closeOn,
          probability: deal.probability,
          daysInStage: deal.daysInStage,
          rotting: deal.rotting,
          nextStep: deal.nextStep,
        })),
      ),
    });
  });
}

/** The deal row with its amount as JSON, which has no bigint. */
export type DealWire = Omit<DealRow, "amount"> & {
  readonly amount: ReturnType<typeof moneyToJson>;
};

/** The default deal pipeline and what each of its stages means for a deal. */
export interface DealPipeline {
  readonly pipeline: { readonly id: string; readonly name: string };
  readonly stages: readonly {
    readonly id: string;
    readonly name: string;
    readonly category: string;
    readonly probability: number | null;
    readonly rottingAfterDays: number | null;
  }[];
}

/** The default deal pipeline with its stages; `undefined` before it exists. */
export function dealPipelineOf(
  db: AppDb,
  tenant: string,
): AsyncResult<DealPipeline | undefined> {
  return db.pipelines
    .page({
      organizationId: tenant,
      filters: { subjectType: ["deal"] },
      limit: 50,
    })
    .map((page) => {
      const pipeline =
        page.items.find((item) => item.isDefault) ?? page.items[0];

      return pipeline
        ? {
            pipeline: { id: pipeline.id, name: pipeline.name },
            stages: pipeline.stages.map((stage) => ({
              id: stage.id,
              name: stage.name,
              category: stage.category,
              probability: stage.probability ?? null,
              rottingAfterDays: stage.rottingAfterDays ?? null,
            })),
          }
        : undefined;
    });
}

/** The deals list's sorts on the deals block's. */
const dealSorts: EntityListMap["sorts"] = {
  closing: { by: "closeOn" },
  amount: { by: "amount", direction: "desc" },
  // The block cannot order by the time in a stage; the oldest deals come first.
  stale: { by: "createdAt" },
  name: { by: "name" },
};

/** The deals overview's URL names on the deals block's page. */
export const dealsMap: EntityListMap = {
  sorts: dealSorts,
  filters: { f: "stageId" },
  facets: { f: "stageId" },
};

/**
 * The deals block's `page` and `facets` for the default pipeline's deals, as
 * the rows the list shows. A deal's days in stage and whether it rots come from
 * the stage it sits in.
 */
export function dealsPager(
  db: AppDb,
  organizationId: string,
  data: DealPipeline | undefined,
): EntityPager<DealRow> {
  const stageOf = new Map(data?.stages.map((stage) => [stage.id, stage]));
  const now = Temporal.Now.instant();

  const scoped = (filters: PageOptions["filters"]) => ({
    ...filters,
    pipelineId: [data?.pipeline.id ?? ""],
  });

  const pager = organizationPager(organizationId, {
    page: (options) =>
      db.deals.page({ ...options, filters: scoped(options.filters) }),
    facets: (options) =>
      db.deals.facets({ ...options, filters: scoped(options.filters) }),
  });

  return {
    facets: (options) => pager.facets(options),
    page: (options) =>
      pager.page(options).map((page) => ({
        ...page,
        items: page.items.map((deal): DealRow => {
          const stage = stageOf.get(deal.stageId ?? "");

          const daysInStage = deal.stageEnteredAt
            ? Math.max(
                0,
                Math.floor(
                  now.since(deal.stageEnteredAt, { largestUnit: "hours" })
                    .hours / 24,
                ),
              )
            : 0;

          return {
            id: deal.id,
            identifier: deal.identifier,
            name: deal.name,
            stageId: deal.stageId ?? "",
            stage: stage?.name ?? "",
            category: stage?.category ?? "open",
            amount: deal.amount,
            ownerId: deal.ownerId ?? null,
            closeOn: deal.closeOn.toString(),
            probability: deal.probability ?? stage?.probability ?? null,
            daysInStage,
            rotting:
              deal.outcome === "open" &&
              stage?.rottingAfterDays !== null &&
              stage?.rottingAfterDays !== undefined &&
              daysInStage > stage.rottingAfterDays,
            nextStep: deal.nextStep ?? null,
          };
        }),
      })),
  };
}

/** The reads module of the `app.deals` entity page (ADR 0894). */
export function dealsReads(db: AppDb): EntityListReads<DealWire> {
  return blockEntityReads({
    pager: (organizationId) => {
      // The default pipeline is read once per request and shared by `page` and `facets`.
      let pipeline: Promise<DealPipeline | undefined> | undefined;

      const resolved = () =>
        (pipeline ??= dealPipelineOf(db, organizationId).orThrow());

      const lazy = {
        page: (options: PageOptions) =>
          AsyncResult.from(async () =>
            dealsPager(db, organizationId, await resolved()).page(options),
          ),
        facets: (options: FacetOptions) =>
          AsyncResult.from(async () =>
            dealsPager(db, organizationId, await resolved()).facets(options),
          ),
      };

      return lazy;
    },
    map: {
      sorts: dealSorts,
      filters: { stage: "stageId" },
      facets: { stage: "stageId" },
    },
    wire: (deal) => ({ ...deal, amount: moneyToJson(deal.amount) }),
  });
}
