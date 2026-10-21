import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.bulk.options`. */
export type BulkSqlOptions = {
  readonly limit?: number;
  readonly actions?: unknown;
};

export const bulkSqlOptions: BlockOptionsSchema<BulkSqlOptions> =
  blockOptions<BulkSqlOptions>({
    limit: option.number({ default: 500, client: true }),
    actions: option.unknown(),
  });
