import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.quotes.options`. */
export type QuotesSqlOptions = {
  readonly company?: string;
  readonly contact?: string;
  readonly prefix?: string;
  readonly validDays?: number;
  readonly extraColumns?: unknown;
};

export const quotesSqlOptions: BlockOptionsSchema<QuotesSqlOptions> =
  blockOptions<QuotesSqlOptions>({
    company: option.string({ default: "company" }),
    contact: option.string({ default: "person" }),
    prefix: option.string({ default: "Q-" }),
    validDays: option.number({ default: 30 }),
    extraColumns: option.unknown(),
  });
