import { formatMoney } from "better-supabase/commerce";
import { PackageIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted, getLocale } from "next-intl/server";
import { refresh } from "next/cache";
import { forbidden } from "next/navigation";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardAction,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import type { Product } from "../shop-queries";

import { getProducts } from "../shop-queries";
import { CreateProductDialog } from "./create-product-dialog";
import { CreatePromotionCodeDialog } from "./promotion-code-field";

// #region recipe:product-catalog-grid
// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

/** Render inside `<Suspense>`: the organization's products as cards. */
export async function ProductCatalogGrid() {
  // The read starts with the permission check; RLS guards it either way.
  const [permissions, products, t, locale] = await Promise.all([
    getPermissions(),
    getProducts(),
    getExtracted("shop"),
    getLocale(),
  ]);

  if (!can(permissions, "catalog.read")) {
    forbidden();
  }

  if (products.kind === "no-organization") {
    return null;
  }

  const canManage = can(permissions, "catalog.manage");

  const status = (product: Product) => {
    switch (product.status) {
      case "active": {
        return <Badge variant="success-light">{t("Active")}</Badge>;
      }

      case "draft": {
        return <Badge variant="secondary">{t("Draft")}</Badge>;
      }

      case "archived": {
        return <Badge variant="warning-light">{t("Archived")}</Badge>;
      }

      default: {
        const unknown: never = product.status;

        return unknown;
      }
    }
  };

  return (
    <div data-recipe="product-catalog-grid" className="flex flex-col gap-4">
      {products.kind === "error" ? (
        <Alert variant="destructive">
          <TriangleAlertIcon />
          <AlertTitle>{t("The products didn't load")}</AlertTitle>
          <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
          <AlertAction>
            <form action={retry}>
              <Button size="sm" variant="outline" type="submit">
                {t("Retry")}
              </Button>
            </form>
          </AlertAction>
        </Alert>
      ) : products.data.length === 0 ? (
        <Empty className="border">
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <PackageIcon />
            </EmptyMedia>
            <EmptyTitle>{t("No products yet")}</EmptyTitle>
            <EmptyDescription>
              {t("Add a product with a price to start taking orders.")}
            </EmptyDescription>
          </EmptyHeader>
          {canManage ? (
            <EmptyContent>
              <CreateProductDialog />
            </EmptyContent>
          ) : null}
        </Empty>
      ) : (
        <>
          <div className="flex items-center justify-between gap-2">
            <p className="text-sm text-muted-foreground">
              {t("{count, plural, one {# product} other {# products}}", {
                count: products.data.length,
              })}
            </p>
            <div className="flex items-center gap-2">
              {can(permissions, "promotions.manage") ? (
                <CreatePromotionCodeDialog />
              ) : null}
              {canManage ? <CreateProductDialog variant="outline" /> : null}
            </div>
          </div>
          <ul className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
            {products.data.map((product) => (
              <li key={product.id}>
                <Card>
                  <CardHeader>
                    <CardTitle>{product.title}</CardTitle>
                    <CardDescription className="font-mono">
                      {product.sku}
                    </CardDescription>
                    <CardAction>{status(product)}</CardAction>
                  </CardHeader>
                  <CardContent className="flex items-end justify-between gap-2">
                    <span className="text-sm font-semibold tabular-nums">
                      {product.price
                        ? formatMoney(product.price, locale)
                        : t("No price")}
                    </span>
                    <span className="text-xs text-muted-foreground">
                      {product.available === null
                        ? t("Not stocked")
                        : t("{count, number} available", {
                            count: product.available,
                          })}
                    </span>
                  </CardContent>
                </Card>
              </li>
            ))}
          </ul>
        </>
      )}
    </div>
  );
}
// #endregion recipe:product-catalog-grid

export function ProductCatalogGridSkeleton() {
  return (
    <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3" aria-busy="true">
      <Skeleton className="h-32 rounded-xl" />
      <Skeleton className="h-32 rounded-xl" />
      <Skeleton className="h-32 rounded-xl" />
    </div>
  );
}
