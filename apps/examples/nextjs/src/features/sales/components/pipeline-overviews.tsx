import { AsyncResult, ok } from "better-supabase";
import { CalendarClockIcon, GitForkIcon, HandshakeIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { connection } from "next/server";

import type { RecordListUrlQuery } from "@/components/record-list/record-list-types";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import { CreateDealDialog } from "@/features/crm/components/create-deal-dialog";
import { CreatePipelineButton } from "@/features/crm/components/create-pipeline-button";
import { settle } from "@/features/crm/crm-queries";
import { loadedPager } from "@/lib/loaded-pager";

import { dealsMap, dealsPager } from "../list-reads/deals-reads";
import { forecastsMap, forecastsPager } from "../list-reads/forecasts-list";
import {
  pipelineOf,
  pipelinesMap,
  pipelinesPager,
} from "../list-reads/pipelines-reads";
import { loadDealPipeline } from "../pipeline/pipeline-queries";
import { takeForecastSnapshot } from "../sales-actions";
import { ActionDialog } from "./action-dialog";
import { BlockOverview } from "./block-overview";
import {
  dateFormatter,
  holds,
  moneyFormatter,
  requirePermission,
} from "./overview-support";

export function DealOverviewSkeleton() {
  return <RecordListSkeleton />;
}

/** The deals of the default pipeline as a server-paged table. */
export async function DealOverview({ query }: { query: RecordListUrlQuery }) {
  await requirePermission("deals.read");

  const [t, loaded, fmtMoney, fmtDate, canWrite, canManage] = await Promise.all(
    [
      getExtracted("sales"),
      settle(loadDealPipeline),
      moneyFormatter(),
      dateFormatter(),
      holds("deals.write"),
      holds("pipelines.manage"),
    ],
  );

  const data = loaded.kind === "ok" ? loaded.data : null;

  const stageLabels = Object.fromEntries(
    (data?.stages ?? []).map((stage) => [stage.id, stage.name]),
  );

  const openStages = (data?.stages ?? [])
    .filter((stage) => stage.category === "open")
    .map((stage) => ({ value: stage.id, label: stage.name }));

  // The create dialog sits above the table so `?new=1` opens it with rows too.
  const createDeal =
    data && canWrite ? (
      <div className="flex justify-end">
        <CreateDealDialog
          pipelineId={data.pipeline.id}
          stages={openStages}
          openFromUrl
        />
      </div>
    ) : null;

  const action =
    data === undefined && canManage ? <CreatePipelineButton /> : undefined;

  return (
    <>
      {createDeal}
      <BlockOverview
        pager={({ db, tenant }) =>
          data
            ? dealsPager(db, tenant, data)
            : loadedPager(
                () => AsyncResult.from(() => Promise.resolve(ok([]))),
                { search: () => "", sorts: {} },
              )
        }
        map={dealsMap}
        query={query}
        toRow={(deal) => ({
          id: deal.id,
          identifier: deal.identifier,
          name: deal.name,
          stage: deal.stage,
          amount: fmtMoney(deal.amount),
          closeOn: fmtDate(deal.closeOn),
          probability:
            deal.probability === null ? null : `${deal.probability}%`,
          daysInStage: deal.daysInStage,
          health: deal.rotting ? "rotting" : "ok",
          nextStep: deal.nextStep,
        })}
        columns={[
          {
            key: "identifier",
            header: t("Deal"),
            kind: "link",
            href: "/crm/deals/{id}",
            size: 110,
          },
          { key: "name", header: t("Name"), kind: "text", size: 260 },
          { key: "stage", header: t("Stage"), kind: "badge", size: 150 },
          { key: "amount", header: t("Amount"), kind: "number", size: 130 },
          {
            key: "closeOn",
            header: t("Expected close"),
            kind: "muted",
            size: 140,
          },
          {
            key: "probability",
            header: t("Probability"),
            kind: "number",
            size: 110,
          },
          {
            key: "daysInStage",
            header: t("Days in stage"),
            kind: "number",
            size: 120,
          },
          {
            key: "health",
            header: t("Health"),
            kind: "badge",
            size: 110,
            labels: { rotting: t("Rotting"), ok: t("On track") },
            tones: { rotting: "warning-light", ok: "success-light" },
          },
          { key: "nextStep", header: t("Next step"), kind: "muted", size: 220 },
        ]}
        facet={{ key: "stage", label: t("Stage"), values: stageLabels }}
        sorts={[
          { value: "closing", label: t("Closing soonest") },
          { value: "amount", label: t("Largest amount") },
          { value: "name", label: t("Name") },
        ]}
        searchLabel={t("Search deals")}
        errorTitle={t("The deals didn't load")}
        emptyIcon={<HandshakeIcon />}
        emptyTitle={
          data === undefined ? t("No pipeline yet") : t("No deals found")
        }
        emptyDescription={
          data === undefined
            ? t("Start with six stages, from qualified to closed won or lost.")
            : t("Add a deal, or change the filters.")
        }
        emptyAction={action}
      />
    </>
  );
}

export function PipelineOverviewSkeleton() {
  return <RecordListSkeleton rows={3} />;
}

export async function PipelineOverview({
  query,
}: {
  query: RecordListUrlQuery;
}) {
  await requirePermission("pipelines.read");

  const [t, canManage] = await Promise.all([
    getExtracted("sales"),
    holds("pipelines.manage"),
  ]);

  return (
    <BlockOverview
      pager={({ db, tenant }) => pipelinesPager(db, tenant)}
      map={pipelinesMap}
      query={query}
      toRow={(row) => {
        const pipeline = pipelineOf(row);

        return {
          id: pipeline.id,
          name: pipeline.name,
          key: pipeline.key,
          stages: pipeline.stages,
          isDefault: pipeline.isDefault ? "default" : "",
        };
      }}
      columns={[
        {
          key: "name",
          header: t("Pipeline"),
          kind: "link",
          href: "/crm/pipelines/{id}",
          size: 260,
        },
        { key: "key", header: t("Key"), kind: "muted", size: 160 },
        { key: "stages", header: t("Stages"), kind: "number", size: 100 },
        {
          key: "isDefault",
          header: t("Default"),
          kind: "badge",
          size: 110,
          labels: { default: t("Default") },
          tones: { default: "primary-light" },
        },
      ]}
      sorts={[{ value: "name", label: t("Name") }]}
      searchLabel={t("Search pipelines")}
      errorTitle={t("The pipelines didn't load")}
      emptyIcon={<GitForkIcon />}
      emptyTitle={t("No pipeline yet")}
      emptyDescription={t(
        "Start with six stages, from qualified to closed won or lost.",
      )}
      emptyAction={canManage ? <CreatePipelineButton /> : undefined}
    />
  );
}

export function ForecastOverviewSkeleton() {
  return <RecordListSkeleton rows={4} />;
}

export async function ForecastOverview({
  query,
}: {
  query: RecordListUrlQuery;
}) {
  await requirePermission("forecasts.read");

  const [t, fmtMoney, fmtDate, canSnapshot] = await Promise.all([
    getExtracted("sales"),
    moneyFormatter(),
    dateFormatter(),
    holds("forecasts.snapshot"),
  ]);

  return (
    <BlockOverview
      pager={({ db, tenant }) => forecastsPager(db, tenant)}
      map={forecastsMap}
      query={query}
      toRow={(snapshot) => ({
        id: snapshot.id,
        period: `${fmtDate(snapshot.since)} – ${fmtDate(snapshot.until)}`,
        deals: snapshot.dealCount,
        won: fmtMoney(snapshot.won),
        commit: fmtMoney(snapshot.commit),
        bestCase: fmtMoney(snapshot.bestCase),
        target: fmtMoney(snapshot.target),
        attainment:
          snapshot.attainment === null
            ? null
            : `${Math.round(snapshot.attainment * 100)}%`,
        takenAt: fmtDate(snapshot.takenAt),
      })}
      columns={[
        {
          key: "period",
          header: t("Period"),
          kind: "link",
          href: "/crm/forecasts/{id}",
          size: 260,
        },
        { key: "deals", header: t("Deals"), kind: "number", size: 80 },
        { key: "won", header: t("Won"), kind: "number", size: 130 },
        { key: "commit", header: t("Commit"), kind: "number", size: 130 },
        { key: "bestCase", header: t("Best case"), kind: "number", size: 130 },
        { key: "target", header: t("Target"), kind: "number", size: 130 },
        {
          key: "attainment",
          header: t("Attainment"),
          kind: "number",
          size: 110,
        },
        {
          key: "takenAt",
          header: t("Snapshot taken"),
          kind: "muted",
          size: 140,
        },
      ]}
      facet={{
        key: "currency",
        label: t("Currency"),
        values: { EUR: "EUR", USD: "USD", GBP: "GBP" },
      }}
      sorts={[
        { value: "newest", label: t("Newest first") },
        { value: "oldest", label: t("Oldest first") },
        { value: "period", label: t("Period start") },
      ]}
      errorTitle={t("The forecasts didn't load")}
      emptyIcon={<CalendarClockIcon />}
      emptyTitle={t("No snapshots yet")}
      emptyDescription={t(
        "A snapshot freezes the forecast of a period, so next week's review can show what changed.",
      )}
      emptyAction={canSnapshot ? <SnapshotDialog /> : undefined}
    />
  );
}

/** The dialog that snapshots the forecast of a period. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function SnapshotDialog() {
  const t = await getExtracted("sales");
  // The default period reads the clock, which a prerender may not.
  await connection();
  const today = new Date();

  const since = new Date(
    Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), 1),
  );

  const until = new Date(
    Date.UTC(today.getUTCFullYear(), today.getUTCMonth() + 1, 0),
  );

  return (
    <ActionDialog
      action={takeForecastSnapshot}
      title={t("Snapshot the forecast")}
      description={t(
        "Freezes the deals of the period with their forecast category.",
      )}
      trigger={t("Take snapshot")}
      submitLabel={t("Take snapshot")}
      successMessage={t("Snapshot taken")}
      redirectTo="/crm/forecasts/{id}"
      fields={[
        {
          name: "since",
          label: t("From"),
          kind: "date",
          required: true,
          defaultValue: since.toISOString().slice(0, 10),
        },
        {
          name: "until",
          label: t("Until"),
          kind: "date",
          required: true,
          defaultValue: until.toISOString().slice(0, 10),
        },
        {
          name: "currency",
          label: t("Currency"),
          kind: "select",
          options: [
            { value: "EUR", label: "EUR" },
            { value: "USD", label: "USD" },
            { value: "GBP", label: "GBP" },
          ],
        },
        {
          name: "target",
          label: t("Target (optional)"),
          kind: "decimal",
          placeholder: "50000.00",
        },
      ]}
    />
  );
}
