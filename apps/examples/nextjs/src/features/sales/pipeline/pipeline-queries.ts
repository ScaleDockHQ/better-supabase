import "server-only";
import type { Money } from "better-supabase/commerce";

import { money } from "better-supabase/commerce";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";
import { Temporal } from "temporal-polyfill";

import { CRM_TAG } from "@/features/crm/crm-cache";
import { bsb } from "@/lib/supabase/server";

import { SALES_TAG } from "../sales-cache";

export interface PipelineStageRow {
  readonly id: string;
  readonly name: string;
  /** `open`, `won` or `lost`. */
  readonly category: string;
  readonly probability: number | null;
  readonly count: number;
  readonly totals: readonly Money[];
  readonly weighted: readonly Money[];
}

export interface DealRow {
  readonly id: string;
  readonly identifier: string;
  readonly name: string;
  readonly stageId: string;
  readonly stage: string;
  readonly category: string;
  readonly amount: Money;
  readonly ownerId: string | null;
  readonly closeOn: string;
  readonly probability: number | null;
  readonly daysInStage: number;
  readonly rotting: boolean;
  readonly nextStep: string | null;
}

export interface DealsData {
  readonly pipeline: { readonly id: string; readonly name: string };
  readonly stages: readonly PipelineStageRow[];
  readonly deals: readonly DealRow[];
}

/**
 * The default deal pipeline with every deal on its board, or `null` without an
 * organization. `undefined` data means the pipeline does not exist yet. The
 * overview filters and pages these rows on the server for each request.
 */
