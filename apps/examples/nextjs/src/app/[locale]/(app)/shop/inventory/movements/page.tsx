import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { InventorySections } from "@/features/inventory/components/inventory-sections";
import {
  MovementsOverview,
  MovementsOverviewSkeleton,
} from "@/features/inventory/components/movements-overview";

// A prefetch of the overview stays static; the rows render on navigation.
export const ensureStatic = "prefetch";

export const instant = true;

export default function MovementsPage() {
  const t = useExtracted("inventory");

  return (
    <>
      <PageHeader
        title={t("Stock movements")}
        description={t(
          "Every receipt, adjustment, sale and count the ledger wrote, newest first.",
        )}
      />
      <InventorySections />
      <Suspense fallback={<MovementsOverviewSkeleton />}>
        <MovementsOverview />
      </Suspense>
    </>
  );
}
