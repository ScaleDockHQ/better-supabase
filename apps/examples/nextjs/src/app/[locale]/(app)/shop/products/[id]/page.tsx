import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { activeTab } from "@/components/record-detail/record-detail-tabs";
import { buttonVariants } from "@/components/ui/button";
import {
  ProductDetail,
  ProductDetailSkeleton,
} from "@/features/shop/components/product-detail";
import { Link } from "@/i18n/navigation";

// A navigation here shows the back link at once; the product streams in behind it.
export const instant = true;

export default function ProductPage({
  params,
  searchParams,
}: PageProps<"/[locale]/shop/products/[id]">) {
  const t = useExtracted("shop");

  return (
    <>
      <Link
        href="/shop"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All products")}
      </Link>
      <Suspense fallback={<ProductDetailSkeleton />}>
        {Promise.all([params, searchParams]).then(([{ id }, raw]) => (
          <ProductDetail
            id={id}
            tab={activeTab(raw, ["overview", "activity", "related"])}
          />
        ))}
      </Suspense>
    </>
  );
}
