import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.leave.options`. */
export type LeaveSqlOptions = {
  readonly policy?: unknown;
  readonly workingDays?: readonly string[];
  readonly allowNegative?: boolean;
  readonly extraColumns?: ExtraColumns;
  /**
   * `false` runs leave without the approvals block: a request stays pending
   * until `decide_leave_request` approves or rejects it.
   */
  readonly approvals?: boolean;
};

export const leaveSqlOptions: BlockOptionsSchema<LeaveSqlOptions> =
  blockOptions<LeaveSqlOptions>({
    policy: option.unknown(),
    workingDays: option.strings({
      default: ["mon", "tue", "wed", "thu", "fri"],
    }),
    allowNegative: option.boolean({ default: false }),
    extraColumns: option.extraColumns(),
    approvals: option.boolean({ default: true }),
  });