export async function loadDeals(): Promise<DealsData | undefined | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(SALES_TAG, CRM_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const pipelines = await db.pipelines
    .list({ organizationId: tenant, subjectType: "deal", limit: 50 })
    .orThrow();

  const pipeline = pipelines.find((item) => item.isDefault) ?? pipelines[0];

  if (!pipeline) {
    return undefined;
  }

  const [board, columns] = await Promise.all([
    db.deals.board({ pipelineId: pipeline.id }).orThrow(),
    db.pipelines
      .board({ subjectType: "deal", pipelineId: pipeline.id })
      .orThrow(),
  ]);

  const weightedOf = new Map(
    columns.map((column) => [
      column.stageId,
      column.totals.map((total) => total.weighted),
    ]),
  );

  return {
    pipeline: { id: pipeline.id, name: pipeline.name },
    stages: board.stages.map((stage) => ({
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
    deals: board.stages.flatMap((stage) =>
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
  };
}

export interface DealDetail {
  readonly deal: DealRow;
  readonly pipeline: { readonly id: string; readonly name: string };
  readonly stages: readonly {
    readonly id: string;
    readonly name: string;
    readonly category: string;
  }[];
  readonly health: {
    readonly slipped: boolean;
    readonly noNextStep: boolean;
    readonly overdue: boolean;
  };
}

/** One deal with its pipeline's stages; `undefined` when it is not on the board. */
export async function loadDeal(
  id: string,
): Promise<DealDetail | undefined | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(SALES_TAG, CRM_TAG);

  if (!tenantOf(session)) {
    return null;
  }

  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const pipelines = await db.pipelines
    .list({ organizationId: tenant, subjectType: "deal", limit: 50 })
    .orThrow();

  for (const pipeline of pipelines) {
    const [board, health] = await Promise.all([
      db.deals.board({ pipelineId: pipeline.id }).orThrow(),
      db.deals.health(pipeline.id).orThrow(),
    ]);

    for (const stage of board.stages) {
      const card = stage.deals.find((deal) => deal.id === id);

      if (!card) {
        continue;
      }

      const checks = health.find((entry) => entry.dealId === id);

      return {
        deal: {
          id: card.id,
          identifier: card.identifier,
          name: card.name,
          stageId: stage.id,
          stage: stage.name,
          category: stage.category,
          amount: money(BigInt(card.amount), card.currency),
          ownerId: card.ownerId,
          closeOn: card.closeOn,
          probability: card.probability,
          daysInStage: card.daysInStage,
          rotting: card.rotting,
          nextStep: card.nextStep,
        },
        pipeline: { id: pipeline.id, name: pipeline.name },
        stages: board.stages.map((entry) => ({
          id: entry.id,
          name: entry.name,
          category: entry.category,
        })),
        health: {
          slipped: checks?.slipped ?? false,
          noNextStep: checks?.noNextStep ?? false,
          overdue: checks?.overdue ?? false,
        },
      };
    }
  }

  return undefined;
}

export interface PipelineRow {
  readonly id: string;
  readonly name: string;
  readonly key: string;
  readonly isDefault: boolean;
  readonly stages: number;
}

export async function loadPipelines(): Promise<readonly PipelineRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(SALES_TAG, CRM_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const pipelines = await db.pipelines
    .list({ organizationId: tenant, subjectType: "deal", limit: 100 })
    .orThrow();

  return pipelines.map((pipeline) => ({
    id: pipeline.id,
    name: pipeline.name,
    key: pipeline.key,
    isDefault: pipeline.isDefault,
    stages: pipeline.stages.length,
  }));
}

export interface PipelineDetail {
  readonly id: string;
  readonly name: string;
  readonly isDefault: boolean;
  readonly stages: readonly PipelineStageRow[];
  readonly won: number;
  readonly lost: number;
  readonly winRate: number | null;
  /** Average seconds in each stage over the last 90 days, by stage id. */
  readonly averageSeconds: Readonly<Record<string, number>>;
}

export async function loadPipeline(
  id: string,
): Promise<PipelineDetail | undefined | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(SALES_TAG, CRM_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const pipelines = await db.pipelines
    .list({ organizationId: tenant, subjectType: "deal", limit: 100 })
    .orThrow();

  const pipeline = pipelines.find((item) => item.id === id);

  if (!pipeline) {
    return undefined;
  }

  const until = Temporal.Now.instant();
  const since = until.subtract({ hours: 90 * 24 });

  const [columns, stats] = await Promise.all([
    db.pipelines.board({ subjectType: "deal", pipelineId: id }).orThrow(),
    db.pipelines.stats({ pipelineId: id, window: { since, until } }).orThrow(),
  ]);

  return {
    id: pipeline.id,
    name: pipeline.name,
    isDefault: pipeline.isDefault,
    stages: columns.map((column) => ({
      id: column.stageId,
      name: column.name,
      category: column.category,
      probability: column.probability ?? null,
      count: column.count,
      totals: column.totals.map((total) => total.amount),
      weighted: column.totals.map((total) => total.weighted),
    })),
    won: stats.won,
    lost: stats.lost,
    winRate: stats.winRate ?? null,
    averageSeconds: Object.fromEntries(
      stats.stages.flatMap((stage) =>
        stage.averageSeconds === undefined
          ? []
          : [[stage.stageId, stage.averageSeconds] as const],
      ),
    ),
  };
}

export interface ForecastRow {
  readonly id: string;
  readonly since: string;
  readonly until: string;
  readonly currency: string;
  readonly dealCount: number;
  readonly commit: Money;
  readonly bestCase: Money;
  readonly won: Money;
  readonly target: Money | null;
  readonly attainment: number | null;
  readonly takenAt: string;
}

export async function loadForecasts(): Promise<readonly ForecastRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(SALES_TAG, CRM_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const snapshots = await db.forecasts
    .list({ organizationId: tenant, filter: { limit: 200 } })
    .orThrow();

  return snapshots.map((snapshot) => ({
    id: snapshot.id,
    since: snapshot.since.toString(),
    until: snapshot.until.toString(),
    currency: snapshot.currency,
    dealCount: snapshot.dealCount,
    commit: snapshot.totals.commit,
    bestCase: snapshot.totals.bestCase,
    won: snapshot.totals.won,
    target: snapshot.target ?? null,
    attainment: snapshot.totals.attainment ?? null,
    takenAt: snapshot.takenAt.toString(),
  }));
}

export interface ForecastDealRow {
  readonly dealId: string;
  readonly name: string;
  readonly forecast: string | null;
  readonly outcome: string;
  readonly amount: Money;
  readonly closeOn: string | null;
}

export interface ForecastChangeRow {
  readonly dealId: string;
  readonly name: string;
  readonly change: string;
}

export interface ForecastDetail {
  readonly snapshot: ForecastRow;
  readonly deals: readonly ForecastDealRow[];
  /** The changes since the snapshot before this one, `null` for the first. */
  readonly changes: readonly ForecastChangeRow[] | null;
  readonly previousId: string | null;
  readonly totals: {
    readonly won: Money;
    readonly commit: Money;
    readonly bestCase: Money;
    readonly pipeline: Money;
    readonly omit: Money;
    readonly later: Money;
  };
}

export async function loadForecast(
  id: string,
): Promise<ForecastDetail | undefined | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(SALES_TAG, CRM_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const [all, detail] = await Promise.all([
    db.forecasts
      .list({ organizationId: tenant, filter: { limit: 200 } })
      .orThrow(),
    db.forecasts.get(id).orThrow(),
  ]);

  const index = all.findIndex((snapshot) => snapshot.id === id);
  const previous = index === -1 ? undefined : all[index + 1];

  const changes = previous
    ? await db.forecasts
        .changes({ fromSnapshotId: previous.id, toSnapshotId: id })
        .orThrow()
    : null;

  return {
    snapshot: {
      id: detail.id,
      since: detail.since.toString(),
      until: detail.until.toString(),
      currency: detail.currency,
      dealCount: detail.dealCount,
      commit: detail.totals.commit,
      bestCase: detail.totals.bestCase,
      won: detail.totals.won,
      target: detail.target ?? null,
      attainment: detail.totals.attainment ?? null,
      takenAt: detail.takenAt.toString(),
    },
    deals: detail.deals.map((deal) => ({
      dealId: deal.dealId,
      name: deal.name,
      forecast: deal.forecast ?? null,
      outcome: deal.outcome,
      amount: deal.amount,
      closeOn: deal.closeOn?.toString() ?? null,
    })),
    changes: changes
      ? changes.deals.map((deal) => ({
          dealId: deal.dealId,
          name: deal.name,
          change: deal.change,
        }))
      : null,
    previousId: previous?.id ?? null,
    totals: {
      won: detail.totals.won,
      commit: detail.totals.commit,
      bestCase: detail.totals.bestCase,
      pipeline: detail.totals.pipeline,
      omit: detail.totals.omit,
      later: detail.totals.later,
    },
  };
}
