import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.leave.options`. */
export type LeaveSqlOptions = {
  readonly policy?: unknown;
  readonly workingDays?: readonly string[];
  readonly allowNegative?: boolean;
  readonly extraColumns?: ExtraColumns;
};

export const leaveSqlOptions: BlockOptionsSchema<LeaveSqlOptions> =
  blockOptions<LeaveSqlOptions>({
    policy: option.unknown(),
    workingDays: option.strings({
      default: ["mon", "tue", "wed", "thu", "fri"],
    }),
    allowNegative: option.boolean({ default: false }),
    extraColumns: option.extraColumns(),
  });
