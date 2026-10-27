import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  OrderList,
  OrderListSkeleton,
} from "@/features/shop/components/order-list";

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
