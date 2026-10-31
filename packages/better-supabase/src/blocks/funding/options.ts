import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.funding.options`. */
export type FundingSqlOptions = {
  /**
   * The claim format keys `build_funding_claim` accepts, such as `iwlz-aw319`.
   * Default: any well-formed key.
   */
  readonly formats?: readonly string[];
  /**
   * The time-tracking entries' extra column whose value is a product code.
   * `register_funding_deliveries_from_time` then picks the award with that
   * product. Default: the record's one active award.
   */
  readonly timeCategory?: string;
  /** Extra columns on the funding awards table. */
  readonly extraColumns?: ExtraColumns;
};

export const fundingSqlOptions: BlockOptionsSchema<FundingSqlOptions> =
  blockOptions<FundingSqlOptions>({
    formats: option.strings({ default: [] }),
    timeCategory: option.string(),
    extraColumns: option.extraColumns(),
  });
