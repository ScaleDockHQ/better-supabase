import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.share-links.options`. */
export type ShareLinksSqlOptions = { readonly extraColumns?: unknown };

export const shareLinksSqlOptions: BlockOptionsSchema<ShareLinksSqlOptions> =
  blockOptions<ShareLinksSqlOptions>({ extraColumns: option.unknown() });
