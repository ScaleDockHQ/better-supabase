import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  CreateRfqDialog,
  RfqListSkeleton,
  RfqOverview,
} from "@/features/rfqs/components/rfqs-overview";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { parseBlockList } from "@/lib/array-list";

// A navigation here shows the header and the list frame at once; the rows
// render on navigation (tests/loading-sequences.spec.ts).
export const instant = true;

export default function RfqsPage({
  searchParams,
}: PageProps<"/[locale]/rfqs">) {
  const t = useExtracted("rfqs");

  return (
    <>
      <PageHeader
        title={t("Requests for quotation")}
        description={t(
          "Ask suppliers to quote on the same lines, compare the answers and award one to a purchase order.",
        )}
        actions={
          <Suspense fallback={null}>
            <PermissionGate permission="rfqs.write">
              <CreateRfqDialog />
            </PermissionGate>
          </Suspense>
        }
      />
      <Suspense fallback={<RfqListSkeleton />}>
        {searchParams.then((raw) => (
          <RfqOverview query={parseBlockList(raw)} />
        ))}
      </Suspense>
    </>
  );
}
