import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.vercel-marketplace.options`. */
export type VercelMarketplaceSqlOptions = {
  /**
   * The currency an invoice takes when the webhook names none (ISO 4217,
   * lowercase).
   */
  readonly currency?: string;
};

export const vercelMarketplaceSqlOptions: BlockOptionsSchema<VercelMarketplaceSqlOptions> =
  blockOptions<VercelMarketplaceSqlOptions>({
    currency: option.string({ default: "usd" }),
  });
