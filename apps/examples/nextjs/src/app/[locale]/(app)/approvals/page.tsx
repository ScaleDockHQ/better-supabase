import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  ApprovalsQueue,
  ApprovalsQueueSkeleton,
} from "@/features/approvals/components/approvals-queue";

export default function ApprovalsPage() {
  const t = useExtracted("approvals");

  return (
    <>
      <PageHeader
        title={t("Approvals")}
        description={t("Requests that need a decision before the action runs.")}
      />
      <Suspense fallback={<ApprovalsQueueSkeleton />}>
        <ApprovalsQueue />
      </Suspense>
    </>
  );
}
