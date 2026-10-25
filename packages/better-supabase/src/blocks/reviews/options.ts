import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.reviews.options`. */
export type ReviewsSqlOptions = {
  readonly scale?: number;
  readonly maxBodyLength?: number;
  readonly moderation?: string;
  readonly requirePurchase?: boolean;
  readonly extraColumns?: ExtraColumns;
};

export const reviewsSqlOptions: BlockOptionsSchema<ReviewsSqlOptions> =
  blockOptions<ReviewsSqlOptions>({
    scale: option.number({ default: 5 }),
    maxBodyLength: option.number({ default: 5000 }),
    moderation: option.string({ default: "pre" }),
    requirePurchase: option.boolean({ default: false }),
    extraColumns: option.extraColumns(),
  });
