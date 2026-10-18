import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  InventoryTable,
  InventoryTableSkeleton,
} from "@/features/shop/components/inventory-table";

export const instant = true;

export default function InventoryPage() {
  const t = useExtracted("shop");

  return (
    <>
      <PageHeader
        title={t("Inventory")}
        description={t(
          "Stock per product and location. Adjust a count after a delivery or a stocktake.",
        )}
      />
      <Suspense fallback={<InventoryTableSkeleton />}>
        <InventoryTable />
      </Suspense>
    </>
  );
}
