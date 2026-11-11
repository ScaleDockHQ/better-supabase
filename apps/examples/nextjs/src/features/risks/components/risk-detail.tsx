import { getExtracted, getFormatter } from "next-intl/server";
import { notFound } from "next/navigation";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { RecordSectionSkeleton } from "@/components/record-detail/record-section-states";
import { Badge } from "@/components/reui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";

import type {
  RiskDetailData,
  RiskLinkView,
  RiskRatingView,
} from "../risks-queries";

import { getRisk } from "../risks-queries";
import { RiskBandBadge } from "./risk-band-badge";
import { RiskDetailError } from "./risk-detail-error";
import { RiskStatusBadge } from "./risk-status-badge";

function Rating({ rating }: { rating: RiskRatingView | null }) {
  return rating === null ? (
    <span className="text-muted-foreground">–</span>
  ) : (
    <RiskBandBadge band={rating.band} tone={rating.tone} score={rating.score} />
  );
}

function TextSection({ title, body }: { title: string; body: string | null }) {
  if (body === null) {
    return null;
  }

  return (
    <Card size="sm">
      <CardHeader>
        <CardTitle>{title}</CardTitle>
      </CardHeader>
      <CardContent className="text-sm whitespace-pre-line">{body}</CardContent>
    </Card>
  );
}

function Links({
  title,
  empty,
  links,
}: {
  title: string;
  empty: string;
  links: readonly RiskLinkView[];
}) {
  return (
    <Card size="sm">
      <CardHeader>
        <CardTitle>{title}</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-2 text-sm">
        {links.length === 0 ? (
          <p className="text-muted-foreground">{empty}</p>
        ) : (
          links.map((link) => (
            <div key={link.linkId} className="flex items-center gap-2">
              <Badge variant="secondary">{link.type}</Badge>
              <span>{link.title ?? link.id}</span>
            </div>
          ))
        )}
      </CardContent>
    </Card>
  );
}

async function Body({ data }: { data: RiskDetailData }) {
  const [t, format] = await Promise.all([
    getExtracted("risks"),
    getFormatter(),
  ]);

  const date = (value: string) =>
    format.dateTime(new Date(value), { dateStyle: "medium", timeZone: "UTC" });

  return (
    <RecordDetailFrame
      title={data.row.title}
      description={`${data.row.number} · ${data.row.category}`}
      status={<RiskStatusBadge status={data.row.status} />}
      aside={
        <>
          <Card size="sm">
            <CardHeader>
              <CardTitle>{t("Rating")}</CardTitle>
              <CardDescription>{data.matrixName}</CardDescription>
            </CardHeader>
            <CardContent className="flex flex-col gap-3 text-sm">
              <div className="flex items-center justify-between gap-2">
                <span className="text-muted-foreground">{t("Inherent")}</span>
                <Rating rating={data.inherent} />
              </div>
              <div className="flex items-center justify-between gap-2">
                <span className="text-muted-foreground">{t("Residual")}</span>
                <Rating rating={data.residual} />
              </div>
              <div className="flex items-center justify-between gap-2">
                <span className="text-muted-foreground">
                  {t("Next review")}
                </span>
                <span className="tabular-nums">
                  {data.row.nextReviewOn === null
                    ? "–"
                    : date(data.row.nextReviewOn)}
                </span>
              </div>
              {data.treatment === null ? null : (
                <div className="flex items-center justify-between gap-2">
                  <span className="text-muted-foreground">
                    {t("Treatment")}
                  </span>
                  <Badge variant="secondary">{data.treatment}</Badge>
                </div>
              )}
            </CardContent>
          </Card>
          <Links
            title={t("Mitigated by")}
            empty={t("No controls linked yet.")}
            links={data.barriers}
          />
          <Links
            title={t("Materialized as")}
            empty={t("No cases linked.")}
            links={data.cases}
          />
        </>
      }
    >
      <TextSection title={t("Description")} body={data.description} />
      <TextSection title={t("Cause")} body={data.cause} />
      <TextSection title={t("Consequence")} body={data.consequence} />
      <Card size="sm">
        <CardHeader>
          <CardTitle>{t("Assessments")}</CardTitle>
          <CardDescription>
            {t("Each assessment freezes the risk's version, newest first.")}
          </CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-3 text-sm">
          {data.assessments.length === 0 ? (
            <p className="text-muted-foreground">
              {t(
                "Not assessed yet. Score the likelihood and impact before and after controls.",
              )}
            </p>
          ) : (
            data.assessments.map((assessment) => (
              <div
                key={assessment.id}
                className="flex flex-col gap-1 border-b pb-3 last:border-b-0 last:pb-0"
              >
                <div className="flex flex-wrap items-center gap-2">
                  <span className="text-muted-foreground tabular-nums">
                    {date(assessment.assessedAt)}
                  </span>
                  <Rating rating={assessment.inherent} />
                  <span className="text-muted-foreground">{t("then")}</span>
                  <Rating rating={assessment.residual} />
                </div>
                {assessment.rationale === null ? null : (
                  <p>{assessment.rationale}</p>
                )}
              </div>
            ))
          )}
        </CardContent>
      </Card>
    </RecordDetailFrame>
  );
}

/** Render inside `<Suspense>`; the fallback is `RiskDetailSkeleton`. */
export async function RiskDetail({ id }: { id: string }) {
  const state = await getRisk(id);

  if (state.kind === "error") {
    return <RiskDetailError />;
  }

  if (state.kind === "no-organization") {
    notFound();
  }

  return <Body data={state.data} />;
}

export function RiskDetailSkeleton() {
  return (
    <div className="grid items-start gap-6 lg:grid-cols-3" aria-busy="true">
      <div className="flex flex-col gap-6 lg:col-span-2">
        <Skeleton className="h-8 w-80" />
        <RecordSectionSkeleton rows={3} />
      </div>
      <div className="flex flex-col gap-6">
        <RecordSectionSkeleton rows={3} />
      </div>
    </div>
  );
}
