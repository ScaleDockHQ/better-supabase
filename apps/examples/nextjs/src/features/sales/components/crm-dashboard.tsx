import { getExtracted } from "next-intl/server";

import { KpiBand, KpiBandSkeleton } from "@/components/record-list/kpi-band";
import { Badge } from "@/components/reui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { CrmLoadError } from "@/features/crm/components/crm-load-error";
import { settle } from "@/features/crm/crm-queries";
import { Link, toAppHref } from "@/i18n/navigation";

import { getDeals } from "../pipeline/pipeline-queries";
import { DetailTable } from "./detail-table";
import {
  dateFormatter,
  moneyFormatter,
  requirePermission,
} from "./overview-support";

export function CrmDashboardSkeleton() {
  return (
    <div className="flex flex-col gap-6" aria-busy="true">
      <KpiBandSkeleton />
      <Skeleton className="h-64 rounded-xl" />
    </div>
  );
}

/** KPIs, the deals per stage and the open deals closing soonest. */
export async function CrmDashboard() {
  await requirePermission("deals.read");

  const [t, loaded, fmtMoney, fmtDate] = await Promise.all([
    getExtracted("sales"),
    settle(getDeals),
    moneyFormatter(),
    dateFormatter(),
  ]);

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <CrmLoadError title={t("The dashboard didn't load")} />;
  }

  const data = loaded.data;

  if (!data) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>{t("No pipeline yet")}</CardTitle>
          <CardDescription>
            <Link href="/crm/deals" className="underline">
              {t("Create the sales pipeline on the deals page.")}
            </Link>
          </CardDescription>
        </CardHeader>
      </Card>
    );
  }

  const open = data.stages.filter((stage) => stage.category === "open");
  const won = data.stages.filter((stage) => stage.category === "won");

  const sum = (
    stages: readonly {
      readonly totals: readonly {
        readonly amount: bigint;
        readonly currency: string;
      }[];
    }[],
  ) =>
    stages
      .flatMap((stage) => stage.totals)
      .map((total) => fmtMoney(total))
      .join(", ") || "–";

  const kpis = [
    {
      label: t("Open deals"),
      value: String(open.reduce((total, stage) => total + stage.count, 0)),
      href: "/crm/deals" as const,
    },
    {
      label: t("Open pipeline"),
      value: sum(open),
      href: "/crm/deals" as const,
    },
    {
      label: t("Weighted forecast"),
      value:
        open
          .flatMap((stage) => stage.weighted)
          .map((total) => fmtMoney(total))
          .join(", ") || "–",
    },
    { label: t("Won"), value: sum(won), href: "/crm/deals" as const },
  ];

  const widest = Math.max(1, ...data.stages.map((stage) => stage.count));

  const closing = data.deals
    .filter((deal) => deal.category === "open")
    .toSorted((a, b) => a.closeOn.localeCompare(b.closeOn))
    .slice(0, 8);

  return (
    <div className="flex flex-col gap-6">
      <KpiBand kpis={kpis} />
      <Card>
        <CardHeader>
          <CardTitle>{data.pipeline.name}</CardTitle>
          <CardDescription>{t("Deals per stage")}</CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-3">
          {data.stages.map((stage) => (
            <div
              key={stage.id}
              className="grid grid-cols-[10rem_1fr_3rem] items-center gap-3 text-sm"
            >
              <span className="truncate">{stage.name}</span>
              <div className="h-2 rounded-full bg-muted">
                <div
                  className="h-2 w-(--stage-share) rounded-full bg-primary"
                  // SAFETY: a CSS custom property is valid in a style object.
                  style={
                    {
                      "--stage-share": `${(stage.count / widest) * 100}%`,
                    } as React.CSSProperties
                  }
                />
                <span className="sr-only">
                  {t("{count} deals", { count: String(stage.count) })}
                </span>
              </div>
              <span className="text-right tabular-nums">{stage.count}</span>
            </div>
          ))}
        </CardContent>
      </Card>
      <DetailTable
        title={t("Closing soonest")}
        description={t("Open deals by expected close date.")}
        head={[t("Deal"), t("Stage"), t("Amount"), t("Expected close")]}
        rows={closing.map((deal) => ({
          key: deal.id,
          cells: [
            <Link
              key="l"
              href={toAppHref(`/crm/deals/${deal.id}`)}
              className="font-medium hover:underline"
            >
              {deal.name}
            </Link>,
            <Badge key="b" variant="secondary">
              {deal.stage}
            </Badge>,
            fmtMoney(deal.amount),
            fmtDate(deal.closeOn),
          ],
        }))}
        emptyTitle={t("No open deals")}
        emptyDescription={t("Add a deal on the deals page.")}
      />
    </div>
  );
}
