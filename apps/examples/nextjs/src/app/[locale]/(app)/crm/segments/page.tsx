import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  SegmentOverview,
  CreateSegmentDialog,
  SalesListSkeleton,
} from "@/features/sales/components/crm-overviews";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { parseBlockList } from "@/lib/array-list";

// A navigation here shows the header and the list frame at once; the rows
// render on navigation (tests/loading-sequences.spec.ts).
export const instant = true;

export default function SegmentsPage({
  searchParams,
}: PageProps<"/[locale]/crm/segments">) {
  const t = useExtracted("sales");

  return (
    <>
      <PageHeader
        title={t("Segments")}
        description={t(
          "Saved filters over your companies, refreshed on a schedule.",
        )}
        actions={
          <Suspense fallback={null}>
            <PermissionGate permission="segments.write">
              <CreateSegmentDialog />
            </PermissionGate>
          </Suspense>
        }
      />
      <Suspense fallback={<SalesListSkeleton />}>
        {searchParams.then((raw) => (
          <SegmentOverview query={parseBlockList(raw)} />
        ))}
      </Suspense>
    </>
  );
}
