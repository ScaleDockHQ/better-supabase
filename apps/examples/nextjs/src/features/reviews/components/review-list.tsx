import { getExtracted } from "next-intl/server";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";

import { getReviews } from "../reviews-queries";
import { ReviewRecordList } from "./review-record-list";

/** Render inside `<Suspense>`; the fallback is `ReviewListSkeleton`. */
export async function ReviewList() {
  const [page, t] = await Promise.all([getReviews(), getExtracted("reviews")]);

  if (page === null) {
    return (
      <p className="text-sm text-muted-foreground">
        {t("Pick an organization to see its reviews.")}
      </p>
    );
  }

  return (
    <ReviewRecordList
      initial={{ items: page.items, nextCursor: page.nextCursor }}
    />
  );
}

export function ReviewListSkeleton() {
  return <RecordListSkeleton rows={4} />;
}
