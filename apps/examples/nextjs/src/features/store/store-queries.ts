import "server-only";
import { cacheTag } from "next/cache";
import * as v from "valibot";

import { SHOP_CURRENCY } from "@/features/shop/shop-currency";
import { bsb } from "@/lib/supabase/server";

import type { StoreSort } from "./store-sorts";

import { STORE_TAG } from "./store-cache";

const MinorUnits = v.pipe(v.string(), v.regex(/^-?\d+$/));

export const STORE_STOCK = ["in_stock", "low", "out"] as const;

export type StoreStock = (typeof STORE_STOCK)[number];

const StoreName = v.object({ name: v.string(), slug: v.string() });

const CatalogProduct = v.object({
  id: v.string(),
  slug: v.string(),
  title: v.string(),
  description: v.nullable(v.string()),
  kind: v.string(),
  variantId: v.string(),
  sku: v.string(),
  amount: v.nullable(MinorUnits),
  compareAt: v.nullable(MinorUnits),
  stock: v.picklist(STORE_STOCK),
});

const Catalog = v.nullable(
  v.object({ store: StoreName, products: v.array(CatalogProduct) }),
);

export type StoreCatalog = NonNullable<v.InferOutput<typeof Catalog>>;

export type StoreProductCard = StoreCatalog["products"][number];

export interface StoreQuery {
  readonly q: string;
  readonly sort: StoreSort;
  readonly inStock: boolean;
}

/**
 * The published products of one organization's store, searched and sorted in
 * the database by `api.public_store_catalog`. It works signed out and returns
 * only public fields; `null` means the store does not exist or is unpublished.
 */
export async function getStoreCatalog(
  slug: string,
  query: StoreQuery,
): Promise<StoreCatalog | null> {
  "use cache: private";
  const { db } = await bsb.cached();
  cacheTag(STORE_TAG);

  return db
    .$api(
      "public_store_catalog",
      {
        org_slug: slug,
        q: query.q === "" ? null : query.q,
        sort: query.sort,
        only_in_stock: query.inStock,
        currency: SHOP_CURRENCY,
      },
      { returns: Catalog },
    )
    .orThrow();
}

const ProductVariant = v.object({
  id: v.string(),
  sku: v.string(),
  title: v.nullable(v.string()),
  amount: v.nullable(MinorUnits),
  compareAt: v.nullable(MinorUnits),
  stock: v.picklist(STORE_STOCK),
});

const ProductPage = v.nullable(
  v.object({
    store: StoreName,
    product: v.object({
      id: v.string(),
      slug: v.string(),
      title: v.string(),
      description: v.nullable(v.string()),
      kind: v.string(),
      manufacturer: v.nullable(v.string()),
      model: v.nullable(v.string()),
      variants: v.array(ProductVariant),
    }),
  }),
);

export type StoreProductPage = NonNullable<v.InferOutput<typeof ProductPage>>;

/** One published product with its variants, prices and stock buckets. */
export async function getStoreProduct(
  slug: string,
  productSlug: string,
): Promise<StoreProductPage | null> {
  "use cache: private";
  const { db } = await bsb.cached();
  cacheTag(STORE_TAG);

  return db
    .$api(
      "public_store_product",
      { org_slug: slug, product_slug: productSlug, currency: SHOP_CURRENCY },
      { returns: ProductPage },
    )
    .orThrow();
}

const CartVariant = v.object({
  variantId: v.string(),
  productSlug: v.string(),
  title: v.string(),
  variantTitle: v.nullable(v.string()),
  sku: v.string(),
  amount: v.nullable(MinorUnits),
  stock: v.picklist(STORE_STOCK),
});

export type StoreCartVariant = v.InferOutput<typeof CartVariant>;

/** The variants in a visitor's cart with their current price and stock. */
export async function getStoreVariants(
  slug: string,
  variantIds: readonly string[],
): Promise<readonly StoreCartVariant[]> {
  "use cache: private";
  const { db } = await bsb.cached();
  cacheTag(STORE_TAG);

  if (variantIds.length === 0) {
    return [];
  }

  return db
    .$api(
      "public_store_variants",
      { org_slug: slug, variant_ids: [...variantIds], currency: SHOP_CURRENCY },
      { returns: v.array(CartVariant) },
    )
    .orThrow();
}
