import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.catalog.options`. */
export type CatalogSqlOptions = {
  readonly storefront?: string;
  readonly extraColumns?: ExtraColumns;
  /** Language tags the catalog translates into; the first is the default. */
  readonly locales?: readonly string[];
  /**
   * `"integer"` when the app's rank columns (options, option values, variants,
   * categories, collection products) are whole-number positions.
   */
  readonly rankType?: "text" | "integer";
};

export const catalogSqlOptions: BlockOptionsSchema<CatalogSqlOptions> =
  blockOptions<CatalogSqlOptions>({
    storefront: option.string({ default: "private" }),
    extraColumns: option.extraColumns(),
    locales: option.strings({ default: ["en"] }),
    rankType: option.string<"text" | "integer">({ default: "text" }),
  });
