import type { SubjectsConfig } from "../../config/types/subjects.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { RankNeighbors } from "../../core/rank-result.ts";
import type { FilterQuery } from "../../list/filter-query.ts";
import type { BlockOptions } from "../shared.ts";

import { DEFAULT_BLOCK_SCHEMA } from "../../core/block-helpers.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError } from "../../core/errors.ts";
import { rankBetweenResult } from "../../core/rank-result.ts";
import { AsyncResult } from "../../core/result.ts";
import { type Money, money } from "../commerce/money.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  instantArg,
  isRecord,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
} from "../shared.ts";

export const PRODUCT_KINDS = ["physical", "digital", "service"] as const;
export type ProductKind = (typeof PRODUCT_KINDS)[number];

export const PRODUCT_STATUSES = ["draft", "active", "archived"] as const;
export type ProductStatus = (typeof PRODUCT_STATUSES)[number];

export interface CatalogOptions extends BlockOptions {
  /** `withBlockHooks` hooks around any catalog method. */
  readonly hooks?: NoInfer<BlockHooks<Catalog>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

export interface ProductInput {
  readonly title: string;
  /** Lower-case letters, digits and hyphens; derived from the title when left out. */
  readonly slug?: string;
  readonly description?: string;
  /** Default `physical`. */
  readonly kind?: ProductKind;
}

export interface SavedProduct {
  readonly id: string;
  readonly slug: string;
  readonly status: ProductStatus;
}

export interface StatusChange {
  readonly status: ProductStatus;
  readonly from: ProductStatus;
}

export interface OptionInput {
  /** Updates this option; creates one when left out. */
  readonly id?: string;
  readonly name: string;
  /** The values in display order. Values left out are removed. */
  readonly values: readonly string[];
}

export interface OptionValue {
  readonly id: string;
  readonly value: string;
}

export interface SavedOption {
  readonly id: string;
  readonly values: readonly OptionValue[];
}

export interface VariantInput {
  readonly sku: string;
  /** One option value id per product option. */
  readonly optionValues?: readonly string[];
  readonly title?: string;
  readonly barcode?: string;
  readonly weightGrams?: number;
  /** Whether inventory counts stock for it. Default `true`. */
  readonly trackInventory?: boolean;
  /** Whether it sells with no stock available. Default `false`. */
  readonly allowBackorder?: boolean;
}

export interface SavedVariant {
  readonly id: string;
  readonly sku: string;
  /** Its rank key among the product's variants. */
  readonly rank: string;
}

export interface PriceListInput {
  readonly id?: string;
  readonly name: string;
  /** The customers it is for, such as a B2B tier. */
  readonly customerGroup?: string;
}

export interface PriceInput {
  readonly amount: Money;
  /** The price before a discount, shown struck through; above `amount`. */
  readonly compareAt?: Money;
  /** A price list's price; the base price when left out. */
  readonly priceListId?: string;
  readonly validFrom?: Temporal.Instant;
  readonly validUntil?: Temporal.Instant;
}

export interface SavedPrice {
  readonly id: string;
  readonly amount: Money;
  /** The amount before this change, when the price existed. */
  readonly previousAmount?: Money;
}

export interface Price {
  readonly id: string;
  readonly variantId: string;
  readonly amount: Money;
  readonly compareAt?: Money;
  /** Set when the price came from a price list rather than the base price. */
  readonly priceListId?: string;
}

export interface VariantPriceOptions {
  readonly priceListId?: string;
  /** Default: now. */
  readonly at?: Temporal.Instant;
}

export interface CategoryInput {
  readonly id?: string;
  /** The parent category; the top level when left out. */
  readonly parentId?: string;
  readonly name: string;
  readonly slug?: string;
  readonly description?: string;
}

export interface SavedCategory {
  readonly id: string;
  readonly slug: string;
  readonly rank: string;
}

interface CollectionBase {
  readonly id?: string;
  readonly title: string;
  readonly slug?: string;
}

/**
 * A manual collection lists ranked products; a rule collection stores a
 * filter tree that the app evaluates with its list query over products.
 */
export type CollectionInput =
  | (CollectionBase & { readonly kind: "manual" })
  | (CollectionBase & { readonly kind: "rule"; readonly rule: FilterQuery });

export interface SavedCollection {
  readonly id: string;
  readonly slug: string;
  readonly kind: "manual" | "rule";
}

export interface Catalog {
  createProduct(
    organizationId: string,
    input: ProductInput,
  ): AsyncResult<SavedProduct>;
  updateProduct(
    organizationId: string,
    productId: string,
    input: ProductInput,
  ): AsyncResult<SavedProduct>;
  /** Moves a product between `draft`, `active` and `archived`. */
  setProductStatus(
    productId: string,
    status: ProductStatus,
  ): AsyncResult<StatusChange>;
  deleteProduct(productId: string): AsyncResult<boolean>;
  saveOption(productId: string, input: OptionInput): AsyncResult<SavedOption>;
  deleteOption(optionId: string): AsyncResult<boolean>;
  createVariant(
    productId: string,
    input: VariantInput,
  ): AsyncResult<SavedVariant>;
  updateVariant(
    productId: string,
    variantId: string,
    input: VariantInput,
  ): AsyncResult<SavedVariant>;
  /** Moves a variant between the variants with rank keys `previous` and `next`. */
  reorderVariant(
    variantId: string,
    neighbors: RankNeighbors,
  ): AsyncResult<string>;
  deleteVariant(variantId: string): AsyncResult<boolean>;
  savePriceList(
    organizationId: string,
    input: PriceListInput,
  ): AsyncResult<{ readonly id: string }>;
  deletePriceList(priceListId: string): AsyncResult<boolean>;
  /** Sets a variant's price in the amount's currency. Emits `catalog.price_changed`. */
  setPrice(variantId: string, input: PriceInput): AsyncResult<SavedPrice>;
  deletePrice(priceId: string): AsyncResult<boolean>;
  /** The price list's price when it has one, otherwise the base price. */
  variantPrice(
    variantId: string,
    currency: string,
    options?: VariantPriceOptions,
  ): AsyncResult<Price | null>;
  saveCategory(
    organizationId: string,
    input: CategoryInput,
  ): AsyncResult<SavedCategory>;
  /** Moves a category under `parentId` (null for the top level) between two siblings. */
  moveCategory(
    categoryId: string,
    parentId: string | null,
    neighbors: RankNeighbors,
  ): AsyncResult<string>;
  deleteCategory(categoryId: string): AsyncResult<boolean>;
  setProductCategories(
    productId: string,
    categoryIds: readonly string[],
  ): AsyncResult<boolean>;
  saveCollection(
    organizationId: string,
    input: CollectionInput,
  ): AsyncResult<SavedCollection>;
  deleteCollection(collectionId: string): AsyncResult<boolean>;
  /** Adds a product to a manual collection, last or between two neighbors. Resolves to its rank key. */
  addToCollection(
    collectionId: string,
    productId: string,
    neighbors?: RankNeighbors,
  ): AsyncResult<string>;
  removeFromCollection(
    collectionId: string,
    productId: string,
  ): AsyncResult<boolean>;
  /** With `options.storefront: "public"`, anyone can read a published storefront's active products. */
  publishStorefront(
    organizationId: string,
    published: boolean,
  ): AsyncResult<boolean>;
}

const minor = (value: Money | undefined): string | null =>
  value === undefined ? null : value.amount.toString();

function moneyOf(value: unknown, currency: string): Money | undefined {
  const amount = optionalText(value);
  return amount === undefined ? undefined : money(BigInt(amount), currency);
}

function productOf(value: unknown): SavedProduct {
  const row = recordOf(value, "save_product");
  return {
    id: textOf(row["id"]),
    slug: textOf(row["slug"]),
    status: enumOrThrow(row["status"], PRODUCT_STATUSES, "product status"),
  };
}

function variantOf(value: unknown): SavedVariant {
  const row = recordOf(value, "save_variant");
  return {
    id: textOf(row["id"]),
    sku: textOf(row["sku"]),
    rank: textOf(row["rank"]),
  };
}

function priceOf(value: unknown): Price | null {
  if (!isRecord(value)) return null;
  const currency = textOf(value["currency"]);
  const compareAt = moneyOf(value["compareAt"], currency);
  const priceListId = optionalText(value["priceListId"]);
  return {
    id: textOf(value["id"]),
    variantId: textOf(value["variantId"]),
    amount: money(BigInt(textOf(value["amount"])), currency),
    ...(compareAt === undefined ? {} : { compareAt }),
    ...(priceListId === undefined ? {} : { priceListId }),
  };
}

function variantArgs(
  productId: string,
  variantId: string | null,
  input: VariantInput,
): Record<string, unknown> {
  return {
    product: productId,
    variant: variantId,
    sku: input.sku,
    option_values: input.optionValues ?? null,
    title: input.title ?? null,
    barcode: input.barcode ?? null,
    weight_grams: input.weightGrams ?? null,
    track_inventory: input.trackInventory ?? null,
    allow_backorder: input.allowBackorder ?? null,
  };
}

function productArgs(
  organizationId: string,
  productId: string | null,
  input: ProductInput,
): Record<string, unknown> {
  return {
    tenant: organizationId,
    product: productId,
    title: input.title,
    slug: input.slug ?? null,
    description: input.description ?? null,
    kind: input.kind ?? null,
  };
}

/** Products, variants, prices, categories and collections over the `catalog` SQL module. */
export function createCatalog(options: CatalogOptions): Catalog {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const catalog: Catalog = {
    createProduct: (organizationId, input) =>
      call("save_product", productArgs(organizationId, null, input), productOf),
    updateProduct: (organizationId, productId, input) =>
      call(
        "save_product",
        productArgs(organizationId, productId, input),
        productOf,
      ),
    setProductStatus: (productId, status) =>
      call("set_product_status", { product: productId, status }, (value) => {
        const row = recordOf(value, "set_product_status");
        return {
          status: enumOrThrow(row["status"], PRODUCT_STATUSES, "status"),
          from: enumOrThrow(row["from"], PRODUCT_STATUSES, "status"),
        };
      }),
    deleteProduct: (productId) =>
      call("delete_product", { product: productId }, (value) => value === true),
    saveOption: (productId, input) =>
      call(
        "save_product_option",
        {
          product: productId,
          option: input.id ?? null,
          name: input.name,
          option_values: input.values,
        },
        (value) => {
          const row = recordOf(value, "save_product_option");
          return {
            id: textOf(row["id"]),
            values: recordsOf(row["values"], "save_product_option").map(
              (entry) => ({
                id: textOf(entry["id"]),
                value: textOf(entry["value"]),
              }),
            ),
          };
        },
      ),
    deleteOption: (optionId) =>
      call(
        "delete_product_option",
        { option: optionId },
        (value) => value === true,
      ),
    createVariant: (productId, input) =>
      call("save_variant", variantArgs(productId, null, input), variantOf),
    updateVariant: (productId, variantId, input) =>
      call("save_variant", variantArgs(productId, variantId, input), variantOf),
    reorderVariant: (variantId, neighbors) => {
      const key = rankBetweenResult(neighbors);
      if (!key.ok) return AsyncResult.err(key.error);
      return call(
        "rank_variant",
        { variant: variantId, rank: key.data },
        () => key.data,
      );
    },
    deleteVariant: (variantId) =>
      call("delete_variant", { variant: variantId }, (value) => value === true),
    savePriceList: (organizationId, input) =>
      call(
        "save_price_list",
        {
          tenant: organizationId,
          price_list: input.id ?? null,
          name: input.name,
          customer_group: input.customerGroup ?? null,
        },
        (value) => ({ id: textOf(recordOf(value, "save_price_list")["id"]) }),
      ),
    deletePriceList: (priceListId) =>
      call(
        "delete_price_list",
        { price_list: priceListId },
        (value) => value === true,
      ),
    setPrice: (variantId, input) => {
      const { currency } = input.amount;
      if (
        input.compareAt !== undefined &&
        input.compareAt.currency !== currency
      ) {
        return AsyncResult.err(
          dbError(
            "invalid_request",
            `compareAt is in ${input.compareAt.currency}, the amount in ${currency}`,
            { hint: "CATALOG_COMPARE_AT_INVALID" },
          ),
        );
      }
      return call(
        "set_price",
        {
          variant: variantId,
          currency,
          amount: minor(input.amount),
          compare_at: minor(input.compareAt),
          price_list: input.priceListId ?? null,
          valid_from: instantArg(input.validFrom) ?? null,
          valid_until: instantArg(input.validUntil) ?? null,
        },
        (value) => {
          const row = recordOf(value, "set_price");
          const previousAmount = moneyOf(row["previousAmount"], currency);
          return {
            id: textOf(row["id"]),
            amount: money(BigInt(textOf(row["amount"])), currency),
            ...(previousAmount === undefined ? {} : { previousAmount }),
          };
        },
      );
    },
    deletePrice: (priceId) =>
      call("delete_price", { price: priceId }, (value) => value === true),
    variantPrice: (variantId, currency, priceOptions = {}) =>
      call(
        "variant_price",
        {
          variant: variantId,
          currency,
          price_list: priceOptions.priceListId ?? null,
          as_of: instantArg(priceOptions.at) ?? null,
        },
        priceOf,
      ),
    saveCategory: (organizationId, input) =>
      call(
        "save_category",
        {
          tenant: organizationId,
          category: input.id ?? null,
          parent: input.parentId ?? null,
          name: input.name,
          slug: input.slug ?? null,
          description: input.description ?? null,
        },
        (value) => {
          const row = recordOf(value, "save_category");
          return {
            id: textOf(row["id"]),
            slug: textOf(row["slug"]),
            rank: textOf(row["rank"]),
          };
        },
      ),
    moveCategory: (categoryId, parentId, neighbors) => {
      const key = rankBetweenResult(neighbors);
      if (!key.ok) return AsyncResult.err(key.error);
      return call(
        "move_category",
        { category: categoryId, parent: parentId, rank: key.data },
        () => key.data,
      );
    },
    deleteCategory: (categoryId) =>
      call(
        "delete_category",
        { category: categoryId },
        (value) => value === true,
      ),
    setProductCategories: (productId, categoryIds) =>
      call(
        "set_product_categories",
        { product: productId, categories: categoryIds },
        (value) => value === true,
      ),
    saveCollection: (organizationId, input) =>
      call(
        "save_collection",
        {
          tenant: organizationId,
          collection: input.id ?? null,
          title: input.title,
          slug: input.slug ?? null,
          kind: input.kind,
          rule: input.kind === "rule" ? input.rule : null,
        },
        (value) => {
          const row = recordOf(value, "save_collection");
          return {
            id: textOf(row["id"]),
            slug: textOf(row["slug"]),
            kind: enumOrThrow(row["kind"], ["manual", "rule"], "kind"),
          };
        },
      ),
    deleteCollection: (collectionId) =>
      call(
        "delete_collection",
        { collection: collectionId },
        (value) => value === true,
      ),
    addToCollection: (collectionId, productId, neighbors) => {
      const add = (rank: string | null): AsyncResult<string> =>
        call(
          "add_to_collection",
          { collection: collectionId, product: productId, rank },
          textOf,
        );
      if (neighbors === undefined) return add(null);
      const key = rankBetweenResult(neighbors);
      return key.ok ? add(key.data) : AsyncResult.err(key.error);
    },
    removeFromCollection: (collectionId, productId) =>
      call(
        "remove_from_collection",
        { collection: collectionId, product: productId },
        (value) => value === true,
      ),
    publishStorefront: (organizationId, published) =>
      call(
        "publish_storefront",
        { tenant: organizationId, published },
        (value) => value === true,
      ),
  };
  return withBlockHooks(catalog, options.hooks, {
    block: "catalog",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}

export interface CatalogSubjectsOptions {
  /** The catalog module's schema. Default `better_supabase`. */
  readonly schema?: string;
  /** The product page path, with `{column}` placeholders. Default `/products/{slug}`. */
  readonly productUrl?: string;
}

/**
 * `config.subjects` entries for products and variants, so comments, tags,
 * watchers and the search index attach to them:
 * `subjects: { ...catalogSubjects(), task: { ... } }`.
 */
export function catalogSubjects(
  subjectOptions: CatalogSubjectsOptions = {},
): SubjectsConfig {
  const schema = subjectOptions.schema ?? DEFAULT_BLOCK_SCHEMA;
  const permissions = { read: "catalog.read", write: "catalog.manage" };
  return {
    product: {
      table: `${schema}.products`,
      idType: "uuid",
      tenant: "tenant_id",
      title: "title",
      url: subjectOptions.productUrl ?? "/products/{slug}",
      permissions,
      cascade: true,
      search: { title: "title", body: ["description", "slug"] },
    },
    product_variant: {
      table: `${schema}.product_variants`,
      idType: "uuid",
      tenant: "tenant_id",
      title: "sku",
      permissions,
      cascade: true,
      search: { title: "sku", body: ["title", "barcode"] },
    },
  };
}
