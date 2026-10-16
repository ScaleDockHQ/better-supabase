import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.collections.options`. */
export type CollectionsSqlOptions = {
  readonly extraColumns?: unknown;
};

export const collectionsSqlOptions: BlockOptionsSchema<CollectionsSqlOptions> =
  blockOptions<CollectionsSqlOptions>({
    extraColumns: option.unknown(),
  });
