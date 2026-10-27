import { ChefHatIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { buttonVariants } from "@/components/ui/button";
import {
  OrderBoard,
  OrderBoardSkeleton,
} from "@/features/shop/components/order-board";
import { Link } from "@/i18n/navigation";

export default function OrderBoardPage() {
  const t = useExtracted("shop");

  return (
    <>
      <PageHeader
        title={t("Order board")}
        description={t(
          "Today's kitchen orders by state. Drag an order forward to move all of its lines.",
        )}
        actions={
          <Link
            href="/shop/kitchen"
            className={buttonVariants({ variant: "outline", size: "sm" })}
          >
            <ChefHatIcon />
            {t("Kitchen")}
          </Link>
        }
      />
      <Suspense fallback={<OrderBoardSkeleton />}>
        <OrderBoard />
      </Suspense>
    </>
  );
}
