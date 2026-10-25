import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.catalog.options`. */
export type CatalogSqlOptions = {
  readonly storefront?: string;
  readonly extraColumns?: ExtraColumns;
  /** Language tags the catalog translates into; the first is the default. */
  readonly locales?: readonly string[];
};

export const catalogSqlOptions: BlockOptionsSchema<CatalogSqlOptions> =
  blockOptions<CatalogSqlOptions>({
    storefront: option.string({ default: "private" }),
    extraColumns: option.extraColumns(),
    locales: option.strings({ default: ["en"] }),
  });
