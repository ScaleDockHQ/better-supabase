import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.qualifications.options`. */
export type QualificationsSqlOptions = {
  /**
   * The kinds of holder a qualification type may name: `member`, `company`
   * (contacts) and `asset` (assets). Default all three.
   */
  readonly holderTypes?: readonly string[];
  /** Days before expiry a holding counts as expiring. Default 30. */
  readonly renewalWindowDays?: number;
  /** Extra columns on the holdings table. */
};

export const qualificationsSqlOptions: BlockOptionsSchema<QualificationsSqlOptions> =
  blockOptions<QualificationsSqlOptions>({
    holderTypes: option.strings({ default: ["member", "company", "asset"] }),
    renewalWindowDays: option.number({ default: 30 }),
  });
