import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  QueueOverview,
  CreateQueueDialog,
  SalesListSkeleton,
} from "@/features/sales/components/crm-overviews";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { parseBlockList } from "@/lib/array-list";

// A navigation here shows the header and the list frame at once; the rows
// render on navigation (tests/loading-sequences.spec.ts).
export const instant = true;

export default function QueuesPage({
  searchParams,
}: PageProps<"/[locale]/crm/queues">) {
  const t = useExtracted("sales");

  return (
    <>
      <PageHeader
        title={t("Queues")}
        description={t(
          "Round robin and weighted queues that pick an owner for new records.",
        )}
        actions={
          <Suspense fallback={null}>
            <PermissionGate permission="assignment.manage">
              <CreateQueueDialog />
            </PermissionGate>
          </Suspense>
        }
      />
      <Suspense fallback={<SalesListSkeleton />}>
        {searchParams.then((raw) => (
          <QueueOverview query={parseBlockList(raw)} />
        ))}
      </Suspense>
    </>
  );
}
