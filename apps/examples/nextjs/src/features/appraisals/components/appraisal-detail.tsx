import { getExtracted, getFormatter } from "next-intl/server";
import { notFound } from "next/navigation";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { RecordSectionSkeleton } from "@/components/record-detail/record-section-states";
import { Badge } from "@/components/reui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { PeopleLoadError } from "@/features/people/components/people-load-error";

import type { AppraisalRow } from "../appraisals-queries";

import { getAppraisal } from "../appraisals-queries";

const STATUS_VARIANT = {
  pending: "secondary",
  reviewed: "info-light",
  calibrated: "info-light",
  awaiting_signoff: "warning-light",
  signed_off: "success-light",
} as const satisfies Record<AppraisalRow["status"], string>;

/**
 * Render inside `<Suspense>`: one appraisal with its rating, the competency
 * results, each review and the calibrations.
 */
export async function AppraisalDetail({ id }: { id: string }) {
  const [t, format, loaded] = await Promise.all([
    getExtracted("appraisals"),
    getFormatter(),
    getAppraisal(id),
  ]);

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <PeopleLoadError title={t("This appraisal didn't load")} />;
  }

  if (loaded.data === "not-found") {
    notFound();
  }

  const appraisal = loaded.data;

  const statusLabel = (status: AppraisalRow["status"]) => {
    switch (status) {
      case "pending": {
        return t("In review");
      }

      case "reviewed": {
        return t("Reviewed");
      }

      case "calibrated": {
        return t("Calibrated");
      }

      case "awaiting_signoff": {
        return t("Awaiting sign-off");
      }

      case "signed_off": {
        return t("Signed off");
      }

      default: {
        const unknown: never = status;

        return unknown;
      }
    }
  };

  const date = (instant: string) =>
    format.dateTime(new Date(instant), {
      dateStyle: "medium",
      timeZone: "UTC",
    });

  return (
    <RecordDetailFrame
      title={appraisal.subjectName}
      description={[
        appraisal.cycleName,
        appraisal.managerName === null
          ? null
          : t("Manager {name}", { name: appraisal.managerName }),
      ]
        .filter(Boolean)
        .join(" · ")}
      status={
        <Badge variant={STATUS_VARIANT[appraisal.status]}>
          {statusLabel(appraisal.status)}
        </Badge>
      }
      aside={
        <Card size="sm">
          <CardHeader>
            <CardTitle>{t("Result")}</CardTitle>
          </CardHeader>
          <CardContent className="flex flex-col gap-2 text-sm">
            <span>
              {t("Review average: {rating}", {
                rating: appraisal.rating ?? "–",
              })}
            </span>
            <span>
              {t("Calibrated rating: {rating}", {
                rating: appraisal.calibratedRating?.toString() ?? "–",
              })}
            </span>
            {appraisal.signedOffAt === null ? null : (
              <span className="text-muted-foreground">
                {t("Signed off on {date}", {
                  date: date(appraisal.signedOffAt),
                })}
              </span>
            )}
          </CardContent>
        </Card>
      }
    >
      <Card size="sm">
        <CardHeader>
          <CardTitle>{t("Competencies")}</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-2 text-sm">
          {appraisal.competencies.length === 0 ? (
            <span className="text-muted-foreground">
              {t("This cycle rates one overall rating.")}
            </span>
          ) : (
            appraisal.competencies.map((competency) => (
              <div
                key={competency.key}
                className="flex items-center justify-between gap-2"
              >
                <span className="font-medium">{competency.name}</span>
                <span className="text-muted-foreground tabular-nums">
                  {competency.calibrated?.toString() ??
                    competency.average ??
                    "–"}
                </span>
              </div>
            ))
          )}
        </CardContent>
      </Card>
      <Card size="sm">
        <CardHeader>
          <CardTitle>{t("Reviews")}</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-3 text-sm">
          {appraisal.reviews.length === 0 ? (
            <span className="text-muted-foreground">
              {t("No review has been written yet.")}
            </span>
          ) : (
            appraisal.reviews.map((review) => (
              <div key={review.id} className="flex flex-col gap-1">
                <div className="flex items-center justify-between gap-2">
                  <span className="font-medium">
                    {review.reviewerName ?? t("Anonymous")}
                  </span>
                  <Badge variant="outline">{review.kind}</Badge>
                </div>
                <span className="text-muted-foreground">
                  {review.submittedAt === null
                    ? t("Not submitted")
                    : date(review.submittedAt)}
                  {review.rating === null ? "" : ` · ${review.rating}`}
                </span>
                {review.comments === null ? null : <p>{review.comments}</p>}
              </div>
            ))
          )}
        </CardContent>
      </Card>
      {appraisal.calibrations.length === 0 ? null : (
        <Card size="sm">
          <CardHeader>
            <CardTitle>{t("Calibrations")}</CardTitle>
          </CardHeader>
          <CardContent className="flex flex-col gap-2 text-sm">
            {appraisal.calibrations.map((calibration) => (
              <div key={calibration.id} className="flex flex-col gap-1">
                <span className="font-medium tabular-nums">
                  {t("Set to {rating} on {date}", {
                    rating: String(calibration.toRating),
                    date: date(calibration.calibratedAt),
                  })}
                </span>
                <span className="text-muted-foreground">
                  {calibration.reason}
                </span>
              </div>
            ))}
          </CardContent>
        </Card>
      )}
    </RecordDetailFrame>
  );
}

export function AppraisalDetailSkeleton() {
  return (
    <div className="flex flex-col gap-6" aria-busy="true">
      <Skeleton className="h-12" />
      <RecordSectionSkeleton rows={3} />
    </div>
  );
}
