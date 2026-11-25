import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  ChangeRequestList,
  ChangeRequestListSkeleton,
} from "@/features/change-requests/components/change-request-list";

export const instant = true;

export default function ChangeRequestsPage() {
  const t = useExtracted("changeRequests");

  return (
    <>
      <PageHeader
        title={t("Change requests")}
        description={t(
          "Changes to production systems, from the request through the change advisory board to the scheduled rollout. The stages come from the organization's change workflow.",
        )}
      />
      <Suspense fallback={<ChangeRequestListSkeleton />}>
        <ChangeRequestList />
      </Suspense>
    </>
  );
}
