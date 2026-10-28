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
  readonly owner?: "user" | "employee";
  /**
   * `"allow"` lets a member's entries overlap, such as a weekly grid that logs
   * every row's time from the same start. Default `"refuse"`.
   */
  readonly overlap?: "refuse" | "allow";
  /**
   * `"many"` runs several timers at once: `start_timer` leaves the others
   * running and `stop_timer` takes the entry. Needs `overlap: "allow"`.
   */
  readonly timers?: "one" | "many";
  /**
   * The entry columns a submitted or approved week refuses to change, as
   * logical names (`startedAt`) or the table's own column names. Default: the
   * ones that change logged time (start, end or duration, subject, owner and
   * rate), so a billable flag, a note or a link column stays writable.
   */
  readonly lockedColumns?: readonly string[];
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
    owner: option.string<"user" | "employee">({ default: "user" }),
    overlap: option.string<"refuse" | "allow">({ default: "refuse" }),
    timers: option.string<"one" | "many">({ default: "one" }),
    lockedColumns: option.strings(),
  });
