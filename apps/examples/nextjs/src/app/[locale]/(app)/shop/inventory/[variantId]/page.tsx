import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  StockDetail,
  StockDetailSkeleton,
} from "@/features/inventory/components/stock-detail";
import { Link } from "@/i18n/navigation";

// A navigation shows the back link at once; the stock streams in.
export const instant = true;

export default function StockItemPage({
  params,
}: PageProps<"/[locale]/shop/inventory/[variantId]">) {
  const t = useExtracted("inventory");

  return (
    <>
      <Link
        href="/shop/inventory"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All stock levels")}
      </Link>
      <Suspense fallback={<StockDetailSkeleton />}>
        {params.then(({ variantId }) => (
          <StockDetail variantId={variantId} />
        ))}
      </Suspense>
    </>
  );
}
