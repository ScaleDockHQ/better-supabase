import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks['bulk-actions'].options`. */
export type BulkActionsSqlOptions = {
  readonly limit?: number;
  readonly actions?: unknown;
};

export const bulkActionsSqlOptions: BlockOptionsSchema<BulkActionsSqlOptions> =
  blockOptions<BulkActionsSqlOptions>({
    limit: option.number({ default: 500, client: true }),
    actions: option.unknown(),
  });
