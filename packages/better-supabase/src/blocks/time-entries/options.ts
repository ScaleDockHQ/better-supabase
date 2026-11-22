import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.time-entries.options`. */
export type TimeEntriesSqlOptions = {
  readonly policy?: unknown;
  readonly timeZone?: string;
  /**
   * `false` keeps timesheets without the approvals block: a status column holds
   * open, submitted, approved or rejected, and members with
   * `time_entries.approve` decide through `approve_timesheet` and
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
  /**
   * The record types an entry can be tracked on, such as `["task", "project"]`.
   * Another type fails with `TIME_SUBJECT_INVALID`. Default: any record type
   * the caller can read.
   */
  readonly on?: readonly string[];
  /**
   * An app function `schema.function(id uuid) returns boolean` that answers
   * whether the caller decides the timesheet `id`, such as a manager up the
   * owner's reporting chain. It decides policy steps whose approvers set
   * `decider: true`, which the default policy does when this is set.
   */
  readonly decider?: string;
  /**
   * An app function `schema.function(tenant, owner uuid) returns boolean` that
   * answers whether the caller may write another owner's time, such as a
   * manager for their reports. `owner` is the employee id with owner
   * `"employee"`, else the member's user id. A caller it accepts logs, changes
   * and archives that owner's entries and submits and withdraws their weeks,
   * next to holders of the manage permission. A null answer denies.
   */
  readonly writer?: string;
  /**
   * An app function `schema.function(tenant, timesheet_id uuid) returns
   * boolean`, such as an organization setting. When it answers false,
   * `submit_timesheet` approves the week at once instead of filing it with the
   * approvals block; true or null files it.
   */
  readonly approvalRequired?: string;
  /**
   * `submit_timesheet` approves the week at once when its owner submits it,
   * holds the approve permission and nobody else could decide it: no other
   * active member holds the permission, and no active manager with a login
   * could (a manager step, or anyone up the chain with a `decider`). The
   * policy's approvers must be the approve permission, the manager or the
   * decider. Default `false`.
   */
  readonly selfApproveWhenTopOfChain?: boolean;
};

export const timeEntriesSqlOptions: BlockOptionsSchema<TimeEntriesSqlOptions> =
  blockOptions<TimeEntriesSqlOptions>({
    policy: option.unknown(),
    timeZone: option.string({ default: "UTC", client: true }),
    approvals: option.boolean({ default: true }),
    userTimeZone: option.unknown<{
      readonly column: string;
      readonly key?: string;
    }>(),
    owner: option.string<"user" | "employee">({ default: "user" }),
    overlap: option.string<"refuse" | "allow">({ default: "refuse" }),
    timers: option.string<"one" | "many">({ default: "one" }),
    lockedColumns: option.strings(),
    decider: option.string(),
    writer: option.string(),
    approvalRequired: option.string(),
    selfApproveWhenTopOfChain: option.boolean({ default: false }),
    on: option.strings(),
  });
