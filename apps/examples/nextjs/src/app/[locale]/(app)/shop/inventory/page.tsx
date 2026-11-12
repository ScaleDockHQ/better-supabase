import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { InventorySections } from "@/features/inventory/components/inventory-sections";
import {
  StockOverview,
  StockOverviewSkeleton,
} from "@/features/inventory/components/stock-overview";

// A prefetch of the overview stays static; the rows render on navigation.
export const ensureStatic = "prefetch";

export const instant = true;

export default function InventoryPage() {
  const t = useExtracted("inventory");

  return (
    <>
      <PageHeader
        title={t("Inventory")}
        description={t(
          "Stock per product and location, from the ledger of every movement.",
        )}
      />
      <InventorySections />
      <Suspense fallback={<StockOverviewSkeleton />}>
        <StockOverview />
      </Suspense>
    </>
  );
}
