import type { ReactNode } from "react";

import { getExtracted, getFormatter } from "next-intl/server";
import { notFound } from "next/navigation";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { RecordSectionSkeleton } from "@/components/record-detail/record-section-states";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { getReview } from "../reviews-queries";
import { ReviewActionsBar } from "./review-actions-bar";
import { ReviewStatusBadge } from "./review-status";

/** One review with its text, reply and moderation state. */
export async function ReviewDetail({ id }: { id: string }): Promise<ReactNode> {
  const [review, permissions, t, format] = await Promise.all([
    getReview(id),
    getPermissions(),
    getExtracted("reviews"),
    getFormatter(),
  ]);

  if (review === null) {
    notFound();
  }

  return (
    <RecordDetailFrame
      title={
        review.title ??
        t("Review by {author}", { author: review.author ?? "–" })
      }
      description={`${"★".repeat(review.rating)}${"☆".repeat(5 - review.rating)}`}
      status={<ReviewStatusBadge status={review.status} />}
      actions={
        can(permissions, "reviews.manage") ? (
          <ReviewActionsBar reviewId={review.id} status={review.status} />
        ) : null
      }
    >
      <Card size="sm">
        <CardHeader>
          <CardTitle>{t("Review")}</CardTitle>
        </CardHeader>
        <CardContent className="grid gap-4 text-sm">
          <p>{review.body ?? t("No text, a rating only.")}</p>
          <div className="grid grid-cols-2 gap-2">
            <span className="text-muted-foreground">{t("Author")}</span>
            <span className="text-right">{review.author ?? "–"}</span>
            <span className="text-muted-foreground">{t("Subject")}</span>
            <span className="text-right">{review.subject}</span>
            <span className="text-muted-foreground">
              {t("Verified purchase")}
            </span>
            <span className="text-right">
              {review.verified ? t("Yes") : t("No")}
            </span>
            <span className="text-muted-foreground">{t("Written")}</span>
            <span className="text-right">
              {format.dateTime(new Date(review.createdAt), {
                dateStyle: "medium",
              })}
            </span>
            {review.rejectionReason ? (
              <>
                <span className="text-muted-foreground">{t("Reason")}</span>
                <span className="text-right">{review.rejectionReason}</span>
              </>
            ) : null}
            {review.reply ? (
              <>
                <span className="text-muted-foreground">{t("Reply")}</span>
                <span className="text-right">{review.reply}</span>
              </>
            ) : null}
          </div>
        </CardContent>
      </Card>
    </RecordDetailFrame>
  );
}

export function ReviewDetailSkeleton() {
  return (
    <div className="flex flex-col gap-6" aria-busy="true">
      <Skeleton className="h-10 w-72" />
      <RecordSectionSkeleton rows={4} />
    </div>
  );
}
