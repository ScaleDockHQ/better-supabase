import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.impersonation.options`. */
export type ImpersonationSqlOptions = {
  readonly allowPlatformTargets?: unknown;
  readonly allowWrites?: unknown;
  readonly approval?: unknown;
  readonly approvalTtl?: unknown;
  readonly auditCategory?: unknown;
  readonly claimsHook?: unknown;
  readonly maxTtl?: unknown;
  readonly requireReason?: unknown;
};

export const impersonationSqlOptions: BlockOptionsSchema<ImpersonationSqlOptions> =
  blockOptions<ImpersonationSqlOptions>({
    allowPlatformTargets: option.unknown(),
    allowWrites: option.unknown(),
    approval: option.unknown(),
    approvalTtl: option.unknown(),
    auditCategory: option.unknown(),
    claimsHook: option.unknown(),
    maxTtl: option.unknown(),
    requireReason: option.unknown(),
  });
