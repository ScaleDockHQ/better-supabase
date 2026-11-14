import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { buttonVariants } from "@/components/ui/button";
import {
  ProductCatalogGrid,
  ProductCatalogGridSkeleton,
} from "@/features/shop/components/product-catalog-grid";
import { Link } from "@/i18n/navigation";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function ShopPage() {
  const t = useExtracted("shop");

  return (
    <>
      <PageHeader
        title={t("Shop")}
        description={t(
          "The products your organization sells, with their prices.",
        )}
        actions={
          <>
            <Link
              href="/shop/inventory"
              className={buttonVariants({ variant: "ghost", size: "sm" })}
            >
              {t("Inventory")}
            </Link>
            <Link
              href="/shop/orders"
              className={buttonVariants({ variant: "ghost", size: "sm" })}
            >
              {t("Orders")}
            </Link>
            <Link
              href="/shop/kitchen"
              className={buttonVariants({ variant: "ghost", size: "sm" })}
            >
              {t("Kitchen")}
            </Link>
          </>
        }
      />
      <Suspense fallback={<ProductCatalogGridSkeleton />}>
        <ProductCatalogGrid />
      </Suspense>
    </>
  );
}
