import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.access-requests.options`. */
export type AccessRequestsSqlOptions = {
  readonly roles?: unknown;
  readonly policy?: unknown;
  readonly maxDuration?: unknown;
  readonly join?: boolean;
  readonly emergency?: unknown;
};

export const accessRequestsSqlOptions: BlockOptionsSchema<AccessRequestsSqlOptions> =
  blockOptions<AccessRequestsSqlOptions>({
    roles: option.unknown(),
    policy: option.unknown(),
    maxDuration: option.unknown(),
    join: option.boolean({ default: false }),
    emergency: option.unknown(),
  });
