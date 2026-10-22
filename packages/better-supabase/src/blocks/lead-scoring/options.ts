import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks["lead-scoring"].options`. */
export type LeadScoringSqlOptions = {
  /** The key of the score model people are scored under. Default "lead". */
  readonly personModel?: string;
  /**
   * The key of the score model companies are scored under; empty leaves them
   * out.
   */
  readonly companyModel?: string;
  /** Hours after which an unchanged record is scored again. Default 24. */
  readonly rescoreAfterHours?: number;
};

export const leadScoringSqlOptions: BlockOptionsSchema<LeadScoringSqlOptions> =
  blockOptions<LeadScoringSqlOptions>({
    personModel: option.string({ default: "lead" }),
    companyModel: option.string({ default: "" }),
    rescoreAfterHours: option.number({ default: 24 }),
  });
