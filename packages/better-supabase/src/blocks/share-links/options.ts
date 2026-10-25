import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.share-links.options`. */
export type ShareLinksSqlOptions = { readonly extraColumns?: ExtraColumns };

export const shareLinksSqlOptions: BlockOptionsSchema<ShareLinksSqlOptions> =
  blockOptions<ShareLinksSqlOptions>({ extraColumns: option.extraColumns() });
