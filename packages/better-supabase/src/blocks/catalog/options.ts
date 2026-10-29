import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.catalog.options`. */
export type CatalogSqlOptions = {
  readonly storefront?: string;
  readonly extraColumns?: ExtraColumns;
  /** App columns of the variants table, which `saveVariant` sets from `fields`. */
  readonly variantExtraColumns?: ExtraColumns;
  /**
   * App columns of the categories table, which `saveCategory` sets from
   * `fields`.
   */
  readonly categoryExtraColumns?: ExtraColumns;
  /** Language tags the catalog translates into; the first is the default. */
  readonly locales?: readonly string[];
  /**
   * `"integer"` when the app's rank columns (options, option values, variants,
   * categories, collection products) are whole-number positions.
   */
  readonly rankType?: "text" | "integer";
  /**
   * A function of the app's, `(variant uuid) returns boolean`, true while
   * something still references the variant. Removing an option value then
   * archives such a variant (with a mapped `columns.variants.status`) instead
   * of deleting it.
   */
  readonly variantInUse?: string;
  readonly maxVariants?: number;
};

export const catalogSqlOptions: BlockOptionsSchema<CatalogSqlOptions> =
  blockOptions<CatalogSqlOptions>({
    storefront: option.string({ default: "private" }),
    extraColumns: option.extraColumns(),
    variantExtraColumns: option.extraColumns(),
    categoryExtraColumns: option.extraColumns(),
    locales: option.strings({ default: ["en"] }),
    rankType: option.string<"text" | "integer">({
      default: "text",
      client: true,
    }),
    variantInUse: option.string(),
    maxVariants: option.number({ default: 100 }),
  });
