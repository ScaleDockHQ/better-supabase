import { getExtracted } from "next-intl/server";
import { notFound } from "next/navigation";

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
import { hireApplication } from "@/features/composites/composites-actions";
import { ActionButton } from "@/features/sales/components/action-button";
import { ActionDialog } from "@/features/sales/components/action-dialog";
import {
  dateFormatter,
  holds,
  requirePermission,
} from "@/features/sales/components/overview-support";

import { closeApplication } from "../people-actions";
import { getApplication, settle } from "../people-queries";
import { PeopleLoadError } from "./people-load-error";

export function ApplicationDetailSkeleton() {
  return <Skeleton className="h-96 rounded-xl" aria-busy="true" />;
}

/**
 * The application desk: the stage path, the hire action, scorecards and
 * interviews.
 */
export async function ApplicationDetail({
  id,
  tab,
}: {
  id: string;
  tab: string;
}) {
  await requirePermission("hiring.read");

  const [t, loaded, fmtDate, canManage, canWrite] = await Promise.all([
    getExtracted("people"),
    settle(() => getApplication(id)),
    dateFormatter(),
    holds("hiring.manage"),
    holds("hiring.write"),
  ]);

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <PeopleLoadError title={t("The application didn't load")} />;
  }

  if (loaded.data === "not-found") {
    notFound();
  }

  const { row, stages, scorecards, interviews } = loaded.data;
  const subject = { type: "application", id: row.id } as const;
  const open = row.state === "active";

  const states = {
    active: t("Active"),
    hired: t("Hired"),
    rejected: t("Rejected"),
    withdrawn: t("Withdrawn"),
  };

  const facts = [
    { label: t("Opening"), value: row.jobTitle },
    { label: t("Stage"), value: row.stageName ?? "–" },
    { label: t("Source"), value: row.source ?? "–" },
    { label: t("Applied"), value: fmtDate(row.createdAt) },
    { label: t("Hired on"), value: fmtDate(loaded.data.hiredAt ?? undefined) },
  ];

  return (
    <RecordDetailFrame
      aside={
        <>
          <PropertiesRail title={t("Details")} properties={facts} />
          <RecordBoundSections
            subject={subject}
            sections={["tags", "fields", "approvals", "reminders"]}
            alongside={tab === "related" ? ["files", "relations"] : []}
          />
        </>
      }
      title={row.candidateName}
      description={row.jobTitle}
      status={
        <Badge
          variant={
            row.state === "hired"
              ? "success-light"
              : row.state === "active"
                ? "info-light"
                : "secondary"
          }
        >
          {states[row.state]}
        </Badge>
      }
      actions={
        open ? (
          <>
            {canManage ? (
              <ActionDialog
                action={hireApplication}
                title={t("Hire this candidate")}
                description={t(
                  "Marks the application hired and creates the employee record.",
                )}
                trigger={t("Hire")}
                submitLabel={t("Hire")}
                successMessage={t("Candidate hired")}
                hidden={{ applicationId: row.id }}
                redirectTo="/people/{id}"
                fields={[
                  { name: "jobTitle", label: t("Job title"), kind: "text" },
                  { name: "startDate", label: t("Start date"), kind: "date" },
                ]}
              />
            ) : null}
            {canWrite ? (
              <ActionButton
                action={closeApplication}
                input={{ applicationId: row.id, outcome: "rejected" }}
                label={t("Reject")}
                successMessage={t("Application rejected")}
                variant="outline"
              />
            ) : null}
          </>
        ) : undefined
      }
    >
      <RecordDetailTabs
        base={`/people/hiring/${id}`}
        active={tab}
        tabs={[
          { value: "overview", label: t("Overview") },
          { value: "activity", label: t("Activity") },
          { value: "related", label: t("Related") },
        ]}
      />
      {tab === "related" ? (
        <RecordBoundSections
          subject={subject}
          sections={["files", "relations"]}
          alongside={["tags", "fields", "approvals", "reminders"]}
        />
      ) : tab === "activity" ? (
        <RecordBoundSections
          subject={subject}
          sections={["discussion", "history"]}
        />
      ) : (
        <>
          <Card>
            <CardHeader>
              <CardTitle>{t("Pipeline")}</CardTitle>
              <CardDescription>
                {t("Where the candidate stands in the hiring process.")}
              </CardDescription>
            </CardHeader>
            <CardContent>
              <StageStepper
                stages={stages.filter(
                  (stage) =>
                    stage.category !== "rejected" &&
                    stage.category !== "withdrawn",
                )}
                currentId={row.stageId}
                label={t("Application stage")}
              />
            </CardContent>
          </Card>
          <Card>
            <CardHeader>
              <CardTitle>{t("Interviews")}</CardTitle>
              <CardDescription>
                {interviews.length === 0
                  ? t("No interviews scheduled yet.")
                  : t("Scheduled conversations with the candidate.")}
              </CardDescription>
            </CardHeader>
            {interviews.length > 0 ? (
              <CardContent>
                <ul className="flex flex-col gap-2 text-sm">
                  {interviews.map((interview) => (
                    <li
                      key={interview.id}
                      className="flex justify-between gap-4"
                    >
                      <span>{interview.kind ?? t("Interview")}</span>
                      <span className="text-muted-foreground">
                        {fmtDate(interview.startsAt)}
                      </span>
                    </li>
                  ))}
                </ul>
              </CardContent>
            ) : null}
          </Card>
          <Card>
            <CardHeader>
              <CardTitle>{t("Scorecards")}</CardTitle>
              <CardDescription>
                {scorecards.length === 0
                  ? t("No scorecards submitted yet.")
                  : t("Ratings from 1 to 4 by the interviewers.")}
              </CardDescription>
            </CardHeader>
            {scorecards.length > 0 ? (
              <CardContent>
                <ul className="flex flex-col gap-2 text-sm">
                  {scorecards.map((card) => (
                    <li key={card.id} className="flex justify-between gap-4">
                      <span>{card.notes ?? t("No notes")}</span>
                      <span className="text-muted-foreground tabular-nums">
                        {card.rating} / 4
                      </span>
                    </li>
                  ))}
                </ul>
              </CardContent>
            ) : null}
          </Card>
        </>
      )}
    </RecordDetailFrame>
  );
}
