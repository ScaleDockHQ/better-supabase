import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.time-tracking.options`. */
export type TimeTrackingSqlOptions = {
  readonly policy?: unknown;
  readonly timeZone?: string;
  readonly extraColumns?: ExtraColumns;
  /**
   * `false` keeps timesheets without the approvals block: a status column holds
   * open, submitted, approved or rejected, and members with
   * `time_tracking.approve` decide through `approve_timesheet` and
   * `reject_timesheet`. Default `true`.
   */
  readonly approvals?: boolean;
  /**
   * The column that holds each user's IANA time zone, as `{ column:
   * "schema.table.column", key? }` (`key` defaults to `id`). Weeks then start
   * in the user's own zone, and in `timeZone` for a user without one.
   */
  readonly userTimeZone?: { readonly column: string; readonly key?: string };
};

export const timeTrackingSqlOptions: BlockOptionsSchema<TimeTrackingSqlOptions> =
  blockOptions<TimeTrackingSqlOptions>({
    policy: option.unknown(),
    timeZone: option.string({ default: "UTC", client: true }),
    extraColumns: option.extraColumns(),
    approvals: option.boolean({ default: true }),
    userTimeZone: option.unknown<{
      readonly column: string;
      readonly key?: string;
    }>(),
  });
