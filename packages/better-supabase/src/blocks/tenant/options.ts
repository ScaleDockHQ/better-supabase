import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.tenant.options`. */
export type TenantSqlOptions = {
  readonly claimFormat?: string;
  readonly roleThrough?: unknown;
  readonly sameTenant?: unknown;
};

export const tenantSqlOptions: BlockOptionsSchema<TenantSqlOptions> =
  blockOptions<TenantSqlOptions>({
    claimFormat: option.string({ default: "array" }),
    roleThrough: option.unknown(),
    sameTenant: option.unknown(),
  });
