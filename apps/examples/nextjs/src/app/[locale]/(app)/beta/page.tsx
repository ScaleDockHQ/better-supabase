import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  BetaContent,
  BetaContentSkeleton,
} from "@/features/flags/components/beta-content";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function BetaPage() {
  const t = useExtracted("beta");

  return (
    <>
      <PageHeader
        title={t("Beta")}
        description={t("Features still behind a flag.")}
      />
      <Suspense fallback={<BetaContentSkeleton />}>
        <BetaContent />
      </Suspense>
    </>
  );
}
