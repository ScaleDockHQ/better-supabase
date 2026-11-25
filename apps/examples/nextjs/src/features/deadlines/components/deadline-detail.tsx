import { getExtracted } from "next-intl/server";
import { notFound } from "next/navigation";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { RecordSectionSkeleton } from "@/components/record-detail/record-section-states";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { holds } from "@/features/sales/components/overview-support";

import { getDeadline } from "../deadlines-queries";
import { DeadlineStateBadge } from "./deadline-badges";
import { MarkDeadlineDone } from "./mark-deadline-done";

/** One deadline: the date, why it applies and what it still asks. */
export async function DeadlineDetail({ id }: { id: string }) {
  const [deadline, t, canWrite] = await Promise.all([
    getDeadline(id),
    getExtracted("work"),
    holds("deadlines.write"),
  ]);

  if (deadline === null) {
    notFound();
  }

  return (
    <RecordDetailFrame
      title={deadline.kind}
      description={t("{group} in {jurisdiction}", {
        group: deadline.groupKey,
        jurisdiction: deadline.jurisdiction,
      })}
      status={<DeadlineStateBadge state={deadline.state} />}
      actions={
        canWrite && deadline.state === "pending" ? (
          <MarkDeadlineDone deadlineId={deadline.id} />
        ) : null
      }
      aside={
        <Card size="sm">
          <CardHeader>
            <CardTitle>{t("Details")}</CardTitle>
          </CardHeader>
          <CardContent className="grid grid-cols-2 gap-2 text-sm">
            <span className="text-muted-foreground">{t("Due")}</span>
            <span className="text-right tabular-nums">
              {deadline.dueOn ?? t("No date")}
            </span>
            <span className="text-muted-foreground">{t("Result")}</span>
            <span className="text-right">{deadline.result}</span>
            <span className="text-muted-foreground">{t("Evaluated on")}</span>
            <span className="text-right tabular-nums">{deadline.asOf}</span>
            <span className="text-muted-foreground">{t("Rule")}</span>
            <span className="text-right">
              {deadline.ruleKey === null
                ? "–"
                : `${deadline.ruleKey} v${deadline.ruleVersion ?? 1}`}
            </span>
            <span className="text-muted-foreground">{t("Record")}</span>
            <span className="text-right">{deadline.subjectType}</span>
          </CardContent>
        </Card>
      }
    >
      <Card size="sm">
        <CardHeader>
          <CardTitle>{t("Citation")}</CardTitle>
          <CardDescription>{deadline.citation.reference}</CardDescription>
        </CardHeader>
        {deadline.citation.text === null ? null : (
          <CardContent>
            <blockquote className="border-l-2 pl-3 text-sm text-muted-foreground">
              {deadline.citation.text}
            </blockquote>
          </CardContent>
        )}
      </Card>
      <Card size="sm">
        <CardHeader>
          <CardTitle>{t("Open questions")}</CardTitle>
          <CardDescription>
            {deadline.provisional
              ? t("A missing answer could still change this date.")
              : t("Nothing can change this date.")}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {deadline.missingFacts.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              {t("Every fact the rule asks is known.")}
            </p>
          ) : (
            <ul className="flex list-disc flex-col gap-1 pl-5 text-sm">
              {deadline.missingFacts.map((fact) => (
                <li key={fact}>{fact}</li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>
    </RecordDetailFrame>
  );
}

export function DeadlineDetailSkeleton() {
  return (
    <div className="grid gap-6 lg:grid-cols-3" aria-busy="true">
      <div className="flex flex-col gap-6 lg:col-span-2">
        <RecordSectionSkeleton rows={3} />
      </div>
      <RecordSectionSkeleton rows={4} />
    </div>
  );
}
