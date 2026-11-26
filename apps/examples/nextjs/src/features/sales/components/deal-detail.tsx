import { getExtracted } from "next-intl/server";
import { notFound } from "next/navigation";
import { Suspense } from "react";

import type { BoundSection } from "@/components/record-detail/record-bound-sections";

import { AfterNavigation } from "@/components/record-detail/after-navigation";
import { PropertiesRail } from "@/components/record-detail/properties-rail";
import { RecordBoundSections } from "@/components/record-detail/record-bound-sections";
import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { RecordDetailTabs } from "@/components/record-detail/record-detail-tabs";
import { StageStepper } from "@/components/record-detail/stage-stepper";
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
  closeDealLost,
  closeDealWon,
} from "@/features/composites/composites-actions";
import {
  ActivityTimeline,
  ActivityTimelineSkeleton,
} from "@/features/crm/components/activity-timeline";
import { CrmLoadError } from "@/features/crm/components/crm-load-error";
import { moveDeal } from "@/features/crm/crm-actions";
import { settle } from "@/features/crm/crm-queries";

import { getDeal } from "../pipeline/pipeline-queries";
import { reopenDeal, winDeal } from "../sales-actions";
import { ActionButton } from "./action-button";
import { ActionDialog } from "./action-dialog";
import {
  DealConversation,
  DealConversationSkeleton,
} from "./deal-conversation";
import { FieldHistoryTable } from "./field-history-table";
import {
  dateFormatter,
  holds,
  moneyFormatter,
  requirePermission,
} from "./overview-support";

const ASIDE_SECTIONS: readonly BoundSection[] = [
  "tags",
  "fields",
  "approvals",
  "reminders",
  "conversations",
  "tasks",
  "workflows",
];

const RELATED_SECTIONS: readonly BoundSection[] = ["files", "relations"];

export function DealDetailSkeleton() {
  return <Skeleton className="h-96 rounded-xl" aria-busy="true" />;
}

/** The deal desk: the stage path, the facts and the deal's activity. */
export async function DealDetail({
  id,
  tab,
  conversation,
}: {
  id: string;
  tab: string;
  conversation?: string | undefined;
}) {
  await requirePermission("deals.read");

  const [t, loaded, fmtMoney, fmtDate, canWrite, canReadInbox] =
    await Promise.all([
      getExtracted("sales"),
      settle(() => getDeal(id)),
      moneyFormatter(),
      dateFormatter(),
      holds("deals.write"),
      holds("inbox.read"),
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
  const subject = { type: "deal", id: deal.id } as const;
  const open = deal.category === "open";

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
      aside={
        <>
          <PropertiesRail title={t("Details")} properties={facts} />
          <RecordBoundSections
            subject={subject}
            sections={ASIDE_SECTIONS}
            alongside={tab === "related" ? RELATED_SECTIONS : []}
          />
        </>
      }
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
              <ActionButton
                action={closeDealWon}
                input={{ dealId: deal.id }}
                label={t("Win and draft quote")}
                successMessage={t("Deal won, quote drafted")}
              />
              <ActionDialog
                action={closeDealLost}
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
          { value: "related", label: t("Related") },
          ...(canReadInbox
            ? [{ value: "conversation", label: t("Conversation") }]
            : []),
        ]}
      />
      {tab === "conversation" && canReadInbox ? (
        <Suspense fallback={<DealConversationSkeleton />}>
          <AfterNavigation>
            <DealConversation dealId={deal.id} selected={conversation} />
          </AfterNavigation>
        </Suspense>
      ) : tab === "related" ? (
        <RecordBoundSections
          subject={subject}
          sections={RELATED_SECTIONS}
          alongside={ASIDE_SECTIONS}
        />
      ) : tab === "activity" ? (
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
          <RecordBoundSections
            subject={subject}
            sections={["discussion", "history"]}
          />
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
              <StageStepper
                stages={stages}
                currentId={deal.stageId}
                label={t("Deal stage")}
              />
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
          {flags.length > 0 ? (
            <Card>
              <CardHeader>
                <CardTitle>{t("Needs attention")}</CardTitle>
                <CardDescription className="flex flex-wrap gap-2">
                  {flags.map((flag) => (
                    <Badge key={flag} variant="warning-light">
                      {flag}
                    </Badge>
                  ))}
                </CardDescription>
              </CardHeader>
            </Card>
          ) : null}
        </>
      )}
    </RecordDetailFrame>
  );
}
