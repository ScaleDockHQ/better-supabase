import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.promotions.options`. */
export type PromotionsSqlOptions = { readonly extraColumns?: ExtraColumns };

export const promotionsSqlOptions: BlockOptionsSchema<PromotionsSqlOptions> =
  blockOptions<PromotionsSqlOptions>({ extraColumns: option.extraColumns() });
