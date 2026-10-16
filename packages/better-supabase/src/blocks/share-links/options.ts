import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.share-links.options`. */
export type ShareLinksSqlOptions = {
  readonly subjects?: unknown;
  readonly extraColumns?: unknown;
};

export const shareLinksSqlOptions: BlockOptionsSchema<ShareLinksSqlOptions> =
  blockOptions<ShareLinksSqlOptions>({
    subjects: option.unknown(),
    extraColumns: option.unknown(),
  });
