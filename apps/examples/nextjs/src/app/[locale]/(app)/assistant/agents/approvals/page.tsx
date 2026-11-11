import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { loadOpsList } from "@/components/ops-list/ops-list-params";
import { PageHeader } from "@/components/page-header";
import {
  ApprovalInbox,
  ApprovalInboxSkeleton,
} from "@/features/agents/components/approval-inbox";

export const ensureStatic = "prefetch";
export const instant = true;

export default function ApprovalsPage({
  searchParams,
}: PageProps<"/[locale]/assistant/agents/approvals">) {
  const t = useExtracted("agents");

  return (
    <>
      <PageHeader
        title={t("Action approvals")}
        description={t(
          "Tool calls that wait for a decision. Select several and decide them together.",
        )}
      />
      <Suspense fallback={<ApprovalInboxSkeleton />}>
        <ApprovalInbox query={loadOpsList(searchParams)} />
      </Suspense>
    </>
  );
}
