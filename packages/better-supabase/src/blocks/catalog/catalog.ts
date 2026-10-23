import type { Money } from "../../commerce/money.ts";
import type { BlockFields, FieldsOf } from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { RankNeighbors } from "../../core/rank-result.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { FilterQuery } from "../../list/filter-query.ts";
import type { BlockOptions, CursorPageOptions } from "../shared.ts";

import { money } from "../../commerce/money.ts";
import {
  blockFields,
  extraFieldsArg,
  withFields,
} from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError } from "../../core/errors.ts";
import { rankBetweenResult } from "../../core/rank-result.ts";
import { AsyncResult } from "../../core/result.ts";
import { optionalAmountText, optionalMoneyOf } from "../money-codec.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  instantArg,
  instantOf,
  isRecord,
  optionalText,
  pageOf,
  recordOf,
  recordsOf,
  textOf,
} from "../shared.ts";

export const PRODUCT_KINDS = ["physical", "digital", "service"] as const;

export type ProductKind = (typeof PRODUCT_KINDS)[number];

export const PRODUCT_STATUSES = ["draft", "active", "archived"] as const;

export type ProductStatus = (typeof PRODUCT_STATUSES)[number];

export interface CatalogOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockOptions {
  /**
   * A Standard Schema for the product columns the app adds
   * (`blocks.catalog.options.extraColumns`), keyed by column name. It validates
   * them on `createProduct` and `updateProduct`, which return a `validation`
   * error for a bad value, and types and parses them on the saved product they
   * return.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around any catalog method. */
  readonly hooks?: NoInfer<BlockHooks<Catalog<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

export interface ProductInput {
  readonly title: string;
  /**
   * Lower-case letters, digits and hyphens; derived from the title when left
   * out.
   */
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
 * A manual collection lists ranked products; a rule collection stores a filter
 * tree that the app evaluates with its list query over products.
 */
export type CollectionInput =
  | (CollectionBase & { readonly kind: "manual" })
  | (CollectionBase & { readonly kind: "rule"; readonly rule: FilterQuery });

export interface SavedCollection {
  readonly id: string;
  readonly slug: string;
  readonly kind: "manual" | "rule";
}

export interface ChannelInput {
  /** Updates this channel; creates one when left out. */
  readonly id?: string;
  /** Lower-case letters, digits and hyphens, unique per organization. */
  readonly key: string;
  readonly name: string;
  /** The ISO 4217 code the channel sells in. */
  readonly currency?: string;
  /** The price list its prices come from; base prices when left out. */
  readonly priceListId?: string;
  /** Default `true` for a new channel; an update keeps it when left out. */
  readonly active?: boolean;
}

export interface SavedChannel {
  readonly id: string;
  readonly key: string;
  readonly active: boolean;
}

export interface LocaleOptions {
  /**
   * A language tag. A locale the catalog doesn't list falls back to its
   * language, then to the default locale (`options.locales[0]`).
   */
  readonly locale?: string;
}

/** `cursor` is the `slug` of the previous page's last product. */
export interface ChannelProductsOptions
  extends LocaleOptions, CursorPageOptions<string> {}

export interface ChannelProduct {
  readonly id: string;
  readonly slug: string;
  /** `draft`, `active`, `archived`, or a state a state machine adds. */
  readonly status: string;
  readonly kind?: ProductKind;
  /** The locale the text is in. */
  readonly locale: string;
  readonly title: string;
  readonly description?: string;
  readonly listedAt: Temporal.Instant;
}

/** A product's text in one locale; a key left out falls back to the default. */
export interface ProductTranslation {
  readonly title?: string;
  readonly description?: string;
}

export interface LocalizedVariant {
  readonly id: string;
  readonly sku: string;
  readonly title?: string;
}

export interface LocalizedProduct {
  readonly id: string;
  readonly slug: string;
  readonly locale: string;
  readonly title: string;
  readonly description?: string;
  readonly variants: readonly LocalizedVariant[];
}

export interface ProductMediaInput {
  /** Shows the file for one variant of the product. */
  readonly variantId?: string;
  /** Alt text keyed by configured locale. */
  readonly alt?: Readonly<Record<string, string>>;
}

export interface SavedProductMedia {
  readonly id: string;
  readonly position: number;
}

export interface ProductMedia {
  readonly id: string;
  readonly attachmentId: string;
  readonly variantId?: string;
  /** From 0, in display order. */
  readonly position: number;
  /** The alt text in the requested locale, or the default locale's. */
  readonly alt?: string;
  readonly altByLocale: Readonly<Record<string, string>>;
}

/** `F` is the extra product fields `options.fields` describes. */
export interface Catalog<F extends object = Record<never, never>> {
  /** Keys besides the input's own are the product's extra columns. */
  createProduct(
    organizationId: string,
    input: ProductInput & Partial<F>,
  ): AsyncResult<SavedProduct & F>;
  updateProduct(
    organizationId: string,
    productId: string,
    input: ProductInput & Partial<F>,
  ): AsyncResult<SavedProduct & F>;
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
  /**
   * Sets a variant's price in the amount's currency. Emits
   * `catalog.price_changed`.
   */
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
  /**
   * Moves a category under `parentId` (null for the top level) between two
   * siblings.
   */
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
  /**
   * Adds a product to a manual collection, last or between two neighbors.
   * Resolves to its rank key.
   */
  addToCollection(
    collectionId: string,
    productId: string,
    neighbors?: RankNeighbors,
  ): AsyncResult<string>;
  removeFromCollection(
    collectionId: string,
    productId: string,
  ): AsyncResult<boolean>;
  /**
   * With `options.storefront: "public"`, anyone can read a published
   * storefront's active products.
   */
  publishStorefront(
    organizationId: string,
    published: boolean,
  ): AsyncResult<boolean>;
  /** Creates a sales channel, or updates the one `input.id` names. */
  saveChannel(
    organizationId: string,
    input: ChannelInput,
  ): AsyncResult<SavedChannel>;
  /** Deletes a channel and its listings. */
  deleteChannel(channelId: string): AsyncResult<boolean>;
  /** Lists products on a channel. Resolves to how many were new there. */
  listOnChannel(
    channelId: string,
    productIds: readonly string[],
  ): AsyncResult<number>;
  /** Takes products off a channel. Resolves to how many were listed. */
  unlistFromChannel(
    channelId: string,
    productIds: readonly string[],
  ): AsyncResult<number>;
  /** The products listed on a channel by slug, 100 a page (500 at most). */
  channelProducts(
    channelId: string,
    options?: ChannelProductsOptions,
  ): AsyncResult<readonly ChannelProduct[]>;
  /**
   * The variant's price in the channel's currency and price list; null when the
   * channel has no currency or the variant no price.
   */
  channelPrice(
    channelId: string,
    variantId: string,
    options?: { readonly at?: Temporal.Instant },
  ): AsyncResult<Price | null>;
  /**
   * Sets a product's text in a locale other than the default. An empty
   * translation removes it. Resolves to whether one is stored.
   */
  setProductTranslation(
    productId: string,
    locale: string,
    translation: ProductTranslation,
  ): AsyncResult<boolean>;
  /** Sets a variant's title in a locale; null removes the translation. */
  setVariantTranslation(
    variantId: string,
    locale: string,
    title: string | null,
  ): AsyncResult<boolean>;
  /** A product's text and its variants' titles in a locale, with fallback. */
  productText(
    productId: string,
    options?: LocaleOptions,
  ): AsyncResult<LocalizedProduct | null>;
  /**
   * Adds an attachment of the product or one of its variants to the product's
   * media, last. Needs the attachments block.
   */
  addProductMedia(
    productId: string,
    attachmentId: string,
    input?: ProductMediaInput,
  ): AsyncResult<SavedProductMedia>;
  /** Replaces a media item's variant and alt text. */
  updateProductMedia(
    mediaId: string,
    input: ProductMediaInput,
  ): AsyncResult<boolean>;
  /** Puts the product's media in this order; it lists every item once. */
  reorderProductMedia(
    productId: string,
    mediaIds: readonly string[],
  ): AsyncResult<boolean>;
  /** Removes a media item; the attachment stays. */
  removeProductMedia(mediaId: string): AsyncResult<boolean>;
  productMedia(
    productId: string,
    options?: LocaleOptions,
  ): AsyncResult<readonly ProductMedia[]>;
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
  if (!isRecord(value)) {
    return null;
  }

