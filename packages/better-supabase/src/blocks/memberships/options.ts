import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.memberships.options`. */
export type MembershipsSqlOptions = {
  readonly claimFormat?: string;
  readonly roleThrough?: unknown;
  readonly sameTenant?: unknown;
};

export const membershipsSqlOptions: BlockOptionsSchema<MembershipsSqlOptions> =
  blockOptions<MembershipsSqlOptions>({
    claimFormat: option.string({ default: "array" }),
    roleThrough: option.unknown(),
    sameTenant: option.unknown(),
  });
