import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.catalog.options`. */
export type CatalogSqlOptions = {
  readonly storefront?: string;
  readonly extraColumns?: unknown;
};

export const catalogSqlOptions: BlockOptionsSchema<CatalogSqlOptions> =
  blockOptions<CatalogSqlOptions>({
    storefront: option.string({ default: "private" }),
    extraColumns: option.unknown(),
  });
