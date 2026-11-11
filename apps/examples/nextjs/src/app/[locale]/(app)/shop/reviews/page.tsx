import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  ReviewList,
  ReviewListSkeleton,
} from "@/features/reviews/components/review-list";
import { PermissionGate } from "@/features/user/components/permission-gate";

// A prefetch of the overview stays static; the rows render on navigation.
export const ensureStatic = "prefetch";

export const instant = true;

export default function ReviewsPage() {
  const t = useExtracted("reviews");

  return (
    <>
      <PageHeader
        title={t("Reviews")}
        description={t("Moderate what customers wrote about your products.")}
      />
      <Suspense fallback={<ReviewListSkeleton />}>
        <PermissionGate permission="reviews.manage">
          <ReviewList />
        </PermissionGate>
      </Suspense>
    </>
  );
}
