import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  OrderDetail,
  OrderDetailSkeleton,
} from "@/features/shop/components/order-detail";
import { Link } from "@/i18n/navigation";

/** The back link is the static shell; the order streams in. */
export default function OrderPage({
  params,
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
        <OrderDetail params={params} />
      </Suspense>
    </>
  );
}
