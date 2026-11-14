import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  OrderList,
  OrderListSkeleton,
} from "@/features/shop/components/order-list";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function OrdersPage() {
  const t = useExtracted("shop");

  return (
    <>
      <PageHeader
        title={t("Orders")}
        description={t(
          "Draft orders you're putting together and the orders placed so far.",
        )}
      />
      <Suspense fallback={<OrderListSkeleton />}>
        <OrderList />
      </Suspense>
    </>
  );
}
