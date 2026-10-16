import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.promotions.options`. */
export type PromotionsSqlOptions = {
  readonly extraColumns?: unknown;
};

export const promotionsSqlOptions: BlockOptionsSchema<PromotionsSqlOptions> =
  blockOptions<PromotionsSqlOptions>({
    extraColumns: option.unknown(),
  });
