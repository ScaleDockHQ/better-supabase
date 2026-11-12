import { getExtracted } from "next-intl/server";
import { notFound } from "next/navigation";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { Badge } from "@/components/reui/badge";
import { CrmLoadError } from "@/features/crm/components/crm-load-error";
import { settle } from "@/features/crm/crm-queries";
import { Link, toAppHref } from "@/i18n/navigation";

import { loadForecast, loadPipeline } from "../pipeline/pipeline-queries";
import { DetailTable, FactGrid } from "./detail-table";
import {
  dateFormatter,
  moneyFormatter,
  requirePermission,
} from "./overview-support";

/** A pipeline's stages with their deal counts, totals and time in stage. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function PipelineDetail({ id }: { id: string }) {
  await requirePermission("pipelines.read");

  const [t, loaded, fmtMoney] = await Promise.all([
    getExtracted("sales"),
    settle(() => loadPipeline(id)),
    moneyFormatter(),
  ]);

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <CrmLoadError title={t("The pipeline didn't load")} />;
  }

  const pipeline = loaded.data;

  if (!pipeline) {
    notFound();
  }

  const days = (seconds: number | undefined) =>
    seconds === undefined
      ? "–"
      : t("{days} days", { days: (seconds / 86_400).toFixed(1) });

  return (
    <RecordDetailFrame
      title={pipeline.name}
      description={t("Deals closed in the last 90 days.")}
      status={
        pipeline.isDefault ? (
          <Badge variant="primary-light">{t("Default")}</Badge>
        ) : undefined
      }
    >
      <FactGrid
        facts={[
          { label: t("Won"), value: String(pipeline.won) },
          { label: t("Lost"), value: String(pipeline.lost) },
          {
            label: t("Win rate"),
            value:
              pipeline.winRate === null
                ? "–"
                : `${Math.round(pipeline.winRate * 100)}%`,
          },
        ]}
      />
      <DetailTable
        title={t("Stages")}
        head={[
          t("Stage"),
          t("Deals"),
          t("Value"),
          t("Weighted"),
          t("Average time"),
        ]}
        rows={pipeline.stages.map((stage) => ({
          key: stage.id,
          cells: [
            stage.name,
            <span key="c" className="tabular-nums">
              {stage.count}
            </span>,
            stage.totals.map((total) => fmtMoney(total)).join(", ") || "–",
            stage.weighted.map((total) => fmtMoney(total)).join(", ") || "–",
            days(pipeline.averageSeconds[stage.id]),
          ],
        }))}
        emptyTitle={t("No stages")}
      />
      <p className="text-sm text-muted-foreground">
        <Link href="/crm/deals" className="underline">
          {t("See the deals")}
        </Link>
      </p>
    </RecordDetailFrame>
  );
}

/** A forecast snapshot with its deals and what changed since the one before. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function ForecastDetail({ id }: { id: string }) {
  await requirePermission("forecasts.read");

  const [t, loaded, fmtMoney, fmtDate] = await Promise.all([
    getExtracted("sales"),
    settle(() => loadForecast(id)),
    moneyFormatter(),
    dateFormatter(),
  ]);

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <CrmLoadError title={t("The forecast didn't load")} />;
  }

  const detail = loaded.data;

  if (!detail) {
    notFound();
  }

  const { snapshot, totals } = detail;

  return (
    <RecordDetailFrame
      title={`${fmtDate(snapshot.since)} – ${fmtDate(snapshot.until)}`}
      description={t("Taken {date}", { date: fmtDate(snapshot.takenAt) })}
      status={
        snapshot.attainment === null ? undefined : (
          <Badge variant="info-light">
            {t("{percent}% of target", {
              percent: String(Math.round(snapshot.attainment * 100)),
            })}
          </Badge>
        )
      }
    >
      <FactGrid
        facts={[
          { label: t("Won"), value: fmtMoney(totals.won) },
          { label: t("Commit"), value: fmtMoney(totals.commit) },
          { label: t("Best case"), value: fmtMoney(totals.bestCase) },
          { label: t("Pipeline"), value: fmtMoney(totals.pipeline) },
          { label: t("Omitted"), value: fmtMoney(totals.omit) },
          { label: t("Closing later"), value: fmtMoney(totals.later) },
        ]}
      />
      <DetailTable
        title={t("Changes since the previous snapshot")}
        description={
          detail.previousId === null
            ? t("This is the first snapshot.")
            : undefined
        }
        head={[t("Deal"), t("Change")]}
        rows={(detail.changes ?? []).map((change) => ({
          key: change.dealId,
          cells: [
            <Link
              key="l"
              href={toAppHref(`/crm/deals/${change.dealId}`)}
              className="font-medium hover:underline"
            >
              {change.name}
            </Link>,
            <Badge key="b" variant="secondary">
              {change.change.replaceAll("_", " ")}
            </Badge>,
          ],
        }))}
        emptyTitle={t("Nothing changed")}
      />
      <DetailTable
        title={t("Deals in the snapshot")}
        head={[
          t("Deal"),
          t("Category"),
          t("Outcome"),
          t("Amount"),
          t("Close date"),
        ]}
        rows={detail.deals.map((deal) => ({
          key: deal.dealId,
          cells: [
            <Link
              key="l"
              href={toAppHref(`/crm/deals/${deal.dealId}`)}
              className="font-medium hover:underline"
            >
              {deal.name}
            </Link>,
            deal.forecast ? deal.forecast.replaceAll("_", " ") : "–",
            deal.outcome,
            fmtMoney(deal.amount),
            fmtDate(deal.closeOn),
          ],
        }))}
        emptyTitle={t("No deals in this period")}
      />
    </RecordDetailFrame>
  );
}
