import type { AsyncResult } from "better-supabase";
import type { EntityListReads } from "better-supabase/list";

import { ok } from "better-supabase";
import { money, moneyToJson } from "better-supabase/commerce";

import type { BlockListSpec } from "@/lib/array-list";
import type { AppDb } from "@/lib/array-reads";

import { arrayReads } from "@/lib/array-reads";
import { readAllPagesResult } from "@/lib/read-all-pages";

import type { DealRow, DealsData } from "../pipeline/pipeline-queries";

/** The search, sort and facet of the deals list, shared with its overview. */
export const dealsSpec: BlockListSpec<DealRow> = {
  search: (deal) => `${deal.identifier} ${deal.name} ${deal.nextStep ?? ""}`,
  facet: (deal) => deal.stageId,
  defaultSort: "closing",
  sorts: {
    closing: (a, b) => a.closeOn.localeCompare(b.closeOn),
    amount: (a, b) =>
      Number(b.amount.amount - a.amount.amount) || a.name.localeCompare(b.name),
    stale: (a, b) => b.daysInStage - a.daysInStage,
    name: (a, b) => a.name.localeCompare(b.name),
  },
};

/**
 * The default deal pipeline with every deal on its board. `undefined` means the
 * pipeline does not exist yet.
 */
export function dealsFrom(
  db: AppDb,
  tenant: string,
): AsyncResult<DealsData | undefined> {
  return readAllPagesResult((page) =>
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

/** The reads module of the `app.deals` entity page (ADR 0894). */
export function dealsReads(db: AppDb): EntityListReads<DealWire> {
  return arrayReads({
    load: (tenant) => dealsFrom(db, tenant).map((data) => data?.deals ?? []),
    facet: "stage",
    spec: dealsSpec,
    wire: (deal) => ({ ...deal, amount: moneyToJson(deal.amount) }),
  });
}
