import { getExtracted, getFormatter } from "next-intl/server";
import { notFound } from "next/navigation";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { RecordSectionSkeleton } from "@/components/record-detail/record-section-states";
import { Badge } from "@/components/reui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { PeopleLoadError } from "@/features/people/components/people-load-error";
import { Link } from "@/i18n/navigation";

import { getRegisterDocument } from "../document-register-queries";
import { RegisterStatusBadge } from "./register-status";

/**
 * Render inside `<Suspense>`: one controlled document with its effective
 * version, review date and revisions.
 */
export async function RegisterDetail({ id }: { id: string }) {
  const [t, format, loaded] = await Promise.all([
    getExtracted("documents"),
    getFormatter(),
    getRegisterDocument(id),
  ]);

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <PeopleLoadError title={t("This document didn't load")} />;
  }

  if (loaded.data === "not-found") {
    notFound();
  }

  const { row, reviewIntervalMonths, effectiveFrom, revisions } = loaded.data;

  const date = (value: string) =>
    format.dateTime(new Date(value), { dateStyle: "medium", timeZone: "UTC" });

  return (
    <RecordDetailFrame
      title={`${row.number} · ${row.name}`}
      description={row.type}
      status={<RegisterStatusBadge status={row.status} />}
      actions={
        <Link href="/drive" className="text-sm underline underline-offset-4">
          {t("Open in the drive")}
        </Link>
      }
      aside={
        <Card size="sm">
          <CardHeader>
            <CardTitle>{t("Control")}</CardTitle>
          </CardHeader>
          <CardContent className="flex flex-col gap-2 text-sm">
            <span>
              {row.effectiveVersion === null
                ? t("Not released yet")
                : t("Effective version {version}", {
                    version: String(row.effectiveVersion),
                  })}
            </span>
            {effectiveFrom === null ? null : (
              <span className="text-muted-foreground">
                {t("Since {date}", { date: date(effectiveFrom) })}
              </span>
            )}
            {row.nextReviewOn === null ? null : (
              <span className="flex items-center gap-2">
                {t("Next review {date}", { date: date(row.nextReviewOn) })}
                {row.reviewDue ? (
                  <Badge variant="warning-light">{t("Review due")}</Badge>
                ) : null}
              </span>
            )}
            {reviewIntervalMonths === null ? null : (
              <span className="text-muted-foreground">
                {t("Reviewed every {months} months", {
                  months: String(reviewIntervalMonths),
                })}
              </span>
            )}
          </CardContent>
        </Card>
      }
    >
      <Card size="sm">
        <CardHeader>
          <CardTitle>{t("Revisions")}</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-2 text-sm">
          {revisions.length === 0 ? (
            <span className="text-muted-foreground">
              {t("No revision has been saved yet.")}
            </span>
          ) : (
            revisions.map((revision) => (
              <div
                key={revision.id}
                className="flex items-center justify-between gap-2"
              >
                <span className="font-medium tabular-nums">
                  {t("Revision {number}", { number: String(revision.number) })}
                  {revision.label === null ? "" : ` · ${revision.label}`}
                </span>
                <span className="flex items-center gap-2 text-muted-foreground">
                  {date(revision.createdAt)}
                  {revision.current ? (
                    <Badge variant="success-light">{t("Current")}</Badge>
                  ) : null}
                </span>
              </div>
            ))
          )}
        </CardContent>
      </Card>
    </RecordDetailFrame>
  );
}

export function RegisterDetailSkeleton() {
  return (
    <div className="flex flex-col gap-6" aria-busy="true">
      <Skeleton className="h-12" />
      <RecordSectionSkeleton rows={3} />
    </div>
  );
}
