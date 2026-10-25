import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.memberships.options`. */
export type MembershipsSqlOptions = {
  readonly claimFormat?: string;
  readonly roleThrough?: unknown;
  readonly sameTenant?: unknown;
  /** `{ many: true }` lets a member hold several roles (`membership_roles`). */
  readonly roles?: { readonly many?: boolean };
};

export const membershipsSqlOptions: BlockOptionsSchema<MembershipsSqlOptions> =
  blockOptions<MembershipsSqlOptions>({
    claimFormat: option.string({ default: "array" }),
    roleThrough: option.unknown(),
    sameTenant: option.unknown(),
    roles: option.unknown<{ readonly many?: boolean }>(),
  });
