import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.share-links.options`. */
export type ShareLinksSqlOptions = {
  /**
   * `create_share_link` takes a `token_hash` the caller made (sha256 hex), and
   * `find_share_link(token_hash)` looks a live link up by it without counting a
   * use.
   */
  readonly tokenHash?: boolean;
  /**
   * `list_share_links` returns each link's tenant, subject, creator and
   * creation time, and takes `include_revoked`.
   */
  readonly fullRows?: boolean;
};

export const shareLinksSqlOptions: BlockOptionsSchema<ShareLinksSqlOptions> =
  blockOptions<ShareLinksSqlOptions>({
    tokenHash: option.boolean({ default: false }),
    fullRows: option.boolean({ default: false }),
  });
