import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  HealthOverview,
  SalesListSkeleton,
} from "@/features/sales/components/crm-overviews";
import { parseBlockList } from "@/lib/array-list";

// A navigation here shows the header and the list frame at once; the rows
// render on navigation (tests/loading-sequences.spec.ts).
export const instant = true;

export default function SuccessPage({
  searchParams,
}: PageProps<"/[locale]/crm/success">) {
  const t = useExtracted("sales");

  return (
    <>
      <PageHeader
        title={t("Customer success")}
        description={t(
          "Account health from your score models, with the lowest scores first.",
        )}
      />
      <Suspense fallback={<SalesListSkeleton />}>
        {searchParams.then((raw) => (
          <HealthOverview query={parseBlockList(raw)} />
        ))}
      </Suspense>
    </>
  );
}
