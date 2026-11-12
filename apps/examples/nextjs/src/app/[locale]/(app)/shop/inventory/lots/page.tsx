import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { InventorySections } from "@/features/inventory/components/inventory-sections";
import {
  LotsOverview,
  LotsOverviewSkeleton,
} from "@/features/inventory/components/lots-overview";

// A prefetch of the overview stays static; the rows render on navigation.
export const ensureStatic = "prefetch";

export const instant = true;

export default function LotsPage() {
  const t = useExtracted("inventory");

  return (
    <>
      <PageHeader
        title={t("Lots")}
        description={t(
          "Lots with stock and an expiry date, so nothing expires on the shelf.",
        )}
      />
      <InventorySections />
      <Suspense fallback={<LotsOverviewSkeleton />}>
        <LotsOverview />
      </Suspense>
    </>
  );
}
