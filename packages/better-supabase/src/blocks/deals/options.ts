import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.deals.options`. */
export type DealsSqlOptions = {
  readonly company?: string;
  readonly contact?: string;
  readonly motions?: unknown;
  readonly priorities?: unknown;
  readonly prefix?: string;
  readonly readAll?: boolean;
  readonly extraColumns?: unknown;
};

export const dealsSqlOptions: BlockOptionsSchema<DealsSqlOptions> =
  blockOptions<DealsSqlOptions>({
    company: option.string({ default: "company" }),
    contact: option.string({ default: "person" }),
    motions: option.unknown(),
    priorities: option.unknown(),
    prefix: option.string({ default: "DEAL-" }),
    readAll: option.boolean({ default: true }),
    extraColumns: option.unknown(),
  });
