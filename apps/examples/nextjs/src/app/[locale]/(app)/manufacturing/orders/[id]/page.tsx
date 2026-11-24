import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { activeTab } from "@/components/record-detail/record-detail-tabs";
import { buttonVariants } from "@/components/ui/button";
import {
  ProductionOrderDetail,
  ProductionOrderDetailSkeleton,
} from "@/features/manufacturing/components/production-order-detail";
import { Link } from "@/i18n/navigation";

// A navigation here shows the back link at once; the order streams in behind it.
export const instant = true;

export default function ProductionOrderPage({
  params,
  searchParams,
}: PageProps<"/[locale]/manufacturing/orders/[id]">) {
  const t = useExtracted("manufacturing");

  return (
    <>
      <Link
        href="/manufacturing/orders"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All production orders")}
      </Link>
      <Suspense fallback={<ProductionOrderDetailSkeleton />}>
        {Promise.all([params, searchParams]).then(([{ id }, raw]) => (
          <ProductionOrderDetail
            id={id}
            tab={activeTab(raw, ["overview", "activity", "related"])}
          />
        ))}
      </Suspense>
    </>
  );
}
