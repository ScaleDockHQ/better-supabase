import type { QualificationGapStatus } from "better-supabase/blocks/qualifications";

import { getExtracted, getFormatter } from "next-intl/server";
import { notFound } from "next/navigation";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { RecordSectionSkeleton } from "@/components/record-detail/record-section-states";
import { Badge } from "@/components/reui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { PeopleLoadError } from "@/features/people/components/people-load-error";

import { getQualificationType } from "../qualifications-queries";

const GAP_VARIANT = {
  missing: "destructive-light",
  expired: "destructive-light",
  expiring: "warning-light",
} as const satisfies Record<QualificationGapStatus, string>;

/**
 * Render inside `<Suspense>`: one qualification type with who has to hold it,
 * who holds it today and who lacks it.
 */
export async function QualificationTypeDetail({ id }: { id: string }) {
  const [t, format, loaded] = await Promise.all([
    getExtracted("qualifications"),
    getFormatter(),
    getQualificationType(id),
  ]);

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <PeopleLoadError title={t("This qualification didn't load")} />;
  }

  if (loaded.data === "not-found") {
    notFound();
  }

  const { row, description, requirements, holders, gaps } = loaded.data;

  const gapLabel = (status: QualificationGapStatus) => {
    switch (status) {
      case "missing": {
        return t("Missing");
      }

      case "expired": {
        return t("Expired");
      }

      case "expiring": {
        return t("Expiring");
      }

      default: {
        const unknown: never = status;

        return unknown;
      }
    }
  };

  return (
    <RecordDetailFrame
      title={row.name}
      description={
        description ??
        (row.validForMonths === null
          ? t("Never expires")
          : t("Valid for {months} months", {
              months: String(row.validForMonths),
            }))
      }
      status={
        row.archived ? (
          <Badge variant="secondary">{t("Archived")}</Badge>
        ) : (
          <Badge variant="success-light">{t("Active")}</Badge>
        )
      }
      aside={
        <Card size="sm">
          <CardHeader>
            <CardTitle>{t("Who has to hold it")}</CardTitle>
          </CardHeader>
          <CardContent className="flex flex-col gap-2 text-sm">
            {requirements.length === 0 ? (
              <span className="text-muted-foreground">
                {t("No role, team or title requires it.")}
              </span>
            ) : (
              requirements.map((requirement) => (
                <span key={requirement.id}>
                  {requirement.targetType}: {requirement.targetValue}
                </span>
              ))
            )}
            {row.evidenceRequired ? (
              <span className="text-muted-foreground">
                {t("A grant needs evidence.")}
              </span>
            ) : null}
          </CardContent>
        </Card>
      }
    >
      <Card size="sm">
        <CardHeader>
          <CardTitle>{t("Holders today")}</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-2 text-sm">
          {holders.length === 0 ? (
            <span className="text-muted-foreground">
              {t("Nobody holds a valid one.")}
            </span>
          ) : (
            holders.map((holder) => <span key={holder.id}>{holder.name}</span>)
          )}
        </CardContent>
      </Card>
      <Card size="sm">
        <CardHeader>
          <CardTitle>{t("Gaps")}</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-2 text-sm">
          {gaps.length === 0 ? (
            <span className="text-muted-foreground">
              {t("Everyone who needs it holds it.")}
            </span>
          ) : (
            gaps.map((gap) => (
              <div
                key={gap.key}
                className="flex items-center justify-between gap-2"
              >
                <span className="font-medium">{gap.holderTitle}</span>
                <span className="flex items-center gap-2">
                  {gap.expiresOn === null ? null : (
                    <span className="text-muted-foreground tabular-nums">
                      {format.dateTime(new Date(`${gap.expiresOn}T12:00:00Z`), {
                        dateStyle: "medium",
                        timeZone: "UTC",
                      })}
                    </span>
                  )}
                  <Badge variant={GAP_VARIANT[gap.status]}>
                    {gapLabel(gap.status)}
                  </Badge>
                </span>
              </div>
            ))
          )}
        </CardContent>
      </Card>
    </RecordDetailFrame>
  );
}

export function QualificationTypeDetailSkeleton() {
  return (
    <div className="flex flex-col gap-6" aria-busy="true">
      <Skeleton className="h-12" />
      <RecordSectionSkeleton rows={3} />
    </div>
  );
}
