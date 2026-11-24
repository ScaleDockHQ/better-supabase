import { getExtracted } from "next-intl/server";
import { notFound } from "next/navigation";

import { PropertiesRail } from "@/components/record-detail/properties-rail";
import { RecordBoundSections } from "@/components/record-detail/record-bound-sections";
import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { RecordDetailTabs } from "@/components/record-detail/record-detail-tabs";
import { Badge } from "@/components/reui/badge";
import { buttonVariants } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { CrmLoadError } from "@/features/crm/components/crm-load-error";
import { ActionButton } from "@/features/sales/components/action-button";
import {
  dateFormatter,
  holds,
  requirePermission,
} from "@/features/sales/components/overview-support";
import { Link } from "@/i18n/navigation";

import { archiveCarePlan, publishCarePlan } from "../care-plans-actions";
import { getCarePlanDetail } from "../care-plans-queries";
import { CarePlanEditor } from "./care-plan-editor";
import { CarePlanEvaluations } from "./care-plan-evaluations";

export function CarePlanDetailSkeleton() {
  return <Skeleton className="h-96 rounded-xl" aria-busy="true" />;
}

/** The plan's page: status, publish actions, problems and goals, evaluations. */
export async function CarePlanDetail({ id, tab }: { id: string; tab: string }) {
  await requirePermission("care_plans.read");

  const [t, loaded, fmtDate, canPublish, canWrite] = await Promise.all([
    getExtracted("care-plans"),
    getCarePlanDetail(id),
    dateFormatter(),
    holds("care_plans.publish"),
    holds("care_plans.write"),
  ]);

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <CrmLoadError title={t("The plan didn't load")} />;
  }

  const detail = loaded.data;

  if (!detail) {
    notFound();
  }

  const { view } = detail;
  const subject = { type: "care_plan", id: detail.id } as const;

  const facts = [
    { label: t("Version"), value: `v${view.version}` },
    { label: t("Starts on"), value: fmtDate(detail.startsOn) },
    { label: t("Review on"), value: fmtDate(view.reviewOn) },
    { label: t("Published"), value: fmtDate(detail.publishedAt) },
    { label: t("Agreed"), value: fmtDate(detail.agreedAt) },
  ];

  const statusLabels = {
    draft: t("Draft"),
    active: t("Active"),
    archived: t("Archived"),
  };

  const state = { kind: "ok", data: view } as const;

  return (
    <RecordDetailFrame
      aside={
        <>
          <PropertiesRail title={t("Details")} properties={facts} />
          <RecordBoundSections
            subject={subject}
            sections={["tags", "fields", "approvals", "reminders"]}
          />
        </>
      }
      title={view.title}
      description={view.clientName}
      status={
        <Badge
          variant={
            view.status === "active"
              ? "success-light"
              : view.status === "archived"
                ? "warning-light"
                : "secondary"
          }
        >
          {statusLabels[view.status]}
        </Badge>
      }
      actions={
        <>
          <Link
            href={`/care/${detail.clientId}`}
            className={buttonVariants({ variant: "outline", size: "sm" })}
          >
            {t("Open dossier")}
          </Link>
          {canPublish && view.status === "draft" ? (
            <ActionButton
              action={publishCarePlan}
              input={{ planId: detail.id }}
              label={t("Publish")}
              successMessage={t("Plan published")}
              variant="default"
            />
          ) : null}
          {canWrite && view.status !== "archived" ? (
            <ActionButton
              action={archiveCarePlan}
              input={{ planId: detail.id }}
              label={t("Archive")}
              successMessage={t("Plan archived")}
            />
          ) : null}
        </>
      }
    >
      <RecordDetailTabs
        base={`/care-plans/${id}`}
        active={tab}
        tabs={[
          { value: "overview", label: t("Overview") },
          { value: "evaluations", label: t("Evaluations") },
          { value: "activity", label: t("Activity") },
          { value: "related", label: t("Related") },
        ]}
      />
      {tab === "evaluations" ? (
        <CarePlanEvaluations state={state} />
      ) : tab === "related" ? (
        <RecordBoundSections
          subject={subject}
          sections={["files", "relations"]}
        />
      ) : tab === "activity" ? (
        <RecordBoundSections
          subject={subject}
          sections={["discussion", "history"]}
        />
      ) : (
        <CarePlanEditor state={state} />
      )}
    </RecordDetailFrame>
  );
}
