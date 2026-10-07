import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  BetaContent,
  BetaContentSkeleton,
} from "@/features/flags/components/beta-content";

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
