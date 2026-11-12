import { PackageIcon } from "lucide-react";
import { getExtracted, getLocale } from "next-intl/server";
import { notFound } from "next/navigation";

import { Badge } from "@/components/reui/badge";
import { buttonVariants } from "@/components/ui/button";
import {
  Card,
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
import { settle } from "@/features/status/status-queries";
import { Link } from "@/i18n/navigation";

import type { StoreProductCard, StoreQuery } from "../store-queries";

import { getStoreCatalog } from "../store-queries";
import { STORE_SORTS } from "../store-sorts";
import { StoreLoadError } from "./store-load-error";
import { priceText } from "./store-price";
import { StoreSearch } from "./store-search";
import { StoreStockBadge } from "./store-stock-badge";

type RawParams = Readonly<Record<string, string | string[] | undefined>>;

const first = (value: string | string[] | undefined): string =>
  (Array.isArray(value) ? value[0] : value) ?? "";

/** The URL's `?q=&sort=&stock=` as a catalog query; anything unknown is ignored. */
function parseStoreQuery(raw: RawParams): StoreQuery {
  const sort = STORE_SORTS.find(
    (candidate) => candidate === first(raw["sort"]),
  );

  return {
    q: first(raw["q"]).trim().slice(0, 100),
    sort: sort ?? "newest",
    inStock: first(raw["stock"]) === "true",
  };
}

async function ProductCard({
  slug,
  product,
}: {
  slug: string;
  product: StoreProductCard;
}) {
  const locale = await getLocale();
  const t = await getExtracted("store");

  return (
    <Card size="sm">
      <CardHeader>
        <CardTitle>
          <Link
            href={`/store/${slug}/${product.slug}`}
            className="hover:underline"
          >
            {product.title}
          </Link>
        </CardTitle>
        <CardDescription className="line-clamp-2">
          {product.description ?? ""}
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        <div className="flex items-baseline gap-2">
          <span className="text-lg font-semibold tabular-nums">
            {product.amount === null
              ? t("Ask for a price")
              : priceText(product.amount, locale)}
          </span>
          {product.compareAt === null ? null : (
            <span className="text-sm text-muted-foreground tabular-nums line-through">
              {priceText(product.compareAt, locale)}
            </span>
          )}
        </div>
        <div className="flex items-center gap-2">
          <StoreStockBadge stock={product.stock} />
          {product.kind === "digital" ? (
            <Badge variant="outline">{t("Digital")}</Badge>
          ) : null}
        </div>
      </CardContent>
    </Card>
  );
}

/**
 * Render inside `<Suspense>`: the store's published products for the search,
 * sort and stock filter in the URL.
 */
export async function StoreCatalog({
  slug,
  urlQuery,
}: {
  slug: string;
  urlQuery: Promise<RawParams>;
}) {
  const [t, raw] = await Promise.all([getExtracted("store"), urlQuery]);
  const query = parseStoreQuery(raw);
  const catalog = await settle(() => getStoreCatalog(slug, query));

  if (catalog.kind === "missing") {
    notFound();
  }

  if (catalog.kind === "error") {
    return <StoreLoadError title={t("The store didn't load")} />;
  }

  const { store, products } = catalog.data;
  const filtered = query.q !== "" || query.inStock;

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-1">
        <h1 className="text-2xl font-semibold tracking-tight">{store.name}</h1>
        <p className="text-sm text-muted-foreground">
          {t("Browse the catalog and keep what you like in your cart.")}
        </p>
      </div>
      <StoreSearch />
      {products.length === 0 ? (
        <Empty className="border">
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <PackageIcon />
            </EmptyMedia>
            <EmptyTitle>{t("No products found")}</EmptyTitle>
            <EmptyDescription>
              {filtered
                ? t("Nothing matches the search or the filter.")
                : t("This store has no products yet.")}
            </EmptyDescription>
          </EmptyHeader>
          {filtered ? (
            <EmptyContent>
              <Link
                href={`/store/${slug}`}
                className={buttonVariants({ size: "sm", variant: "outline" })}
              >
                {t("Clear the search")}
              </Link>
            </EmptyContent>
          ) : null}
        </Empty>
      ) : (
        <div className="grid gap-4 sm:grid-cols-2">
          {products.map((product) => (
            <ProductCard key={product.id} slug={slug} product={product} />
          ))}
        </div>
      )}
    </div>
  );
}

export function StoreCatalogSkeleton() {
  return (
    <div className="flex flex-col gap-6" aria-busy="true">
      <Skeleton className="h-10 w-64" />
      <Skeleton className="h-9 w-full max-w-sm" />
      <div className="grid gap-4 sm:grid-cols-2">
        <Skeleton className="h-40 rounded-xl" />
        <Skeleton className="h-40 rounded-xl" />
        <Skeleton className="h-40 rounded-xl" />
        <Skeleton className="h-40 rounded-xl" />
      </div>
    </div>
  );
}
