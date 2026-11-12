import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { AdminBackLink } from "@/features/admin-lists/admin-detail-page";
import {
  CreditList,
  CreditListSkeleton,
} from "@/features/credits/components/credits-list";

// A prefetch of this list stays static; the rows render on navigation.
export const ensureStatic = "prefetch";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/loading-sequences.spec.ts checks it in a build.
export const instant = true;

export default function CreditsPage() {
  const t = useExtracted("credits");

  return (
    <>
      <AdminBackLink href="/settings/billing">{t("Billing")}</AdminBackLink>
      <Suspense fallback={<CreditListSkeleton />}>
        <CreditList />
      </Suspense>
    </>
  );
}
