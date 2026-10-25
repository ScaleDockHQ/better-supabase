import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.access-requests.options`. */
export type AccessRequestsSqlOptions = {
  readonly roles?: unknown;
  readonly policy?: unknown;
  readonly maxDuration?: unknown;
  readonly join?: boolean;
  readonly extraColumns?: ExtraColumns;
};

export const accessRequestsSqlOptions: BlockOptionsSchema<AccessRequestsSqlOptions> =
  blockOptions<AccessRequestsSqlOptions>({
    roles: option.unknown(),
    policy: option.unknown(),
    maxDuration: option.unknown(),
    join: option.boolean({ default: false }),
    extraColumns: option.extraColumns(),
  });
