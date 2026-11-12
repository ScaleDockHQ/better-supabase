import { ArrowLeftIcon } from "lucide-react";
import { getExtracted, getLocale } from "next-intl/server";
import { notFound } from "next/navigation";

import { Button, buttonVariants } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { settle } from "@/features/status/status-queries";
import { Link } from "@/i18n/navigation";

import { getStoreProduct } from "../store-queries";
import { StoreLoadError } from "./store-load-error";
import { priceText } from "./store-price";
import { StoreStockBadge } from "./store-stock-badge";

/** Render inside `<Suspense>`: one published product with its variants. */
export async function StoreProduct({
  slug,
  productSlug,
}: {
  slug: string;
  productSlug: string;
}) {
  const [t, locale] = await Promise.all([getExtracted("store"), getLocale()]);

  const loaded = await settle(() => getStoreProduct(slug, productSlug));

  if (loaded.kind === "missing") {
    notFound();
  }

  if (loaded.kind === "error") {
    return <StoreLoadError title={t("This product didn't load")} />;
  }

  const { product } = loaded.data;

  return (
    <div className="flex flex-col gap-6">
      <Link
        href={`/store/${slug}`}
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All products")}
      </Link>
      <div className="flex flex-col gap-2">
        <h1 className="text-2xl font-semibold tracking-tight">
          {product.title}
        </h1>
        {product.manufacturer ? (
          <p className="text-sm text-muted-foreground">
            {t("By {name}", { name: product.manufacturer })}
          </p>
        ) : null}
        {product.description ? (
          <p className="text-sm">{product.description}</p>
        ) : null}
      </div>
      <Card size="sm">
        <CardHeader>
          <CardTitle>{t("Choose an option")}</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-4">
          {product.variants.map((variant) => (
            <form
              key={variant.id}
              action="/api/store/cart"
              method="post"
              className="flex flex-wrap items-center justify-between gap-3"
            >
              <input type="hidden" name="intent" value="add" />
              <input type="hidden" name="slug" value={slug} />
              <input type="hidden" name="variantId" value={variant.id} />
              <div className="flex min-w-0 flex-col gap-1">
                <span className="text-sm font-medium">
                  {variant.title ?? product.title}
                </span>
                <span className="font-mono text-xs text-muted-foreground">
                  {variant.sku}
                </span>
              </div>
              <div className="flex items-center gap-3">
                <StoreStockBadge stock={variant.stock} />
                <span className="font-semibold tabular-nums">
                  {variant.amount === null
                    ? t("Ask for a price")
                    : priceText(variant.amount, locale)}
                </span>
                <Button
                  type="submit"
                  size="sm"
                  disabled={variant.stock === "out" || variant.amount === null}
                >
                  {t("Add to cart")}
                </Button>
              </div>
            </form>
          ))}
        </CardContent>
      </Card>
    </div>
  );
}

export function StoreProductSkeleton() {
  return (
    <div className="flex flex-col gap-6" aria-busy="true">
      <Skeleton className="h-8 w-32" />
      <Skeleton className="h-10 w-72" />
      <Skeleton className="h-40 rounded-xl" />
    </div>
  );
}
