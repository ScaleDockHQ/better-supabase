import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { activeTab } from "@/components/record-detail/record-detail-tabs";
import { buttonVariants } from "@/components/ui/button";
import {
  OrderDetail,
  OrderDetailSkeleton,
} from "@/features/shop/components/order-detail";
import { Link } from "@/i18n/navigation";

/** The back link is the static shell; the order streams in. */
// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function OrderPage({
  params,
  searchParams,
}: PageProps<"/[locale]/shop/orders/[id]">) {
  const t = useExtracted("shop");

  return (
    <>
      <Link
        href="/shop/orders"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All orders")}
      </Link>
      <Suspense fallback={<OrderDetailSkeleton />}>
        {Promise.all([params, searchParams]).then(([{ id }, raw]) => (
          <OrderDetail
            id={id}
            tab={activeTab(raw, ["overview", "activity", "related"])}
          />
        ))}
      </Suspense>
    </>
  );
}
