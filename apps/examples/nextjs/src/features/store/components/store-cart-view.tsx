import { ShoppingCartIcon } from "lucide-react";
import { getExtracted, getLocale } from "next-intl/server";
import { notFound } from "next/navigation";

import { Button, buttonVariants } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import { settle } from "@/features/status/status-queries";
import { Link } from "@/i18n/navigation";

import { readCart } from "../store-cart";
import { getStoreVariants } from "../store-queries";
import { StoreLoadError } from "./store-load-error";
import { priceText } from "./store-price";
import { StoreStockBadge } from "./store-stock-badge";

/**
 * Render inside `<Suspense>`: the visitor's cart priced from the catalog.
 * Reading the cookie is what makes this region dynamic.
 */
export async function StoreCartView({ slug }: { slug: string }) {
  const [t, locale, lines] = await Promise.all([
    getExtracted("store"),
    getLocale(),
    readCart(slug),
  ]);

  const loaded = await settle(async () =>
    getStoreVariants(
      slug,
      lines.map((line) => line.variantId),
    ),
  );

  if (loaded.kind === "missing") {
    notFound();
  }

  if (loaded.kind === "error") {
    return <StoreLoadError title={t("The cart didn't load")} />;
  }

  const quantity = new Map(
    lines.map((line) => [line.variantId, line.quantity]),
  );

  const items = loaded.data.filter((item) => quantity.has(item.variantId));

  if (items.length === 0) {
    return (
      <Empty className="border">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <ShoppingCartIcon />
          </EmptyMedia>
          <EmptyTitle>{t("Your cart is empty")}</EmptyTitle>
          <EmptyDescription>
            {t("Add a product from the store to see it here.")}
          </EmptyDescription>
        </EmptyHeader>
        <EmptyContent>
          <Link
            href={`/store/${slug}`}
            className={buttonVariants({ size: "sm" })}
          >
            {t("Browse the store")}
          </Link>
        </EmptyContent>
      </Empty>
    );
  }

  const total = items.reduce(
    (sum, item) =>
      sum +
      BigInt(item.amount ?? "0") * BigInt(quantity.get(item.variantId) ?? 0),
    0n,
  );

  const blocked = items.some(
    (item) => item.stock === "out" || item.amount === null,
  );

  return (
    <div className="flex flex-col gap-6">
      <Card size="sm">
        <CardHeader>
          <CardTitle>{t("Your cart")}</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-4">
          {items.map((item) => (
            <form
              key={item.variantId}
              action="/api/store/cart"
              method="post"
              className="flex flex-wrap items-center justify-between gap-3"
            >
              <input type="hidden" name="intent" value="set" />
              <input type="hidden" name="slug" value={slug} />
              <input type="hidden" name="variantId" value={item.variantId} />
              <div className="flex min-w-0 flex-col gap-1">
                <Link
                  href={`/store/${slug}/${item.productSlug}`}
                  className="text-sm font-medium hover:underline"
                >
                  {item.title}
                </Link>
                <span className="font-mono text-xs text-muted-foreground">
                  {item.sku}
                </span>
              </div>
              <div className="flex items-center gap-3">
                <StoreStockBadge stock={item.stock} />
                <span className="tabular-nums">
                  {item.amount === null ? "–" : priceText(item.amount, locale)}
                </span>
                <Button
                  type="submit"
                  name="quantity"
                  value={String((quantity.get(item.variantId) ?? 1) - 1)}
                  size="sm"
                  variant="outline"
                  aria-label={t("Remove one {title}", { title: item.title })}
                >
                  −
                </Button>
                <span className="w-6 text-center tabular-nums">
                  {quantity.get(item.variantId)}
                </span>
                <Button
                  type="submit"
                  name="quantity"
                  value={String((quantity.get(item.variantId) ?? 0) + 1)}
                  size="sm"
                  variant="outline"
                  aria-label={t("Add one {title}", { title: item.title })}
                >
                  +
                </Button>
                <Button
                  type="submit"
                  name="quantity"
                  value="0"
                  size="sm"
                  variant="ghost"
                >
                  {t("Remove")}
                </Button>
              </div>
            </form>
          ))}
        </CardContent>
      </Card>
      <Card size="sm">
        <CardContent className="flex flex-wrap items-center justify-between gap-4">
          <div className="flex flex-col gap-1">
            <span className="text-sm text-muted-foreground">{t("Total")}</span>
            <span className="text-xl font-semibold tabular-nums">
              {priceText(total.toString(), locale)}
            </span>
          </div>
          <div className="flex flex-col items-end gap-1">
            <Link
              href={`/login?next=/store/${slug}/cart`}
              className={buttonVariants({
                size: "default",
                className: blocked ? "pointer-events-none opacity-50" : "",
              })}
              aria-disabled={blocked}
            >
              {t("Sign in to check out")}
            </Link>
            <span className="text-xs text-muted-foreground">
              {blocked
                ? t("Remove the items that are out of stock to continue.")
                : t("Your cart is kept for 14 days.")}
            </span>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}

export function StoreCartViewSkeleton() {
  return (
    <div className="flex flex-col gap-6" aria-busy="true">
      <Skeleton className="h-48 rounded-xl" />
      <Skeleton className="h-20 rounded-xl" />
    </div>
  );
}