  const currency = textOf(value["currency"]);
  const compareAt = optionalMoneyOf(value["compareAt"], currency);
  const priceListId = optionalText(value["priceListId"]);

  return {
    id: textOf(value["id"]),
    variantId: textOf(value["variantId"]),
    amount: money(BigInt(textOf(value["amount"])), currency),
    ...(compareAt === undefined ? {} : { compareAt }),
    ...(priceListId === undefined ? {} : { priceListId }),
  };
}

function countOf(value: unknown): number {
  const count = typeof value === "number" ? value : Number(textOf(value));

  if (!Number.isInteger(count)) {
    throw new TypeError(
      `set_channel_listing returned ${JSON.stringify(value)}`,
    );
  }

  return count;
}

function textsOf(value: unknown): Readonly<Record<string, string>> {
  if (!isRecord(value)) {
    return {};
  }

  return Object.fromEntries(
    Object.entries(value).flatMap(([key, entry]) =>
      typeof entry === "string" ? [[key, entry]] : [],
    ),
  );
}

function channelProductOf(row: Record<string, unknown>): ChannelProduct {
  const description = optionalText(row["description"]);

  const kind =
    row["kind"] === null || row["kind"] === undefined
      ? undefined
      : enumOrThrow(row["kind"], PRODUCT_KINDS, "product kind");

  return {
    id: textOf(row["id"]),
    slug: textOf(row["slug"]),
    status: textOf(row["status"]),
    ...(kind === undefined ? {} : { kind }),
    locale: textOf(row["locale"]),
    title: textOf(row["title"]),
    ...(description === undefined ? {} : { description }),
    listedAt: instantOf(row["listedAt"]),
  };
}

function localizedOf(value: unknown): LocalizedProduct | null {
  if (!isRecord(value)) {
    return null;
  }

  const description = optionalText(value["description"]);

  return {
    id: textOf(value["id"]),
    slug: textOf(value["slug"]),
    locale: textOf(value["locale"]),
    title: textOf(value["title"]),
    ...(description === undefined ? {} : { description }),
    variants: recordsOf(value["variants"], "product_text").map((entry) => {
      const title = optionalText(entry["title"]);

      return {
        id: textOf(entry["id"]),
        sku: textOf(entry["sku"]),
        ...(title === undefined ? {} : { title }),
      };
    }),
  };
}

function mediaOf(row: Record<string, unknown>): ProductMedia {
  const variantId = optionalText(row["variantId"]);
  const alt = optionalText(row["alt"]);

  return {
    id: textOf(row["id"]),
    attachmentId: textOf(row["attachmentId"]),
    ...(variantId === undefined ? {} : { variantId }),
    position: Number(row["position"]),
    ...(alt === undefined ? {} : { alt }),
    altByLocale: textsOf(row["altByLocale"]),
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

/**
 * Products, variants, prices, categories, collections, sales channels,
 * translations and product media over the `catalog` SQL module.
 */
export function createCatalog<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: CatalogOptions<S>): Catalog<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const fields: BlockFields<F> = blockFields(options.fields, "product fields");

  const saveProduct = (
    organizationId: string,
    productId: string | null,
    { title, slug, description, kind, ...extra }: ProductInput,
  ): AsyncResult<SavedProduct & F> =>
    AsyncResult.from(() => extraFieldsArg(fields, extra))
      .andThen((more) =>
        call(
          "save_product",
          {
            tenant: organizationId,
            product: productId,
            title,
            slug: slug ?? null,
            description: description ?? null,
            kind: kind ?? null,
            ...more,
          },
          (value) => value,
        ),
      )
      .andThen((value) => withFields(fields, value, productOf(value)));

  const catalog: Catalog<F> = {
    createProduct: (organizationId, input) =>
      saveProduct(organizationId, null, input),
    updateProduct: (organizationId, productId, input) =>
      saveProduct(organizationId, productId, input),
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

      if (!key.ok) {
        return AsyncResult.err(key.error);
      }

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
          amount: optionalAmountText(input.amount),
          compare_at: optionalAmountText(input.compareAt),
          price_list: input.priceListId ?? null,
          valid_from: instantArg(input.validFrom) ?? null,
          valid_until: instantArg(input.validUntil) ?? null,
        },
        (value) => {
          const row = recordOf(value, "set_price");

          const previousAmount = optionalMoneyOf(
            row["previousAmount"],
            currency,
          );

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

      if (!key.ok) {
        return AsyncResult.err(key.error);
      }

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

      if (neighbors === undefined) {
        return add(null);
      }

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
    saveChannel: (organizationId, input) =>
      call(
        "save_catalog_channel",
        {
          tenant: organizationId,
          channel: input.id ?? null,
          key: input.key,
          name: input.name,
          currency: input.currency ?? null,
          price_list: input.priceListId ?? null,
          active: input.active ?? null,
        },
        (value) => {
          const row = recordOf(value, "save_catalog_channel");

          return {
            id: textOf(row["id"]),
            key: textOf(row["key"]),
            active: row["active"] === true,
          };
        },
      ),
    deleteChannel: (channelId) =>
      call(
        "delete_catalog_channel",
        { channel: channelId },
        (value) => value === true,
      ),
    listOnChannel: (channelId, productIds) =>
      call(
        "set_channel_listing",
        { channel: channelId, products: productIds, listed: true },
        countOf,
      ),
    unlistFromChannel: (channelId, productIds) =>
      call(
        "set_channel_listing",
        { channel: channelId, products: productIds, listed: false },
        countOf,
      ),
    channelProducts: (channelId, listOptions = {}) => {
      const { limit, cursor } = pageOf(listOptions);

      return call(
        "channel_products",
        {
          channel: channelId,
          locale: listOptions.locale ?? null,
          page_size: limit ?? null,
          after: cursor ?? null,
        },
        (value) => recordsOf(value, "channel_products").map(channelProductOf),
      );
    },
    channelPrice: (channelId, variantId, priceOptions = {}) =>
      call(
        "channel_price",
        {
          channel: channelId,
          variant: variantId,
          as_of: instantArg(priceOptions.at) ?? null,
        },
        priceOf,
      ),
    setProductTranslation: (productId, locale, translation) =>
      call(
        "set_product_translation",
        {
          product: productId,
          locale,
          title: translation.title ?? null,
          description: translation.description ?? null,
        },
        (value) => value === true,
      ),
    setVariantTranslation: (variantId, locale, title) =>
      call(
        "set_variant_translation",
        { variant: variantId, locale, title },
        (value) => value === true,
      ),
    productText: (productId, textOptions = {}) =>
      call(
        "product_text",
        { product: productId, locale: textOptions.locale ?? null },
        localizedOf,
      ),
    addProductMedia: (productId, attachmentId, input = {}) =>
      call(
        "add_product_media",
        {
          product: productId,
          attachment: attachmentId,
          variant: input.variantId ?? null,
          alt: input.alt ?? null,
        },
        (value) => {
          const row = recordOf(value, "add_product_media");

          return { id: textOf(row["id"]), position: Number(row["position"]) };
        },
      ),
    updateProductMedia: (mediaId, input) =>
      call(
        "update_product_media",
        {
          media: mediaId,
          variant: input.variantId ?? null,
          alt: input.alt ?? null,
        },
        (value) => value === true,
      ),
    reorderProductMedia: (productId, mediaIds) =>
      call(
        "reorder_product_media",
        { product: productId, media: mediaIds },
        (value) => value === true,
      ),
    removeProductMedia: (mediaId) =>
      call(
        "remove_product_media",
        { media: mediaId },
        (value) => value === true,
      ),
    productMedia: (productId, mediaOptions = {}) =>
      call(
        "product_media",
        { product: productId, locale: mediaOptions.locale ?? null },
        (value) => recordsOf(value, "product_media").map(mediaOf),
      ),
  };

  return withBlockHooks(catalog, options.hooks, {
    block: "catalog",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
