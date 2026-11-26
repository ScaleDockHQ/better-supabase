import { TriangleAlertIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { notFound } from "next/navigation";
import * as v from "valibot";

import { PropertiesRail } from "@/components/record-detail/properties-rail";
import { RecordBoundSections } from "@/components/record-detail/record-bound-sections";
import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { RecordDetailTabs } from "@/components/record-detail/record-detail-tabs";
import { Alert, AlertDescription, AlertTitle } from "@/components/reui/alert";
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
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { ActionButton } from "@/features/sales/components/action-button";
import {
  holds,
  requirePermission,
} from "@/features/sales/components/overview-support";

import { closeInspection, raiseFindingCase } from "../inspections-actions";
import { getInspectionRun } from "../inspections-queries";
import { FindingTypeBadge, InspectionKind } from "./inspection-bits";
import { InspectionStatusBadge } from "./inspection-labels";

const InspectionId = v.pipe(v.string(), v.uuid());

export function InspectionDetailSkeleton() {
  return <Skeleton className="h-96 rounded-xl" aria-busy="true" />;
}

/** One inspection: its findings and cases, and Close once each has its case. */
export async function InspectionDetail({
  id,
  tab,
}: {
  id: string;
  tab: string;
}) {
  await requirePermission("inspections.read");

  if (!v.is(InspectionId, id)) {
    notFound();
  }

  const [t, loaded, canWrite] = await Promise.all([
    getExtracted("inspections"),
    getInspectionRun(id),
    holds("inspections.write"),
  ]);

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return (
      <Alert variant="destructive">
        <TriangleAlertIcon />
        <AlertTitle>{t("The inspection didn't load")}</AlertTitle>
        <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
      </Alert>
    );
  }

  const run = loaded.data;
  const subject = { type: "inspection", id: run.id } as const;

  const waiting = run.findings.filter(
    (finding) => finding.needsCase && finding.caseId === null,
  ).length;

  const working = run.status === "in_progress" || run.status === "reporting";

  const facts = [
    { label: t("Kind"), value: <InspectionKind kind={run.kind} /> },
    { label: t("Findings"), value: String(run.findings.length) },
    { label: t("Waiting for a case"), value: String(waiting) },
    { label: t("Team"), value: String(run.team.length) },
    {
      label: t("Checklist"),
      value:
        run.checklist === null
          ? "–"
          : run.checklist === "submitted"
            ? t("Submitted")
            : t("Draft"),
    },
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
      title={run.number}
      description={run.title}
      status={<InspectionStatusBadge status={run.status} />}
      actions={
        canWrite && working && waiting === 0 ? (
          <ActionButton
            action={closeInspection}
            input={{ inspectionId: run.id }}
            label={t("Close inspection")}
            successMessage={t("Inspection closed")}
            variant="default"
          />
        ) : undefined
      }
    >
      <RecordDetailTabs
        base={`/inspections/${id}`}
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
          {waiting > 0 ? (
            <Alert variant="warning">
              <TriangleAlertIcon />
              <AlertTitle>{t("Findings need a case")}</AlertTitle>
              <AlertDescription>
                {t(
                  "{count, plural, one {# finding needs} other {# findings need}} a corrective action case before the inspection can close.",
                  { count: waiting },
                )}
              </AlertDescription>
            </Alert>
          ) : null}
          <Card>
            <CardHeader>
              <CardTitle>{t("Findings")}</CardTitle>
              <CardDescription>
                {t("What the inspection found, and the case each one raised.")}
              </CardDescription>
            </CardHeader>
            <CardContent>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>{t("No.")}</TableHead>
                    <TableHead>{t("Type")}</TableHead>
                    <TableHead>{t("Finding")}</TableHead>
                    <TableHead>{t("Case")}</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {run.findings.length === 0 ? (
                    <TableRow>
                      <TableCell colSpan={4} className="text-muted-foreground">
                        {t("No findings recorded yet.")}
                      </TableCell>
                    </TableRow>
                  ) : (
                    run.findings.map((finding) => (
                      <TableRow key={finding.id}>
                        <TableCell>{finding.number}</TableCell>
                        <TableCell>
                          <FindingTypeBadge type={finding.type} />
                        </TableCell>
                        <TableCell>
                          {finding.title}
                          {finding.clause === null ? null : (
                            <span className="text-xs text-muted-foreground">
                              {` (${finding.clause})`}
                            </span>
                          )}
                        </TableCell>
                        <TableCell>
                          {finding.caseId === null ? (
                            finding.needsCase && canWrite && working ? (
                              <ActionButton
                                action={raiseFindingCase}
                                input={{ findingId: finding.id }}
                                label={t("Raise case")}
                                successMessage={t("Case raised")}
                              />
                            ) : (
                              "–"
                            )
                          ) : (
                            <Badge variant="success-light">
                              {t("Case raised")}
                            </Badge>
                          )}
                        </TableCell>
                      </TableRow>
                    ))
                  )}
                </TableBody>
              </Table>
            </CardContent>
          </Card>
        </>
      )}
    </RecordDetailFrame>
  );
}
