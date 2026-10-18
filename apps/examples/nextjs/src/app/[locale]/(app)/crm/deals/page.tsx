import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  DealBoard,
  DealBoardSkeleton,
} from "@/features/crm/components/deal-board";
import {
  TargetsProgress,
  TargetsProgressSkeleton,
} from "@/features/crm/components/targets-progress";

export const instant = true;

export default function DealsPage() {
  const t = useExtracted("crm");

  return (
    <>
      <PageHeader
        title={t("Deals")}
        description={t(
          "Your pipeline by stage, and how the targets are going.",
        )}
      />
      <Suspense fallback={<TargetsProgressSkeleton />}>
        <TargetsProgress />
      </Suspense>
      <Suspense fallback={<DealBoardSkeleton />}>
        <DealBoard />
      </Suspense>
    </>
  );
}
