import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.referrals.options`. */
export type ReferralsSqlOptions = {
  /**
   * Attribute the referral of an invitation's code to the user who accepts the
   * invitation. Needs the invitations block with an `acceptedBy` column.
   * Default `false`.
   */
  readonly invitations?: boolean;
};

export const referralsSqlOptions: BlockOptionsSchema<ReferralsSqlOptions> =
  blockOptions<ReferralsSqlOptions>({ invitations: option.boolean() });
