import { ChevronRightIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { notFound } from "next/navigation";
import { Suspense } from "react";

import { AfterNavigation } from "@/components/record-detail/after-navigation";
import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { RecordDetailTabs } from "@/components/record-detail/record-detail-tabs";
import { Badge } from "@/components/reui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import {
  ActivityTimeline,
  ActivityTimelineSkeleton,
} from "@/features/crm/components/activity-timeline";
import { CrmLoadError } from "@/features/crm/components/crm-load-error";
import { moveDeal } from "@/features/crm/crm-actions";
import { settle } from "@/features/crm/crm-queries";

import { loadDeal } from "../pipeline/pipeline-queries";
import { loseDeal, reopenDeal, winDeal } from "../sales-actions";
import { ActionButton } from "./action-button";
import { ActionDialog } from "./action-dialog";
import { FieldHistoryTable } from "./field-history-table";
import {
  dateFormatter,
  holds,
  moneyFormatter,
  requirePermission,
} from "./overview-support";

export function DealDetailSkeleton() {
  return <Skeleton className="h-96 rounded-xl" aria-busy="true" />;
}

/** The deal desk: the stage path, the facts and the deal's activity. */
export async function DealDetail({ id, tab }: { id: string; tab: string }) {
  await requirePermission("deals.read");

  const [t, loaded, fmtMoney, fmtDate, canWrite] = await Promise.all([
    getExtracted("sales"),
    settle(() => loadDeal(id)),
    moneyFormatter(),
    dateFormatter(),
    holds("deals.write"),
  ]);

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <CrmLoadError title={t("The deal didn't load")} />;
  }

  const detail = loaded.data;

  if (!detail) {
    notFound();
  }

  const { deal, stages, health } = detail;
  const open = deal.category === "open";
  const current = stages.findIndex((stage) => stage.id === deal.stageId);

  const facts = [
    { label: t("Amount"), value: fmtMoney(deal.amount) },
    { label: t("Expected close"), value: fmtDate(deal.closeOn) },
    {
      label: t("Probability"),
      value: deal.probability === null ? "–" : `${deal.probability}%`,
    },
    { label: t("Days in stage"), value: String(deal.daysInStage) },
    { label: t("Next step"), value: deal.nextStep ?? "–" },
    { label: t("Pipeline"), value: detail.pipeline.name },
  ];

  const flags = [
    deal.rotting ? t("Rotting") : null,
    health.slipped ? t("Close date slipped") : null,
    health.noNextStep && open ? t("No next step") : null,
    health.overdue ? t("Overdue") : null,
  ].filter((flag) => flag !== null);

  return (
    <RecordDetailFrame
      title={deal.name}
      description={deal.identifier}
      status={
        <Badge
          variant={
            deal.category === "won"
              ? "success-light"
              : deal.category === "lost"
                ? "destructive-light"
                : "primary-light"
          }
        >
          {deal.stage}
        </Badge>
      }
      actions={
        canWrite ? (
          open ? (
            <>
              <ActionButton
                action={winDeal}
                input={{ dealId: deal.id }}
                label={t("Mark won")}
                successMessage={t("Deal won")}
                variant="default"
              />
              <ActionDialog
                action={loseDeal}
                title={t("Mark lost")}
                trigger={t("Mark lost")}
                submitLabel={t("Mark lost")}
                successMessage={t("Deal lost")}
                variant="outline"
                hidden={{ dealId: deal.id }}
                fields={[
                  {
                    name: "reason",
                    label: t("Reason (optional)"),
                    kind: "textarea",
                  },
                ]}
              />
            </>
          ) : (
            <ActionButton
              action={reopenDeal}
              input={{ dealId: deal.id }}
              label={t("Reopen")}
              successMessage={t("Deal reopened")}
            />
          )
        ) : undefined
      }
    >
      <RecordDetailTabs
        base={`/crm/deals/${id}`}
        active={tab}
        tabs={[
          { value: "overview", label: t("Overview") },
          { value: "activity", label: t("Activity") },
        ]}
      />
      {tab === "activity" ? (
        <>
          <Suspense fallback={<ActivityTimelineSkeleton />}>
            <AfterNavigation>
              <ActivityTimeline subject={{ type: "deal", id: deal.id }} />
            </AfterNavigation>
          </Suspense>
          <Suspense fallback={<Skeleton className="h-48 rounded-xl" />}>
            <AfterNavigation>
              <FieldHistoryTable type="deal" id={deal.id} />
            </AfterNavigation>
          </Suspense>
        </>
      ) : (
        <>
          <Card>
            <CardHeader>
              <CardTitle>{t("Stage")}</CardTitle>
              <CardDescription>
                {open
                  ? t("Move the deal to another stage.")
                  : t("The deal is closed.")}
              </CardDescription>
            </CardHeader>
            <CardContent className="flex flex-col gap-4">
              <ol className="flex flex-wrap items-center gap-2">
                {stages.map((stage, index) => (
                  <li key={stage.id} className="flex items-center gap-2">
                    {index > 0 ? (
                      <ChevronRightIcon className="size-4 text-muted-foreground" />
                    ) : null}
                    <Badge
                      variant={
                        index === current
                          ? "primary-light"
                          : index < current
                            ? "secondary"
                            : "outline"
                      }
                      aria-current={index === current ? "step" : undefined}
                    >
                      {stage.name}
                    </Badge>
                  </li>
                ))}
              </ol>
              {open && canWrite ? (
                <div className="flex flex-wrap gap-2">
                  {stages
                    .filter(
                      (stage) =>
                        stage.category === "open" && stage.id !== deal.stageId,
                    )
                    .map((stage) => (
                      <ActionButton
                        key={stage.id}
                        action={moveDeal}
                        input={{ dealId: deal.id, stageId: stage.id }}
                        label={t("Move to {stage}", { stage: stage.name })}
                        successMessage={t("Deal moved")}
                      />
                    ))}
                </div>
              ) : null}
            </CardContent>
          </Card>
          <Card>
            <CardHeader>
              <CardTitle>{t("Details")}</CardTitle>
              {flags.length > 0 ? (
                <CardDescription className="flex flex-wrap gap-2">
                  {flags.map((flag) => (
                    <Badge key={flag} variant="warning-light">
                      {flag}
                    </Badge>
                  ))}
                </CardDescription>
              ) : null}
            </CardHeader>
            <CardContent>
              <dl className="grid gap-4 sm:grid-cols-2">
                {facts.map((fact) => (
                  <div key={fact.label} className="flex flex-col gap-1">
                    <dt className="text-xs text-muted-foreground">
                      {fact.label}
                    </dt>
                    <dd className="text-sm font-medium">{fact.value}</dd>
                  </div>
                ))}
              </dl>
            </CardContent>
          </Card>
        </>
      )}
    </RecordDetailFrame>
  );
}
